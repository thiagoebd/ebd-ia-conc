# CLAUDE-dealernet.md — DealerNet Workflow (SQL Server)

> **DealerNet Workflow**: DMS do ecossistema automotivo, homologado por
> Volkswagen, GM/ABRAC e outras montadoras. Cobre CRM, vendas, oficina, peças,
> financeiro e contábil numa base única — o workflow *é* o produto, não um módulo.
>
> Base: `GrupoEBD_DealernetWF` · SQL Server 2022 · schema `dbo`
> Servidor: `clussp06wfw.grupoebd.ebdbr.com.br:1433` (10.10.3.158)
> 2.850 tabelas · 32.405 colunas · 3.979 FKs · 247 views
> Discover em 25/08/2026. **Tudo aqui verificado no dicionário.**

---

## 1. Escopo — 30 empresas, 6 razões sociais, 7 marcas

`Empresa` é a tabela mais referenciada (**264 FKs**) e `Empresa_Codigo` aparece
em **107 tabelas**. Escopo é de **coluna**, com três níveis:

```
GrupoEmpresa_Codigo  →  Empresa_Codigo  →  Empresa_MarcaCod
```

Há ainda `Empresa_EmpresaCodMatriz` (matriz da razão social).

| Cód | Fantasia | Razão social | Marca |
| --- | --- | --- | --- |
| 1 | THAI MACAPA | BACABA VEÍCULOS | Toyota |
| 2 | THAI AVARÉ | BACABA | Toyota |
| 3 | THAI ANANINDEUA | BACABA | Toyota |
| 4 | THAI CASTANHAL | BACABA | Toyota |
| 5 | THAI OURINHOS | BACABA | Toyota |
| 6 | THAI BOTUCATU | BACABA | Toyota |
| 27 | THAI ALTAMIRA | BACABA | Toyota |
| 29 | TSERVICE BELEM | BACABA | Toyota |
| 7 | MISO MACAPA | MISO | Hyundai |
| 8 | MISO SANTAREM | MISO | Hyundai |
| 9 | VM MATRIZ MANAUS | VIA MARCONI | Fiat |
| 10 | VM FILIAL SANTAREM | VIA MARCONI | Fiat |
| 12 | VM FILIAL AVARE | VIA MARCONI | Fiat |
| 13 | VM FILIAL CACHOEIRINHA | VIA MARCONI | Fiat |
| 22 | DEPOSITO C NERY MANAUS | VIA MARCONI | Fiat |
| 11, 14–21, 28 | VM WAY (Avaré, Macapá, Mundurucus, Ananindeua, STM, Diogo, Castanhal, Assis, Itapetininga, Municipalidade) | VIA MARCONI | Jeep |
| 30 | LEAPMOTOR MANAUS | VIA MARCONI | Leapmotor |
| 23 | VIALE CASTANHAL | VIALE AUTOMOVEIS | Fiat |
| 26 | VIALE PARAGOMINAS | VIALE | Fiat |
| 24 | ANTARES TERESINA | ANTARES VEICULOS | Ford |
| 25 | ANTARES BARAO | ANTARES | Ford |

Estados: AP, PA, AM, SP, PI.

**A ISAR MOTORS (BMW) não está aqui** — ela é o NBS. Os dois DMS são
complementares, sem sobreposição de unidade.

**Regra:** toda consulta filtra `Empresa_Codigo`. Sem exceção — são 30 empresas.

---

## 2. Domínios (valores reais, contados na base)

### `NotaFiscal_Status` (char)
| Valor | Significado | Volume |
| --- | --- | --- |
| `EMI` | **Emitida (válida)** | 2.053.387 |
| `CAN` | Cancelada | 37.429 |
| `INU` | Inutilizada | 9.992 |
| `DEN` | Denegada | 682 |
| `PRC`, `PCA`, `PEN`, `PIN` | em processamento | <100 |

**Faturamento sempre `= 'EMI'`.**

### `NotaFiscal_Movimento` (char)
`S` saída (1.354.257) · `E` entrada (747.315).
**Venda é `'S'`.** Sem esse filtro, compras entram no faturamento.

### `OS_Status` (char)
`PEN` pendente/aberta (384.552) · `ENC` encerrada (164.090) · `CAN` (1)

### `Titulo_Status` (char)
`PAG` pago (3.465.586) · `CAN` (312.478) · `AUT` autorizado (56.926) ·
`ENB` (3.401) · `PEN` (69)

### `Veiculo_Status` (char)
`U` usado (367.380) · `N` novo (38.899)

