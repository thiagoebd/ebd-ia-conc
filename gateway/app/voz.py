"""voz.py — transcricao (Whisper) e sintese (Piper) locais.

Nada sai da rede: sao conversas sobre faturamento das 31 concessionarias.

Modelos carregam sob demanda (lazy) e ficam em memoria. O primeiro uso paga
uns 10s; os seguintes sao rapidos.
"""
from __future__ import annotations

import logging
import os
import re
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

log = logging.getLogger("uvicorn.error")

AUDIO_DIR = Path(os.getenv("VOZ_AUDIO_DIR", "/var/ebd-ia/audio"))
MODELO_STT = os.getenv("VOZ_STT_MODELO", "small")     # tiny|base|small|medium
VOZ_TTS = os.getenv("VOZ_TTS_MODELO", "/opt/piper-vozes/pt_BR-faber-medium.onnx")

_whisper = None


def _modelo_stt():
    global _whisper
    if _whisper is None:
        from faster_whisper import WhisperModel
        log.info("voz: carregando Whisper %s (cpu/int8)...", MODELO_STT)
        _whisper = WhisperModel(MODELO_STT, device="cpu", compute_type="int8")
        log.info("voz: Whisper pronto")
    return _whisper


# ---------------------------------------------------------------------------
# STT
# ---------------------------------------------------------------------------
def transcrever(audio_bytes: bytes, sufixo: str = ".webm") -> dict:
    """Audio do navegador -> texto. Retorna {texto, duracao_s, idioma}."""
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=sufixo, delete=False) as f:
        f.write(audio_bytes)
        bruto = f.name
    wav = bruto + ".wav"
    try:
        # Whisper quer 16 kHz mono; o navegador manda webm/opus
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", bruto,
             "-ar", "16000", "-ac", "1", wav],
            check=True, timeout=60,
        )
        segs, info = _modelo_stt().transcribe(
            wav, language="pt", beam_size=1, vad_filter=True,
            initial_prompt=(
                "Concessionaria, faturamento, oficina, passagens, seminovos, "
                "Thai, Way, Jeep, Toyota, Fiat, Ford, Hyundai, Leapmotor, "
                "Isar, BMW, Avare, Macapa, Ananindeua, Castanhal, Santarem, "
                "Manaus, Teresina, DealerNet, NBS."
            ),
        )
        texto = " ".join(s.text.strip() for s in segs).strip()
        log.info("voz: transcrito %.1fs -> %r", info.duration, texto[:120])
        return {"texto": texto, "duracao_s": round(info.duration, 1),
                "idioma": info.language}
    finally:
        for p in (bruto, wav):
            try:
                os.unlink(p)
            except OSError:
                pass


# ---------------------------------------------------------------------------
# TTS
# ---------------------------------------------------------------------------
_SIMBOLOS = [
    (r"R\$\s*([\d.,]+)\s*mi\b", r"\1 milhões de reais"),
    (r"R\$\s*([\d.,]+)\s*mil\b", r"\1 mil reais"),
    (r"R\$\s*", "  "),
    (r"\bp\.p\.", "pontos percentuais"),
    (r"%", " por cento"),
    (r"−|–|—", " menos "),
    (r"[*_#`>|]", " "),      # markdown nao se fala
    (r"\s{2,}", " "),
]


def preparar_fala(texto: str) -> str:
    """Limpa markdown e expande simbolos para o TTS nao soletrar."""
    t = texto
    for pad, rep in _SIMBOLOS:
        t = re.sub(pad, rep, t)
    return t.strip()


def sintetizar(texto: str, nome: str | None = None) -> str:
    """Texto -> WAV em AUDIO_DIR. Retorna o nome do arquivo."""
    AUDIO_DIR.mkdir(parents=True, exist_ok=True)
    nome = nome or f"{uuid.uuid4().hex}.wav"
    destino = AUDIO_DIR / nome
    fala = preparar_fala(texto)
    _bin = shutil.which("piper") or "/usr/local/bin/piper"
    proc = subprocess.run(
        [_bin, "--model", VOZ_TTS, "--output_file", str(destino)],
        input=fala.encode("utf-8"),
        capture_output=True, timeout=120,
    )
    if proc.returncode != 0 or not destino.exists():
        raise RuntimeError(f"piper falhou: {proc.stderr.decode()[:300]}")
    log.info("voz: sintetizado %s (%d bytes)", nome, destino.stat().st_size)
    return nome


