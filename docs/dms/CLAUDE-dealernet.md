# CLAUDE-dealernet.md — DealerNet Workflow (SQL Server)

> **DealerNet Workflow**: DMS do ecossistema automotivo, homologado por
> Volkswagen, GM/ABRAC e outras montadoras. Cobre CRM, vendas, oficina, peças,
> financeiro e contábil numa base única — o workflow *é* o produto, não um módulo.
>
> Base: `GrupoEBD_DealernetWF` · SQL Server 2022 · schema `dbo`
> Servidor: `clussp06wfw.grupoebd.ebdbr.com.br:1433` (10.10.3.158)
> 2.850 tabelas · 32.405 colunas · 3.979 FKs · 247 views
> Discover em 25/08/2026; revisado em 26/08/2026 contra o DealerUp.
> **Tudo aqui verificado no dicionário ou medido na base.**

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

## 3. Duas dimensões diferentes — não confundir

O DealerNet classifica a nota por **duas** dimensões independentes. Usar a
errada é a causa nº 1 de número que não bate com o BI.

| | Dimensão | Tabela | Ligação | Para que serve |
| --- | --- | --- | --- | --- |
| **Fiscal** | `NaturezaOperacao` (301 códigos) | `NaturezaOperacao_Codigo` | `NotaFiscal_NaturezaOperacaoCod` | O que a nota **é** perante o fisco |
| **Gestão** | `Departamento` (35) | `Departamento_Codigo` | `NotaFiscal_DepartamentoCod` | A que **área** o resultado pertence |

**A regra:** o departamento diz *de quem é* o número; a natureza diz *se ele
conta*. Faturamento correto exige **as duas** — departamento para agrupar,
natureza para filtrar.

> Versões anteriores deste arquivo diziam que a natureza separava o
> departamento. **Está errado** e produziu o caso Thai Ananindeua jul/26
> (novos inflados em R$ 7,1M por somar venda direta dentro de novos).

### `NaturezaOperacao` — os códigos que importam

| Cód | Descrição | Movimento |
| --- | --- | --- |
| 11 | Venda de veículos novos | S |
| **13** | **Devolução de venda — veículos novos** | **E** |
| 19 | Venda de veículos usados show room | S |
| 165 | Venda de veículos usados repasse | S |
| 48 | Venda de veículos imobilizados | S |
| 74 | Venda de VN **direta** | S |
| 37 | Venda oficina | S |
| 38 | Venda garantia | S |
| **77** | **Devolução de venda — peças oficina** | **E** |
| 147 | Venda merc. adquiridos de terceiros | S |
| 129 | Venda peças — outra revenda | S |
| 289 | Venda peças — e-commerce | S |
| **12** | **Devolução de venda — peças varejo** | **E** |
| 31, 83, 173, 47, 168 | Comissões (financiamento, venda direta, seguros, outras) | S |
| 39 | Venda interna (baixa consumo interno) | S |
| 64 | Saída remessa para demonstração — VN | S |
| 65 | Entrada retorno de demonstração — VN | E |
| 7, 8 | Transferência de peças (saída / entrada) | S / E |
| 80, 79 | Ajuste de estoque (saída / entrada) | S / E |
| 1–4, 9, 71, 164 | Compras | E |

### `Departamento` — as 35 siglas

| Cód | Sigla | Descrição | Cód | Sigla | Descrição |
| --- | --- | --- | --- | --- | --- |
| 1 | AD | Administração | 19 | JO | Jeep Ourinhos |
| 2 | FP | Funilaria e pintura | 20 | MC | Oficina mec |
| 3 | PA | Peças e acessórios | 21 | NA | Ananindeua |
| 4 | SP | Assistência técnica | 22 | OF | Oficina adm |
| 5 | **VN** | **Veículos novos** | 23 | PF | Prod funilaria |
| 6 | **VU** | **Veículos usados** | 24 | PR | Prod mecânica |
| 7 | **VD** | **Venda direta** | 25 | VM | Veículos imobilizado |
| 8 | VI | Venda internet | 26 | VP | Paragominas |
| 9 | AU | Auto centro | 27 | GH | Outros |
| 10 | DF | Depósito fechado | 28 | AT | Altamira |
| 11 | DM | Diogo Moia | 29 | TS | T-Service |
| 12 | GA | Garantia | 30 | F&I | F&I |
| 13 | GU | Garantia usados | 31 | FA | Fiscont aud cont |
| 14 | IF | Improd funilaria | 32 | FIN | Financeiro |
| 15 | IM | Improd mecânica | 33 | TI | Tecnologia T.I |
| 16 | JA | Jeep Assis | 34 | GG | Gente e gestão |
| 17 | JB | Jeep Botucatu | 35 | FVM | Funilaria VM SP |
| 18 | JI | Jeep Itapetininga | | | |

