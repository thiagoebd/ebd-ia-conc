#!/usr/bin/env bash
# ============================================================
# Separa cicatrizes por DMS e exige verificacao antes de propor.
#
# PROBLEMA 1: o knowledge_append aponta para docs/sql-corrections.md,
#             que virou sql-corrections-nbs.md -> /aprovar quebrou.
# PROBLEMA 2: com 2 DMS, cicatriz do DealerNet caia no arquivo do NBS.
# PROBLEMA 3 (o grave): a #D12 foi aprovada citando uma coluna que NAO
#             existe. A base absorveu informacao falsa e so descobriu ao
#             errar de novo. Agora o agente tem que verificar antes.
#
# Rodar da raiz do repo: bash separa-cicatrizes.sh
# ============================================================
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
STAMP=$(date +%Y%m%d-%H%M%S)
cp core/app/tools/knowledge_append.py "core/app/tools/knowledge_append.py.bak-$STAMP"
cp core/app/system_prompt.py "core/app/system_prompt.py.bak-$STAMP"

# ------------------------------------------------------------
# 1. Arquivo de cicatrizes do DealerNet
# ------------------------------------------------------------
if [ ! -f docs/sql-corrections-dealernet.md ]; then
cat > docs/sql-corrections-dealernet.md <<'MDEOF'
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
MDEOF
echo "  docs/sql-corrections-dealernet.md criado (#D01-#D11)"
fi

# ------------------------------------------------------------
# 2. Whitelist do knowledge_append: um arquivo por DMS
# ------------------------------------------------------------
python3 - <<'PY'
import pathlib, re
p = pathlib.Path("core/app/tools/knowledge_append.py")
t = p.read_text(encoding="utf-8")

novo_map = '''ARQUIVOS_PERMITIDOS = {
    "cicatriz": "sql-corrections-nbs.md",            # compat: default NBS
    "cicatriz_nbs": "sql-corrections-nbs.md",
    "cicatriz_dealernet": "sql-corrections-dealernet.md",
    "knowledge": "knowledge.md",
    "template": "query_templates.md",
}'''
t = re.sub(r"ARQUIVOS_PERMITIDOS = \{.*?\n\}", novo_map, t, count=1, flags=re.S)

# enum do parametro tipo, na descricao da tool
t = t.replace('"enum": ["cicatriz", "knowledge", "template"]',
              '"enum": ["cicatriz_nbs", "cicatriz_dealernet", "knowledge", "template"]')
t = t.replace("'enum': ['cicatriz', 'knowledge', 'template']",
              "'enum': ['cicatriz_nbs', 'cicatriz_dealernet', 'knowledge', 'template']")

p.write_text(t, encoding="utf-8")
print("  whitelist atualizada")
PY
python3 -c "import ast; ast.parse(open('core/app/tools/knowledge_append.py').read()); print('  sintaxe ok')"
grep -n "ARQUIVOS_PERMITIDOS" -A7 core/app/tools/knowledge_append.py

# ------------------------------------------------------------
# 3. Regra: verificar ANTES de propor  (o problema grave)
# ------------------------------------------------------------
python3 - <<'PY'
import pathlib
p = pathlib.Path("core/app/system_prompt.py")
t = p.read_text(encoding="utf-8")
if "CURADORIA DA BASE" in t:
    print("  regra ja existe")
else:
    alvo = "### PROIBIDO INVENTAR CAPACIDADE"
    regra = '''### CURADORIA DA BASE — verifique ANTES de propor

A tool `knowledge_append` grava conhecimento permanente. Cicatriz errada
aprovada **envenena todas as consultas seguintes** — ja aconteceu: a #D12
afirmou que existia uma coluna `OSTipoOS_TipoOSClas` que nao existe, e o erro
so apareceu quando o agente tentou usa-la.

Antes de propor cicatriz que cite **nome de tabela ou coluna**:
1. Verifique no dicionario NESTA sessao
   (`ALL_TAB_COLUMNS` no NBS · `INFORMATION_SCHEMA.COLUMNS` no DealerNet)
2. So proponha o que voce confirmou executando
3. Se nao verificou, verifique — nao proponha "de memoria" nem por analogia

Escolha o `tipo` certo, senao a cicatriz vai para o arquivo do outro banco:
- `cicatriz_nbs` — armadilha do NBS (Oracle)
- `cicatriz_dealernet` — armadilha do DealerNet (SQL Server)
- `knowledge` — vocabulario e regra de negocio (vale para os dois)
- `template` — SQL validado contra numero de referencia externo

'''
    t = t.replace(alvo, regra + alvo, 1)
    p.write_text(t, encoding="utf-8")
    print("  regra de curadoria adicionada")
PY
python3 -c "import ast; ast.parse(open('core/app/system_prompt.py').read()); print('  sintaxe ok')"

# ------------------------------------------------------------
# 4. KB_FILES: carregar os dois arquivos de cicatriz
# ------------------------------------------------------------
python3 - <<'PY'
import pathlib, re
p = pathlib.Path("core/app/system_prompt.py")
t = p.read_text(encoding="utf-8")
t = t.replace('    "sql-corrections.md",', '    "sql-corrections-nbs.md",')
if "sql-corrections-dealernet.md" not in t:
    t = t.replace('    "sql-corrections-nbs.md",',
                  '    "sql-corrections-nbs.md",\n    "sql-corrections-dealernet.md",', 1)
p.write_text(t, encoding="utf-8")
print("  KB_FILES ok")
PY
grep -n "^KB_FILES" -A12 core/app/system_prompt.py

# ------------------------------------------------------------
# 5. Remover a #D12 falsa, se estiver gravada
# ------------------------------------------------------------
if grep -q "OSTipoOS_TipoOSClas" docs/*.md 2>/dev/null; then
  echo
  echo "  !! A cicatriz falsa (#D12 com OSTipoOS_TipoOSClas) esta gravada em:"
  grep -ln "OSTipoOS_TipoOSClas" docs/*.md
  echo "     Revise e remova a mao — nao apago automaticamente."
fi

echo
echo "=============================================="
echo " Feito. Reinicie o gateway:"
echo "   pkill -f 'uvicorn gateway.app.main'; sleep 1"
echo "   nohup python3 -m uvicorn gateway.app.main:app --host 0.0.0.0 --port 8000 > /tmp/gw.log 2>&1 &"
echo " Backups: *.bak-$STAMP"
echo "=============================================="
