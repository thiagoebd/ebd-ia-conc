"""acl.py — ACL do MCP NBS.

Base unica (BMW): nao existe escopo de filial para injetar em coluna, entao o
escopo e resolvido no nivel da CONEXAO. Este modulo so responde QUEM pode
consultar, lendo acl_users no Postgres.

Quando entrar a segunda concessionaria, decidir: outra base (novo MCP) ou
multi-empresa na mesma base (ai o scope_guard volta, filtrando a coluna de
empresa).
"""
from __future__ import annotations

import logging as _logging
import os

from .models import UserContext

log = _logging.getLogger(__name__)


def _pg_lookup_user(identifier: str) -> dict | None:
    try:
        import psycopg
    except Exception:
        return None
    dsn = (
        f"host={os.getenv('POSTGRES_HOST', 'postgres')} "
        f"port={os.getenv('POSTGRES_PORT', '5432')} "
        f"dbname={os.getenv('POSTGRES_DB', '')} "
        f"user={os.getenv('POSTGRES_USER', '')} "
        f"password={os.getenv('POSTGRES_PASSWORD', '')}"
    )
    try:
        with psycopg.connect(dsn, connect_timeout=5) as con, con.cursor() as cur:
            cur.execute(
                "SELECT id, nome, email, role, active FROM acl_users "
                "WHERE lower(email) = lower(%s)",
                (identifier,),
            )
            row = cur.fetchone()
    except Exception as e:
        log.error("acl_pg_falhou: %s", str(e)[:200])
        return None
    if not row:
        return None
    uid, nome, email, role, active = row
    if not active:
        return None
    return {"user_id": uid, "nome": nome, "email": email, "role": role or "analista"}


def resolve_user_by_identifier(identifier: str) -> UserContext | None:
    dados = _pg_lookup_user(identifier)
    if not dados:
        log.warning("acl_negado: %s", identifier)
        return None
    return UserContext(
        user_id=dados["user_id"],
        nome=dados["nome"],
        role=dados["role"],
        filiais="*",
    )
