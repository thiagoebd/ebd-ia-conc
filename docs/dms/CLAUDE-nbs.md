# CLAUDE.md — Agente das Concessionárias (NBS / Oracle) — v2

> Base: NBS, schema `NBS`, service `bmw.grupoebd.ebdbr.com.br`.
> Empresa operacional: **ISAR MOTORS** (BMW, Teresina/PI), `COD_EMPRESA = 1`.
> Fonte: dicionário Oracle (8.160 tabelas, 114.008 colunas, 24.804 constraints,
> 2.432 tabelas comentadas), extraído em 04/08/2026. **Nada inferido do Winthor.**

---

## 1. Escopo de empresa — regra de toda consulta

`EMPRESAS` é a tabela mais referenciada do modelo (492 FKs) e `COD_EMPRESA` é a
**primeira coluna da PK** de toda tabela de movimento.

| Tabela | Chave primária |
| --- | --- |
| `OS` | `COD_EMPRESA`, `NUMERO_OS` |
| `VENDAS` | `COD_EMPRESA`, `CONTROLE`, `SERIE` |
| `VEICULOS` | `COD_EMPRESA`, `COD_PRODUTO`, `COD_MODELO`, `CHASSI_RESUMIDO` |
| `COMPRA` | `COD_EMPRESA`, `COD_CONTROLE` |
| `CLIENTES` | `COD_CLIENTE` *(global, sem empresa)* |

1. Toda consulta a movimento filtra `COD_EMPRESA`.
2. Todo JOIN entre movimentos inclui `COD_EMPRESA` nos dois lados.
3. `CLIENTES` é global: não filtrar nem juntar por empresa.

Hoje: empresa `1` (operacional, filial de `100`) e `100` (matriz, sem movimento),
mesmo CNPJ. **Uma segunda BMW entrará como `COD_EMPRESA` nova sob a matriz 100.**

---

## 2. Status — valores reais, lidos das tabelas de domínio

### `VENDAS.STATUS` (VARCHAR2 — comparar com aspas)

| Valor | Significado |
| --- | --- |
| `0` | Ativa |
| `1` | Cancelada |
| `2` | Devolução parcial |
| `3` | Devolução total |
| `5` | Cupom pendente |

**Faturamento sempre com `STATUS = '0'`.** Devolução parcial (`2`) conta o valor
da nota original: se o indicador precisa do líquido, tratar a devolução à parte.

### `OS.STATUS_OS` (NUMBER — sem aspas)

| Valor | Significado |
| --- | --- |
| `0` | Ativa |
| `1` | Encerrada |
| `2` | Cancelada |
| `3` | Orçamento cancelado por tempo |
| `4` | Aprovado |
| `5` | Agrupadora |
| `6` | Agrupadora cancelada |
| `8` | Orçamento — cliente não aprovou |

**A mesma tabela `OS` guarda ordem de serviço e orçamento.** Status `3` e `8` são
orçamento; `5`/`6` são OS agrupadora (a "OS única" que consolida outras — contar
duas vezes se somar agrupadora + agrupadas). Para oficina realizada: `0` e `1`.

---

## 3. Valores da nota (`VENDAS`) — documentados no banco

| Coluna | Conteúdo |
| --- | --- |
| `TOTAL_NOTA` | **valor final da nota fiscal** |
| `TOTAL_PRODUTOS` | valor dos produtos (peças/veículos) |
| `TOTAL_SERVICOS` | valor dos serviços |
| `DESCONTO_PRODUTOS` | soma dos descontos aplicados nos itens |
| `FRETE`, `SEGURO` | acessórios da nota |
| `EMISSAO` | data da nota |

Faturamento = `SUM(TOTAL_NOTA)` com `STATUS='0'`. Para separar peças de serviço,
usar `TOTAL_PRODUTOS` e `TOTAL_SERVICOS`. As dezenas de colunas `BASE_*`,
`ALIQ_*`, `VALOR_*_RETIDO` são fiscais — não usar para gestão.

---

## 4. `NATUREZA.NATUREZA_APLICACAO` — o classificador de receita

Documentado no banco. É o que separa os departamentos da concessionária:

| Código | Aplicação |
| --- | --- |
| `F` | Venda de veículos **novos** |
| `K` | Venda de veículos **usados/consignados** |
| `M` | O.S. — prestação de serviço |
| `N` | O.S. — débito interno |
| `O` | O.S. — garantia |
| `C` | Cortesia |
| `5` / `3` / `7` | Peças — balcão e serviços (tributadas / isentas / fonte) |
| `1` / `2` | Compra e frete / devolução de compra |
| `6` | Devolução de vendas |
| `8` / `G` | Transferência (entrada / saída) |
| `P` / `Q` | Estorno de peças / de veículos |

