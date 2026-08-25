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

    @property
    def query_timeout_ms(self) -> int:
        """Alias: o server.py usa esse nome."""
        return self.timeout_ms

    @property
    def default_row_limit(self) -> int:
        import os
        return int(os.getenv("DN_DEFAULT_ROW_LIMIT", "1000"))

    @property
    def query_timeout_ms(self) -> int:
        """Alias: o server.py usa esse nome."""
        return self.timeout_ms

    @property
    def default_row_limit(self) -> int:
        import os
        return int(os.getenv("DN_DEFAULT_ROW_LIMIT", "1000"))

    def safe_repr(self) -> str:
        return repr(self)

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
_fachada = None
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


def get_pool():
    global _cfg, _pool, _fachada
    with _lock:
        if _pool is None:
            _cfg = _config()
            logger.info("Inicializando pool SQL Server: %s", _cfg)
            _pool = queue.LifoQueue(maxsize=_cfg.pool_max)
            for _ in range(_cfg.pool_min):
                _pool.put(_nova_conexao())
            _fachada = _Pool(_pool)
            logger.info("Pool SQL Server pronto (min=%d, max=%d)",
                        _cfg.pool_min, _cfg.pool_max)
    return _fachada


class _Conexao:
    """Wrapper: imita a interface do oracledb (with pool.acquire() as conn).

    Delega qualquer atributo (cursor, commit, close...) para a conexao real,
    para funcionar tambem quando usado SEM o `with`.
    """
    def __init__(self, fila):
        self._fila = fila
        self._c = None

    def _conn(self):
        if self._c is None:
            try:
                self._c = self._fila.get_nowait()
                self._c.cursor().execute("SELECT 1")
            except Exception:
                self._c = _nova_conexao()
        return self._c

    def __getattr__(self, nome):
        return getattr(self._conn(), nome)

    def __enter__(self):
        return self._conn()

    def __exit__(self, *a):
        if self._c is None:
            return
        try:
            self._fila.put_nowait(self._c)
        except Exception:
            try:
                self._c.close()
            except Exception:
                pass


class _Pool:
    """Fachada com .acquire(), igual ao pool do oracledb."""
    def __init__(self, fila):
        self._fila = fila

    def acquire(self):
        return _Conexao(self._fila)

    def release(self, conn):
        """Devolve a conexao ao pool (compat. com a API do oracledb)."""
        real = getattr(conn, "_c", conn)
        if real is None:
            return
        try:
            self._fila.put_nowait(real)
        except Exception:
            try:
                real.close()
            except Exception:
                pass

    def close(self):
        close_pool()

    def release(self, conn):
        """Devolve a conexao ao pool (compat. com a API do oracledb)."""
        real = getattr(conn, "_c", conn)
        if real is None:
            return
        try:
            self._fila.put_nowait(real)
        except Exception:
            try:
                real.close()
            except Exception:
                pass

    def close(self):
        close_pool()

    def release(self, conn):
        """Devolve a conexao ao pool (compat. com a API do oracledb)."""
        real = getattr(conn, "_c", conn)
        if real is None:
            return
        try:
            self._fila.put_nowait(real)
        except Exception:
            try:
                real.close()
            except Exception:
                pass

    def close(self):
        close_pool()


def conexao():
    return get_pool().acquire()


def get_config() -> DNConfig:
    global _cfg
    if _cfg is None:
        _cfg = _config()
    return _cfg


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
