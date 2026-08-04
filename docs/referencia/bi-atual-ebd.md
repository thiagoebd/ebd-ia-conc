# Mapa do BI atual da EBD — 11 dashboards

> Extraído dos `.pbix` em 04/08/2026. Todos são **conexão viva com o Power BI
> Service**, então não trazem SQL nem código M — o modelo mora no serviço.
> O que se extraiu foi a **camada semântica**: tabelas do modelo, colunas e
> nomes das medidas. É o dicionário do que a gestão já mede.

---

## 1. Achados que mudam decisões do projeto

**`dealernet_vendacompraveiculoimobilizado`** aparece como entidade no dashboard
de Veículos Imobilizados. Confirma que o DealerNet já está integrado ao BI e
mostra a convenção de nome (`dealernet_<entidade>`). É a primeira evidência
concreta do modelo do segundo DMS.

**`f_objetivo`** (dashboard *Objetivo*) tem exatamente `loja`, `setor`,
`indicador`, `quadrimestre`, `Resultado`. **É a fonte de metas** que faltava —
está fora do DMS, como suspeitávamos, e é genérica por indicador. Serve tanto
para NBS quanto para DealerNet.

**`bases_syonet`** aparece em pós-venda e marketing: o CRM é o **Syonet**,
provável origem do NPS e do funil de leads.

**A granularidade do negócio é `loja`, não empresa.** `d_Loja` / `dEmpresa` /
`dMarcaLoja` estão em todos os modelos, sempre com `montadora`/`marca` junto.
Quando a segunda BMW entrar no NBS como `COD_EMPRESA` nova, ela é **outra loja**
no BI. O contrato de indicador deve ter `loja` como dimensão base.

**O modelo é multimarca e multi-DMS por desenho.** `dMontadora`, `dMarcaLoja`,
`Regional Jeep`, `Competitive Set` mostram que o BI já consolida bandeiras
diferentes. O Conc.ia precisa nascer com a mesma premissa.

---

## 2. Os 11 dashboards

| Dashboard | Fato principal | Do que trata |
| --- | --- | --- |
| Inteligência de Pós-Venda v10 | `fat_fat_demore_historico` | Score Card consolidado de pós-venda |
| pos_venda_mod_os | `f_os`, `f_faturamentoOsProduto` | oficina, OS |
| pos_venda_mod_estoque | `f_estoque`, `f_historico_vendas` | estoque de peças |
| pos_venda_mod_balcao | `f_balcao` | venda de peças no balcão |
| Dashboard Comercial | `fVenda`, `fEstoque`, `dVeiculo` | venda de veículos, margem |
| Dashboard Faturamento Geral | (medidas) `dMarcaLoja` | faturamento x meta, por setor |
| Dashboard Seminovos | (medidas) | usados: margem, repasse, trade-in |
| Gestão de Veículos Imobilizados | `dealernet_vendacompra...` | frota própria / demonstração |
| BI Corporativo Value Chain | `fVenda`, `dDRE`, `dPlanoContas` | DRE e cadeia de valor |
| Dashboard Análise de Mercado | `fArea_Operacional` | emplacamentos, share (externo) |
| Inteligência de Marketing | `fat_marketing_custos`, `f_abracaf` | custo de mídia x resultado |
| Objetivo | `f_objetivo` | **metas** por loja/setor/indicador |

Dimensões compartilhadas em quase todos: `d_Loja`/`dEmpresa`, `d_Calendario`,
`TabelaUFs`, `dMontadora`/`dMarca`, `f_abracaf`, `bases_syonet`.

---

## 3. Catálogo de indicadores consolidado

### Pós-venda — Oficina (`f_os`)
`Qtde Os` · `Oficina_Passagens` · `Faturamento Oficina` ·
`Faturamento Oficina Peças & Serviços` · `Faturamento Peças Oficina` ·
`Faturamento Serviços Oficina` · `Ticket médio por OS` ·
`Ticket médio por cliente` · `Ticket médio Peças por OS` ·
`Ticket médio Serviços por OS` · `OS Média/Mês` · `FaixaTempoOs`
Colunas de origem: `Nr_OS`, `Chassi`, `Placa`, `Dt_Criacao_OS`, `Status_OS`,
`Status_Andamento`, `TipoOS`, `Vl_Atendido`, `Total Produtos`,
`Total Serviços`, `Consultor`, `TMO_Descricao`, `tipoServico`, `Cobrar`

### Pós-venda — Balcão (`f_balcao`)
`Qtde vendas balcão` · `Faturamento Balcão` · `Qtde Clientes` ·
`Faturamento por Cliente` · `Faturamento Médio por cliente/mês` ·
`Faturamento Balcão Objetivo` · `Desempenho Faturamento Balcão`
Colunas: `produto`, `grupo_item`, `Status_NF`, `Cliente_Tipo`,
`condicao_pagamento`, `nome_vendedor`, `vlTotal_nota_fiscal`