`VENDAS.COD_NATUREZA → NATUREZA.COD_NATUREZA`. **Novo vs usado, garantia vs
cliente, peça vs serviço — tudo sai daqui**, não de flag na venda.

---

## 5. Tipos de OS

`OS.TIPO → OS_TIPOS.TIPO`, com dois flags documentados:

- `OS_TIPOS.GARANTIA` — OS de garantia (serviço anterior ou veículo em garantia)
- `OS_TIPOS.INTERNO` — manutenção na frota da própria empresa

`OS_TIPOS_EMPRESAS` parametriza o tipo **por empresa** (PK inclui `COD_EMPRESA`) —
o mesmo tipo pode se comportar diferente em cada concessionária.

---

## 6. Cicatrizes

**#01 — `VENDAS.STATUS` é texto, `OS.STATUS_OS` é número.** Comparar com aspas em
um e sem no outro. Erro silencioso garantido se trocar.

**#02 — OS agrupadora.** Status `5`/`6` consolidam outras OS
(`OS.TEM_PRE_FECHAMENTO = 'S'`, `OS_SERVICOS.NUMERO_OS_ORIGINAL`). Somar sem
excluir agrupadora conta duas vezes.

**#03 — Orçamento mora na tabela OS.** `OS.ORCAMENTO` e os status `3`/`8`.
"Quantas OS abrimos" sem filtro de status inclui orçamento não aprovado.

**#04 — Usuário e vendedor ligados por NOME, não código.** `OS.QUEM_ABRIU`,
`QUEM_APROVOU`, `QUEM_ENCERROU`, `QUEM_LIBEROU*`, `VENDAS.VENDEDOR`,
`VENDAS.USUARIO_LOGADO` → `EMPRESAS_USUARIOS.NOME` (VARCHAR2). Acento, caixa ou
espaço divergente quebra o join sem erro. Conferir se o total por vendedor bate
com o geral.

**#05 — `EMPRESAS.NUMR_CNPJ` e `VENDAS.CNPJ_INTERMED` estão DEPRECATED** (dito no
próprio comentário). Usar `EMPRESAS.CNPJ` / `CGC`.

**#06 — `ALL_TABLES.NUM_ROWS` é estimativa** e só 1.853 das 8.160 tabelas têm
estatística. Contar com `COUNT(*)`.

**#07 — NLS.** O servidor entrega sessão `AMERICAN`; o MCP força
`BRAZILIAN PORTUGUESE / BRAZIL`, `DD/MM/RRRR`, `,.`, `WEST_EUROPEAN` no
`session_callback`. Ainda assim, **usar máscara explícita** em `TO_DATE`/`TO_NUMBER`.

**#08 — `PARM_SYS`, `PARM_SYS2`, `PARM_SYS3`** são as tabelas de parâmetro do
sistema (606 colunas comentadas só na 3ª). Muito comportamento do NBS depende
delas — quando um número não fizer sentido, o parâmetro costuma ser a explicação.

---

## 7. O que ignorar

`FAB_*` (2.256 tabelas) e as tabelas por marca (`BMW_`, `FCA_`, `NISS`, `RENA`,
`FORD`, `TOYO`, `HYUN`, `PORS`, `VW_E`, `GM_I`) são integração com fábrica — as
maiores do banco (`BMW_KSD_AW03_04`, 17,4M linhas), mas fila e log, não gestão.

Idem `AUDITORIA_LOG`, `LOG_*`, `TMP_*`, `SPED_*` e os registros fiscais (`C100`,
`C170`, `C190`, `R0200`, `H010`): obrigação acessória.

---

## 8. Ainda aberto

- `VEICULOS.NOVO_USADO` — existe, valores não confirmados (a classificação de
  receita vem da `NATUREZA`, mas o estoque precisa desse campo).
- `OS.COD_ANDAMENTO → ANDAMENTO` — etapa dentro da oficina, valores não lidos.
- Relação `OS_SERVICOS` / `OS_REQUISICOES` para separar mão de obra de peça
  dentro da OS.
- `AUTOWARE_INDICADOR_EMP` está **vazia** — a parametrização de indicador de BI
  não foi usada nesta instalação.
