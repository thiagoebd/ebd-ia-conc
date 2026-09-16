# Dealer.ia

Agente conversacional das **concessionárias do Grupo EBD**. Responde perguntas
de gestão em linguagem natural consultando diretamente os DMS da operação.

> Produto irmão do [EBD.ia](https://github.com/thiagoebd/ebd-ia), que atende a
> frente de distribuição. Mesmo arcabouço, negócio diferente — e nenhuma
> sobreposição de dado.

---

## O que faz

Um gestor pergunta *"como foi a oficina da Thai Avaré em agosto?"* e recebe
faturamento, passagens, ticket médio e comparativo com o período anterior — sem
abrir relatório, sem pedir para a TI, sem exportar planilha.

O agente resolve o nome (*"Thai Avaré"* → DealerNet, empresa 2), escolhe o
sistema certo, escreve o SQL, executa em modo somente-leitura e devolve a
leitura de gestão. Quando a pergunta não cita unidade, consolida o grupo
inteiro e mostra a quebra por marca.

---

## Anexos — imagem e planilha

**Foto de veículo.** O gestor manda a foto e pergunta se o carro está no
estoque. O agente identifica marca e modelo, lê **placa** e **chassi** quando
visíveis, e consulta o DMS: é nosso? está no pátio? novo ou seminovo? já
passou pela oficina? Se a placa for de campanha ou a foto for de divulgação,
ele diz isso em vez de fingir que achou.

A placa é reconhecida nos dois formatos — `ABC1234` (antigo) e `ABC1D23`
(Mercosul) — e o agente descobre sozinho se recebeu placa, chassi, código ou
nome.

**Planilha (xlsx, csv, multi-aba).** A planilha **nunca entra no prompt**: vai
para o Postgres e o agente recebe só o resumo — colunas, tipos, contagem e
três exemplos, cerca de 200 tokens seja de 50 ou 50.000 linhas.

O cruzamento acontece em Python, em blocos de 1.000 chaves (limite do `IN` do
Oracle), com normalização do que o Excel destrói: zero à esquerda comido,
EAN em notação científica, inteiro virando `123.0`.

Arquivo com várias abas: o agente mostra quais são, com o tamanho de cada, e
pergunta em qual trabalhar.

**Resolução de nome.** Planilha com *"joão silva"* em vez do código: a busca é
por tokens e casa com *"JOÃO PEDRO SILVA"*. O resultado vem em três grupos —
resolvido, ambíguo e não achado. **Com mais de um candidato o agente mostra e
pergunta**, nunca escolhe. E sempre diz quantas linhas casaram e quantas não.

---

## Cobertura

**31 concessionárias · 7 marcas · 5 estados · 2 DMS**

| DMS | Banco | Concessionárias | Marcas |
| --- | --- | --- | --- |
| **NBS** | Oracle | 1 — ISAR MOTORS (Teresina/PI) | BMW · Motorrad · Mini |
| **DealerNet Workflow** | SQL Server | 30 | Toyota · Fiat · Jeep · Hyundai · Ford · Leapmotor |

Razões sociais no DealerNet: Bacaba (Thai/Toyota), Via Marconi (VM/Fiat,
Way/Jeep, Leapmotor), Viale (Fiat), Antares (Ford), Miso (Hyundai).
Estados: AP, PA, AM, SP, PI.

---

## Arquitetura

```
┌──────────────┐   SSE    ┌─────────────┐        ┌──────────────────┐
│  React 19    │◄────────►│   Gateway   │◄──────►│  Agente (core)   │
│  MSAL/Entra  │          │  FastAPI    │        │  loop de tools   │
└──────────────┘          └──────┬──────┘        └────────┬─────────┘
                                 │                        │
                          ┌──────▼──────┐        ┌────────▼─────────┐
                          │  Postgres   │        │   MCP NBS  :8990 │──► Oracle
                          │  ACL, chat  │        │   MCP DN   :8991 │──► SQL Server
                          └─────────────┘        └──────────────────┘
```

**MCPs irmãos, não genéricos.** Cada DMS tem servidor próprio, com dialeto,
driver e modelo separados. O agente recebe **duas tools** (`oracle_query` e
`dealernet_query`) em vez de uma com parâmetro de fonte — assim é impossível
mandar sintaxe Oracle para o T-SQL, em vez de apenas improvável.

**Somente leitura, comprovado no banco.** Os usuários de consulta não têm
nenhum privilégio de escrita — verificado em `all_tab_privs` (Oracle) e
`fn_my_permissions` (SQL Server). O SQL Guard da aplicação é a segunda camada,
não a única.

### Base de conhecimento em três camadas

| Camada | Arquivo | Papel |
| --- | --- | --- |
| 0 · Roteador | `docs/CLAUDE.md` | mapa unidade→DMS→código, regra de decisão, consolidação |
| 1 · Por DMS | `docs/dms/CLAUDE-*.md` | modelo, entidades, joins canônicos de cada banco |
| 2 · Operação | `sql-corrections.md`, `query_templates.md`, `formato-resposta.md` | cicatrizes, templates validados, padrão de resposta |

### Auto-evolução

Quando o agente descobre uma armadilha do banco, ele **propõe** uma cicatriz.
Um admin aprova no chat com `/aprovar PROP-XXXX`, e ela vira commit, entra na
branch `agent-proposals`, faz merge na `main` e é recarregada no prompt em
memória — sem restart.

Exemplo real: o agente errou ao filtrar `Empresa_Codigo` na tabela
`NotaFiscal`, descobriu que ali a coluna é `NotaFiscal_EmpresaCod`, e a
cicatriz `#D11` corrigiu a documentação que um humano tinha escrito errado.

---

## Anti-fabricação

Um agente que inventa número é pior que nenhum agente. Três mecanismos:

- **`grounding.py`** — mede quantos números da resposta têm lastro nos
  resultados das consultas do turno. Sem lastro, a resposta é bloqueada.
- **`preflight.py`** — recusa coluna inexistente antes de ir ao banco.
  (74% dos erros do agente eram `ORA-00904` no produto irmão.)
- **`loop_policy.py`** — falha *consecutiva*, não cumulativa: fecha com dado
  parcial em vez de descartar nove consultas boas por causa da décima.

E uma regra dura no prompt: **não encontrou, diz que não encontrou e para.**

---

## Validação

Template só entra no catálogo depois de bater com número de referência externo.
Estado atual (competência julho/2026, ISAR MOTORS, conferido contra o DealerUp):

| Indicador | Dealer.ia | Referência |
| --- | --- | --- |
| Faturamento peças balcão | R$ 85.647,13 / 34 notas | idêntico |
| Faturamento peças oficina | R$ 415.078,31 / 153 notas | idêntico |
| Margem peças balcão | R$ 18.020,23 | R$ 18.020,19 |
| Margem peças oficina | R$ 114.070,60 | R$ 114.070,65 |

Indicadores sem validação ficam marcados como exploratórios, e o agente avisa.

---

## Stack

- **Runtime** — Ubuntu 24.04, Docker + Compose v2
- **LLM** — DeepSeek (compatível Anthropic Messages API)
- **Backend** — Python 3.12, FastAPI, Postgres 16, Redis
- **Frontend** — React 19 + Vite, MSAL (Entra ID)
- **Dados** — Oracle (`python-oracledb`, thin) · SQL Server (`pymssql`)
- **Voz** — `faster-whisper` (STT) + Piper pt-BR (TTS), 100% local
- **Observabilidade** — Grafana, Prometheus, Loki, Tempo
- **Artefatos** — Excel, PDF, PPTX, gráficos, mapas
- **Anexos** — imagem (visão do `deepseek-flash`) e planilha (pandas + calamine)

---

## Canal de voz

Pergunta falada não pode esperar em silêncio. A resposta vem em duas etapas:

1. **ACK em ~2s** — *"Ok. Buscando os dados de oficina da Thai Avaré. Já te
   retorno."* Montado da própria transcrição, sem chamar o modelo. Funciona
   como confirmação implícita: se entendeu errado, você corrige na hora.
2. **Resposta** — texto completo na tela e um resumo falado de 2-3 frases,
   arredondado. Ler tabela em voz alta é insuportável, então o agente produz
   as duas saídas separadamente.

Transcrição e síntese rodam no servidor. Nenhum áudio sai da rede.

---

## Operação

### Reiniciar o gateway

`systemctl restart` sozinho **não basta**. O processo antigo pode continuar
segurando a porta 8000, o novo morre com `address already in use`, e o systemd
reporta `active` enquanto o código velho responde.

```bash
sudo systemctl stop concia-gateway
sudo pkill -f "uvicorn gateway.app.main"
sleep 3
sudo systemctl start concia-gateway
sleep 8
systemctl is-active concia-gateway
sudo lsof -i :8000 -sTCP:LISTEN -P -n    # um PID só
```

O gateway **não roda em container** — é serviço systemd com o Python do
sistema. Biblioteca nova precisa de
`sudo pip3 install --break-system-packages`.

### Depois de mexer no frontend

```bash
cd frontend && npm run build
```

E `Ctrl+Shift+R` no navegador — o bundle muda de nome, mas o `index.html` fica
em cache.

### Trocar o modelo

O nome do modelo vive em cinco arquivos (`core/.env`, `models_catalog.py`,
`config.py`, o `DEFAULT` da coluna em `db.py` e o `App.tsx`). Trocar em um só
deixa o sistema inconsistente.

```bash
bash scripts/troca_modelo.sh                   # só diagnostica
bash scripts/troca_modelo.sh deepseek-flash    # troca em todos
```

| Modelo | Lê imagem |
| --- | --- |
| `deepseek-flash` | **sim** — padrão |
| `deepseek-v4-pro` | não |

> **14/09/2026** — o `deepseek-flash` parou de responder por horas:
> requisição travando sem erro nem timeout, enquanto o `v4-pro` respondia em
> 1,7s. O painel de status do DeepSeek mostrava tudo verde. Se o agente travar
> em "Pensando…", rode o `troca_modelo.sh` sem argumento antes de procurar bug
> no código.

### Logs

```bash
journalctl -u concia-gateway --since "10 min ago" --no-pager
docker compose logs --tail 50 mcp-nbs
```

---

## Documentação

```
docs/
├── CLAUDE.md                    roteador multi-DMS
├── knowledge.md                 vocabulário de concessionária
├── sql-corrections.md           cicatrizes (armadilhas do banco)
├── query_templates.md           templates validados
├── formato-resposta.md          padrão de resposta executiva
├── canal-voz.md                 regras do canal de voz
├── dms/                         base de conhecimento por DMS
├── adr/                         decisões de arquitetura
└── referencia/                  mapa do BI atual do grupo
```

---

## Responsável

**Thiago Martins Parreira** — TI / Grupo EBD

---

*Projeto interno do Grupo EBD.*
