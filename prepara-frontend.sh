#!/usr/bin/env bash
# ============================================================
# Configura e builda o frontend das concessionarias.
# Pergunta o que precisa — nao precisa editar nada antes.
#   bash prepara-frontend.sh
# ============================================================
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
test -d frontend || { echo "frontend/ nao encontrado"; exit 1; }

pergunta() {
  local var="$1" texto="$2" padrao="${3:-}" resp
  if [ -n "$padrao" ]; then
    read -r -p "$texto [$padrao]: " resp
    resp="${resp:-$padrao}"
  else
    read -r -p "$texto: " resp
  fi
  printf -v "$var" '%s' "$resp"
}

echo "=== Frontend — concessionarias ==="
echo
pergunta NOME_PRODUTO "Nome do produto (aparece no titulo e no chat)" "NBS.ia"
pergunta NOME_CURTO   "Nome curto (parte antes do .ia no header)"     "${NOME_PRODUTO%%.*}"
echo
echo "Do App Registration no Entra ID (Visao geral do app):"
pergunta AZURE_CLIENT_ID "  Application (client) ID"
pergunta AZURE_TENANT_ID "  Directory (tenant) ID"
pergunta AZURE_SCOPE     "  Scope exposto" "api://$AZURE_CLIENT_ID/access_as_user"
echo
pergunta API_BASE_URL "URL da API (vazio = mesma origem, gateway serve o dist)" ""

for v in NOME_PRODUTO NOME_CURTO AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_SCOPE; do
  [ -n "${!v}" ] || { echo "ERRO: $v vazio"; exit 1; }
done

echo
echo "----------------------------------------"
echo " produto : $NOME_PRODUTO  (header: $NOME_CURTO.ia)"
echo " client  : $AZURE_CLIENT_ID"
echo " tenant  : $AZURE_TENANT_ID"
echo " scope   : $AZURE_SCOPE"
echo " api     : ${API_BASE_URL:-<mesma origem>}"
echo "----------------------------------------"
read -r -p "Confirma? [s/N] " ok
[ "$ok" = "s" ] || [ "$ok" = "S" ] || { echo "abortado"; exit 1; }

STAMP=$(date +%Y%m%d-%H%M%S)
cd frontend

# 1. .env do Vite (VITE_* sao embutidas no bundle durante o build)
cat > .env <<EOF
VITE_AZURE_CLIENT_ID=$AZURE_CLIENT_ID
VITE_AZURE_TENANT_ID=$AZURE_TENANT_ID
VITE_AZURE_SCOPE=$AZURE_SCOPE
VITE_API_BASE_URL=$API_BASE_URL
EOF
grep -q '^\.env' .gitignore 2>/dev/null || echo ".env" >> .gitignore

# 2. Logo — placeholder se o definitivo ainda nao existe
if [ ! -f public/logo-conc.png ]; then
  cp public/logo-ebd.png public/logo-conc.png
  echo ">> AVISO: logo do EBD como placeholder — substituir public/logo-conc.png depois"
fi
[ -f public/favicon-conc.png ] || cp public/favicon-ebd.png public/favicon-conc.png

# 3. Marca — os 5 pontos de EBD no codigo
cp index.html "index.html.bak-$STAMP"
cp src/App.tsx "src/App.tsx.bak-$STAMP"

sed -i \
  -e "s|/logo-ebd.png?v=1|/logo-conc.png?v=1|" \
  -e "s|<title>EBD.ia</title>|<title>$NOME_PRODUTO</title>|" \
  index.html

sed -i \
  -e "s|src=\"/logo-ebd.png\" alt=\"EBD\"|src=\"/logo-conc.png\" alt=\"$NOME_CURTO\"|g" \
  -e "s|<span className=\"name\">EBD<em>.ia</em></span>|<span className=\"name\">$NOME_CURTO<em>.ia</em></span>|" \
  -e "s|\"EBD.ia\" : firstName|\"$NOME_PRODUTO\" : firstName|" \
  -e "s|Pergunte ao EBD.ia…|Pergunte ao $NOME_PRODUTO…|" \
  src/App.tsx

# 4. Build
npm ci
npm run build

cd ..
echo
echo ">> dist gerado em frontend/dist (o gateway serve dele)."
echo ">> Restou algum 'EBD' no front?"
grep -rn "EBD\|logo-ebd" frontend/src frontend/index.html || echo "   nenhum."