`Departamento_Sigla` é `char` — vem com **padding à direita** (`'VN        '`).
Comparar com `=` funciona em T-SQL (ignora espaço à direita), mas ao trazer
para Python é preciso `.strip()`.

---

## 4. FATURAMENTO — a regra canônica

Validada contra o DealerUp em Thai Ananindeua (empresa 3), julho/2026,
com **zero de diferença** nos três blocos de veículos e na contagem de unidades.

### Filtros obrigatórios

```sql
nf.NotaFiscal_EmpresaCod = :empresa      -- #D11: NÃO é Empresa_Codigo
AND nf.NotaFiscal_Status = 'EMI'         -- exclui CAN, INU, DEN
AND nf.NotaFiscal_DataEmissao >= :inicio
AND nf.NotaFiscal_DataEmissao <  :fim    -- fim exclusivo, nunca BETWEEN
```

**Não filtrar `Movimento = 'S'` no WHERE.** As devoluções são `'E'` e
precisam entrar com sinal negativo — ver a regra 1 abaixo.

### As sete regras

**R1 — Devolução ABATE faturamento e unidade.** Naturezas 13 (VN), 77 (peças
oficina) e 12 (peças varejo), todas `Movimento='E'`. Entram com sinal
negativo e reduzem também a contagem de notas. É a regra mais fácil de
esquecer e a de maior impacto: sem ela o mês inteiro fica inflado.

**R2 — Natureza 48 (venda de imobilizados) é USADO** e entra no faturamento.
O próprio banco a classifica no departamento `VU`. É veículo que rodou
(ex-demonstração, ex-frota) sendo vendido a cliente final.

**R3 — Natureza 74 é VENDA DIRETA**, bloco próprio. Nunca somar dentro de
novos — tem margem e comissionamento distintos e o BI reporta separado.

**R4 — Natureza 39 (baixa consumo interno) SAI, não abate.** Peça retirada
para uso próprio da loja. Nunca houve receita reconhecida, então não há o que
estornar: retirar do numerador é o correto; subtrair criaria receita negativa
fictícia. *Provado:* VU bruto 6.420.210,84 − 17.200,84 = 6.403.010,00 exato.

**R5 — Natureza 64 (remessa demonstração) fica FORA.** Não é venda: é
circulação de veículo entre lojas do grupo, com contrapartida na natureza 65
(retorno). Em jul/26 foram 14 saídas (2.960.203,19) contra 16 retornos
(3.434.951,03), todos de/para THAI Altamira e THAI Castanhal.

**R6 — F&I identifica-se por NATUREZA, nunca por departamento.** O
departamento `F&I` (código 30) existe no cadastro mas tem **zero notas**; as
comissões vivem dentro de `VN` (31, 173, 47, 168) e `VD` (83). Agrupar por
departamento faz o bloco vir vazio.

**R7 — Fora do faturamento:** 7 (transf. peças), 80 (ajuste estoque), 102
(simples remessa), 125 (retorno comodato), 148 (baterias inservíveis), 243
(remessa peças garantia), 263 (bonificação/uso interno), 17 (devolução de
compra). São remessas, transferências e ajustes — não há receita.

### Divergência conhecida contra o DealerUp

Duas, ambas por desenho:

1. **F&I.** Por decisão do Grupo EBD, o Conc.ia **soma** as comissões F&I no
   total faturado da loja e as **reporta como bloco à parte**. O DealerUp não
   as conta. O Conc.ia ficará sistematicamente acima — jul/26: R$ 549.862,45.
   O número comparável com o DealerUp é o **total ex-F&I**.
