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
