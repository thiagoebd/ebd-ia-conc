# sql-corrections-dealernet.md — cicatrizes do DealerNet (SQL Server)

> Só DealerNet. As cicatrizes do NBS (`COD_OPERACAO`, `VENDA_ITENS`,
> `OS_TIPOS`, `NATUREZA_APLICACAO`, `PRECO_LIQUIDO_FINAL`) estão em
> `sql-corrections-nbs.md` e **não se aplicam aqui** — essas tabelas e colunas
> não existem nesta base.

---

## #D01 — Filtrar SEMPRE a empresa

São 30 empresas em 5 estados. Consulta sem escopo mistura Toyota do Pará com
Jeep de São Paulo. Sem exceção.

## #D02 — `NotaFiscal` tem entrada E saída

`NotaFiscal_Movimento`: `S` saída (1.354.257) · `E` entrada (747.315).
`NotaFiscal_Status`: `EMI` válida (2.053.387) · `CAN` (37.429) · `INU` (9.992)
· `DEN` (682).

Faturamento sempre `Status = 'EMI'`. **Mas cuidado com o `Movimento`** — ver
#D14: filtrar `= 'S'` cegamente esconde as devoluções.

## #D03 — Nomes de coluna de data não seguem o padrão óbvio

Não existe `NotaFiscal_Data` nem `OS_DataAbertura`. É `NotaFiscal_DataEmissao`
e `OS_DataCriacao`. Conferir no `INFORMATION_SCHEMA` antes de escrever.

## #D04 — `Lancamento` tem data futura

Existem registros em 2029 e 2033 (erro de digitação). Agregação por ano
precisa de teto: `< GETDATE()`.

## #D05 — Padrão `X` + `XHistorico`

`Lancamento`/`LancamentoHistorico`, `NotaFiscal`/`NotaFiscalHistorico`,
`Titulo`/`TituloHistorico`, `OficinaServico`/`OficinaServicoHistorico`.
A tabela sem sufixo é a viva.

## #D06 — Tabelas gigantes exigem cuidado

`ProdutoPreco` tem **800 milhões** de linhas, `ProdutoEstoqueClasABC` 108M,
`TMOTempo` 45M. Nunca consultar sem `WHERE` restritivo. Preferir
`WITH (NOLOCK)` para não travar a operação.

## #D07 — Ruído: 693 tabelas, 525M linhas

`WF*` (workflow interno), `*Historico`, `Monitor*`, `Audit*`, `Log*`, `Std*`,
`Calculo*`, `Tmp*`. Não são fonte de indicador de gestão.

## #D08 — Classificação de OS vem de `TipoOS_Classificacao`

