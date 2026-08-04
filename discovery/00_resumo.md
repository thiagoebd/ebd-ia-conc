# Discover NBS — schema NBS

Gerado em 04/08/2026 11:02

- Tabelas: **8160** (com estatistica: 1853, com comentario: 2432)
- Colunas: **114008**
- Registros de chave (PK/UK/FK): **24804**
- Tabelas referenciadas por FK: **2689**

## Prefixos de nome (4 letras, >=20 tabelas)

| prefixo | tabelas |
|---|---|
| FAB_ | 2256 |
| CRM_ | 263 |
| GARA | 142 |
| SEF2 | 136 |
| FCA_ | 123 |
| CLIE | 108 |
| VEIC | 97 |
| BMW_ | 96 |
| NISS | 93 |
| RENA | 92 |
| CONT | 89 |
| FORD | 87 |
| RECA | 69 |
| TOYO | 65 |
| INTE | 63 |
| ITEN | 60 |
| COMP | 59 |
| VEND | 56 |
| BSC_ | 52 |
| NBSA | 52 |
| MERC | 47 |
| TMP_ | 47 |
| TIPO | 46 |
| ECF_ | 45 |
| APUR | 44 |
| LOG_ | 42 |
| PEDI | 42 |
| ORC_ | 38 |
| REIN | 37 |
| PORT | 36 |
| CNH_ | 35 |
| NFE_ | 34 |
| PARM | 34 |
| DRCS | 33 |
| SERV | 32 |
| PAT_ | 31 |
| COM_ | 30 |
| HYUN | 29 |
| OS_A | 26 |
| OS_T | 26 |
| EMPR | 25 |
| ENTR | 25 |
| NBS_ | 25 |
| SPED | 25 |
| GAR_ | 24 |
| MEF_ | 23 |
| XENT | 23 |
| BIHO | 22 |
| PARA | 22 |
| VW_E | 22 |
| ALIQ | 21 |
| GODR | 21 |
| MOB_ | 21 |
| PORS | 21 |
| TEMP | 21 |
| AUTO | 20 |
| DEF_ | 20 |
| ECOM | 20 |
| GM_I | 20 |
| NFSE | 20 |
| SIST | 20 |

## 60 maiores por num_rows

| tabela | num_rows | comentario |
|---|---|---|
| BMW_KSD_AW03_04 | 17448343 |  |
| BMW_KSD_FG01 | 13643432 |  |
| ITENS_HISTORICO | 10077394 |  |
| ITEM_PRECO_HIS | 7947506 | Armazena os logs das operacoes de atualizacoes de precos dos |
| BMW_SALES_ATENDIMENTO_DET | 6620246 | Tabela utilizada para armazenar os detalhes de integracao de |
| TMP_CARGA_BMW_AW04 | 3040992 |  |
| AUDITORIA_LOG | 2305201 |  |
| FAB_MOV_DET_BMW_CRG | 1203658 | Entidade responsavel por armazenar as tentativas de comunica |
| FAB_MOV_BMW_CRG | 1194565 | Entidade responsavel por armazenar os movimentos de integrac |
| FAB_MOV_TAR_BMW_CRG | 1194565 | Entidade responsavel por armazenar as tarefas dos movimentos |
| LOG_LANCAMENTO_CONTABIL | 894391 |  |
| SAAM_CONTR_MALHA | 891831 |  |
| CARGA_TRIBUTARIA_IBPT | 670147 | Carga tributaria IBPT |
| LANCAMENTO_CONTABIL | 666560 |  |
| ITENS_FORNECEDOR_LOG | 436602 |  |
| CRUZAMENTO_VEIC_MOTOR | 431012 |  |
| CRUZAMENTO_VEIC_COR_EXT | 417549 |  |
| BMW_BIC_OS_DET | 330231 |  |
| R0200 | 328314 |  |
| LOG_LOTE_CONTABIL | 310061 |  |
| LOG_FINANCEIRO | 287796 |  |
| CAMPANHA_VEICULOS | 230890 |  |
| LOG_PAF_ECF | 220982 |  |
| TEMPOS_PADROES | 207999 |  |
| H010 | 199010 |  |
| NFE_MENSAGEM | 194918 |  |
| ITENS_FORNECEDOR | 185152 |  |
| ITENS_CUSTOS | 185151 |  |
| ITENS | 185136 |  |
| BMW_SRD_DISPO | 184258 |  |
| ITENS_FABRICA | 184012 |  |
| C190 | 183531 |  |
| FAB_LOG_ASYNC | 179998 |  |
| LOTE_CONTABIL | 172255 |  |
| SPED_MSG | 159025 |  |
| C170 | 151652 |  |
| MEM | 150121 |  |
| C100 | 147996 |  |
| EMAIL_FILA | 143882 |  |
| TMP_CARGA_BMW_AW03 | 137907 |  |
| LCONTAS | 129741 |  |
| PC_DEF_MOVIMENTO | 127414 |  |
| SPED_ARQ_REGISTRO | 117785 |  |
| C170_PIS | 115959 |  |
| CARDEX_CONTABIL | 92263 |  |
| LOG_NORDESTE | 89904 |  |
| BMW_KSD_AW02 | 84686 |  |
| CRUZAMENTO_VEIC_COMBUST | 84044 |  |
| OS_ORIGINAL | 83296 |  |
| RECADOS | 80650 |  |
| RECADO_TEXTO | 80650 |  |
| TOTALIZADOR_MENSAL | 78447 |  |
| VEIC_CUSTO_CARDEX | 76888 |  |
| C195 | 71608 |  |
| NFE_DISTRIBUICAO | 68958 |  |
| VEICULOS_CUSTOS_ESPECIFICOS | 68574 |  |
| R0200_PIS | 68129 |  |
| SERVICOS | 67631 |  |
| RECLAMACAO_PECAS | 67567 |  |
| RECLAMACAO_PECAS_EMPRESA | 67567 |  |

