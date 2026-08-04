# Indicadores de pós-venda — desenho agnóstico de DMS

> Objetivo: um mesmo indicador ("Faturamento Oficina") ter **uma definição só**,
> válida para NBS e DealerNet, com o SQL específico de cada base isolado numa
> camada fina de tradução.
> Base do catálogo: KPIs do BI atual da EBD (Inteligência de Pós-Venda v10).

---

## 1. O erro a evitar

O caminho natural — e errado — é escrever um `query_templates.md` por DMS. Isso
dá dois catálogos que divergem em seis meses: alguém corrige a regra de garantia
no NBS e esquece do DealerNet, e o mesmo indicador passa a significar coisas
diferentes em cada concessionária. Foi o que aconteceu no Winthor com as views
`GD_*` convivendo com as tabelas `PC*`.

**A definição do indicador é de negócio, não de banco.** Só o SQL muda.

---

## 2. Estrutura em três camadas

```
┌───────────────────────────────────────────────┐
│ 1. CONTRATO (um por indicador, agnóstico)     │  indicadores.yaml
│    codigo, nome, unidade, granularidade,      │
│    regra em português, o que inclui/exclui    │
├───────────────────────────────────────────────┤
│ 2. ADAPTADOR (um por DMS)                     │  adapters/nbs.sql
│    o SQL que materializa o contrato           │  adapters/dealernet.sql
├───────────────────────────────────────────────┤
│ 3. VALIDAÇÃO (por DMS + concessionária)       │  validacoes.md
│    número de referência conferido com quem    │
│    é dono do indicador na operação            │
└───────────────────────────────────────────────┘
```

O agente lê a camada 1 para **entender o que é pedido**, e a camada 2 para
**executar**. Se o adaptador do DMS não existe, ele responde que o indicador não
está disponível naquela base — em vez de improvisar SQL.

---

## 3. O contrato

Formato sugerido (`core/app/data/indicadores.yaml`):

```yaml
- codigo: FAT_OFICINA
  nome: Faturamento Oficina
  unidade: BRL
  granularidade: [empresa, mes]
  definicao: >
    Valor faturado de serviços e peças aplicados em ordem de serviço,
    excluindo balcão, funilaria e garantia de fábrica.
  inclui:
    - nota fiscal de saída vinculada a uma OS
    - peças requisitadas dentro da OS
  exclui:
    - venda de balcão (sem OS)
    - OS interna (débito da própria empresa)
    - OS de garantia (fábrica é quem paga)
    - notas canceladas e devolvidas
  dimensoes_opcionais: [consultor, tipo_os, marca]
  fonte_referencia: "Score Card mensal — gestor de pós-venda"
  adaptadores: [nbs]          # dealernet entra quando existir
```

O bloco `exclui` é a parte mais valiosa. É onde mora a diferença entre um número
certo e um número plausível — e é o que se perde quando a regra vive só no SQL.

---

## 4. O adaptador

Um arquivo por DMS, com o mesmo `codigo` e a mesma assinatura de saída:

```sql
-- adapters/nbs/FAT_OFICINA.sql
-- Contrato: FAT_OFICINA. Saída: EMPRESA, COMPETENCIA, VALOR
SELECT v.COD_EMPRESA                        AS EMPRESA,
       TO_CHAR(v.EMISSAO,'YYYY-MM')         AS COMPETENCIA,
       SUM(v.TOTAL_SERVICOS + v.TOTAL_PRODUTOS) AS VALOR
  FROM NBS.VENDAS v
  JOIN NBS.OS o        ON o.COD_EMPRESA = v.COD_EMPRESA
                      AND o.NUMERO_OS   = v.NUMERO_OS
  JOIN NBS.OS_TIPOS t  ON t.TIPO = o.TIPO
  JOIN NBS.NATUREZA n  ON n.COD_NATUREZA = v.COD_NATUREZA
 WHERE v.COD_EMPRESA = :empresa
   AND v.STATUS = '0'                     -- exclui cancelada/devolvida
   AND NVL(t.GARANTIA,'N') <> 'S'         -- exclui garantia de fábrica
   AND NVL(t.INTERNO ,'N') <> 'S'         -- exclui OS interna
   AND n.NATUREZA_APLICACAO = 'M'         -- O.S. prestação de serviço
   AND v.EMISSAO >= :dt_ini AND v.EMISSAO < :dt_fim
 GROUP BY v.COD_EMPRESA, TO_CHAR(v.EMISSAO,'YYYY-MM')
```

