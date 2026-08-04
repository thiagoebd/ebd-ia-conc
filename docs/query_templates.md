# query_templates.md — templates SQL validados (NBS)

> Um template só entra aqui depois de **bater com número de referência externo**.
> Referência atual: painel **DealerUp**, competência **julho/2026**, empresa 1
> (ISAR MOTORS). Conferido em 04/08/2026.
>
> Template sem `Validado: sim` **não existe** — o agente escreve SQL próprio e
> avisa que o resultado é exploratório.

---

## T-001 — Faturamento Peças Balcão

**Validado: SIM** — jul/2026: `85.647,13` em `34` notas · DealerUp: `85.647,13 / 34` ✅
Binds: `:empresa`, `:dt_ini`, `:dt_fim`

```sql
SELECT COUNT(DISTINCT v.CONTROLE)      AS QTD_NOTAS,
       SUM(i.PRECO_LIQUIDO_FINAL)      AS FATURAMENTO
  FROM NBS.VENDAS v
  JOIN NBS.VENDA_ITENS i
    ON i.COD_EMPRESA = v.COD_EMPRESA
   AND i.CONTROLE    = v.CONTROLE
   AND i.SERIE       = v.SERIE
 WHERE v.COD_EMPRESA  = :empresa
   AND v.STATUS       = '0'
   AND v.COD_OPERACAO = 1                          -- Venda de Balcao
   AND (i.REQUISICAO IS NULL OR i.REQUISICAO = 0)  -- sem OS = balcao
   AND v.EMISSAO >= :dt_ini AND v.EMISSAO < :dt_fim
```

---

## T-002 — Faturamento Peças Oficina

**Validado: SIM** — jul/2026: `415.078,31` em `153` notas · DealerUp: `415.078,31 / 153` ✅
(op 2 = 274.532,84 em 107 · op 3 = 140.545,47 em 46)

```sql
SELECT COUNT(DISTINCT v.CONTROLE)      AS QTD_NOTAS,
       SUM(i.PRECO_LIQUIDO_FINAL)      AS FATURAMENTO
  FROM NBS.VENDAS v
  JOIN NBS.VENDA_ITENS i
    ON i.COD_EMPRESA = v.COD_EMPRESA
   AND i.CONTROLE    = v.CONTROLE
   AND i.SERIE       = v.SERIE
 WHERE v.COD_EMPRESA  = :empresa
   AND v.STATUS       = '0'
   AND v.COD_OPERACAO IN (2, 3)   -- notas de oficina
   AND i.REQUISICAO   > 0         -- peca requisitada na OS
   AND v.EMISSAO >= :dt_ini AND v.EMISSAO < :dt_fim
```

---

## T-003 — Margem Peças Balcão

**Validado: SIM** — jul/2026: `18.020,23` · DealerUp: `18.020,19` ✅ (4 centavos)

```sql
SELECT SUM(i.PRECO_LIQUIDO_FINAL)                     AS FATURAMENTO,
       SUM(i.PRECO_CONTABIL * i.QTDE)                 AS CUSTO,
       SUM(NVL(i.VALOR_PIS,0) + NVL(i.VALOR_COFINS,0)
         + NVL(i.VALOR_ICMS,0))                       AS IMPOSTOS,
       SUM(i.PRECO_LIQUIDO_FINAL
           - i.PRECO_CONTABIL * i.QTDE
           - (NVL(i.VALOR_PIS,0) + NVL(i.VALOR_COFINS,0)
            + NVL(i.VALOR_ICMS,0)))                   AS MARGEM
  FROM NBS.VENDAS v
  JOIN NBS.VENDA_ITENS i
    ON i.COD_EMPRESA = v.COD_EMPRESA
   AND i.CONTROLE    = v.CONTROLE
   AND i.SERIE       = v.SERIE
 WHERE v.COD_EMPRESA  = :empresa
   AND v.STATUS       = '0'
   AND v.COD_OPERACAO = 1
   AND (i.REQUISICAO IS NULL OR i.REQUISICAO = 0)
   AND v.EMISSAO >= :dt_ini AND v.EMISSAO < :dt_fim
```

