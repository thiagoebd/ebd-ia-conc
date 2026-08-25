#!/usr/bin/env bash
# ============================================================
# Adiciona a tool dealernet_query ao agente (2o DMS).
# Rodar da raiz do repo: bash aplica-tool-dealernet.sh
# ============================================================
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
STAMP=$(date +%Y%m%d-%H%M%S)
for f in core/app/config.py core/app/agent.py; do cp "$f" "$f.bak-$STAMP"; done

# ------------------------------------------------------------
# 1. config.py — par URL/token do DealerNet
# ------------------------------------------------------------
python3 - <<'PY'
import pathlib
p = pathlib.Path("core/app/config.py")
t = p.read_text(encoding="utf-8")
alvo = '''    mcp_oracle_url: str = Field(..., alias="MCP_ORACLE_URL")
    mcp_oracle_token: str = Field(..., alias="MCP_ORACLE_TOKEN")'''
novo = '''    mcp_oracle_url: str = Field(..., alias="MCP_ORACLE_URL")
    mcp_oracle_token: str = Field(..., alias="MCP_ORACLE_TOKEN")

    # MCP DealerNet (SQL Server) — 30 concessionarias
    mcp_dn_url: str = Field("http://localhost:8991/mcp", alias="MCP_DN_URL")
    mcp_dn_token: str = Field("", alias="MCP_DN_TOKEN")'''
assert t.count(alvo) == 1, "ancora do config nao encontrada"
p.write_text(t.replace(alvo, novo), encoding="utf-8")
print("  config.py ok")
PY

# ------------------------------------------------------------
# 2. dealernet_bridge.py — copia do oracle_bridge, trocando alvo
# ------------------------------------------------------------
python3 - <<'PY'
import pathlib, re
src = pathlib.Path("core/app/tools/oracle_bridge.py").read_text(encoding="utf-8")
t = src
# endpoint e token
t = t.replace("settings.mcp_oracle_url", "settings.mcp_dn_url")
t = t.replace("settings.mcp_oracle_token", "settings.mcp_dn_token")
# nomes de simbolo
t = t.replace("ORACLE_QUERY_TOOL", "DEALERNET_QUERY_TOOL")
t = t.replace("execute_oracle_query", "execute_dealernet_query")
t = t.replace('"oracle_query"', '"dealernet_query"')
t = t.replace("'oracle_query'", "'dealernet_query'")
t = t.replace("ORACLE_FORENSE", "DEALERNET_FORENSE")
t = t.replace("oracle_query OK", "dealernet_query OK")
t = t.replace('"""Ponte pro MCP Oracle local. Expoe oracle_query como tool do Claude SDK."""',
              '"""Ponte pro MCP DealerNet (SQL Server). Expoe dealernet_query como tool."""')
# descricao da tool: dialeto T-SQL e regras do DealerNet
t = re.sub(
    r'("description": \()\s*\n(\s+)"Executa uma query SQL READ-ONLY.*?\n(\s+)\),',
    r'''\1
\2"Executa uma query SQL READ-ONLY (T-SQL) contra o DealerNet Workflow "
\2"(SQL Server) — 30 concessionarias: Toyota(Thai), Jeep(Way), Fiat(VM/Viale), "
\2"Ford(Antares), Hyundai(Miso), Leapmotor. "
\2"DIALETO T-SQL: use TOP n (nao FETCH FIRST), GETDATE() (nao SYSDATE), "
\2"ISNULL (nao NVL), CONVERT/FORMAT (nao TO_DATE/TO_CHAR). "
\2"SEMPRE filtre Empresa_Codigo. Para venda: NotaFiscal_Status=\'EMI\' AND "
\2"NotaFiscal_Movimento=\'S\'. Tabelas: NotaFiscal, NotaFiscalItem, OS, "
\2"OficinaServico, OficinaProduto, Veiculo, Pessoa, Produto, Titulo, Empresa. "
\2"Base grande (ProdutoPreco tem 800M linhas) — sempre com WHERE restritivo. "
\2"Retorna ate 1000 linhas."
\3),''',
    t, count=1, flags=re.S)
pathlib.Path("core/app/tools/dealernet_bridge.py").write_text(t, encoding="utf-8")
print("  dealernet_bridge.py criado")
PY

# ------------------------------------------------------------
# 3. agent.py — importar e registrar a tool
# ------------------------------------------------------------
python3 - <<'PY'
import pathlib, re
p = pathlib.Path("core/app/agent.py")
t = p.read_text(encoding="utf-8")

# import
if "dealernet_bridge" not in t:
    t = t.replace(
        "from app.tools.artifact_tools import CREATE_EXCEL_TOOL",
        "from app.tools.dealernet_bridge import (\n"
        "    DEALERNET_QUERY_TOOL,\n"
        "    execute_dealernet_query,\n"
        ")\n"
        "from app.tools.artifact_tools import CREATE_EXCEL_TOOL", 1)

# lista de tools
t = t.replace("_tools = [ORACLE_QUERY_TOOL,",
              "_tools = [ORACLE_QUERY_TOOL, DEALERNET_QUERY_TOOL,", 1)

# dispatcher: replicar o bloco do oracle_query
m = re.search(r'\n(\s+)(if|elif) name == "oracle_query":\n(.*?)(?=\n\s+(?:el)?if name == )', t, re.S)
if m and 'name == "dealernet_query"' not in t:
    indent, corpo = m.group(1), m.group(3)
    novo = corpo.replace("execute_oracle_query", "execute_dealernet_query")
    bloco = f'\n{indent}elif name == "dealernet_query":\n{novo}'
    t = t[:m.end()] + bloco + t[m.end():]
    print("  dispatcher: bloco dealernet_query inserido")
else:
    print("  ATENCAO: dispatcher nao alterado — inserir manualmente")

p.write_text(t, encoding="utf-8")
PY

python3 -c "
import ast
for f in ['core/app/config.py','core/app/agent.py','core/app/tools/dealernet_bridge.py']:
    ast.parse(open(f).read()); print('  sintaxe ok:', f)
"

# ------------------------------------------------------------
# 4. core/.env — URL e token do MCP DealerNet
# ------------------------------------------------------------
TOKEN=$(grep '^MCP_DN_TOKEN=' .env | cut -d= -f2)
grep -q '^MCP_DN_URL=' core/.env || cat >> core/.env <<EOF

# MCP DealerNet (SQL Server)
MCP_DN_URL=http://localhost:8991/mcp
MCP_DN_TOKEN=$TOKEN
EOF
grep '^MCP_DN' core/.env

echo
echo ">> Tools registradas:"
grep -n "^_tools = " core/app/agent.py
echo ">> Backups: *.bak-$STAMP"
