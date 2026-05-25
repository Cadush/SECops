#!/bin/bash
# SECops - Limpeza completa do ambiente Docker
# Remove containers, volumes, imagens e libera espaço em disco

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${YELLOW}Isso vai remover TODOS os dados do SECops (volumes, imagens, containers)${NC}"
echo -e "${YELLOW}   Espaço estimado a ser liberado: ~15GB${NC}"
echo ""
read -p "Confirma? (s/N): " confirm
[[ "$confirm" != "s" && "$confirm" != "S" ]] && echo "Cancelado." && exit 0

echo -e "\n${GREEN}[1/4]${NC} Parando containers..."
docker compose -f "$PROJECT_DIR/docker-compose.yml" down -v 2>/dev/null || true

echo -e "${GREEN}[2/4]${NC} Removendo imagens do compose..."
docker compose -f "$PROJECT_DIR/docker-compose.yml" down --rmi all -v 2>/dev/null || true

echo -e "${GREEN}[3/4]${NC} Removendo imagens das ferramentas de scan..."
IMAGES=(
  "zricethezav/gitleaks"
  "trufflesecurity/trufflehog"
  "semgrep/semgrep"
  "cytopia/bandit"
  "securego/gosec"
  "presidentbeef/brakeman"
  "aquasec/trivy"
  "anchore/syft"
  "anchore/grype"
  "ghcr.io/google/osv-scanner"
  "hadolint/hadolint"
  "goodwithtech/dockle"
  "bridgecrew/checkov"
  "checkmarx/kics"
  "projectdiscovery/nuclei"
  "secfigo/nikto"
  "paoloo/sqlmap"
  "sonarsource/sonar-scanner-cli"
)

for img in "${IMAGES[@]}"; do
  docker rmi -f "$(docker images -q "$img" 2>/dev/null)" 2>/dev/null && \
    echo "  [OK] $img" || true
done

echo -e "${GREEN}[4/4]${NC} Limpando cache do Docker..."
docker system prune -f --volumes 2>/dev/null || true

FREED=$(docker system df 2>/dev/null | tail -1 | awk '{print $4}' || echo "N/A")
echo -e "\n${GREEN}Limpeza concluída!${NC}"
echo -e "   Para usar novamente: ${YELLOW}make pull && make up${NC}"