### `Proposta_Status` (char)
`FAT` faturada (77.645) · `CAN` (24.864) · `NEG` em negociação (3.869) ·
`DEV` devolvida (1.494) · `PED` pedido (345) · `AUT` (43)

### `OficinaServico_StatusExecucao` (char)
`AUT` autorizado (1.277.374) · `PEN` pendente (645.320) · `CAN` (599.067) · `AGA` (30)

---

## 3. `TipoOS` — classificação pronta pelo fabricante

218 tipos, com **`TipoOS_Classificacao`** dizendo quem é o pagador:

| Classificação | Significado |
| --- | --- |
| `CLI` | **Cliente pagante** — receita de oficina |
| `GAR` | Garantia (fábrica paga) |
| `DEP` | Interna / departamento (não é receita) |
| `OUT` | Comissão e outros (F&I, venda compartilhada) |
| `REC` | Retorno / retrabalho |

Também há `TipoOS_FontePagadora`, `TipoOS_Revisao` (bit), `TipoOS_ServicoRapido`,
`TipoOS_SetorServicoCod` e `TipoOS_Ativo`.

Exemplos: `CSR` cliente serviço reparo · `CFR` fast repair · `CSP` manutenção
periódica · `GS` garantia serviços · `GSR` recall · `ISN` interno serviço novos.

> No NBS o equivalente (`OS_TIPOS.PRODUTIVA`) levou horas para ser descoberto.
> Aqui a classificação é explícita — **usar `Classificacao`, não parsear a sigla**.

---

## 4. `NaturezaOperacao` — o que a nota é (301 códigos)

| Cód | Descrição |
| --- | --- |
| 11 | **Venda de veículos novos** |
| 19 | **Venda de veículos usados show room** |
| 37 | **Venda oficina** |
| 38 | **Venda garantia** |
| 10 | Venda peças varejo — revenda |
| 56 | Venda peças — atacado |
| 39 | Venda interna (baixa consumo interno) |
| 48 | Venda de veículos imobilizados |
| 12–17 | Devoluções (venda e compra) |
| 1–4, 9 | Compras (peças, VN, VU, consumo, imobilizado) |
| 5–8, 52, 53 | Transferências |
| 31, 47 | Comissão (financiamento, outras vendas) |

**É por aqui que se separa departamento**, não pela `TipoOS`.

---

## 5. Departamento (35) — a dimensão de gestão

`Departamento_Sigla`: `VN` novos · `VU` usados · `VD` venda direta ·
`VI` internet · `PA` peças e acessórios · `SP` assistência técnica ·
`FP` funilaria e pintura · `GA` garantia · `GU` garantia usados ·
`F&I` · `AU` auto centro · `AD` administração · `FIN` financeiro.

`NotaFiscal_DepartamentoCod` liga a nota ao departamento.

---

## 6. Entidades núcleo (por centralidade de FK)

| Tabela | FKs | Linhas | Papel |
| --- | --- | --- | --- |
| `Empresa` | 264 | 30 | escopo |
| `Pessoa` | 148 | 532.735 | cliente/fornecedor/vendedor (unificado) |
| `Marca` | 96 | 157 | bandeira |
| `Usuario` | 71 | 3.529 | usuário do sistema |
| `ModeloVeiculo` | 60 | 20.203 | modelo |
| `Produto` | 57 | 902.141 | peça |
| `NotaFiscal` | 55 | 2.101.542 | nota (entrada e saída) |
| `Veiculo` | 51 | 406.279 | veículo por chassi |
| `Titulo` | 36 | 3.838.404 | financeiro |
| `OS` | 34 | 548.641 | ordem de serviço |
| `TMO` | 34 | 88.850 | tempo padrão de serviço |
| `OficinaServico` | 20 | 2.521.767 | mão de obra na OS |
| `NotaFiscalItem` | 20 | 4.752.334 | item da nota |
| `Atendimento` | 27 | 211.189 | CRM / lead |
| `Proposta` | 14 | 108.260 | proposta de venda |
| `OficinaProduto` | — | 3.891.631 | peça aplicada na OS |

`Pessoa` unifica cliente, fornecedor e concessionária — diferente do NBS, que
separa `CLIENTES` de `CLIENTE_DIVERSO`.

---

## 7. Campos de valor e data

**`NotaFiscal`**: `_ValorTotal`, `_ValorDesconto`, `_ValorFrete`, `_ValorSeguro`,
`_ValorAcrescimo`, `_ValorJuros` · datas: `_DataEmissao`, `_DataMovimento`,
`_DataExpedicao`, `_DataChegada`

**`OS`**: `_DataCriacao` (abertura), `_DataPrometida`, `_DataRecepcao`,
`_DataLiberacaoVeiculo`, `_DataTecnicoInicio/Fim`, `_AgendamentoData`