### Pós-venda — Estoque de peças (`f_estoque`)
`Qtde em Estoque` · `Qtde Bloqueada` · `vl Bloqueado` · `Custo Médio` ·
`Valor Produto Médio em Estoque` · `Ticket Médio de Produto` ·
`Estoque atual para (meses)` · `Média Mês Itens Vendidos` · `Teve Movimentação`
Colunas: `cod_produto`, `descricao_produto`, `referencia`, `grupo_produto`,
`tpProduto`, `classificacao_abc`, `vlCusto`, `vlCustoMedio`, `vl_estoque`,
`Preço Público`, `Preço Garantia`

### Comercial — Veículos (`fVenda`, `dVeiculo`, `fEstoque`)
`Volume de Vendas` · `Faturamento de Vendas` · `Margem` · `Margem Combinada` ·
`Qtd_Chassi_Distintos` · `TempoEstoque` · comparativos AA/MA (ano/mês anterior),
acumulado e média de mês fechado
Dimensões: `Marca_Descricao`, `ModeloVeiculo_Descricao`,
`FamiliaVeiculo_Descricao`, `Vendedor`, `TIPO DE VENDA`, `Setor`

### Comercial — Seminovos
`Faturamento Usados` · `Volume Usados` · `% Margem Usados` ·
`% Rentabilidade Usados` · `% Repasse Usados` · `% Trade-In Usados` ·
`Preco Medio Usados` · `Valor Percapto Usados` · versões acumuladas e vs meta

### Faturamento geral
`Faturamento real` / `meta` · `Volume real` / `meta` · % real x meta ·
% vs mês anterior · % vs ano anterior · versões acumuladas · por `Setor`

### Financeiro / DRE (`dDRE`, `dPlanoContas`)
`Lucro Bruto` · `Despesas Variáveis` ·
`Custo de Estrutura - Propaganda - Desp. Financeira` · `% Value Chain` ·
`AV` / `AH` (análise vertical e horizontal) · `Cadeia de Valor`

### Externo (não sai do DMS)
Emplacamentos AOP / Nacional, Share, Competitive Set, Sub Segmento
(fonte: Fenabrave/ABRACAF) · custo de mídia (marketing) · NPS (Syonet) ·
metas (`f_objetivo`)

---

## 4. Consequências para o desenho de indicadores

**O padrão de medida é sempre o mesmo tripé:** valor realizado, comparativo
(mês anterior, ano anterior, acumulado) e meta. O contrato de indicador deve
prever isso como **estrutura**, não como indicadores separados — senão o
catálogo multiplica por 5 e vira inadministrável.

Proposta de assinatura única:

```
INDICADOR(codigo, loja, competencia)
  → realizado, meta, mes_anterior, ano_anterior, acumulado
```

Assim `FAT_OFICINA` é **um** contrato que responde 5 perguntas, e o cálculo de
variação vive na camada de apresentação, não em SQL repetido.

**A meta vem do `f_objetivo`, não do DMS.** É a mesma fonte para todos os
indicadores e todas as lojas. Precisa de uma origem acessível ao agente —
provavelmente uma tabela no Postgres do Conc.ia, alimentada por carga.

**Prioridade revisada** (o que o BI mais usa, e é conferível):
1. `FAT_OFICINA` e `OFICINA_PASSAGENS` — o coração do pós-venda
2. `FAT_BALCAO` e `QTDE_CLIENTES_BALCAO`
3. `ESTOQUE_QTDE`, `ESTOQUE_VALOR`, `COBERTURA_MESES`
4. `VOLUME_VENDAS` e `FAT_VENDAS` (veículos)
5. Margem e seminovos — dependem de custo, são os mais delicados

---

## 5. O que ainda falta descobrir

- `Vl_Atendido` (em `f_os`) não apareceu no dicionário do NBS com esse nome —
  é campo calculado no BI ou coluna que ainda não mapeamos.
- Como o BI separa **peças** de **serviços** dentro da OS: provavelmente
  `OS_REQUISICOES` x `OS_SERVICOS`, mas falta confirmar contra número real.
- `Cobrar` (em `f_os`) — flag que decide o que entra no faturamento.
- Definição de **margem** e de **repasse/trade-in** em seminovos: são as
  medidas mais sensíveis e não dá para inferir do nome.

Se conseguir exportar o modelo do dataset publicado (as queries de origem de
cada tabela), essas quatro pendências se resolvem de uma vez — e cada medida
vira um adaptador já validado por alguém.