# ---------------------------------------------------------------------------
# ACK — a peca que faz a voz ser usavel
# ---------------------------------------------------------------------------
_UNIDADES = {
    "thai": "Thai", "way": "Way", "jeep": "Jeep", "toyota": "Toyota",
    "fiat": "Fiat", "ford": "Ford", "hyundai": "Hyundai", "miso": "Miso",
    "antares": "Antares", "viale": "Viale", "leapmotor": "Leapmotor",
    "isar": "Isar", "bmw": "BMW", "motorrad": "Motorrad", "mini": "Mini",
}
_PRACAS = {
    "avare": "Avaré", "avaré": "Avaré", "macapa": "Macapá", "macapá": "Macapá",
    "ananindeua": "Ananindeua", "castanhal": "Castanhal", "santarem": "Santarém",
    "santarém": "Santarém", "manaus": "Manaus", "teresina": "Teresina",
    "botucatu": "Botucatu", "ourinhos": "Ourinhos", "assis": "Assis",
    "itapetininga": "Itapetininga", "altamira": "Altamira", "belem": "Belém",
    "paragominas": "Paragominas", "cachoeirinha": "Cachoeirinha",
}
_ASSUNTOS = [
    (r"faturamento|fatura|receita|vendeu|venda", "o faturamento"),
    (r"oficina|passagem|passagens|\bos\b", "os dados de oficina"),
    (r"estoque|imobilizad|parado", "a posição de estoque"),
    (r"pe[çc]a|balc[ãa]o", "os números de peças"),
    (r"seminovo|usado", "os seminovos"),
    (r"novo[s]?\b|zero km", "os veículos novos"),
    (r"margem|lucro|rentab", "a margem"),
    (r"cliente|carteira", "os dados de clientes"),
]


def montar_ack(pergunta: str) -> str:
    """Frase de reconhecimento, montada da propria transcricao.

    NAO chama o modelo — precisa sair em menos de 1s. E confirmacao implicita:
    se entendeu 'Thai' quando voce disse 'Way', voce corrige AGORA e nao
    depois de dois minutos.
    """
    p = pergunta.lower()
    marca = next((v for k, v in _UNIDADES.items() if re.search(rf"\b{k}\b", p)), None)
    praca = next((v for k, v in _PRACAS.items() if re.search(rf"\b{k}\b", p)), None)
    assunto = next((rot for pad, rot in _ASSUNTOS if re.search(pad, p)), "essa informação")

    alvo = " ".join(x for x in (marca, praca) if x) or "do grupo"
    if marca or praca:
        alvo = f"da {alvo}" if not alvo.startswith("do") else alvo

    return f"Ok. Buscando {assunto} {alvo}. Já te retorno."


def extrair_fala(resposta: str) -> str:
    """Pega o bloco <FALA>...</FALA> que o agente produz no canal voz.

    Sem o bloco, cai num resumo pobre (primeiras frases sem markdown) — que e
    ruim de ouvir, mas melhor que ler a tabela inteira.
    """
    m = re.search(r"<FALA>(.*?)</FALA>", resposta, re.S | re.I)
    if m:
        return m.group(1).strip()
    limpo = re.sub(r"\|.*?\|", " ", resposta)          # tira tabelas
    limpo = re.sub(r"[#*_`>\-]", " ", limpo)
    limpo = re.sub(r"\s{2,}", " ", limpo).strip()
    return " ".join(limpo.split(". ")[:3])[:400]


def limpar_texto_visual(resposta: str) -> str:
    """Remove o bloco <FALA> da resposta que vai para a tela."""
    return re.sub(r"<FALA>.*?</FALA>", "", resposta, flags=re.S | re.I).strip()
