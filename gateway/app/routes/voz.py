"""routes/voz.py — canal de voz do Dealer.ia.

  POST /api/voz/perguntar   audio -> {texto, ack_audio, job_id}   (~2-4s)
  GET  /api/voz/resultado/{job_id}  -> {status, texto, audio}
  GET  /api/voz/audio/{nome}        -> WAV

Duas etapas de proposito: a pergunta falada recebe ACK em segundos e a
resposta completa chega depois. Ver docs/canal-voz.md.
"""
from __future__ import annotations

import asyncio
import logging
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse

from gateway.app.auth.entra import verify_token
from gateway.app import acl_store, db, voz as _voz

log = logging.getLogger("uvicorn.error")
router = APIRouter(prefix="/voz")

_JOBS: dict[str, dict] = {}          # job_id -> {status, texto, audio, erro}
_MAX_JOBS = 200


async def _processar(job_id: str, pergunta: str, conv_id: str | None,
                     user_id: str, user_email: str):
    """Roda o agente e sintetiza o resumo falado."""
    try:
        from app.agent import run_turn_stream

        _cid = conv_id if conv_id and not str(conv_id).startswith("tmp-") else None
        window = await db.build_model_window(_cid, user_id) if _cid else []
        resposta = ""
        async for ev in run_turn_stream(
            user_message=pergunta,
            conversation_history=window,
            user_id=user_id,
            user_role="admin",
            user_filiais="*",
            channel="voz",
            user_email=user_email,
        ):
            if ev.get("type") == "token":
                resposta += ev.get("text", "")

        visual = _voz.limpar_texto_visual(resposta)
        fala = _voz.extrair_fala(resposta)
        nome = await asyncio.to_thread(_voz.sintetizar, fala)

        if _cid:
            await db.add_message(_cid, "assistant", {"text": visual})

        _JOBS[job_id] = {"status": "pronto", "texto": visual,
                         "fala": fala, "audio": nome}
        log.info("voz: job %s pronto (%d chars)", job_id, len(visual))
    except Exception as e:
        log.exception("voz: job %s falhou", job_id)
        _JOBS[job_id] = {"status": "erro", "erro": str(e)[:300]}


@router.post("/perguntar")
async def perguntar(
    audio: UploadFile = File(...),
    conversation_id: str | None = None,
    claims: dict = Depends(verify_token),
):
    _email = (claims.get("preferred_username") or claims.get("upn")
              or claims.get("unique_name") or claims.get("email"))
    if not await acl_store.is_allowed(_email):
        raise HTTPException(403, "Acesso nao configurado.")
    user_id = claims.get("oid") or claims.get("sub") or "web-user"

    bruto = await audio.read()
    if len(bruto) > 25 * 1024 * 1024:
        raise HTTPException(413, "Audio muito grande (max 25 MB).")

    sufixo = Path(audio.filename or "a.webm").suffix or ".webm"
    tr = await asyncio.to_thread(_voz.transcrever, bruto, sufixo)
    pergunta = tr["texto"]
    if not pergunta:
        raise HTTPException(422, "Nao consegui entender o audio.")

    # ACK imediato — confirmacao implicita, sem chamar o modelo
    ack_txt = _voz.montar_ack(pergunta)
    ack_wav = await asyncio.to_thread(_voz.sintetizar, ack_txt)

    if conversation_id and not str(conversation_id).startswith("tmp-"):
        try:
            await db.add_message(conversation_id, "user", {"text": pergunta})
        except Exception:
            log.warning("voz: nao gravou a pergunta na conversa")

    job_id = uuid.uuid4().hex[:12]
    _JOBS[job_id] = {"status": "processando"}
    if len(_JOBS) > _MAX_JOBS:                      # poda simples
        for k in list(_JOBS)[:-_MAX_JOBS]:
            _JOBS.pop(k, None)

    asyncio.create_task(_processar(job_id, pergunta, conversation_id,
                                   user_id, _email))

    return {"job_id": job_id, "texto": pergunta, "duracao_s": tr["duracao_s"],
            "ack_texto": ack_txt, "ack_audio": ack_wav}


@router.get("/resultado/{job_id}")
async def resultado(job_id: str, claims: dict = Depends(verify_token)):
    j = _JOBS.get(job_id)
    if not j:
        raise HTTPException(404, "Job nao encontrado ou expirado.")
    return j


@router.get("/audio/{nome}")
async def audio(nome: str, claims: dict = Depends(verify_token)):
    if "/" in nome or ".." in nome:
        raise HTTPException(400, "nome invalido")
    caminho = _voz.AUDIO_DIR / nome
    if not caminho.exists():
        raise HTTPException(404, "audio nao encontrado")
    return FileResponse(caminho, media_type="audio/wav")
