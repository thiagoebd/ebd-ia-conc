# ADR 002 — Arquitetura multi-DMS (NBS + DealerNet)

> Decisão de 25/08/2026. Substitui a premissa de DMS único do ADR 001.
> Contexto: o Conc.ia passa a atender **31 concessionárias** — 1 no NBS
> (ISAR/BMW) e 30 no DealerNet (Toyota, Fiat, Jeep, Hyundai, Ford, Leapmotor).

---

## 1. O problema

O agente hoje tem **uma** tool (`oracle_query`) e **um** KB carregado inteiro no
prompt. Com dois DMS surgem três problemas novos:

1. **Roteamento** — "faturamento de julho" precisa saber *de quem*: Isar? Thai
   Macapá? o grupo todo?
2. **Custo de contexto** — carregar os dois KBs em todo turno dobra o prompt
   (hoje 23 KB) sem ganho: 90% das perguntas tocam um DMS só.
3. **Consolidação** — "total de veículos novos do grupo" exige somar os dois,
   com definições que **não são idênticas** (`NATUREZA_APLICACAO='F'` no NBS vs.
   `NaturezaOperacao=11` no DealerNet).

---

## 2. Decisão: KB em três camadas

```
┌──────────────────────────────────────────────────────────┐
│ CAMADA 0 — ROTEADOR (sempre no prompt, ~2 KB)            │
│ • quais DMS existem e o que cada um cobre                │
│ • mapa concessionária → DMS → código                     │
│ • regra de decisão: 1 DMS, 2 DMS ou perguntar            │
│ • glossário de negócio agnóstico (o que é "passagem")    │
├──────────────────────────────────────────────────────────┤
│ CAMADA 1 — KB DO DMS (sob demanda, via tool)             │
│ • CLAUDE-nbs.md      → carregado se a pergunta é NBS     │
│ • CLAUDE-dealernet.md → carregado se é DealerNet         │
│ • cicatrizes e templates de cada um                      │
├──────────────────────────────────────────────────────────┤
│ CAMADA 2 — CONTRATO DE INDICADOR (agnóstico)             │
│ • definição de negócio + adaptador por DMS               │
│ • é o que permite somar os dois sem misturar regra       │
└──────────────────────────────────────────────────────────┘
```

**Por que não carregar tudo:** o EBD.ia chegou a 315 KB de KB e paga isso em
todo turno. Aqui, com dois DMS, o caminho é o oposto — prompt enxuto que
**sabe onde buscar**, e busca só o necessário.

---

## 3. Camada 0 — o roteador

Conteúdo (arquivo `docs/CLAUDE.md`, sempre no prompt):

### Mapa de unidades

| Concessionária | Marca | DMS | Código |
| --- | --- | --- | --- |
| ISAR MOTORS (Teresina/PI) | BMW · Motorrad · Mini | **NBS** | `COD_EMPRESA=1` |
| THAI (8 unidades) | Toyota | **DealerNet** | `Empresa_Codigo` 1-6, 27, 29 |
| VIA MARCONI (14) | Fiat · Jeep · Leapmotor | **DealerNet** | 9-22, 28, 30 |
| MISO (2) | Hyundai | **DealerNet** | 7, 8 |
| VIALE (2) | Fiat | **DealerNet** | 23, 26 |
| ANTARES (2) | Ford | **DealerNet** | 24, 25 |

> ⚠️ **Os códigos de empresa COLIDEM entre os DMS.** `Empresa_Codigo = 1` no
> DealerNet é THAI MACAPA; `COD_EMPRESA = 1` no NBS é ISAR. Nunca falar de
> "empresa 1" sem dizer o DMS.

### Regra de decisão

1. Pergunta cita **marca ou unidade** → resolve o DMS pelo mapa acima.
   ("como foi a oficina da Thai Ananindeua" → DealerNet, empresa 3)
2. Pergunta cita **BMW/Motorrad/Mini/Isar** → NBS.
3. Pergunta diz **"grupo", "todas", "consolidado", "total"** → os DOIS,
   via indicador consolidado (seção 5).
4. Pergunta **ambígua e sem escopo** → responder com o escopo do usuário
   (do `acl_users`); se ele tem acesso a ambos, perguntar qual antes de gastar
   consulta.

---

## 4. Duas tools, não uma