---

## T-004 — Margem Peças Oficina

**Validado: SIM** — jul/2026: `114.070,60` · DealerUp: `114.070,65` ✅ (5 centavos)
Mesma fórmula do T-003, trocando o filtro de operação/requisição pelo do T-002.

```sql
SELECT SUM(i.PRECO_LIQUIDO_FINAL)                     AS FATURAMENTO,
       SUM(i.PRECO_LIQUIDO_FINAL
           - i.PRECO_CONTABIL * i.QTDE
           - (NVL(i.VALOR_PIS,0) + NVL(i.VALOR_COFINS,0)
            + NVL(i.VALOR_ICMS,0)))                   AS MARGEM
  FROM NBS.VENDAS v
  JOIN NBS.VENDA_ITENS i
    ON i.COD_EMPRESA = v.COD_EMPRESA
   AND i.CONTROLE    = v.CONTROLE
   AND i.SERIE       = v.SERIE
 WHERE v.COD_EMPRESA  = :empresa
   AND v.STATUS       = '0'
   AND v.COD_OPERACAO IN (2, 3)
   AND i.REQUISICAO   > 0
   AND v.EMISSAO >= :dt_ini AND v.EMISSAO < :dt_fim
```

---

## T-005 — Faturamento Veículos (volume validado, valor NÃO)

**Validado: PARCIAL.** Volume bate; valor não.

| | NBS | DealerUp |
| --- | --- | --- |
| Novos (op 4) | 4.700.710 / 10 | 4.379.031,18 / 10 |
| Usados (op 9 + 129) | 2.992.714 / 10 | 2.932.727,30 / 10 |

O DealerUp conta `Patrimonio - Venda` (op 129) como usado — sem isso o volume
dá 8, não 10. A diferença de valor (321.678,82 em novos) ainda não foi explicada;
provável dedução de imposto ou desconto de fábrica. **Não usar para número
oficial até fechar.**

```sql
SELECT CASE WHEN v.COD_OPERACAO = 4 THEN 'NOVOS' ELSE 'USADOS' END AS TIPO,
       COUNT(DISTINCT v.CONTROLE) AS QTD, SUM(v.TOTAL_NOTA) AS FATURAMENTO
  FROM NBS.VENDAS v
 WHERE v.COD_EMPRESA = :empresa AND v.STATUS = '0'
   AND v.COD_OPERACAO IN (4, 9, 129)
   AND v.EMISSAO >= :dt_ini AND v.EMISSAO < :dt_fim
 GROUP BY CASE WHEN v.COD_OPERACAO = 4 THEN 'NOVOS' ELSE 'USADOS' END
```

---

## EM INVESTIGAÇÃO — Faturamento Serviços Oficina

Alvo DealerUp jul/2026: **95.637,07 / 183**. Nenhuma combinação fechou:

| Caminho | Resultado |
| --- | --- |
| `VENDAS.TOTAL_SERVICOS` op 2+3 | 78.545,60 · 135 notas |
| `OS_SERVICOS` P+T, OS distintas | 84.482,74 · 176 OS |
| `OS_SERVICOS` sem DISTINCT | 151.992,55 (duplicado) |
| + op 23 | descartado: op 23 é **comissão** (F&I, consórcio, financiamento), `NATUREZA_APLICACAO = 'A'` |

Falta **17.091,47** — exatamente a mesma diferença que sobra no total de
pós-vendas (596.362,51 vs 579.271,04). Indica uma quarta linha de receita fora
de `VENDAS`, provavelmente garantia faturada à montadora
(`NATUREZA_APLICACAO = 'O'`). **Perguntar ao gestor de pós-venda** antes de
inventar fórmula.

---

## Fila

| Código | Indicador | Status |
| --- | --- | --- |
| T-006 | Oficina — passagens | a construir (usar `OS_TIPOS.PRODUTIVA='S'`) |
| T-007 | OS pendentes | a construir |
| T-008 | Ticket médio por OS | depende de T-006 |
| T-009 | Estoque de peças — valor e cobertura | a construir |