2. **Pós-venda.** O DealerUp mede OS/item; nós medimos nota fiscal. Em jul/26
   ele conta 2.456 itens contra ~2.200 notas, e a receita diverge em
   R$ 46.980,04 (1,8%). **Não fecha por NF** e não vale perseguir.

Veículos, que são ~92% do faturamento, fecham ao centavo.

### Prova da reconciliação — Thai Ananindeua, jul/2026

| Bloco | Conta | Valor | Notas |
| --- | --- | --- | --- |
| VN | nat 11 − nat 13 | 18.960.680,00 − 368.908,00 = **18.591.772,00** | 79 − 2 = **77** |
| VU | nat 19 + 165 + 48 | 2.619.530,00 + 3.345.500,00 + 437.980,00 = **6.403.010,00** | 15 + 30 + 3 = **48** |
| VD | nat 74 | **6.774.157,12** | **31** |
| **Veículos** | | **31.768.939,12** | **156** |

DealerUp: 31.768.939,12 · 156 unidades. Diferença: **zero**.

---

## 5. Template T-DN-FAT-01 — faturamento por bloco

```sql
WITH mov AS (
    SELECT
        d.Departamento_Sigla AS depto,
        nf.NotaFiscal_NaturezaOperacaoCod AS nat,
        CASE
            WHEN nf.NotaFiscal_NaturezaOperacaoCod = 11  THEN 'VEICULOS NOVOS'
            WHEN nf.NotaFiscal_NaturezaOperacaoCod = 13  THEN 'VEICULOS NOVOS'
            WHEN nf.NotaFiscal_NaturezaOperacaoCod IN (19, 165, 48) THEN 'SEMINOVOS'
            WHEN nf.NotaFiscal_NaturezaOperacaoCod = 74  THEN 'VENDA DIRETA'
            WHEN nf.NotaFiscal_NaturezaOperacaoCod IN (37, 38, 77) THEN 'OFICINA'
            WHEN nf.NotaFiscal_NaturezaOperacaoCod IN (147, 129, 289, 70, 59, 170, 41, 12) THEN 'PECAS'
            WHEN nf.NotaFiscal_NaturezaOperacaoCod IN (31, 83, 173, 47, 168) THEN 'F&I'
        END AS bloco,
        CASE WHEN nf.NotaFiscal_NaturezaOperacaoCod IN (13, 77, 12)
             THEN -1 ELSE 1 END AS sinal,
        nf.NotaFiscal_ValorTotal AS valor
    FROM NotaFiscal nf WITH (NOLOCK)
    LEFT JOIN Departamento d WITH (NOLOCK)
           ON d.Departamento_Codigo = nf.NotaFiscal_DepartamentoCod
    WHERE nf.NotaFiscal_EmpresaCod = :empresa
      AND nf.NotaFiscal_Status = 'EMI'
      AND nf.NotaFiscal_DataEmissao >= :inicio
      AND nf.NotaFiscal_DataEmissao <  :fim
      AND nf.NotaFiscal_NaturezaOperacaoCod IN
          (11, 13, 19, 165, 48, 74, 37, 38, 77, 147, 129, 289, 70, 59, 170, 41, 12,
           31, 83, 173, 47, 168)
)
SELECT bloco,
       SUM(sinal)         AS notas,
       SUM(sinal * valor) AS faturamento
FROM mov
GROUP BY bloco
ORDER BY faturamento DESC;
```

Ao apresentar: mostrar **F&I como linha à parte** e dois totais — *total
faturado* (com F&I) e *total ex-F&I* (comparável ao DealerUp).

---

## 6. `TipoOS` — classificação pronta pelo fabricante

218 tipos, com **`TipoOS_Classificacao`** dizendo quem é o pagador:

| Classificação | Significado |
| --- | --- |
| `CLI` | **Cliente pagante** — receita de oficina |
| `GAR` | Garantia (fábrica paga) |
| `DEP` | Interna / departamento (não é receita) |
| `OUT` | Comissão e outros (F&I, venda compartilhada) |
| `REC` | Retorno / retrabalho |

Também há `TipoOS_FontePagadora`, `TipoOS_Revisao` (bit),
`TipoOS_ServicoRapido`, `TipoOS_SetorServicoCod` e `TipoOS_Ativo`.