```python
NBS_QUERY_TOOL        # Oracle · schema NBS · ISAR/BMW
DEALERNET_QUERY_TOOL  # SQL Server · GrupoEBD_DealernetWF · 30 concessionárias
```

**Por que separadas:** o modelo escolhe pela descrição, e os dialetos são
diferentes o bastante (`FETCH FIRST` vs `TOP`, `SYSDATE` vs `GETDATE()`,
`NVL` vs `ISNULL`) para que uma tool com parâmetro `fonte` produza SQL
misturado. Tool separada = erro impossível, não improvável.

Cada tool traz na descrição o **resumo do dialeto e das 3 regras principais**,
para o agente acertar sem carregar o KB inteiro.

### Tool auxiliar: `carregar_kb(dms)`

Retorna o KB completo daquele DMS (CLAUDE + cicatrizes + templates).
O agente chama quando a pergunta é não-trivial. Perguntas com template
validado não precisam — o template já vem no catálogo.

---

## 5. Consolidação — o problema difícil

"Total de veículos novos vendidos no grupo em julho" exige:

```
NBS:        VENDAS + NATUREZA_APLICACAO='F' + STATUS='0'     → 10 unidades
DealerNet:  NotaFiscal + NaturezaOperacao=11 + Status='EMI'
            + Movimento='S'                                   → N unidades
                                                     TOTAL = soma
```

As definições **não são a mesma query traduzida** — são duas regras de negócio
que produzem a mesma grandeza. É exatamente o que o **contrato de indicador**
(ADR 001) resolve.

### Regras de consolidação

1. **Só consolida indicador com contrato e adaptador validado nos DOIS DMS.**
   Sem isso, responder separado e dizer que a soma não está validada.
2. **Sempre mostrar a quebra**, nunca só o total:
   ```
   Veículos novos — julho/2026
   NBS (ISAR/BMW)        10
   DealerNet (30 conc.)  NNN
   ─────────────────────────
   TOTAL                 NNN
   ```
   O gestor precisa ver de onde veio; total isolado esconde erro.
3. **Competência e status precisam ser equivalentes.** Data de emissão da nota
   nos dois; status "válido" em cada um (`'0'` vs `'EMI'`).
4. **Nunca somar o que não é comparável.** Margem no NBS é líquida de tributos
   (validado); no DealerNet ainda não sabemos. Até validar, não somar margem.

---

## 6. ACL com dois DMS

O `acl_users.filiais` hoje é campo único (`"*"` ou lista). Precisa virar escopo
por DMS:

```json
{
  "nbs": [1],
  "dealernet": [9, 10, 12, 13]
}
```

Ou `"*"` para acesso total. Migração `006_acl_multi_dms.sql`:
- coluna nova `escopo` jsonb
- `filiais` mantida por compatibilidade (o `acl.py` lê a nova, cai na antiga)
- tela de Acessos ganha seleção por DMS

**Enquanto não migrar:** `"*"` continua valendo para ambos, e quem tem escopo
restrito só enxerga NBS. É degradação segura.

---

## 7. Ordem de implementação

| # | Item | Depende de |
| --- | --- | --- |
| 1 | `mcps/dealernet` (clone do nbs, pymssql, T-SQL) | — |
| 2 | `config.py` com dois pares URL/token | 1 |
| 3 | `DEALERNET_QUERY_TOOL` no agente | 2 |
| 4 | `docs/CLAUDE.md` vira roteador; KBs para `docs/dms/` | — |
| 5 | `carregar_kb(dms)` como tool | 4 |
| 6 | Validar 3 indicadores no DealerNet contra o BI | 3 |
| 7 | Consolidação (contratos com dois adaptadores) | 6 |
| 8 | ACL multi-DMS | 3 |

Os itens 1-5 são de infraestrutura e não dependem de validação de número —
podem sair hoje. Os 6-7 exigem número de referência do gestor.

---

## 8. O que NÃO fazer

- **Não** criar um MCP genérico que fale os dois bancos. Dialeto, driver e
  modelo são diferentes; abstrair custa mais que duplicar.
- **Não** traduzir SQL de um DMS para o outro. O contrato é de negócio, não
  de sintaxe.
- **Não** somar indicador sem adaptador validado nos dois lados. Número errado
  consolidado é pior que resposta separada.
- **Não** carregar os dois KBs no prompt por padrão. Custo em todo turno para
  ganho em 10% deles.
