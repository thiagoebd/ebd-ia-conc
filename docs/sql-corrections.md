# sql-corrections.md — armadilhas do NBS

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

## #25 — OS_SERVICOS.COD_PRODUTIVO está nulo; executante só no apontamento

Em jul/2026, **100% das OS_SERVICOS da empresa 1 têm COD_PRODUTIVO nulo** (155 OS
com serviço, nenhum vínculo). Ranking por técnico executante via `OS_SERVICOS`
**não é possível** nesta instalação.

Fonte viável de técnico: `OS_TEMPOS_EXECUTADOS.COD_TECNICO` (NUMBER) →
`SERVICOS_TECNICOS` (COD_EMPRESA + COD_TECNICO + NOME; 16 técnicos cadastrados na
empresa 1; `FUNCIONARIOS` está vazia, COUNT(*) = 0).

Cuidado com produtividade: jul/26 apontou só 152,4h em 147 OS (4 técnicos:
VILTON 59,46h · ROBERT 46,74h · PEDRO IZIDIO 43,63h · DANIEL 2,57h) contra
978,86h vendidas — apontamento subutilizado, não reflete produtividade real.


<!-- AUTO-APPEND PROP-8F4987B4 aprovado por thiago.parreira@ebdgrupo.com.br -->

## #25 — OS_SERVICOS.COD_PRODUTIVO está nulo; executante só no apontamento

Em jul/2026, **100% das OS_SERVICOS da empresa 1 têm COD_PRODUTIVO nulo** (155 OS
com serviço, nenhum vínculo). Ranking por técnico executante via `OS_SERVICOS`
**não é possível** nesta instalação.

Fonte viável de técnico: `OS_TEMPOS_EXECUTADOS.COD_TECNICO` (NUMBER) →
`SERVICOS_TECNICOS` (COD_EMPRESA + COD_TECNICO + NOME; 16 técnicos cadastrados na
empresa 1; `FUNCIONARIOS` está vazia, COUNT(*) = 0).

Cuidado com produtividade: jul/26 apontou só 152,4h em 147 OS (4 técnicos:
VILTON 59,46h · ROBERT 46,74h · PEDRO IZIDIO 43,63h · DANIEL 2,57h) contra
978,86h vendidas — apontamento subutilizado, não reflete produtividade real.


<!-- AUTO-APPEND PROP-641CF7C1 aprovado por thiago.parreira@ebdgrupo.com.br -->

## #D11 — Escopo de empresa na NotaFiscal é `NotaFiscal_EmpresaCod`

Na tabela `NotaFiscal` (DealerNet), a coluna de escopo **não** é `Empresa_Codigo`
— é `NotaFiscal_EmpresaCod` (verificado no dicionário em 25/08/2026; o
CLAUDE.md diz que `Empresa_Codigo` aparece em 107 tabelas, mas NotaFiscal é uma
das exceções).

- `JOIN Empresa e ON e.Empresa_Codigo = nf.NotaFiscal_EmpresaCod` (correto)
- `nf.Empresa_Codigo` → erro `Invalid column name 'Empresa_Codigo'` (207)

Fantasia da empresa é `Empresa_NomeFantasia` (não `Empresa_Fantasia`).
Há também `NotaFiscal_EmpresaCodOrigem` (empresa de origem, para transferências).


<!-- AUTO-APPEND PROP-A3742420 aprovado por thiago.parreira@ebdgrupo.com.br -->

## #D12 — OS↔TipoOS é via tabela ponte OSTipoOS (DealerNet)

A tabela `OS` **não tem coluna de tipo de OS** (busca por `%TipoOS%` em INFORMATION_SCHEMA.COLUMNS da OS retorna vazio — o CLAUDE-dealernet.md chegou a citar `OS_TipoOSCod`, que **não existe**). A classificação `TipoOS_Classificacao` chega à OS por:

```
OS.OS_Codigo → OSTipoOS.OS_Codigo → OSTipoOS.OSTipoOS_TipoOSCod → TipoOS.TipoOS_Codigo
```

