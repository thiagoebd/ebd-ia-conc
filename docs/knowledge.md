# knowledge.md — vocabulário e regras de negócio (concessionárias / NBS)

> Traduz o jeito que o gestor fala para as tabelas do NBS.
> Tudo aqui foi verificado no dicionário do banco em 04/08/2026.
> **Se algo não está aqui, não invente: consulte o dicionário e pergunte.**

---

## 1. Departamentos da concessionária

| Termo do gestor | O que é | Onde vive no NBS |
| --- | --- | --- |
| **Veículos novos** | venda de zero km | `VENDAS` + `NATUREZA.NATUREZA_APLICACAO = 'F'` |
| **Seminovos / usados** | usado e consignado | `NATUREZA_APLICACAO = 'K'` |
| **Oficina** | serviço executado em OS | `OS` + `NATUREZA_APLICACAO = 'M'` |
| **Balcão** | peça vendida sem OS | `NATUREZA_APLICACAO` em `'5'`, `'3'`, `'7'` |
| **Funilaria** | reparo de lataria/pintura | `OS.PAINEL_FUNILARIA`, `OS_SERVICOS.STATUS_FUNILARIA` |
| **Garantia** | serviço pago pela montadora | `OS_TIPOS.GARANTIA = 'S'` / `NATUREZA_APLICACAO = 'O'` |
| **Interna** | serviço na frota da própria empresa | `OS_TIPOS.INTERNO = 'S'` / `NATUREZA_APLICACAO = 'N'` |

## 2. Vocabulário de oficina

- **Passagem** — uma OS aberta para um veículo. Conta-se OS, não serviço.
- **Consultor técnico** — quem recebe o cliente (`OS.QUEM_ABRIU`,
  `OS.CONSULTOR_RECEPCAO`, `OS.CONSULTOR_ENTREGA`).
- **Produtivo / técnico** — quem executa (`SERVICOS_TECNICOS`,
  `OS_SERVICOS.COD_PRODUTIVO`).
- **Reclamação** — o que o cliente relatou (`OS_ORIGINAL`); uma OS tem várias.
- **Requisição** — peça pedida ao estoque dentro da OS (`OS_REQUISICOES`).
- **Apontamento** — registro de tempo do produtivo (`OS_TEMPOS_EXECUTADOS`).
- **Horas vendidas x trabalhadas** — vendidas é o tempo padrão cobrado;
  trabalhadas é o real apontado. A razão entre elas é a produtividade.
- **Orçamento** — mora na MESMA tabela `OS` (`OS.ORCAMENTO`, status 3 e 8).
- **OS única / agrupadora** — consolida várias OS (status 5 e 6).
- **Recall / campanha** — `OS_CAMPANHA.EH_RECALL`, `OS_AGENDA.EH_CAMPANHA`.
- **Revisão** — `OS.EH_REVISAO`, `OS.NUMERO_REVISAO`, `SERVICO_REVISAO`.

## 3. Vocabulário de veículos

- **Chassi** — `CHASSI_RESUMIDO` é a chave de trabalho; `CHASSI_COMPLETO` é o VIN.
- **Novo x usado** — `VEICULOS.NOVO_USADO` (valores a confirmar) e, na receita,
  `NATUREZA_APLICACAO` `F` x `K`.
- **Pátio** — `VEICULOS.COD_PATIO`. **Demonstração** — `DEMO_EXPO`, `DEMONSTRACAO`.
- **Proposta** — `VEICULOS_PROPOSTAS`, antes da nota.
- **Holdback / floor plan** — `VEICULOS_DADOS_HOLDBACK`, `VEICULOS.TAXA_JUROS`.
- **Emplacamento** — `VEICULOS_EMPLACAMENTO` (interno, não confundir com
  emplacamento de mercado da Fenabrave).

## 4. Estrutura organizacional

