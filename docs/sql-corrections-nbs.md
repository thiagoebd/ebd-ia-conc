# sql-corrections-nbs.md — cicatrizes do NBS (Oracle)

> Só NBS. As cicatrizes do DealerNet estão em `dms/sql-corrections-dealernet.md`
> e **não se aplicam aqui** — `NotaFiscal`, `Departamento` e `TipoOS` não
> existem nesta base.

<!-- antigo: sql-corrections.md — armadilhas do NBS

> Cada item aqui custou um número errado. Ler antes de escrever SQL.
> Numeração contínua; nunca reaproveitar número.

## #01 — Tipo do status difere entre tabelas
`VENDAS.STATUS` é `VARCHAR2` → `STATUS = '0'` (com aspas).
`OS.STATUS_OS` é `NUMBER` → `STATUS_OS = 1` (sem aspas).
Trocar não dá erro, dá resultado vazio.

## #02 — Faturamento sem filtro de status conta nota cancelada
`0` Ativa · `1` Cancelada · `2` Dev. parcial · `3` Dev. total · `5` Cupom pendente.
Toda soma de valor exige `STATUS = '0'`.

## #03 — Chave composta com COD_EMPRESA
`OS(COD_EMPRESA, NUMERO_OS)` · `VENDAS(COD_EMPRESA, CONTROLE, SERIE)` ·
`VEICULOS(COD_EMPRESA, COD_PRODUTO, COD_MODELO, CHASSI_RESUMIDO)` ·
`COMPRA(COD_EMPRESA, COD_CONTROLE)`.
JOIN sem `COD_EMPRESA` nos dois lados cruza empresas.

## #04 — CLIENTES é global
Não tem `COD_EMPRESA`. Não filtrar nem juntar por empresa.

## #05 — Orçamento e OS agrupadora inflam a contagem
`STATUS_OS` `3` e `8` são orçamento; `5` e `6` são agrupadora.

## #06 — Usuário/vendedor por NOME, não por código
`OS.QUEM_*`, `VENDAS.VENDEDOR`, `VENDAS.USUARIO_LOGADO` → `EMPRESAS_USUARIOS.NOME`
(`VARCHAR2`). Acento/caixa/espaço divergente quebra o join em silêncio.

## #07 — PC_DEF_ESTATISTICAS_* é dado morto (2014–2020)
Fontes vivas: `OS`, `VENDAS`, `VEICULOS`, `COMPRA` — todas com dado até hoje.

## #08 — NUM_ROWS é estimativa
Só 1.853 das 8.160 tabelas têm estatística. Contar com `COUNT(*)`.

## #09 — Colunas DEPRECATED
`EMPRESAS.NUMR_CNPJ` → usar `CNPJ`/`CGC`.
`VENDAS.CNPJ_INTERMED` → usar `integrador_ecommerce`.

## #10 — Prefixos a ignorar
`FAB_*` e por marca (`BMW_`, `NISS`, `RENA`...): integração com fábrica.
`AUDITORIA_LOG`, `LOG_*`, `TMP_*`, `SPED_*`, `C100`, `C170`, `R0200`: log e fiscal.

## #11 — NLS da sessão
Servidor entrega `AMERICAN`; o MCP força `BRAZIL`/`DD/MM/RRRR`/`,.`/`WEST_EUROPEAN`.
Ainda assim usar máscara explícita em `TO_DATE`/`TO_NUMBER`.

## #12 — PARM_SYS / PARM_SYS2 / PARM_SYS3
Tabelas de parâmetro (606 colunas comentadas só na 3ª). Número estranho:
olhar o parâmetro.

---

# Cicatrizes do batimento com o DealerUp (04/08/2026)

## #13 — NATUREZA tem PK COMPOSTA (COD_NATUREZA, GRUPO) ⚠️ CRÍTICO
364 linhas para 146 códigos distintos. Join só por `COD_NATUREZA` **duplica cada
nota 2 a 3 vezes**. Julho/2026 dava 27 milhões na aplicação `A` quando o total
real do mês era 8,3 milhões.

```sql
-- ERRADO
JOIN NBS.NATUREZA n ON n.COD_NATUREZA = v.COD_NATUREZA
-- CERTO
JOIN NBS.NATUREZA n ON n.COD_NATUREZA = v.COD_NATUREZA AND n.GRUPO = v.GRUPO
```

