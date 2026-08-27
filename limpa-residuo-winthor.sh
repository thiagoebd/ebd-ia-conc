#!/usr/bin/env bash
# ============================================================
# Remove os residuos do Winthor/distribuicao do codigo do agente.
# Rodar da raiz do repo:  bash limpa-residuo-winthor.sh
# Faz backup .bak-<stamp> de cada arquivo alterado.
# ============================================================
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
STAMP=$(date +%Y%m%d-%H%M%S)

bkp() { cp "$1" "$1.bak-$STAMP"; }

# ------------------------------------------------------------
# 1. templates.json — catalogo INTEIRO e do Winthor.
#    E a maior fonte de contaminacao: o agente chama list_templates
#    e recebe T210 "Faturamento por filial", GD_FATO_*, RCA, inadimplencia.
#    Zera mantendo a estrutura; os templates do NBS entram validados, um a um.
# ------------------------------------------------------------
bkp core/app/data/templates.json
python3 - <<'PY'
import json, pathlib, datetime
p = pathlib.Path("core/app/data/templates.json")
d = json.loads(p.read_text(encoding="utf-8"))
d["templates"] = []
d["source"] = "NBS (concessionarias) — catalogo a construir"
d["source_sha256"] = ""
d["generated_at"] = datetime.datetime.now().isoformat(timespec="seconds")
p.write_text(json.dumps(d, ensure_ascii=False, indent=2), encoding="utf-8")
print("templates.json zerado")
PY

# ------------------------------------------------------------
# 2. oracle_bridge.py — descricao da tool mandava usar GD_FATO_*/PC*
# ------------------------------------------------------------
bkp core/app/tools/oracle_bridge.py
sed -i \
  -e 's|Executa uma query SQL READ-ONLY contra o Oracle Winthor (EBD). |Executa uma query SQL READ-ONLY contra o Oracle do NBS (concessionarias). |' \
  -e 's|Use as views GD_FATO_\* / GD_DIM_\* e tabelas PC\* documentadas no system prompt. |Use as tabelas documentadas no system prompt (OS, VENDAS, VEICULOS, COMPRA, CLIENTES...). |' \
  -e 's|sql-corrections.md: varias colunas do Winthor tem grafia |sql-corrections.md: varias colunas do NBS tem grafia |' \
  -e 's|A consulta ao Winthor FALHOU|A consulta ao NBS FALHOU|' \
  -e 's|Responda que o Winthor esta indisponivel no momento e peca |Responda que o NBS esta indisponivel no momento e peca |' \
  -e 's|Isso e ERRO NA SUA CONSULTA, nao no banco — o Winthor |Isso e ERRO NA SUA CONSULTA, nao no banco — o NBS |' \
  core/app/tools/oracle_bridge.py

# ------------------------------------------------------------
# 3. Mensagens de erro do gateway
# ------------------------------------------------------------
bkp gateway/app/routes/chat.py
sed -i 's|Winthor e nao vou arriscar numeros|NBS e nao vou arriscar numeros|g' gateway/app/routes/chat.py

bkp gateway/app/routes/health.py
sed -i 's|mockup 07 — Winthor offline + circuit-breaker|mockup 07 — banco offline + circuit-breaker|' gateway/app/routes/health.py

# ------------------------------------------------------------
# 4. Rodape do Excel
# ------------------------------------------------------------
bkp core/app/tools/excel_builder.py
sed -i 's|EBD.ia · dados do Winthor|Dealer.ia · dados do NBS|' core/app/tools/excel_builder.py

# ------------------------------------------------------------
# 5. Mapa/roteiro — exemplos com RCA e PCCLIENT
# ------------------------------------------------------------
bkp core/app/tools/routemap_builder.py
sed -i \
  -e "s|Roteiro RCA 3366 de 21/07 - coord PCCLIENT|Roteiro do consultor de 21/07 - coord do cadastro|" \
  -e "s|Roteiro RCA 3366 - 21/07|Roteiro do consultor - 21/07|" \
  -e "s|Roteiro do RCA 3366 de 21/07 - coord de cadastro PCCLIENT|Roteiro do consultor de 21/07 - coord do cadastro|" \
  core/app/tools/routemap_builder.py

bkp core/app/tools/artifact_tools.py
sed -i \
  -e "s|o roteiro de um vendedor/RCA|o roteiro de um vendedor/consultor|" \
  -e "s|'onde estao os clientes do RCA'|'onde estao os clientes do vendedor'|" \
  -e "s|a rota inteira do RCA e a carteira toda|a rota inteira do vendedor e a carteira toda|" \
  -e "s|'Rota ativa do RCA X, quarta-feira — |'Rota ativa do vendedor X, quarta-feira — |" \
  -e "s|'Roteiro RCA 3366 (Antonio Fernando) — quarta'|'Roteiro do consultor X — quarta'|" \
  -e "s|Identificacao do RCA. Ex: '3366 — Antonio Fernando (fil 08)'|Identificacao do vendedor|" \
  core/app/tools/artifact_tools.py

# ------------------------------------------------------------
# 6. template_catalog.py — descricao da tool
# ------------------------------------------------------------
bkp core/app/tools/template_catalog.py
sed -i \
  -e 's|Indice dos templates SQL CANONICOS e VALIDADOS do Winthor. |Indice dos templates SQL CANONICOS e VALIDADOS do NBS. |' \
  -e 's|Filtro opcional: faturamento, fornecedores, pedidos, |Filtro opcional: veiculos, oficina, pecas, financeiro, |' \
  -e 's|inadimplencia, equipe_campo, clientes, estoque, |clientes, estoque, |' \
  -e 's|regionais, metas. Omitir = indice completo.|garantia. Omitir = indice completo.|' \
  core/app/tools/template_catalog.py

# ------------------------------------------------------------
# 7. Docstring inofensiva
# ------------------------------------------------------------
bkp core/app/loop_policy.py
sed -i 's|True se alguma consulta ao Winthor deu certo neste turno.|True se alguma consulta ao banco deu certo neste turno.|' core/app/loop_policy.py

# ------------------------------------------------------------
# 8. Adapter do Telegram (canal nao usado aqui) — texto de boas-vindas
# ------------------------------------------------------------
if [ -f core/app/adapters/telegram.py ]; then
  bkp core/app/adapters/telegram.py
  sed -i \
    -e 's|Sou o \*EBD\\\\.ia\*, agente comercial conectado ao Winthor|Sou o *Conc\\.ia*, agente conectado ao NBS|' \
    -e 's|Manda qualquer pergunta sobre vendas, RCAs, ruptura, estoque|Manda qualquer pergunta sobre vendas, oficina, veiculos, pecas|' \
    core/app/adapters/telegram.py
fi

# ------------------------------------------------------------
# 9. Limpa bytecode antigo (o .pyc guarda o texto velho)
# ------------------------------------------------------------
find core gateway -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true

echo
echo "=== residuo restante (fora de .bak e .pyc) ==="
grep -rn "Winthor\|RCA\|GD_FATO\|GD_DIM\|ORIGEMPED\|PCPEDC\|PCCLIENT\|inadimpl" \
  core/app gateway/app --include='*.py' --include='*.json' \
  | grep -v "\.bak-" | grep -v "system_prompt.py" || echo "   limpo."
echo
echo "Backups: *.bak-$STAMP"