- **Empresa** (`EMPRESAS`) é a unidade de escopo. Hoje: 1 operacional, 100 matriz.
- **Divisão / departamento** (`EMPRESAS_DIVISOES`): `PRODUTIVO` =
  B‑Balcão, T‑Tele‑Peças, S‑Serviços, V‑Veículos, O‑Outros; `VEICULOS` =
  N‑Novos, S‑Seminovos, D‑Venda Direta. **É a chave para separar departamento.**
- **Usuário** (`EMPRESAS_USUARIOS`) — referenciado por NOME, não por código.
- **Metas** — `EMPRESAS_META` e `EMPRESAS_META_USUARIO` (prospecção, contato,
  veículos vendidos, test drive), por mês/ano e processo.

## 5. Perguntas ambíguas — o que confirmar antes de consultar

- "Faturamento" sem qualificar → perguntar se é total, oficina, balcão ou veículos.
- "Vendas de hoje" → veículo ou peça? A conta é bem diferente.
- "OS abertas" → inclui orçamento? inclui agrupadora? (padrão: não)
- "Mês" → competência de emissão da nota ou de encerramento da OS?


<!-- AUTO-APPEND PROP-AC9F4A6A aprovado por thiago.parreira@ebdgrupo.com.br -->

## Consultor técnico — como identificar (verificado 06/08/2026)

A coluna `EMPRESAS_USUARIOS.CONSULTOR_TECNICO` (VARCHAR2(1)) **existe mas está 100% nula** nos 173 usuários — não é usada nesta instalação. NÃO usar para contar consultores.

O caminho correto é a função:
- `EMPRESAS_USUARIOS.COD_FUNCAO = 42` → `EMPRESAS_FUNCOES.DESCRICAO = 'Consultor Tecnico'`
- `EMPRESAS_FUNCOES` é global (PK só `COD_FUNCAO`, sem empresa); `EMPRESAS_USUARIOS.COD_FUNCAO` referencia por FK `SYS_C0024412`.
- Ativo/inativo: `EMPRESAS_USUARIOS.DEMITIDO` ('S' = demitido; 'N'/NULL = ativo). Não usar `LIBERADO` como critério (quase todo mundo NULL).
- Empresa 1 (06/08/2026): 10 cadastrados na função 42, 2 demitidos (DANIELLY.P, KATIA.GOME) → 8 ativos.
- Cuidado: AG.BMW (agendamento), CARLOS.CON e NEYLA.CONS são perfis de sistema com essa função — se a pergunta for "pessoas físicas", excluir.


<!-- AUTO-APPEND PROP-54A904B2 aprovado por thiago.parreira@ebdgrupo.com.br -->

## Equipe comercial — regra de consulta (aprovado por admin, 06/08/2026)

**Regra:** toda consulta a funções de equipe (consultor de vendas, consultor técnico, vendedor, supervisor, gerente comercial, balcão) deve retornar **somente ativos** — `EMPRESAS_USUARIOS.DEMITIDO <> 'S'` (ou IS NULL). O gestor não quer ver demitidos em ranking, contagem ou listagem. Sempre aplicar o filtro, sem precisar o usuário repetir.

**Cargos mapeados (EMPRESAS_FUNCOES, empresa 1, 06/08/2026):**
- Função 42 — 'Consultor Tecnico': 10 cadastrados → 8 ativos (2 demitidos: DANIELLY.P, KATIA.GOME)
- Função 15 — 'Executivo de Vendas' (é o "consultor de vendas" do NBS): 15 cadastrados → 8 ativos
- Função 44 — 'Vendedor de Pecas' (balcão): 6 → 4 ativos
- Função 46 — 'Supervisor de Vendas': 1 → 1 ativo
- Função 13 — 'Gerente Comercial': 8 → 4 ativos

**Observação:** `DEMITIDO` = 'S' demitido; 'N'/NULL = ativo. Não usar `LIBERADO` como critério (quase todo mundo NULL).

**Atenção a perfis de sistema:** AG.BMW (agendamento automático BMW), CARLOS.CON, NEYLA.CONS têm função de consultor mas são perfis de sistema, não pessoas físicas — excluir se a pergunta for sobre pessoas.
