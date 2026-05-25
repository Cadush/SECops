#!/bin/bash
set -uo pipefail

# === DefectDojo Importer ===
# Importa todos os relatórios de um scan para o DefectDojo
# Uso: ./import-defectdojo.sh <reports_dir> [product_name]

DEFECTDOJO_URL="${DEFECTDOJO_URL:-http://localhost:8888}"
DEFECTDOJO_TOKEN="${DEFECTDOJO_TOKEN:-}"
REPORTS_DIR="${1:?Uso: $0 <reports_dir> [product_name]}"
PRODUCT_NAME="${2:-SecOps-Scan}"

# Helper para extrair campo JSON (usa jq se disponível, senão grep)
json_get_id() {
  if command -v jq &>/dev/null; then
    jq -r '.id // .results[0].id // empty' 2>/dev/null
  else
    grep -o '"id":[0-9]*' | head -1 | cut -d: -f2
  fi
}

json_get_token() {
  if command -v jq &>/dev/null; then
    jq -r '.token // empty' 2>/dev/null
  else
    grep -o '"token":"[^"]*"' | cut -d'"' -f4
  fi
}

# Obter token se não fornecido
if [[ -z "$DEFECTDOJO_TOKEN" ]]; then
  echo "[*] Obtendo token do DefectDojo..."
  DEFECTDOJO_TOKEN=$(curl -s -X POST "$DEFECTDOJO_URL/api/v2/api-token-auth/" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"admin"}' | json_get_token)

  if [[ -z "$DEFECTDOJO_TOKEN" ]]; then
    echo "Falha ao obter token. DefectDojo está rodando?"
    exit 1
  fi
fi

AUTH="Token $DEFECTDOJO_TOKEN"

# Criar product type se não existir
echo "[*] Configurando produto no DefectDojo..."
PRODUCT_TYPE_ID=$(curl -s "$DEFECTDOJO_URL/api/v2/product_types/?name=SecOps" \
  -H "Authorization: $AUTH" | json_get_id)

if [[ -z "$PRODUCT_TYPE_ID" ]]; then
  PRODUCT_TYPE_ID=$(curl -s -X POST "$DEFECTDOJO_URL/api/v2/product_types/" \
    -H "Authorization: $AUTH" -H "Content-Type: application/json" \
    -d '{"name":"SecOps"}' | json_get_id)
fi

if [[ -z "$PRODUCT_TYPE_ID" ]]; then
  echo "Falha ao criar product type."
  exit 1
fi

# Criar product se não existir
PRODUCT_ID=$(curl -s "$DEFECTDOJO_URL/api/v2/products/?name=$PRODUCT_NAME" \
  -H "Authorization: $AUTH" | json_get_id)

if [[ -z "$PRODUCT_ID" ]]; then
  PRODUCT_ID=$(curl -s -X POST "$DEFECTDOJO_URL/api/v2/products/" \
    -H "Authorization: $AUTH" -H "Content-Type: application/json" \
    -d "{\"name\":\"$PRODUCT_NAME\",\"prod_type\":$PRODUCT_TYPE_ID,\"description\":\"Scan SecOps Pipeline\"}" \
    | json_get_id)
fi

if [[ -z "$PRODUCT_ID" ]]; then
  echo "Falha ao criar product."
  exit 1
fi

# Criar engagement
ENGAGEMENT_ID=$(curl -s -X POST "$DEFECTDOJO_URL/api/v2/engagements/" \
  -H "Authorization: $AUTH" -H "Content-Type: application/json" \
  -d "{
    \"name\":\"Pipeline $(date +%Y-%m-%d_%H%M)\",
    \"product\":$PRODUCT_ID,
    \"target_start\":\"$(date +%Y-%m-%d)\",
    \"target_end\":\"$(date +%Y-%m-%d)\",
    \"engagement_type\":\"CI/CD\",
    \"status\":\"In Progress\"
  }" | json_get_id)

if [[ -z "$ENGAGEMENT_ID" ]]; then
  echo "Falha ao criar engagement."
  exit 1
fi

echo "[*] Product ID: $PRODUCT_ID | Engagement ID: $ENGAGEMENT_ID"

# Mapeamento: arquivo -> scan_type do DefectDojo
declare -A SCAN_TYPES=(
  ["semgrep.json"]="Semgrep JSON Report"
  ["bandit.json"]="Bandit Scan"
  ["trivy-fs.json"]="Trivy Scan"
  ["trivy-image.json"]="Trivy Scan"
  ["gitleaks.json"]="Gitleaks Scan"
  ["trufflehog.json"]="Trufflehog Scan"
  ["grype.json"]="Anchore Grype"
  ["osv-scanner.json"]="OSV Scan"
  ["checkov.json"]="Checkov Scan"
  ["kics.json"]="KICS Scan"
  ["zap.json"]="ZAP Scan"
  ["nuclei.json"]="Nuclei Scan"
  ["nikto.json"]="Nikto Scan"
  ["spotbugs.xml"]="SpotBugs Scan"
  ["gosec.json"]="Gosec Scanner"
  ["brakeman.json"]="Brakeman Scan"
  ["dockle.json"]="Dockle Scan"
  ["syft-sbom.json"]="CycloneDX Scan"
)

# Importar cada relatório
echo "[*] Importando relatórios..."
IMPORTED=0
FAILED=0

for file in "${!SCAN_TYPES[@]}"; do
  filepath="$REPORTS_DIR/$file"
  if [[ -f "$filepath" ]] && [[ -s "$filepath" ]]; then
    scan_type="${SCAN_TYPES[$file]}"
    echo "  → $file ($scan_type)..."

    response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$DEFECTDOJO_URL/api/v2/import-scan/" \
      -H "Authorization: $AUTH" \
      -F "scan_type=$scan_type" \
      -F "file=@$filepath" \
      -F "engagement=$ENGAGEMENT_ID" \
      -F "active=true" \
      -F "verified=false" \
      -F "close_old_findings=false")

    if [[ "$response" == "201" ]]; then
      echo "    Importado"
      ((IMPORTED++))
    else
      echo "    HTTP $response"
      ((FAILED++))
    fi
  fi
done

# Fechar engagement
curl -s -X PATCH "$DEFECTDOJO_URL/api/v2/engagements/$ENGAGEMENT_ID/" \
  -H "Authorization: $AUTH" -H "Content-Type: application/json" \
  -d '{"status":"Completed"}' > /dev/null

echo ""
echo "============================================"
echo " DefectDojo Import Completo"
echo " Importados: $IMPORTED | Falhas: $FAILED"
echo " Dashboard: $DEFECTDOJO_URL/engagement/$ENGAGEMENT_ID"
echo "============================================"
