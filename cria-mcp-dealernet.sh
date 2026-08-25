#!/usr/bin/env bash
# ============================================================
# Cria mcps/dealernet a partir de mcps/nbs (Oracle -> SQL Server).
# Rodar da raiz do repo:  bash cria-mcp-dealernet.sh
# ============================================================
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
STAMP=$(date +%Y%m%d-%H%M%S)

test -d mcps/nbs || { echo "ERRO: mcps/nbs nao encontrado"; exit 1; }
git check-ignore -q .env || { echo "ERRO: .env fora do .gitignore"; exit 1; }
rm -rf mcps/dealernet
cp -r mcps/nbs mcps/dealernet
rm -rf mcps/dealernet/app/__pycache__ mcps/dealernet/app/scripts

# ---- 1. variaveis NBS_* -> DN_* ----
grep -rl 'NBS_\|MCP_NBS' mcps/dealernet 2>/dev/null | xargs -r sed -i \
  -e 's/NBS_USER/DN_USER/g' -e 's/NBS_PASSWORD/DN_PASSWORD/g' \
  -e 's/NBS_DSN/DN_DSN/g'   -e 's/NBS_POOL_MIN/DN_POOL_MIN/g' \
  -e 's/NBS_POOL_MAX/DN_POOL_MAX/g' \
  -e 's/NBS_QUERY_TIMEOUT_MS/DN_QUERY_TIMEOUT_MS/g' \
  -e 's/NBS_DEFAULT_ROW_LIMIT/DN_DEFAULT_ROW_LIMIT/g' \
  -e 's/MCP_NBS_TOKEN/MCP_DN_TOKEN/g' -e 's/MCP_NBS_HOST/MCP_DN_HOST/g' \
  -e 's/MCP_NBS_PORT/MCP_DN_PORT/g'   -e 's|MCP_NBS_LOG_DIR|MCP_DN_LOG_DIR|g' \
  -e 's|logs/mcp-nbs|logs/mcp-dealernet|g' -e 's/8990/8991/g'

# ---- 2. pool.py em pymssql ----
cat > mcps/dealernet/app/pool.py <<'PY'
"""pool.py — conexoes SQL Server (DealerNet Workflow).

pymssql nao tem pool nativo como oracledb; usamos um pool simples de conexoes
reaproveitadas. Cada sessao nasce com READ UNCOMMITTED e LOCK_TIMEOUT curto:
a base tem tabela de 800M linhas e NAO pode travar a operacao.
"""
from __future__ import annotations

import logging
import os
import queue
import threading
from dataclasses import dataclass

import pymssql

logger = logging.getLogger(__name__)


@dataclass
class DNConfig:
    host: str
    porta: int
    user: str
    password: str
    database: str
    pool_min: int
    pool_max: int
    timeout_ms: int

    def __repr__(self):  # nunca logar senha
        return (f"DNConfig(user={self.user}, host={self.host}:{self.porta}, "
                f"db={self.database}, pool={self.pool_min}-{self.pool_max}, "
                f"timeout_ms={self.timeout_ms})")


def _config() -> DNConfig:
    dsn = os.environ["DN_DSN"]            # host:porta/database
    hostporta, _, database = dsn.partition("/")
    host, _, porta = hostporta.partition(":")
    return DNConfig(
        host=host, porta=int(porta or 1433),
        user=os.environ["DN_USER"], password=os.environ["DN_PASSWORD"],
        database=database,
        pool_min=int(os.getenv("DN_POOL_MIN", "2")),
        pool_max=int(os.getenv("DN_POOL_MAX", "10")),
        timeout_ms=int(os.getenv("DN_QUERY_TIMEOUT_MS", "30000")),
    )


_cfg: DNConfig | None = None
_pool: queue.LifoQueue | None = None
_lock = threading.Lock()


def _nova_conexao() -> pymssql.Connection:
    c = pymssql.connect(
        server=_cfg.host, port=_cfg.porta, user=_cfg.user,
        password=_cfg.password, database=_cfg.database,
        login_timeout=10, timeout=_cfg.timeout_ms // 1000,
        autocommit=True,
    )
    cur = c.cursor()
    # SOMENTE LEITURA e sem bloquear a producao
    cur.execute("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED")
    cur.execute("SET LOCK_TIMEOUT 5000")
    cur.execute("SET ARITHABORT ON")
    cur.close()
    return c


def get_pool() -> queue.LifoQueue:
    global _cfg, _pool
    with _lock:
        if _pool is None:
            _cfg = _config()
            logger.info("Inicializando pool SQL Server: %s", _cfg)
            _pool = queue.LifoQueue(maxsize=_cfg.pool_max)
            for _ in range(_cfg.pool_min):
                _pool.put(_nova_conexao())
            logger.info("Pool SQL Server pronto (min=%d, max=%d)",
                        _cfg.pool_min, _cfg.pool_max)
    return _pool


class conexao:
    """Context manager: with conexao() as c: ..."""
    def __enter__(self):
        p = get_pool()
        try:
            self.c = p.get_nowait()
            self.c.cursor().execute("SELECT 1")   # valida
        except Exception:
            self.c = _nova_conexao()
        return self.c

    def __exit__(self, *a):
        try:
            get_pool().put_nowait(self.c)
        except Exception:
            try:
                self.c.close()
            except Exception:
                pass


def close_pool() -> None:
    global _pool
    if _pool is not None:
        while not _pool.empty():
            try:
                _pool.get_nowait().close()
            except Exception:
                pass
        _pool = None
        logger.info("Pool SQL Server fechado")
PY

# ---- 3. preflight T-SQL ----
if [ -f mcps/dealernet/app/preflight.py ]; then
  sed -i \
    -e 's/ALL_TAB_COLUMNS/INFORMATION_SCHEMA.COLUMNS/g' \
    -e 's/OWNER *= *:owner//g' \
    -e "s/'NBS'/'dbo'/g" \
    mcps/dealernet/app/preflight.py
fi

# ---- 4. Dockerfile: oracledb -> pymssql ----
sed -i \
  -e 's/"oracledb>=[^"]*"/"pymssql>=2.3.0"/' \
  -e 's/EBD.ia MCP NBS/EBD.ia MCP DealerNet/' \
  -e 's|read-only NBS (Oracle) access|read-only DealerNet (SQL Server) access|' \
  mcps/dealernet/Dockerfile
sed -i 's/"oracledb>=[^"]*"/"pymssql>=2.3.0"/' mcps/dealernet/pyproject.toml 2>/dev/null || true
sed -i 's/name = "ebd-ia-mcp-nbs"/name = "ebd-ia-mcp-dealernet"/' mcps/dealernet/pyproject.toml 2>/dev/null || true
# pymssql precisa de libs de sistema
grep -q freetds mcps/dealernet/Dockerfile || \
  sed -i '0,/^RUN pip install/s//RUN apt-get update \&\& apt-get install -y --no-install-recommends freetds-dev freetds-bin \&\& rm -rf \/var\/lib\/apt\/lists\/*\nRUN pip install/' mcps/dealernet/Dockerfile

mkdir -p logs/mcp-dealernet

echo
echo ">> mcps/dealernet criado."
echo ">> REVISAR MANUALMENTE (oracledb -> pymssql nao e automatico):"
grep -rln "oracledb\|oracle" mcps/dealernet/app/*.py || echo "   (nenhum residuo obvio)"
echo
echo ">> Proximo: bloco no .env e no compose.yaml (ver ADR 002)."
