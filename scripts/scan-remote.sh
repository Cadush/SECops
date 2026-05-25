#!/bin/bash
set -euo pipefail

# === SecOps Remote Scan ===
# Roda scan local e envia resultados para o DefectDojo centralizado (EC2)
# Uso: ./scan-remote.sh <repo_path> --server <ec2_ip>

REPO="${1:?Uso: $0 <repo_path> --server <ec2_ip_ou_url>}"
SERVER=""

shift
while [[ $# -gt 0 ]]; do
  case $1 in
    --server) SERVER="$2"; shift 2;;
    *) shift;;
  esac
done

if [[ -z "$SERVER" ]]; then
  echo "Informe o servidor: $0 <repo> --server <ip_da_ec2>"
  exit 1
fi

DEFECTDOJO_URL="http://$SERVER:8888"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo " SecOps Remote Scan"
echo " Target: $REPO"
echo " Server: $DEFECTDOJO_URL"
echo "============================================"

# Rodar scan local (gera reports/)
bash "$SCRIPT_DIR/scan.sh" "$REPO"

# Pegar último report gerado
LATEST_REPORT=$(ls -td "$SCRIPT_DIR/../reports"/*/ 2>/dev/null | head -1)

if [[ -z "$LATEST_REPORT" ]]; then
  echo "Nenhum relatório encontrado."
  exit 1
fi

# Enviar para DefectDojo remoto
echo -e "\n[*] Enviando resultados para $DEFECTDOJO_URL..."
DEFECTDOJO_URL="$DEFECTDOJO_URL" bash "$SCRIPT_DIR/import-defectdojo.sh" "$LATEST_REPORT" "$(basename "$(realpath "$REPO")")"

echo ""
echo "Resultados disponíveis em: $DEFECTDOJO_URL"
