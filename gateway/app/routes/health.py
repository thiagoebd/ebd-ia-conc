"""Health check — pública, sem autenticação.

Usado por monitoramento e pelo frontend pra mostrar estado dos componentes
na tela de erro (mockup 07 — banco offline + circuit-breaker).
"""
from fastapi import APIRouter

router = APIRouter()


@router.get("/health")
async def health():
    return {
        "status": "ok",
        "service": "ebd-ia-gateway",
    }
