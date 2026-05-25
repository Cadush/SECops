#!/bin/bash
set -euo pipefail

# === SecOps Scanner (roda DENTRO do container) ===
# Todas as ferramentas já estão instaladas localmente

SOURCE="/src"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_DIR="/reports/${TIMESTAMP}"
mkdir -p "$REPORT_DIR"

echo "============================================"
echo " SecOps Scanner - $TIMESTAMP"
echo " Target: $SOURCE"
echo "============================================"

# --- Auditoria de configuração ---
echo -e "\n[0/10] Auditoria de configuração..."
bash /secops/scripts/audit-config.sh "$SOURCE" "$REPORT_DIR/audit-config.json"

# --- Gitleaks ---
echo -e "\n[1/10] Gitleaks - Secrets..."
gitleaks detect --source "$SOURCE" --report-format json --report-path "$REPORT_DIR/gitleaks.json" 2>/dev/null || echo '[]' > "$REPORT_DIR/gitleaks.json"

# --- TruffleHog ---
echo -e "\n[2/10] TruffleHog - Secrets..."
trufflehog filesystem "$SOURCE" --json > "$REPORT_DIR/trufflehog.json" 2>/dev/null || true

# --- Semgrep ---
echo -e "\n[3/10] Semgrep - SAST..."
semgrep scan --config auto --json --output "$REPORT_DIR/semgrep.json" "$SOURCE" 2>/dev/null || echo '{}' > "$REPORT_DIR/semgrep.json"

# --- Bandit ---
echo -e "\n[4/10] Bandit - SAST Python..."
if find "$SOURCE" -name "*.py" | head -1 | grep -q .; then
    bandit -r "$SOURCE" -f json -o "$REPORT_DIR/bandit.json" 2>/dev/null || true
else
    echo "  [SKIP] Sem arquivos Python"
fi

# --- Trivy ---
echo -e "\n[5/10] Trivy - SCA..."
trivy fs --format json --output "$REPORT_DIR/trivy-fs.json" "$SOURCE" 2>/dev/null || echo '{}' > "$REPORT_DIR/trivy-fs.json"

# --- Grype + Syft ---
echo -e "\n[6/10] Syft + Grype - SBOM + SCA..."
syft "$SOURCE" -o json > "$REPORT_DIR/syft-sbom.json" 2>/dev/null || true
grype dir:"$SOURCE" -o json > "$REPORT_DIR/grype.json" 2>/dev/null || true

# --- OSV-Scanner ---
echo -e "\n[7/10] OSV-Scanner..."
osv-scanner --format json -r "$SOURCE" > "$REPORT_DIR/osv-scanner.json" 2>/dev/null || true

# --- Hadolint ---
echo -e "\n[8/10] Hadolint - Dockerfile..."
find "$SOURCE" -name "Dockerfile*" | while read -r df; do
    name=$(basename "$df")
    hadolint "$df" > "$REPORT_DIR/hadolint-${name}.txt" 2>/dev/null || true
done

# --- Checkov ---
echo -e "\n[9/10] Checkov - IaC..."
checkov -d "$SOURCE" --output json > "$REPORT_DIR/checkov.json" 2>/dev/null || true

# --- Relatório HTML ---
echo -e "\n[10/10] Gerando relatório HTML..."
bash /secops/scripts/report-html.sh "$REPORT_DIR"

echo -e "\n============================================"
echo " Scan completo!"
echo " Relatórios: $REPORT_DIR"
echo " HTML:       $REPORT_DIR/report.html"
echo "============================================"
