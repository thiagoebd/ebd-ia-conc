# sql-corrections-dealernet.md — armadilhas do DealerNet (SQL Server)

> Cicatrizes do **DealerNet Workflow**. As do NBS ficam em
> `sql-corrections-nbs.md` — não misturar, os modelos são diferentes.
>
> Numeração `#D`, contínua. Nunca reaproveitar número.

## #D01 — Filtrar SEMPRE `Empresa_Codigo`
São 30 empresas em 5 estados. Consulta sem escopo mistura Toyota do Pará com
Jeep de São Paulo.

## #D02 — `NotaFiscal` tem entrada E saída
Sem `NotaFiscal_Movimento = 'S'` as compras entram no faturamento.
Sem `NotaFiscal_Status = 'EMI'` entram canceladas, inutilizadas e denegadas.

## #D03 — Nomes de coluna de data não seguem o padrão óbvio
Não existe `NotaFiscal_Data` nem `OS_DataAbertura`. É `NotaFiscal_DataEmissao`
e `OS_DataCriacao`. **Conferir no `INFORMATION_SCHEMA` antes de escrever.**

## #D04 — `Lancamento` tem data futura
Há registros em 2029 e 2033 (erro de digitação). Agregação por ano precisa de
teto: `< GETDATE()`.

## #D05 — Padrão `X` + `XHistorico`
`Lancamento`/`LancamentoHistorico`, `NotaFiscal`/`NotaFiscalHistorico`,
`Titulo`/`TituloHistorico`. A tabela sem sufixo é a viva.

## #D06 — Tabelas gigantes exigem `WHERE` restritivo
`ProdutoPreco` tem 800 milhões de linhas, `ProdutoEstoqueClasABC` 108M,
`TMOTempo` 45M. Preferir `WITH (NOLOCK)` para não travar a operação.

## #D07 — Ruído: 693 tabelas, 525M linhas
`WF*`, `*Historico`, `Monitor*`, `Audit*`, `Log*`, `Std*`, `Calculo*`, `Tmp*`.
Não são fonte de indicador de gestão.

## #D08 — Classificação de OS vem de `TipoOS_Classificacao`
`CLI` cliente · `GAR` garantia · `DEP` interna · `OUT` comissão · `REC` retorno.
Não parsear a sigla do tipo.

## #D09 — `Veiculo_Status` é `U`/`N`, e a base guarda histórico
367 mil usados contra 39 mil novos — inclui veículos de clientes, não só
estoque. Para estoque, usar `Veiculo_EmEstoque`.

## #D10 — `INFORMATION_SCHEMA.COLUMNS` mistura tabela e view
Colunas aparecem duplicadas. Usar `DISTINCT` ao inventariar, ou juntar com
`sys.tables` para pegar só tabela base.

## #D11 — Escopo na `NotaFiscal` é `NotaFiscal_EmpresaCod`
Na `NotaFiscal` a coluna de escopo **não** é `Empresa_Codigo`.
`JOIN Empresa e ON e.Empresa_Codigo = nf.NotaFiscal_EmpresaCod` (correto).
`nf.Empresa_Codigo` → erro 207. Há também `NotaFiscal_EmpresaCodOrigem`
(transferências). Fantasia é `Empresa_NomeFantasia`.