- Uma OS pode ter **várias** linhas em `OSTipoOS` (um tipo por serviço/contexto). Para "passagens de oficina" (contar a OS uma vez), usar `EXISTS` ou `COUNT(DISTINCT OS_Codigo)` — nunca join direto.
- `OSTipoOS` também traz denormalizado `OSTipoOS_TipoOSClas` / `OSTipoOS_TipoOSDes` / `OSTipoOS_TipoOSSgl` (classificação/descrição/sigla no nível do vínculo OS×Tipo).
- Passagens de oficina cliente pagante (validado 26/08/2026): `OS_Status IN ('PEN','ENC')` + `TipoOS_Classificacao = 'CLI'` via EXISTS sobre a ponte → 5.932 OS em ago/2026 (25 das 30 empresas com movimento; Way Mundurucus, Way Diogo, Viale Paragominas, Depósito C Nery e Antares Barão com zero).


<!-- AUTO-APPEND PROP-6743CA1C aprovado por thiago.parreira@ebdgrupo.com.br -->

## #D13 — Modelo do veículo na venda (DealerNet)

A tabela `NotaFiscal` **não tem coluna de modelo, chassi ou placa** (busca por %Modelo%/%Veiculo%/%Chassi% retorna vazio). Para identificar o veículo vendido, o caminho é:

```
NotaFiscal (NotaFiscal_Codigo)
  → NotaFiscalItem (NotaFiscal_Codigo, NotaFiscalItem_VeiculoCod)
  → Veiculo (Veiculo_Codigo, Veiculo_Chassi, Veiculo_Placa, Veiculo_ModeloVeiculoCod)
  → ModeloVeiculo (ModeloVeiculo_Codigo → ModeloVeiculo_Descricao)
```

**Cicatrizes da descoberta (erro 207 / invalid column name):**
- `dbo.Veiculo` **NÃO** tem `Veiculo_ModeloVeiculoDes`, `Veiculo_ModeloVeiculoMarcaDes`, `Veiculo_ModeloVeiculoMarcaSigla`, `Veiculo_ModeloVeiculoModeloMarca` — essas colunas existem em outra schema (o INFORMATION_SCHEMA sem filtro de schema mistura as duas e engana).
- `dbo.ModeloVeiculo` **NÃO** tem `ModeloVeiculo_MarcaDes` nem `ModeloVeiculo_MarcaSigla` — só `ModeloVeiculo_Descricao` (ex.: 'MDA5 - MUSTANG DARKHORSE', 'I/RAM 3500 LONGHORN AT8 05PASSAGEIROS').
- O nome da marca vem de `ModeloVeiculo` via `ModeloVeiculo_MarcaCod` → `Marca` (não testado) ou denormalizado em `Veiculo` de outra schema. Para o Conc.ia, `ModeloVeiculo_Descricao` + `Empresa_NomeFantasia` basta na maioria dos casos.

Query validada (top veículos mais caros do mês, ago/2026 — Mustang Dark Horse R$ 607.000 na Antares Teresina):
```sql
SELECT TOP 10 nf.NotaFiscal_Numero, nf.NotaFiscal_DataEmissao,
       nf.NotaFiscal_ValorTotal, nf.NotaFiscal_NaturezaOperacaoCod,
       e.Empresa_NomeFantasia, mv.ModeloVeiculo_Descricao AS modelo,
       v.Veiculo_Placa, v.Veiculo_Chassi
FROM NotaFiscal nf
JOIN NotaFiscalItem i ON i.NotaFiscal_Codigo = nf.NotaFiscal_Codigo
LEFT JOIN Veiculo v ON v.Veiculo_Codigo = i.NotaFiscalItem_VeiculoCod
LEFT JOIN ModeloVeiculo mv ON mv.ModeloVeiculo_Codigo = v.Veiculo_ModeloVeiculoCod
LEFT JOIN Empresa e ON e.Empresa_Codigo = nf.NotaFiscal_EmpresaCod
WHERE nf.NotaFiscal_Status = 'EMI' AND nf.NotaFiscal_Movimento = 'S'
  AND nf.NotaFiscal_NaturezaOperacaoCod IN (11, 19, 165, 74)
  AND nf.NotaFiscal_DataEmissao >= :inicio AND nf.NotaFiscal_DataEmissao < :fim
ORDER BY nf.NotaFiscal_ValorTotal DESC
```