## 60 mais referenciadas por FK (nucleo do modelo)

| tabela | FKs apontando |
|---|---|
| EMPRESAS | 492 |
| EMPRESAS_USUARIOS | 206 |
| FAB_EMPRESA | 205 |
| OS | 182 |
| ITENS_FORNECEDOR | 172 |
| LCONTAS | 144 |
| VENDAS | 144 |
| PRODUTOS_MODELOS | 132 |
| FAB_TAREFA | 126 |
| FAB_OPERACAO | 123 |
| NATUREZA | 120 |
| CENTRO_CUSTO | 110 |
| VEICULOS | 108 |
| CONTA_CONTABIL | 96 |
| FAB_API_ENDPOINT | 88 |
| LOTE_CONTABIL | 84 |
| COMPRA | 82 |
| CLIENTE_DIVERSO | 80 |
| CONTA_PAGAR | 65 |
| SERVICOS | 64 |
| CRM_EVENTOS | 64 |
| FORMA_COBRANCA | 62 |
| ADIANTAMENTO | 60 |
| HISTORICO_PADRAO | 60 |
| PRODUTOS | 59 |
| NATUREZA_RECEITA_DESPESA | 58 |
| CLIENTES | 58 |
| C100 | 56 |
| EMPRESAS_DIVISOES | 54 |
| EMAIL_GRUPO | 46 |
| FORMA_PGTO | 46 |
| OS_ORIGINAL | 45 |
| PLANO_CONTAS | 45 |
| CONTA_RECEBER | 45 |
| UF | 38 |
| ECF_EMPRESAS | 36 |
| CRM_EVENTOS_TIPO | 35 |
| OS_TIPOS | 34 |
| SERVICOS_TECNICOS | 34 |
| FAB_MOV_BYD_VEND | 34 |
| EMPRESAS_DEPARTAMENTOS | 32 |
| OS_SERVICOS | 32 |
| EMPRESAS_FUNCOES | 31 |
| CONTAS_RECEBER | 30 |
| ITENS_CLASSE_CONTABIL | 29 |
| ITENS | 28 |
| OS_AGENDA | 28 |
| SEF2_8545 | 28 |
| FORNECEDOR_ESTOQUE | 27 |
| CADASTRO_LOCACAO | 27 |
| CUSTOS_ESPECIFICOS | 26 |
| CONTA_CORRENTE | 26 |
| CLASSE | 26 |
| C170 | 25 |
| EMPRESAS_FTP | 24 |
| FAB_MOV_TOY_TAV2 | 24 |
| FCA_MVP_SG | 24 |
| PAF_DAV_ITEM | 24 |
| FAB_MOV_BYD_POSV | 23 |
| OPERACOES | 22 |