Exemplos: `CSR` cliente serviço reparo · `CFR` fast repair · `CSP` manutenção
periódica · `GS` garantia serviços · `GSR` recall · `ISN` interno serviço novos.

> No NBS o equivalente (`OS_TIPOS.PRODUTIVA`) levou horas para ser descoberto.
> Aqui a classificação é explícita — **usar `Classificacao`, não parsear a sigla**.

Isto classifica a **OS**, não a nota. Para faturamento, ver a seção 5.

---

## 7. Entidades núcleo (por centralidade de FK)

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

## 8. Campos de valor e data

**`NotaFiscal`**: `_ValorTotal`, `_ValorDesconto`, `_ValorFrete`, `_ValorSeguro`,
`_ValorAcrescimo`, `_ValorJuros` · datas: `_DataEmissao`, `_DataMovimento`,
`_DataExpedicao`, `_DataChegada`

Em venda de veículo novo, `_ValorDesconto`, `_ValorFrete`, `_ValorSeguro`,
`_ValorAcrescimo` e `_ValorJuros` vêm **todos zerados** — o valor é o
`_ValorTotal` puro. Não existe base de valoração alternativa.

**`NotaFiscalItem`**: `_ValorTotal`, `_ValorUnitario`, `_ValorLucroBruto`,
`_ValorMargemContabil`, `_ValorMargemGerencial`, `_ValorCargaTributaria`,
`_ValorBonusFabrica`, `_ValorTotalBrutoSemDesconto`. Em VN jul/26,
`_ValorBonusFabrica` e `_ValorTotalBrutoSemDesconto` vêm zerados;
`_ValorLucroBruto` é o campo vivo de margem.

**`OS`**: `_DataCriacao` (abertura), `_DataPrometida`, `_DataRecepcao`,
`_DataLiberacaoVeiculo`, `_DataTecnicoInicio/Fim`, `_AgendamentoData`

**`OficinaServico` / `OficinaProduto`**: `_ValorUnitario`, `_ValorDesconto`,
`_ValorCusto` (só em Produto)

**`Titulo`**: `_Valor`, `_DataEmissao`, `_DataVencimento`, `_DataPagamento`

---

## 9. Comparação com o NBS

| | NBS (Oracle) | DealerNet (SQL Server) |
| --- | --- | --- |
| Concessionárias | 1 (Isar/BMW) | 30 (6 grupos, 7 marcas) |
| Tabelas | 8.160 | 2.850 |
| Escopo | `COD_EMPRESA` | `NotaFiscal_EmpresaCod` |
| Nota | `VENDAS` | `NotaFiscal` |
| Status nota | `'0'` ativa | `'EMI'` emitida |
| OS | `OS` (`STATUS_OS` numérico) | `OS` (`OS_Status` char) |
| Cliente | `CLIENTES` + `CLIENTE_DIVERSO` | `Pessoa` (unificado) |
| Classificação de OS | `OS_TIPOS.PRODUTIVA` | `TipoOS_Classificacao` |
| Departamento | `COD_OPERACAO` | `NotaFiscal_DepartamentoCod` |
| Nomenclatura | críptica (`COD_*`) | legível (`Tabela_Campo`), com exceções |

**As cicatrizes do NBS não valem aqui.** `COD_OPERACAO`, `VENDA_ITENS`,
`PRECO_LIQUIDO_FINAL`, `OS_TIPOS` e `NATUREZA_APLICACAO` não existem no
DealerNet. Ver `sql-corrections-dealernet.md`.

---

## 10. Aberto

- `Pessoa` **não tem coluna de CPF/CNPJ** — deve estar em tabela satélite
  ligada por `Pessoa_TipoPessoa`. Não localizada.
- Colunas de ligação `OS` ↔ `NotaFiscal` (existe `NotaFiscal_OSTipoOSCod`,
  falta confirmar a chave completa)
- `TipoOS_FontePagadora` — valores `'0 '`, `'00'`, `'01'` sem significado claro
- Base de cálculo do pós-venda no DealerUp (mede OS/item, não NF)
- Regras validadas em **uma** empresa e **um** mês. Confirmar em agosto e numa
  segunda empresa (VM Manaus, Antares) antes de tratar como lei.