**`OficinaServico` / `OficinaProduto`**: `_ValorUnitario`, `_ValorDesconto`,
`_ValorCusto` (só em Produto) — **margem sai direto do custo gravado**

**`Titulo`**: `_Valor`, `_DataEmissao`, `_DataVencimento`, `_DataPagamento`

---

## 8. Cicatrizes

**#D01 — Filtrar SEMPRE `Empresa_Codigo`.** São 30 empresas em 5 estados.
Consulta sem escopo mistura Toyota do Pará com Jeep de São Paulo.

**#D02 — `NotaFiscal` tem entrada E saída.** Sem `NotaFiscal_Movimento = 'S'`,
compras entram no faturamento. E sem `NotaFiscal_Status = 'EMI'` entram
canceladas, inutilizadas e denegadas.

**#D03 — Os nomes de coluna de data NÃO seguem o padrão óbvio.**
Não existe `NotaFiscal_Data` nem `OS_DataAbertura`. É `NotaFiscal_DataEmissao`
e `OS_DataCriacao`. Conferir no `INFORMATION_SCHEMA` antes de escrever.

**#D04 — `Lancamento` tem data futura.** Existem registros em 2029 e 2033
(erro de digitação). Agregação por ano precisa de teto: `< GETDATE()`.

**#D05 — Padrão `X` + `XHistorico`.** `Lancamento`/`LancamentoHistorico`,
`NotaFiscal`/`NotaFiscalHistorico`, `Titulo`/`TituloHistorico`,
`OficinaServico`/`OficinaServicoHistorico`. A tabela sem sufixo é a viva.

**#D06 — Tabelas gigantes exigem cuidado.** `ProdutoPreco` tem **800 milhões**
de linhas, `ProdutoEstoqueClasABC` 108M, `TMOTempo` 45M. Nunca consultar sem
`WHERE` restritivo. Preferir `WITH (NOLOCK)` para não travar a operação.

**#D07 — Ruído: 693 tabelas, 525M linhas.** `WF*` (workflow interno),
`*Historico`, `Monitor*`, `Audit*`, `Log*`, `Std*`, `Calculo*`, `Tmp*`.
Não são fonte de indicador de gestão.

**#D08 — Classificação de OS vem de `TipoOS_Classificacao`**, não da sigla.
`CLI` cliente · `GAR` garantia · `DEP` interna · `OUT` comissão · `REC` retorno.

**#D09 — `Veiculo_Status` é `U`/`N`**, não descritivo. E há 367 mil usados
contra 39 mil novos — a base guarda o histórico de veículos de clientes, não
só o estoque. Para estoque, usar `Veiculo_EmEstoque`.

**#D10 — Colunas duplicadas no dicionário.** Várias tabelas aparecem com a
mesma coluna duas vezes no `INFORMATION_SCHEMA` (efeito de view/sinônimo).
Não é erro de leitura — usar `DISTINCT` ao inventariar.

---

## 9. Comparação com o NBS

| | NBS (Oracle) | DealerNet (SQL Server) |
| --- | --- | --- |
| Concessionárias | 1 (Isar/BMW) | 30 (6 grupos, 7 marcas) |
| Tabelas | 8.160 | 2.850 |
| Escopo | `COD_EMPRESA` | `Empresa_Codigo` |
| Nota | `VENDAS` | `NotaFiscal` (`Movimento='S'`) |
| Status nota | `'0'` ativa | `'EMI'` emitida |
| OS | `OS` (`STATUS_OS` numérico) | `OS` (`OS_Status` char) |
| Cliente | `CLIENTES` + `CLIENTE_DIVERSO` | `Pessoa` (unificado) |
| Classificação de OS | `OS_TIPOS.PRODUTIVA` | `TipoOS_Classificacao` |
| Nomenclatura | críptica (`COD_*`) | legível (`Tabela_Campo`) |

**O contrato de indicador é o mesmo** (ver `docs/adr/001-camada-de-indicadores.md`);
muda só o adaptador SQL.

---

## 10. Aberto

- Colunas de ligação `OS` ↔ `NotaFiscal` (existe `NotaFiscal_OSTipoOSCod`,
  falta confirmar a chave completa)
- `TipoOS_FontePagadora` — valores `'0 '`, `'00'`, `'01'` sem significado claro
- Como o BI atual calcula margem (o DealerUp usa margem líquida de tributos
  no NBS; confirmar se aqui é `_ValorCusto` direto)
- `Empresa_Segmento` = `'VEC'` em todas as 30 — provavelmente veículos vs. outro
