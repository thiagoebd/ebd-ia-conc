#!/usr/bin/env bash
# ============================================================
# Pluga o botao de voz no App.tsx e ajusta o backend do canal voz.
# Rodar da raiz do repo: bash pluga-voz-front.sh
# ============================================================
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
STAMP=$(date +%Y%m%d-%H%M%S)
cp frontend/src/App.tsx "frontend/src/App.tsx.bak-$STAMP"

# ------------------------------------------------------------
# 1. VozButton.tsx — versao integrada ao fluxo do App
# ------------------------------------------------------------
cat > frontend/src/VozButton.tsx <<'TSXEOF'
import { useState, useRef } from "react";

type Props = {
  apiBase: string;
  getToken: () => Promise<string>;
  conversationId: string | null;
  onPergunta: (texto: string) => void;              // mostra a fala do usuario
  onAck: (texto: string) => void;                   // "ja te retorno"
  onResposta: (texto: string, erro?: boolean) => void;
  disabled?: boolean;
};

/** Microfone: grava -> transcreve -> ACK falado -> resposta falada. */
export default function VozButton({
  apiBase, getToken, conversationId, onPergunta, onAck, onResposta, disabled,
}: Props) {
  const [estado, setEstado] = useState<"parado" | "gravando" | "enviando" | "aguardando">("parado");
  const rec = useRef<MediaRecorder | null>(null);
  const pedacos = useRef<Blob[]>([]);
  const timer = useRef<number | null>(null);

  async function tocar(nome: string) {
    try {
      const tok = await getToken();
      const r = await fetch(`${apiBase}/api/voz/audio/${nome}`, {
        headers: { Authorization: `Bearer ${tok}` },
      });
      if (!r.ok) return;
      const url = URL.createObjectURL(await r.blob());
      const a = new Audio(url);
      a.onended = () => URL.revokeObjectURL(url);
      await a.play().catch(() => {});
    } catch { /* audio e complemento, nunca bloqueia */ }
  }

  async function iniciar() {
    let stream: MediaStream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch {
      onResposta("Preciso de permissao do microfone para ouvir voce.", true);
      return;
    }
    pedacos.current = [];
    const mime = MediaRecorder.isTypeSupported("audio/webm")
      ? "audio/webm" : "audio/mp4";
    const mr = new MediaRecorder(stream, { mimeType: mime });
    mr.ondataavailable = (e) => { if (e.data.size) pedacos.current.push(e.data); };
    mr.onstop = async () => {
      stream.getTracks().forEach((t) => t.stop());
      setEstado("enviando");
      const blob = new Blob(pedacos.current, { type: mime });
      if (blob.size < 2000) { setEstado("parado"); return; }   // clique sem fala

      const fd = new FormData();
      fd.append("audio", blob, mime.includes("webm") ? "p.webm" : "p.m4a");
      const qs = conversationId && !conversationId.startsWith("tmp-")
        ? `?conversation_id=${conversationId}` : "";
      try {
        const tok = await getToken();
        const r = await fetch(`${apiBase}/api/voz/perguntar${qs}`, {
          method: "POST",
          headers: { Authorization: `Bearer ${tok}` },
          body: fd,
        });
        if (!r.ok) throw new Error(`HTTP ${r.status}: ${(await r.text()).slice(0, 200)}`);
        const d = await r.json();

        onPergunta(d.texto);
        onAck(d.ack_texto);
        tocar(d.ack_audio);
        setEstado("aguardando");

        const t0 = Date.now();
        timer.current = window.setInterval(async () => {
          if (Date.now() - t0 > 6 * 60 * 1000) {
            clearInterval(timer.current!);
            onResposta("A consulta passou de 6 minutos e eu parei de esperar.", true);
            setEstado("parado");
            return;
          }
          try {
            const tk = await getToken();
            const rr = await fetch(`${apiBase}/api/voz/resultado/${d.job_id}`, {
              headers: { Authorization: `Bearer ${tk}` },
            });
            if (!rr.ok) return;
            const j = await rr.json();
            if (j.status === "pronto") {
              clearInterval(timer.current!);
              onResposta(j.texto);
              tocar(j.audio);
              setEstado("parado");
            } else if (j.status === "erro") {
              clearInterval(timer.current!);
              onResposta(`Nao consegui: ${j.erro}`, true);
              setEstado("parado");
            }
          } catch { /* rede instavel: tenta no proximo tick */ }
        }, 2500);
      } catch (e: any) {
        onResposta(`Erro no envio do audio: ${e?.message || e}`, true);
        setEstado("parado");
      }
    };
    mr.start();
    rec.current = mr;
    setEstado("gravando");
  }

  const rotulo = { parado: "🎤", gravando: "⏹", enviando: "⋯", aguardando: "🔎" }[estado];
  const titulo = {
    parado: "Perguntar por voz",
    gravando: "Gravando — clique para enviar",
    enviando: "Transcrevendo…",
    aguardando: "Buscando a resposta…",
  }[estado];

  return (
    <button
      type="button"
      className={`voz-btn ${estado}`}
      title={titulo}
      aria-label={titulo}
      disabled={disabled || estado === "enviando" || estado === "aguardando"}
      onClick={() => (estado === "gravando" ? rec.current?.stop() : estado === "parado" && iniciar())}
    >
      {rotulo}
    </button>
  );
}
TSXEOF
echo "  VozButton.tsx ok"

# ------------------------------------------------------------
# 2. App.tsx — import, handlers e o botao no composer
# ------------------------------------------------------------
python3 - <<'PY'
import pathlib, re
p = pathlib.Path("frontend/src/App.tsx")
t = p.read_text(encoding="utf-8")