## #14 — A nota tem CINCO pares de natureza, não um
`COD_NATUREZA`/`GRUPO` (principal), `_SERV`/`GRUPO_SERV`, `2`, `3`, `4`.
Cada um classifica uma composição diferente. Classificar a nota inteira por um
slot só sempre erra: em julho, 251 das 354 notas não casavam pelo principal.
**Para classificar a nota, usar `COD_OPERACAO`, não natureza.**

## #15 — PRECO_LIQUIDO_FINAL, não PRECO_LIQUIDO
Em `VENDA_ITENS`, o valor que bate com o faturamento é `PRECO_LIQUIDO_FINAL`.
Peças oficina jul/26: `PRECO_LIQUIDO_FINAL` = 415.078,31 (correto) ·
`PRECO_LIQUIDO` = 375.148,34 (errado).

## #16 — REQUISICAO separa balcão de oficina
`VENDA_ITENS.REQUISICAO` preenchida = peça saiu por OS (oficina).
Nula ou zero = balcão. É isso, e não a natureza, que divide os dois departamentos.

## #17 — Margem é líquida de tributos
A margem do painel = `PRECO_LIQUIDO_FINAL − PRECO_CONTABIL*QTDE − (PIS+COFINS+ICMS)`.
Sem deduzir imposto sobra ~18% no balcão e ~5% na oficina.
A coluna `VENDA_ITENS.MARGEM` é quase toda nula — **não usar**.

## #18 — Somar serviço da OS sem DISTINCT duplica
A mesma OS aparece em várias notas (op 2 e 3). Julho: com join direto deu
151.992,55 em 828 linhas; com `DISTINCT` da OS antes, 84.482,74 em 459.
Sempre isolar as OS distintas num `WITH` antes de somar `OS_SERVICOS`.

## #19 — Operação 23 é comissão, não serviço de oficina
`Servicos Diversos - Comissao`: F&I, financiamento, consórcio, seguro —
todas `NATUREZA_APLICACAO = 'A'`. Não entra em pós-venda.

## #20 — Usados incluem "Patrimônio - Venda" (op 129)
O DealerUp conta op 9 + op 129 como usados. Só op 9 dá volume menor.

## #21 — OS_TIPOS.PRODUTIVA é a flag de passagem
Não é redundante com `GARANTIA`/`INTERNO`: `IG`/`IM` (garantia test drive) são
internas mas `PRODUTIVA='S'`. Para "passagens de oficina", usar `PRODUTIVA`.

## #22 — Segmento (Autos/Motorrad/Mini) não sai do tipo de OS
`M7`, `M1`, `Y1`, `Y4`, `FU`, `GB` fogem do padrão "dígito = segmento".
Usar `OS.COD_PRODUTO → PRODUTOS.ID_SEG` (1 BMW · 2 Moto · 3 Mini).
**Cuidado:** os 791 veículos usados têm `ID_SEG` nulo.

## #23 — VEICULOS.NOVO_USADO tem 4 valores
`N` novo (1.655) · `U` usado (829) · `P` (44) · `C` (17). Não é binário.
E `RESERVADO='S'` em 98% do estoque — essa flag não significa "vendido".

## #24 — EMPRESAS_DIVISOES não separa departamento
Só 3 linhas na empresa 1 (Marketing, Gerência, Vendedor). Apesar do comentário
do banco sugerir `PRODUTIVO = B/T/S/V/O`, não serve para dividir
oficina/balcão/veículos. Usar `COD_OPERACAO`.

## #25 — OS_SERVICOS.COD_PRODUTIVO vem nulo; executante está em OS_TEMPOS_EXECUTADOS
Julho/2026, empresa 1: `COD_PRODUTIVO` nulo em 100% das linhas de `OS_SERVICOS`.
Não serve para ranking de técnico nem produtividade por executante.
Fonte viva: `OS_TEMPOS_EXECUTADOS` (apontamento), com `COD_TECNICO` preenchido.

**Cuidado ao interpretar:** o apontamento está subutilizado — julho teve
152,40h apontadas contra 978,86h vendidas (15,6%). Produtividade por técnico
não fecha por essa via até o apontamento ser disciplinado na oficina.


<!-- AUTO-APPEND PROP-8F4987B4 aprovado por thiago.parreira@ebdgrupo.com.br -->

