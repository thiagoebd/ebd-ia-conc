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
