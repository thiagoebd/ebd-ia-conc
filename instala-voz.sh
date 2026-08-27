#!/usr/bin/env bash
# ============================================================================
#  instala-voz.sh — feature de voz do Dealer.ia, de ponta a ponta
#
#  O QUE FAZ
#   1. Instala faster-whisper (STT) e Piper (TTS) — 100% local, nada sai da rede
#   2. Cria gateway/app/voz.py       — transcricao + sintese
#   3. Cria gateway/app/routes/voz.py — endpoints /api/voz/*
#   4. Registra a rota no main.py
#   5. Adiciona docs/canal-voz.md a KB e liga no system_prompt
#   6. Aplica o patch de UI (botao de microfone + player) no frontend
#
#  DESENHO (o ponto central)
#   Pergunta por voz nao pode esperar 3 minutos em silencio. Entao a resposta
#   vem em DUAS ETAPAS:
#     (a) ACK imediato (~2s) — "Buscando o faturamento da Thai Avare, ja te
#         retorno." Confirma que entendeu ANTES de gastar minutos. Se entendeu
#         errado, voce corrige na hora.
#     (b) Resposta final — texto completo na tela + resumo falado de 2-3 frases.
#
#   O agente passa a produzir DUAS saidas quando o canal e voz: a visual
#   (tabela, como hoje) e a falada (arredondada, com a leitura de gestao),
#   delimitada por <FALA>...</FALA>. Ler tabela em voz alta e insuportavel.
#
#  Rodar da raiz do repo:  bash instala-voz.sh
# ============================================================================
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
STAMP=$(date +%Y%m%d-%H%M%S)
echo "== Dealer.ia · feature de voz =="

# ---------------------------------------------------------------------------
# 0. Guarda-corpos
# ---------------------------------------------------------------------------
test -f gateway/app/main.py || { echo "ERRO: rode da raiz do repo"; exit 1; }
git diff --quiet || echo ">> AVISO: ha alteracoes nao commitadas"

# ---------------------------------------------------------------------------
# 1. Dependencias de sistema e Python
# ---------------------------------------------------------------------------
echo
echo "[1/6] dependencias"
sudo apt-get update -qq
sudo apt-get install -y -qq ffmpeg  # decodifica webm/ogg do navegador

sudo pip3 install --break-system-packages -q \
  "faster-whisper>=1.0" "piper-tts>=1.2" "python-multipart>=0.0.9" || {
    echo "ERRO no pip. Se reclamar de conflito, ver cicatriz do python3-jwt."; exit 1; }

# Modelo de voz PT-BR do Piper (~63 MB)
VOZ_DIR=/opt/piper-vozes
sudo mkdir -p "$VOZ_DIR"
if [ ! -f "$VOZ_DIR/pt_BR-faber-medium.onnx" ]; then
  echo "  baixando voz pt_BR-faber-medium..."
  BASE=https://huggingface.co/rhasspy/piper-voices/resolve/main/pt/pt_BR/faber/medium
  sudo curl -fsSL -o "$VOZ_DIR/pt_BR-faber-medium.onnx"      "$BASE/pt_BR-faber-medium.onnx"
  sudo curl -fsSL -o "$VOZ_DIR/pt_BR-faber-medium.onnx.json" "$BASE/pt_BR-faber-medium.onnx.json"
fi
sudo chmod -R a+r "$VOZ_DIR"
ls -la "$VOZ_DIR"

mkdir -p /var/ebd-ia/audio && chmod 755 /var/ebd-ia/audio

# ---------------------------------------------------------------------------
# 2. gateway/app/voz.py — STT + TTS
# ---------------------------------------------------------------------------
echo
echo "[2/6] gateway/app/voz.py"
cat > gateway/app/voz.py <<'PYEOF'
"""voz.py — transcricao (Whisper) e sintese (Piper) locais.

Nada sai da rede: sao conversas sobre faturamento das 31 concessionarias.

Modelos carregam sob demanda (lazy) e ficam em memoria. O primeiro uso paga
uns 10s; os seguintes sao rapidos.
"""
from __future__ import annotations