**Contrato de saída fixo** (`EMPRESA, COMPETENCIA, VALOR`, mais as dimensões
opcionais). Assim o mesmo código de apresentação, gráfico e Excel serve para
qualquer DMS, e comparar NBS com DealerNet vira `UNION ALL`.

> ⚠️ O SQL acima é **hipótese**, não está validado. Nasce como
> `validated: false` e só vira template canônico depois de bater com o número do
> gestor de pós-venda.

---

## 5. Catálogo inicial (do BI atual)

| Código | Indicador | Complexidade | Depende de |
| --- | --- | --- | --- |
| `FAT_TOTAL` | Faturamento Total | baixa | VENDAS + NATUREZA |
| `FAT_OFICINA` | Faturamento Oficina | média | VENDAS + OS + OS_TIPOS |
| `FAT_BALCAO` | Faturamento Balcão | média | VENDAS + NATUREZA (peças sem OS) |
| `FAT_FUNILARIA` | Faturamento Funilaria | média | OS + setor/painel funilaria |
| `FAT_PECAS_OF` | Faturamento Peças Oficina | média | OS_REQUISICOES |
| `FAT_SERV_OF` | Faturamento Serviços Oficina | média | OS_SERVICOS |
| `FAT_ACESSORIOS` | Faturamento Acessórios | média | NATUREZA / classe de item |
| `OF_PASSAGENS` | Oficina Passagens | baixa | OS (contagem) |
| `OS_PENDENTES` | OS Pendentes | baixa | OS.STATUS_OS |
| `PCT_HORAS_APL` | % Horas Aplicadas | alta | OS_TEMPOS_EXECUTADOS |
| `TICKET_SERV` | Ticket Serviços | baixa | derivado de FAT_SERV_OF / passagens |
| `TICKET_PECAS_OF` | Ticket Peças Oficina | baixa | derivado |
| `GIRO_ESTOQUE` | Giro de Estoque | alta | ITENS + movimento |
| `ESTOQUE_OBSOLETO` | Valor Obsoleto | alta | ITENS + última movimentação |
| `ESTORNO_GARANTIA` | Estorno de Garantia | alta | OS garantia + retorno fábrica |
| `SCORE_CARD` | Score Card | composto | agrega os acima + metas |

**Fora do DMS** (não tentar extrair do banco): `NPS Pós-Venda`, `NPS Vendas`,
emplacamentos/ABRACAF e as **metas** por KPI. Precisam de origem própria —
provavelmente carga manual ou integração à parte.

**Ordem sugerida:** começar por `FAT_TOTAL`, `OF_PASSAGENS` e `OS_PENDENTES`.
São os mais simples e os mais fáceis de conferir na mão — servem para calibrar o
método antes de atacar os compostos.

---

## 6. O que muda quando o DealerNet entrar

| Camada | Reaproveitamento |
| --- | --- |
| Contrato (`indicadores.yaml`) | **100%** — não se toca |
| Adaptador SQL | 0% — reescrito em T-SQL sobre o modelo do DealerNet |
| Validação | por concessionária (cada gestor confirma o seu) |
| Apresentação (Excel, gráfico, chat) | **100%** — o contrato de saída é o mesmo |

O trabalho por DMS novo passa a ser **só o adaptador**, com a regra de negócio já
decidida e escrita. É o mesmo princípio dos MCPs irmãos: duplicar o específico,
compartilhar o contrato.

---

## 7. Impacto no agente

- `list_templates` / `get_template` passam a servir **contratos + adaptador do
  DMS da sessão**, não SQL solto.
- O system prompt ganha uma regra: *"para indicador do catálogo, use o
  adaptador; nunca escreva SQL próprio para um indicador que já tem contrato"*.
  Isso evita que o agente invente uma variação do Faturamento Oficina.
- Indicador sem adaptador para aquele DMS → responder que não está disponível.
  Falha explícita é melhor que número plausível.
