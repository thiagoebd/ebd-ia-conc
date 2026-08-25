#!/usr/bin/env bash
# ============================================================
# Aplica o MCP NBS (Oracle BMW) no projeto das concessionarias.
# Rodar da raiz do repo:  bash aplica-mcp-nbs.sh
# Idempotente: pode rodar de novo depois de corrigir algo.
# ============================================================
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
echo ">> repo: $(pwd)"

# ------------------------------------------------------------
# 0. Guarda-corpos
# ------------------------------------------------------------
test -d mcps/oracle || { echo "ERRO: mcps/oracle nao encontrado"; exit 1; }
git check-ignore -q .env || { echo "ERRO: .env NAO esta no .gitignore — abortando"; exit 1; }

STAMP=$(date +%Y%m%d-%H%M%S)
cp compose.yaml "compose.yaml.bak-$STAMP"
[ -f .env ] && cp .env ".env.bak-$STAMP"

# ------------------------------------------------------------
# 1. mcps/nbs a partir de mcps/oracle
# ------------------------------------------------------------
rm -rf mcps/nbs
cp -r mcps/oracle mcps/nbs
rm -rf mcps/nbs/tests mcps/nbs/app/scripts mcps/nbs/app/__pycache__

grep -rl 'ORACLE_' mcps/nbs/app mcps/nbs/Dockerfile 2>/dev/null | xargs -r sed -i \
  -e 's/ORACLE_USER/NBS_USER/g' \
  -e 's/ORACLE_PASSWORD/NBS_PASSWORD/g' \
  -e 's/ORACLE_DSN/NBS_DSN/g' \
  -e 's/ORACLE_POOL_MIN/NBS_POOL_MIN/g' \
  -e 's/ORACLE_POOL_MAX/NBS_POOL_MAX/g' \
  -e 's/ORACLE_QUERY_TIMEOUT_MS/NBS_QUERY_TIMEOUT_MS/g' \
  -e 's/ORACLE_DEFAULT_ROW_LIMIT/NBS_DEFAULT_ROW_LIMIT/g' \
  -e 's/MCP_ORACLE_TOKEN/MCP_NBS_TOKEN/g' \
  -e 's/MCP_ORACLE_HOST/MCP_NBS_HOST/g' \
  -e 's/MCP_ORACLE_PORT/MCP_NBS_PORT/g' \
  -e 's|MCP_ORACLE_LOG_DIR|MCP_NBS_LOG_DIR|g' \
  -e 's|logs/mcp-oracle|logs/mcp-nbs|g'

sed -i 's/8989/8990/g' mcps/nbs/app/server.py mcps/nbs/Dockerfile
sed -i \
  -e 's/EBD.ia MCP Oracle/EBD.ia MCP NBS/' \
  -e 's|MCP server for read-only Winthor (Oracle) access|MCP server for read-only NBS (Oracle) access|' \
  mcps/nbs/Dockerfile
sed -i 's/name = "ebd-ia-mcp-oracle"/name = "ebd-ia-mcp-nbs"/' mcps/nbs/pyproject.toml 2>/dev/null || true

# ACL propria: base unica, sem escopo de filial. Falha FECHADA.
cat > mcps/nbs/app/acl.py <<'PY'
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
PY

mkdir -p logs/mcp-nbs

# ------------------------------------------------------------
# 2. .env — bloco NBS
# ------------------------------------------------------------
touch .env
sed -i '/^NBS_/d; /^MCP_NBS_/d; /^# ----- NBS (Oracle/d' .env
sed -i '/^ORACLE_/d; /^MCP_ORACLE_/d; /^# ----- Winthor (Oracle)/d' .env

MCP_NBS_TOKEN=$(openssl rand -hex 32)
cat >> .env <<EOF

# ----- NBS (Oracle — concessionaria BMW, somente leitura) -----
NBS_USER=ebd_consulta
NBS_PASSWORD=Ebd@2025
NBS_DSN=ssp06orascan.grupoebd.ebdbr.com.br:1521/bmw.grupoebd.ebdbr.com.br
NBS_POOL_MIN=2
NBS_POOL_MAX=10
NBS_QUERY_TIMEOUT_MS=30000
NBS_DEFAULT_ROW_LIMIT=10000
MCP_NBS_TOKEN=$MCP_NBS_TOKEN
MCP_NBS_HOST=0.0.0.0
MCP_NBS_PORT=8990
EOF
chmod 600 .env

# ------------------------------------------------------------
# 3. compose.yaml — remove mcp-oracle, injeta mcp-nbs
# ------------------------------------------------------------
python3 - <<'PY'
import re, pathlib
p = pathlib.Path("compose.yaml")
t = p.read_text(encoding="utf-8")

# remove o servico mcp-oracle (do cabecalho de comentario ate a secao networks)
t = re.sub(
    r"\n  # -+\n  # MCP Oracle.*?(?=\n# =+\n# Rede interna)",
    "\n", t, flags=re.S)

servico = '''
  # ----------------------------------------------------------
  # MCP NBS — leitura read-only do NBS (Oracle, concessionaria BMW)
  # ----------------------------------------------------------
  mcp-nbs:
    build:
      context: ./mcps/nbs
      dockerfile: Dockerfile
    image: conc/mcp-nbs:0.1.0
    container_name: conc_mcp_nbs
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      NBS_USER: ${NBS_USER}
      NBS_PASSWORD: ${NBS_PASSWORD}
      NBS_DSN: ${NBS_DSN}
      NBS_POOL_MIN: ${NBS_POOL_MIN:-2}
      NBS_POOL_MAX: ${NBS_POOL_MAX:-10}
      NBS_QUERY_TIMEOUT_MS: ${NBS_QUERY_TIMEOUT_MS:-30000}
      NBS_DEFAULT_ROW_LIMIT: ${NBS_DEFAULT_ROW_LIMIT:-10000}
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      TZ: America/Sao_Paulo
      MCP_NBS_TOKEN: ${MCP_NBS_TOKEN}
      MCP_NBS_LOG_DIR: /app/logs/mcp-nbs
    volumes:
      - ./logs/mcp-nbs:/app/logs/mcp-nbs
    ports:
      - "127.0.0.1:8990:8990"
    networks:
      - ebdia_net
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8990/health', timeout=12)"]
      interval: 30s
      timeout: 15s
      retries: 3
      start_period: 30s
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"

'''
marcador = "# ============================================================\n# Rede interna"
if "mcp-nbs:" not in t:
    t = t.replace(marcador, servico + marcador, 1)
p.write_text(t, encoding="utf-8")
print("compose.yaml atualizado")
PY

# ------------------------------------------------------------
# 4. espera_mcp.sh — nome do container
# ------------------------------------------------------------
sed -i 's/ebdia_mcp_oracle/conc_mcp_nbs/g' scripts/espera_mcp.sh scripts/autoheal_mcp.sh scripts/ebdia_supervisor.py 2>/dev/null || true

# ------------------------------------------------------------
# 5. Validacao
# ------------------------------------------------------------
docker compose config >/dev/null && echo ">> compose valido"
echo
echo "OK. Agora:"
echo "  docker compose build --no-cache mcp-nbs"
echo "  docker compose up -d mcp-nbs"
echo "  docker compose logs -f mcp-nbs"
echo "  curl -s localhost:8990/health"
echo
echo "Backups: compose.yaml.bak-$STAMP  .env.bak-$STAMP"