import logging
import os
import re
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
    proc = subprocess.run(
        ["python3", "-m", "piper", "--model", VOZ_TTS,
         "--output_file", str(destino)],
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
PYEOF
python3 -c "import ast; ast.parse(open('gateway/app/voz.py').read()); print('  sintaxe ok')"

# ---------------------------------------------------------------------------
# 3. gateway/app/routes/voz.py — endpoints
# ---------------------------------------------------------------------------
echo
echo "[3/6] gateway/app/routes/voz.py"
cat > gateway/app/routes/voz.py <<'PYEOF'
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

from gateway.app.auth import verify_token
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

        window = await db.build_model_window(conv_id, user_id) if conv_id else []
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

        if conv_id:
            await db.add_message(conv_id, "assistant", {"text": visual})

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

    if conversation_id:
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
PYEOF
python3 -c "import ast; ast.parse(open('gateway/app/routes/voz.py').read()); print('  sintaxe ok')"

# ---------------------------------------------------------------------------
# 4. Registrar a rota no main.py
# ---------------------------------------------------------------------------
echo
echo "[4/6] registrando a rota"
cp gateway/app/main.py "gateway/app/main.py.bak-$STAMP"
python3 - <<'PY'
import pathlib, re
p = pathlib.Path("gateway/app/main.py")
t = p.read_text(encoding="utf-8")
if "routes import voz" not in t:
    t = t.replace("from gateway.app.routes import mercado",
                  "from gateway.app.routes import mercado\nfrom gateway.app.routes import voz as voz_routes", 1)
    m = re.search(r'app\.include_router\(\s*mercado\.router[^\)]*\)', t)
    if m:
        linha = m.group(0)
        prefixo = "/api" if 'prefix="/api"' in linha else None
        novo = linha + ('\napp.include_router(voz_routes.router, prefix="/api")'
                        if prefixo else '\napp.include_router(voz_routes.router)')
        t = t.replace(linha, novo, 1)
        print("  include_router inserido")
    else:
        print("  ATENCAO: nao achei o include_router do mercado — registrar a mao")
    p.write_text(t, encoding="utf-8")
else:
    print("  ja registrado")
PY
python3 -c "import ast; ast.parse(open('gateway/app/main.py').read()); print('  sintaxe ok')"
grep -n "voz" gateway/app/main.py

# ---------------------------------------------------------------------------
# 5. KB: regras do canal de voz
# ---------------------------------------------------------------------------
echo
echo "[5/6] docs/canal-voz.md + system_prompt"
cat > docs/canal-voz.md <<'MDEOF'
# canal-voz.md — como responder quando a pergunta veio por voz

Quando o contexto disser `CANAL: voz`, a resposta tem **duas partes**.

## 1. A resposta visual (como sempre)
Segue o `formato-resposta.md`: tabela, quebras, pontos de atenção. Vai para a
tela e fica registrada na conversa.

## 2. O bloco falado — OBRIGATÓRIO

No **fim** da resposta, acrescente:

```
<FALA>
Duas ou três frases, no máximo. É isso que a pessoa vai ouvir.
</FALA>
```

### Como escrever o bloco falado

- **Arredonde.** "oitenta e cinco mil" e não "oitenta e cinco mil seiscentos e
  quarenta e sete reais e treze centavos". Quem quer o centavo lê na tela.
- **No máximo 3 números.** Ninguém retém mais que isso de ouvido.
- **Comece pelo que importa**, não pelo contexto. "Caiu 42% em agosto" antes de
  "no período de 1 a 26 de agosto de 2026".
- **Diga a leitura, não só o dado.** "A oficina puxou a queda" vale mais que
  três percentuais em sequência.
- **Sem markdown, sem sigla, sem código.** Nada de `COD_EMPRESA`, `**`, `|`.
- **Frase curta.** Ponto final a cada 15 palavras, mais ou menos.

### Exemplos

✅ **Bom**
> Thai Avaré fechou agosto com 1,2 milhão de faturamento, 8% acima de julho. A
> oficina foi o destaque, com alta de 15%. O ponto de atenção é o estoque, com
> 40 carros parados há mais de 90 dias.

❌ **Ruim** (lê a tabela)
> Peças balcão, R$ 85.647,13, 34 notas, menos 42%. Peças oficina, R$ 415.078,31,
> 153 notas, menos 63%. Veículos novos, 10 unidades, R$ 4,70 milhões.

❌ **Ruim** (não diz nada)
> Consultei os dados e encontrei as informações solicitadas. Confira na tela.

## 3. Se a consulta falhar

O bloco falado também é obrigatório no erro, e deve ser direto:

```
<FALA>
Não consegui esse número: a base do DealerNet não respondeu. Tenta de novo em
alguns minutos.
</FALA>
```

## 4. O que NÃO fazer

- Não repetir a tabela em prosa dentro do `<FALA>`
- Não soletrar código de empresa, chassi, número de nota ou CNPJ
- Não passar de 3 frases — a pessoa desliga
MDEOF

python3 - <<'PY'
import pathlib
p = pathlib.Path("core/app/system_prompt.py")
t = p.read_text(encoding="utf-8")
if "canal-voz.md" not in t:
    alvo = '    "formato-resposta.md",'
    if alvo in t:
        t = t.replace(alvo, alvo + '\n    "canal-voz.md",            # regras do canal de voz', 1)
    else:
        t = t.replace('    "knowledge.md",',
                      '    "canal-voz.md",            # regras do canal de voz\n    "knowledge.md",', 1)
    p.write_text(t, encoding="utf-8")
    print("  canal-voz.md no KB_FILES")
else:
    print("  ja estava no KB_FILES")
PY
python3 -c "import ast; ast.parse(open('core/app/system_prompt.py').read()); print('  sintaxe ok')"

# ---------------------------------------------------------------------------
# 6. Frontend — botao de microfone e player
# ---------------------------------------------------------------------------
echo
echo "[6/6] frontend"
cp frontend/src/App.tsx "frontend/src/App.tsx.bak-$STAMP"
cat > frontend/src/VozButton.tsx <<'TSXEOF'
import { useState, useRef } from "react";

const API = import.meta.env.VITE_API_BASE_URL || "";

type Props = {
  token: string;
  conversationId?: string | null;
  onTranscricao: (texto: string) => void;
  onResposta: (texto: string) => void;
};

/** Botao de microfone: grava, envia, toca o ACK e depois a resposta. */
export default function VozButton({ token, conversationId, onTranscricao, onResposta }: Props) {
  const [estado, setEstado] = useState<"parado" | "gravando" | "enviando" | "aguardando">("parado");
  const rec = useRef<MediaRecorder | null>(null);
  const pedacos = useRef<Blob[]>([]);

  async function tocar(nome: string) {
    const r = await fetch(`${API}/api/voz/audio/${nome}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    const url = URL.createObjectURL(await r.blob());
    const a = new Audio(url);
    await a.play().catch(() => {});
    a.onended = () => URL.revokeObjectURL(url);
  }

  async function iniciar() {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    pedacos.current = [];
    const mr = new MediaRecorder(stream, { mimeType: "audio/webm" });
    mr.ondataavailable = (e) => e.data.size && pedacos.current.push(e.data);
    mr.onstop = async () => {
      stream.getTracks().forEach((t) => t.stop());
      setEstado("enviando");
      const fd = new FormData();
      fd.append("audio", new Blob(pedacos.current, { type: "audio/webm" }), "p.webm");
      const url = `${API}/api/voz/perguntar` +
        (conversationId ? `?conversation_id=${conversationId}` : "");
      try {
        const r = await fetch(url, {
          method: "POST",
          headers: { Authorization: `Bearer ${token}` },
          body: fd,
        });
        if (!r.ok) throw new Error(await r.text());
        const d = await r.json();
        onTranscricao(d.texto);
        tocar(d.ack_audio);              // "ja te retorno"
        setEstado("aguardando");
        // polling ate a resposta ficar pronta
        const t0 = Date.now();
        const timer = setInterval(async () => {
          if (Date.now() - t0 > 5 * 60 * 1000) { clearInterval(timer); setEstado("parado"); return; }
          const rr = await fetch(`${API}/api/voz/resultado/${d.job_id}`, {
            headers: { Authorization: `Bearer ${token}` },
          });
          if (!rr.ok) return;
          const j = await rr.json();
          if (j.status === "pronto") {
            clearInterval(timer);
            onResposta(j.texto);
            tocar(j.audio);
            setEstado("parado");
          } else if (j.status === "erro") {
            clearInterval(timer);
            onResposta(`Erro: ${j.erro}`);
            setEstado("parado");
          }
        }, 2500);
      } catch (e: any) {
        onResposta(`Erro no envio do audio: ${e.message || e}`);
        setEstado("parado");
      }
    };
    mr.start();
    rec.current = mr;
    setEstado("gravando");
  }

  function parar() {
    rec.current?.stop();
  }

  const rotulo = { parado: "🎤", gravando: "⏹", enviando: "…", aguardando: "🔎" }[estado];
  const titulo = {
    parado: "Perguntar por voz",
    gravando: "Gravando — clique para enviar",
    enviando: "Transcrevendo…",
    aguardando: "Buscando a resposta…",
  }[estado];

  return (
    <button
      type="button"
      className="voz-btn"
      title={titulo}
      disabled={estado === "enviando"}
      onClick={estado === "gravando" ? parar : estado === "parado" ? iniciar : undefined}
      style={{
        border: "none", background: "transparent", cursor: "pointer",
        fontSize: 20, opacity: estado === "enviando" ? 0.5 : 1,
      }}
    >
      {rotulo}
    </button>
  );
}
TSXEOF
echo "  VozButton.tsx criado"

cat <<'NOTA'

  >> O botao NAO foi plugado automaticamente no App.tsx.
     A area do input varia; plugar as cegas quebra o build.
     Para ligar, no App.tsx:

       import VozButton from "./VozButton";

     e, dentro da barra do input (perto do botao de enviar):

       <VozButton
         token={token}
         conversationId={convId}
         onTranscricao={(t) => setInput(t)}
         onResposta={(t) => console.log(t)}
       />

     Trocar `token` e `convId` pelos nomes reais no seu escopo.
NOTA

# ---------------------------------------------------------------------------
# Fim
# ---------------------------------------------------------------------------
echo
echo "=============================================="
echo " Instalado. Para ativar:"
echo
echo "   pkill -f 'uvicorn gateway.app.main'; sleep 1"
echo "   nohup python3 -m uvicorn gateway.app.main:app --host 0.0.0.0 --port 8000 > /tmp/gw.log 2>&1 &"
echo
echo " Teste do STT/TTS sem passar pelo gateway:"
echo "   python3 -c \"import sys; sys.path.insert(0,'gateway');"
echo "   from app.voz import sintetizar, montar_ack;"
echo "   print(sintetizar(montar_ack('como foi a oficina da thai avare')))\""
echo
echo " Backups: *.bak-$STAMP"
echo "=============================================="