# 2.1 import
if "VozButton" not in t:
    m = re.search(r'^import .*?;\n', t, re.M)
    t = t[:m.end()] + 'import VozButton from "./VozButton";\n' + t[m.end():]

# 2.2 handlers, logo antes da funcao send
alvo = "  async function send(presetQuestion?: string) {"
handlers = '''  // ---- canal de voz -------------------------------------------------
  function vozAbreThread(pergunta: string) {
    let tid = activeId;
    if (tid === null) {
      tid = `tmp-${Date.now()}`;
      const title = pergunta.length > 42 ? pergunta.slice(0, 42) + "…" : pergunta;
      setThreads((ts) => [{ id: tid!, title, msgs: [], loaded: true }, ...ts]);
      setActiveId(tid);
    }
    streamTidRef.current = tid;
    setThreads((ts) => ts.map((th) => th.id === tid
      ? { ...th, msgs: [...th.msgs, { role: "user", text: pergunta },
                        { role: "assistant", text: "", status: "Pensando", tools: [] }] }
      : th));
  }

  function vozAtualizaAssistente(texto: string, status?: string, tools?: string[]) {
    setThreads((ts) => ts.map((th) => {
      if (th.id !== streamTidRef.current) return th;
      const msgs = [...th.msgs];
      for (let i = msgs.length - 1; i >= 0; i--) {
        if (msgs[i].role === "assistant") {
          msgs[i] = { ...msgs[i], text: texto, status, tools: tools ?? msgs[i].tools };
          break;
        }
      }
      return { ...th, msgs };
    }));
  }

'''
assert t.count(alvo) == 1, "ancora de send() nao encontrada"
t = t.replace(alvo, handlers + alvo)

# 2.3 botao ao lado do textarea
alvo2 = '''                  rows={1}
                  disabled={busy}
                />'''
botao = '''                  rows={1}
                  disabled={busy}
                />
                <VozButton
                  apiBase={API_BASE}
                  getToken={token}
                  conversationId={activeId}
                  onPergunta={(txt) => { vozAbreThread(txt); setBusy(true); }}
                  onAck={(txt) => vozAtualizaAssistente("", txt)}
                  onResposta={(txt, erro) => {
                    vozAtualizaAssistente(txt, undefined, erro ? [] : ["voz"]);
                    setBusy(false);
                  }}
                  disabled={busy}
                />'''
assert t.count(alvo2) == 1, "ancora do textarea nao encontrada"
t = t.replace(alvo2, botao)

p.write_text(t, encoding="utf-8")
print("  App.tsx ok")
PY

# ------------------------------------------------------------
# 3. CSS do botao
# ------------------------------------------------------------
grep -q "\.voz-btn" frontend/src/App.css || cat >> frontend/src/App.css <<'CSSEOF'

/* ── Botão de voz ──────────────────────────────────────────────────────── */
.voz-btn {
  position: absolute; right: 52px; bottom: 54px;
  width: 34px; height: 34px; border: none; border-radius: 50%;
  background: transparent; cursor: pointer; font-size: 18px; line-height: 1;
  display: flex; align-items: center; justify-content: center;
  transition: background .15s ease, transform .1s ease;
}
.voz-btn:hover:not(:disabled) { background: rgba(0,0,0,.06); }
.voz-btn:disabled { opacity: .45; cursor: default; }
.voz-btn.gravando { background: rgba(220,38,38,.12); animation: voz-pulse 1.2s infinite; }
.voz-btn.aguardando { animation: voz-pulse 2s infinite; }
@keyframes voz-pulse { 0%,100% { transform: scale(1); } 50% { transform: scale(1.12); } }
CSSEOF
echo "  App.css ok"

# ------------------------------------------------------------
# 4. Backend: aceitar conversa nova (tmp-) e canal voz no prompt
# ------------------------------------------------------------
python3 - <<'PY'
import pathlib
p = pathlib.Path("gateway/app/routes/voz.py")
t = p.read_text(encoding="utf-8")
t = t.replace(
    '    if conversation_id:\n        try:\n            await db.add_message(conversation_id, "user", {"text": pergunta})',
    '    if conversation_id and not str(conversation_id).startswith("tmp-"):\n'
    '        try:\n            await db.add_message(conversation_id, "user", {"text": pergunta})')
t = t.replace(
    '        window = await db.build_model_window(conv_id, user_id) if conv_id else []',
    '        _cid = conv_id if conv_id and not str(conv_id).startswith("tmp-") else None\n'
    '        window = await db.build_model_window(_cid, user_id) if _cid else []')
t = t.replace('        if conv_id:\n            await db.add_message(conv_id, "assistant", {"text": visual})',
              '        if _cid:\n            await db.add_message(_cid, "assistant", {"text": visual})')
p.write_text(t, encoding="utf-8")
print("  voz.py: conversa nova tratada")
PY
python3 -c "import ast; ast.parse(open('gateway/app/routes/voz.py').read()); print('  sintaxe ok')"

# ------------------------------------------------------------
# 5. Build
# ------------------------------------------------------------
echo
echo "[build]"
cd frontend && npm run build 2>&1 | tail -8 && cd ..

echo
echo "=============================================="
echo " Pronto. Reinicie o gateway:"
echo "   pkill -f 'uvicorn gateway.app.main'; sleep 1"
echo "   nohup python3 -m uvicorn gateway.app.main:app --host 0.0.0.0 --port 8000 > /tmp/gw.log 2>&1 &"
echo
echo " O microfone so aparece em HTTPS (getUserMedia exige contexto seguro)."
echo " Acesse por https://conc.ebd.ia.br — nao pelo IP."
echo " Backup: frontend/src/App.tsx.bak-$STAMP"
echo "=============================================="