Não da sigla. `CLI` cliente · `GAR` garantia · `DEP` interna · `OUT` comissão ·
`REC` retorno. Isso classifica a **OS**, não a nota — para faturamento, usar
natureza + departamento (#D15).

## #D09 — `Veiculo_Status` é `U`/`N`

Não descritivo. E há 367 mil usados contra 39 mil novos — a base guarda o
histórico de veículos de clientes, não só o estoque. Para estoque, usar
`Veiculo_EmEstoque`.

## #D10 — Colunas duplicadas no dicionário

Várias tabelas aparecem com a mesma coluna duas vezes no
`INFORMATION_SCHEMA` (efeito de view/sinônimo). Não é erro de leitura — usar
`DISTINCT` ao inventariar.

## #D11 — Escopo de empresa na `NotaFiscal` é `NotaFiscal_EmpresaCod`

A coluna **não** é `Empresa_Codigo` — `NotaFiscal` é exceção à convenção.

```sql
JOIN Empresa e ON e.Empresa_Codigo = nf.NotaFiscal_EmpresaCod   -- correto
nf.Empresa_Codigo                                                -- erro 207
```

Fantasia da empresa é `Empresa_NomeFantasia` (não `Empresa_Fantasia`).
Há também `NotaFiscal_EmpresaCodOrigem` (empresa de origem, para
transferências).

## #D12 — A FK de `NotaFiscalItem` para `NotaFiscal` é `NotaFiscal_Codigo`

Sem prefixo da tabela filha. `NotaFiscalItem_NotaFiscalCod` **não existe**.

```sql
JOIN NotaFiscalItem i ON i.NotaFiscal_Codigo = nf.NotaFiscal_Codigo   -- correto
```

São três as exceções à convenção `Tabela_Campo` nessa tabela:
`NotaFiscal_Codigo`, `PedidoCompra_Codigo`, `VeiculoTipoFaturamento_Codigo`.
Todas as demais FKs seguem `NotaFiscalItem_XxxCod`.

**Lição geral:** a convenção `Tabela_Campo` do DealerNet tem exceções em
colunas de FK. Antes de escrever um JOIN novo, consultar
`sys.foreign_keys` em vez de inferir o nome.

## #D13 — `Pessoa` não tem coluna de CPF/CNPJ

Só `Pessoa_Nome`, `Pessoa_NomeFantasia` e `Pessoa_TipoPessoa`. O documento
deve estar em tabela satélite ainda não localizada.

**Armadilha:** buscar coluna de nome por ordem alfabética devolve
`Pessoa_NFSegNomeSegurado` (nome do segurado em nota de seguradora, quase
sempre nulo) antes de `Pessoa_Nome`. Usar `Pessoa_Nome` explicitamente.

## #D14 — Devolução de venda é `Movimento='E'` e ABATE o faturamento

**A cicatriz mais cara até agora.** Filtrar `NotaFiscal_Movimento = 'S'` no
`WHERE` é o reflexo natural e **esconde as devoluções**, que são lançadas como
entrada.

| Natureza | Descrição | Bloco que abate |
| --- | --- | --- |
| 13 | Devolução de venda — veículos novos | VN |
| 77 | Devolução de venda — peças oficina | Oficina |
| 12 | Devolução de venda — peças varejo | Peças |

Thai Ananindeua jul/26: natureza 11 somava 18.960.680,00 em 79 notas, mas o
DealerUp mostrava 18.591.772,00 em 77. A diferença era **exatamente** as 2
notas de natureza 13 (368.908,00) — invisíveis sob o filtro `'S'`.

**Diagnóstico rápido:** se todas as notas de venda de veículo terminam em zero
(múltiplos de 10) e o alvo do BI não termina em zero, o componente que falta
está fora do conjunto `Movimento='S'`. Teste de paridade fecha a hipótese em
segundos.

Padrão correto: trazer saídas e devoluções juntas e aplicar sinal.

```sql
CASE WHEN nf.NotaFiscal_NaturezaOperacaoCod IN (13, 77, 12) THEN -1 ELSE 1 END
```

A devolução abate **valor e contagem de unidades**.

## #D15 — Natureza é dimensão FISCAL; departamento é dimensão de GESTÃO

`NaturezaOperacao` (301 códigos, via `NotaFiscal_NaturezaOperacaoCod`) diz o
que a nota é perante o fisco. `Departamento` (35, via
`NotaFiscal_DepartamentoCod`) diz a que área o resultado pertence.

Nenhuma das duas resolve sozinha:

- **Só departamento:** VN em jul/26 dá 108 notas / 22.288.003,97, porque o
  departamento carrega junto remessa de demonstração (64), comissões e baixa
  de consumo.
- **Só natureza:** a 74 (venda direta) parece "veículo novo" e vira 7,1M
  somados no bloco errado.

Faturamento correto usa **as duas**: departamento para agrupar, natureza para
filtrar. Versões antigas do `CLAUDE-dealernet.md` afirmavam que a natureza
separava o departamento — está errado.

## #D16 — Natureza 48 (imobilizados) é USADO e entra no faturamento

O banco a classifica no departamento `VU`. É veículo que rodou
(ex-demonstração, ex-frota) vendido a cliente final. Excluí-la derruba os
usados em 437.980,00 e 3 unidades no caso Thai jul/26.

Correção de uma regra anterior (PROP-7246E418), que mandava excluir 48 junto
com 64. **Só a 64 fica fora.**

## #D17 — Natureza 39 (baixa consumo) SAI do faturamento, mas não abate

Peça retirada para uso próprio da loja. Não houve receita reconhecida, logo
não há o que estornar: retirar do numerador é correto; subtrair criaria
receita negativa que nunca existiu.

*Prova:* VU bruto jul/26 = 6.420.210,84. Menos a 39 do VU (17.200,84) =
6.403.010,00, exatamente o DealerUp. Se abatesse, daria 6.385.809,16.

Distinguir de #D14: devolução **abate** (houve receita, foi desfeita);
consumo interno **sai** (nunca houve receita).

## #D18 — Departamento `F&I` existe no cadastro mas não é usado

Código 30, zero notas. As comissões estão dentro de `VN` (naturezas 31, 173,
47, 168) e `VD` (natureza 83). Agrupar F&I por departamento devolve bloco
vazio — identificar **por natureza**.

## #D19 — Nota de veículo novo tem exatamente 1 item

79 notas → 79 itens em jul/26. Somar por nota ou por item dá o mesmo
resultado em VN, sem risco de fan-out. Diferente da oficina, onde a mesma OS
aparece em várias notas.

## #D20 — Campos de valor alternativos vêm zerados em VN

`NotaFiscal_ValorDesconto`, `_ValorFrete`, `_ValorSeguro`, `_ValorAcrescimo`,
`_ValorJuros` = 0 em todas as notas de veículo novo. Em
`NotaFiscalItem`, `_ValorBonusFabrica` e `_ValorTotalBrutoSemDesconto` também.
`NotaFiscal_ValorTotal` é a única base de valoração. `_ValorLucroBruto` é o
campo vivo de margem.

`VeiculoTipoFaturamento` está sempre nulo nesta instalação — a FK existe mas
não serve para segmentar.

## #D21 — `Departamento_Sigla` é `char` com padding

Vem como `'VN        '`. Comparação com `=` funciona em T-SQL (ignora espaço à
direita), mas ao trazer para Python é preciso `.strip()` antes de comparar ou
usar como chave de dicionário.
