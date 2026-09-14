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



<!-- AUTO-APPEND PROP-36D46BCA aprovado por thiago.parreira@ebdgrupo.com.br -->

## Estoque de veículos DealerNet — FONTE ENCONTRADA (verificado 03/09/2026) ⚠️ CORRIGE a entrada de 31/08

A entrada anterior ("Estoque de veículos — tabelas vazias", 31/08/2026) está **desatualizada**: ela testou apenas `AI_VeiculoEstoque` (0 linhas) e `DashVeiculo` (0 linhas) — ambas continuam vazias e NÃO usar — mas **não testou a tabela `VeiculoEstoque` nem as views do time EBD**.

### Fonte 1 — tabela `VeiculoEstoque` (existe, com escopo por empresa)
- Colunas-chave: `VeiculoEstoque_EmpresaCod` (smallint — **escopo por concessionária**), `VeiculoEstoque_VeiculoCod`, `VeiculoEstoque_VeiculoMovCodEntrada`, `VeiculoEstoque_VeiculoMovCodSaida`, `VeiculoEstoque_NotaFiscalCodCompra`, `VeiculoEstoque_NotaFiscalCodVenda`, `VeiculoEstoque_EstoqueCod`, `VeiculoEstoque_Fisicamente` (bit).
- **A tabela é histórico/posição** (ex.: empresa 9 tem 30.627 linhas). "Em estoque agora" ≈ linha com `VeiculoEstoque_VeiculoMovCodSaida IS NULL` (empresa 9: 662).
- Modelo/descrição NÃO está em `Veiculo` (a tabela real não tem `Veiculo_ModeloVeiculoDes` — veio de VIEW homônima; cicatriz #D10). Descrição vem de `ModeloVeiculo` via `Veiculo_ModeloVeiculoCod` → `ModeloVeiculo_Descricao`.

### Fonte 2 (RECOMENDADA) — view `VW_EBDDEV_ESTOQUEVEICULOS_ATUAL`
Criada pelo time de dados EBD. **Snapshot único por dia** (Data_Estoque = data corrente; em 03/09/2026: 1.926 linhas para as 30 empresas — conferir sempre que há 1 só Data_Estoque, senão duplica). Colunas:
- `Empresa_Codigo`, `Empresa_Nome`, `estoque_Descricao` (VN - VEICULOS NOVOS, VN ... DEPOSITO, VU - USADOS SHOW ROOM, VR - USADOS PARCEIRO, VI - IMOBILIZADOS, etc.), `ModeloVeiculo_Descricao`, `Marca_Descricao`, `Cor_Descricao`, `FamiliaVeiculo_Descricao`
- `veiculo_codigo`, `veiculo_chassi`, `Placa`, `Veiculo_Km`, `ANO`, `DiasEstoque`, `DiasTransito`, `TransitoEstoque`
- **`Valor_Venda`** (preço de venda tabelado), **`Valor_Compra`** (custo), `Pago` (situação de pagamento), `Vl_Top`
- `Status` (vazio = disponível; 'Em Negociação' = reservado em negociação), `TesteDrive`

### Caso validado — VM Matriz Manaus (empresa 9), 03/09/2026
263 veículos / R$ 30,2 mi valor de venda. Quebra: VN 155 (R$ 19,44M) + VN Depósito 61 (R$ 8,35M) + VU 19 (R$ 1,91M) + VR 8 (R$ 364k) + VI 20 (R$ 103k). Topo: Ducato Minibus 2.2 Diesel R$ 358.000 (203 dias de estoque!) · Titano Ranch R$ 250.500 · Toro Ranch R$ 205.800 (x3).

### Regras
- Para "top carros em estoque", ordenar por `Valor_Venda` DESC na view `_ATUAL`, filtrando `Empresa_Codigo`.
- Usar `sys.columns`/`sys.tables` para schema real (INFORMATION_SCHEMA mistura com views homônimas — existe uma VIEW chamada `Veiculo` e `ModeloVeiculo`).
- View tem mais versões: `VW_EBDDEV_ESTOQUEVEICULOS` (base), `_ATUAL` (snapshot do dia), `_GERAL`/`_GERAL_V2`, `VW_EBDDEV_ESTOQUEVEICULOSUSADOS`, `rel_EstoqueVeiculo`.


<!-- AUTO-APPEND PROP-D5F243CA aprovado por thiago.parreira@ebdgrupo.com.br -->

## Operação 32 no NBS — venda de veículo que desaparece em JOIN por NATUREZA (verificado 11/09/2026)

`NBS.VENDAS.COD_OPERACAO = 32` (empresa 1) é **venda de veículo** — mas a nota vem com `COD_NATUREZA`, `GRUPO`, `COD_NATUREZA_SERV` e `GRUPO_SERV` **todos nulos**. Consequência: ela não aparece em nenhum JOIN por `NATUREZA` (ver cicatriz #13/#14) e fica fora de qualquer contagem de veículos feita por `NATUREZA_APLICACAO='F'/'K'` ou por operação 4 e 9.

**Evidência medida nesta base:**
- ago/26: 1 nota · R$ 477.015,10 · `TOTAL_PRODUTOS` = 477.015,10 (serviços = 0) · `CHASSI_RESUMIDO` preenchido · `COD_PRODUTO = 20278` = `PRODUTOS.DESCRICAO_PRODUTO` "BMW AUTO X3" · `PRODUTOS.NOVO_USADO = 'N'` (novo) · `ID_SEG = 1` (BMW).
- ago/25: 2 notas · R$ 1.321.805,08.
- jan/2025 a ago/2026: 38 notas · R$ 14.481.940,73 (ticket médio ~R$ 381 mil — compatível com veículo, não com peça).
- `VENDAS` não tem coluna `OBSERVACAO` (tentativa de leitura dá ORA-00904) e a tabela `NBS.MODELOS` não existe no schema acessível.

**Como tratar ao medir veículos do NBS:**
1. Incluir `COD_OPERACAO = 32` **junto** com 4 (novos), 9 e 129 (usados) no bloco de veículos.
2. Classificar novo x usado pelo produto: `JOIN NBS.PRODUTOS p ON p.COD_PRODUTO = v.COD_PRODUTO` → `p.NOVO_USADO` ('N' novo / 'U' usado).
3. Não tentar classificar por natureza — está nula; a nota precisa de classificação manual.

**Impacto:** em ago/2026, ignorar a op 32 subestima os veículos do NBS em 1 unidade e R$ 477 mil (de 21 para 20 un / R$ 3,58 para 4,06 mi).


<!-- AUTO-APPEND PROP-3B13B4A9 aprovado por thiago.parreira@ebdgrupo.com.br -->

## Operação 32 no NBS — é DEMONSTRAÇÃO, não venda de veículo (verificado 14/09/2026) — ⚠️ CORRIGE PROP-D5F243CA

A cicatriz anterior (PROP-D5F243CA, 11/09/2026) classificou `NBS.VENDAS.COD_OPERACAO = 32` como *venda de veículo* e mandou incluí-la no bloco de veículos junto com as operações 4, 9 e 129. **Está errado.**

### Prova 1 — o cadastro da operação é explícito
`NBS.OPERACOES` (empresa 1) — colunas `COD_OPERACAO`, `OPERACAO`, `GRUPO` (a descrição está em `OPERACAO`, **não** em `DESCRICAO`):

| Cód | Operação | Grupo |
| --- | --- | --- |
| 32 | **Demonstracao Veiculos (Saida)** | 9 |
| 33 | **Demonstracao Veiculos (entrada)** | 9 |

### Prova 2 — o par saída/entrada existe e casa
- `VENDAS` op 32: **38 notas · R$ 14.481.940,73** (jan/2025–ago/2026)
- `COMPRA` op 33: **37 notas · R$ 14.004.925,63** (mesmo período)

### Por que o erro era plausível
A op 32 traz `TOTAL_PRODUTOS` cheio, `CHASSI_RESUMIDO` preenchido, produto de veículo (`PRODUTOS.NOVO_USADO='N'`) e `COD_NATUREZA`/`GRUPO` nulos — **exatamente igual a uma venda de veículo**. Essas colunas não distinguem remessa de venda; só o cadastro da operação distingue. É o equivalente NBS da natureza **64** do DealerNet (remessa para demonstração), que a regra R5 manda deixar **fora** do faturamento.

### Como tratar
1. **Op 32 NÃO entra em faturamento de veículos.** Ao montar o bloco de veículos do NBS, usar **apenas** op 4 (novos), 9 e 129 (usados).
2. Se o gestor quiser medir demonstração (carro na rua para test drive), reportar **à parte**, nunca somado a venda.
3. Impacto de continuar errado: ~R$ 14,5 mi inflados em 20 meses (R$ 477 mil só em ago/26).
