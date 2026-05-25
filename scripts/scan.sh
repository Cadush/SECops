#!/bin/bash
set -euo pipefail

# === SecOps Pipeline Orchestrator (Full) ===
# Uso: ./scan.sh <repo_url_ou_path> [--dast <target_url>] [--image <docker_image>]

REPORTS_DIR="$(cd "$(dirname "$0")/../reports" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_DIR="${REPORTS_DIR}/${TIMESTAMP}"
mkdir -p "$REPORT_DIR"

REPO="${1:?Uso: $0 <repo_url_ou_path> [--dast <target_url>] [--image <docker_image>]}"
DAST_TARGET=""
DOCKER_IMAGE=""

shift
while [[ $# -gt 0 ]]; do
  case $1 in
    --dast) DAST_TARGET="$2"; shift 2;;
    --image) DOCKER_IMAGE="$2"; shift 2;;
    *) shift;;
  esac
done

# Clone se for URL
if [[ "$REPO" == http* || "$REPO" == git@* ]]; then
  WORK_DIR=$(mktemp -d)
  echo "[*] Clonando $REPO..."
  git clone "$REPO" "$WORK_DIR/source"
  SOURCE="$WORK_DIR/source"
else
  SOURCE="$(realpath "$REPO")"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo " SecOps Full Scan Pipeline - $TIMESTAMP"
echo " Target: $SOURCE"
echo "============================================"

# --- 0. Auditoria de configuração (.env, .gitignore, secrets) ---
echo -e "\n[0/14] Auditoria de configuração..."
bash "$SCRIPT_DIR/audit-config.sh" "$SOURCE" "$REPORT_DIR/audit-config.json"

# ===================== SECRETS =====================

# --- 1. Gitleaks ---
echo -e "\n[1/14] Gitleaks - Secrets no histórico git..."
docker run --rm -v "$SOURCE:/src" zricethezav/gitleaks:latest detect --source /src --report-format json --report-path /src/.gitleaks-report.json 2>/dev/null || true
cp "$SOURCE/.gitleaks-report.json" "$REPORT_DIR/gitleaks.json" 2>/dev/null || echo '[]' > "$REPORT_DIR/gitleaks.json"
rm -f "$SOURCE/.gitleaks-report.json"

# --- 2. TruffleHog ---
echo -e "\n[2/14] TruffleHog - Secrets no filesystem..."
docker run --rm -v "$SOURCE:/src" trufflesecurity/trufflehog:latest filesystem /src --json > "$REPORT_DIR/trufflehog.json" 2>/dev/null || true

# ===================== SAST =====================

# --- 3. Semgrep ---
echo -e "\n[3/14] Semgrep - SAST (XSS, SQLi, RCE, secrets)..."
docker run --rm -v "$SOURCE:/src" -v "$SCRIPT_DIR/../config:/rules" semgrep/semgrep:latest \
  semgrep scan --config auto --config /rules/semgrep-rules.yml --json --output /src/.semgrep-report.json /src 2>/dev/null || true
cp "$SOURCE/.semgrep-report.json" "$REPORT_DIR/semgrep.json" 2>/dev/null || echo '{}' > "$REPORT_DIR/semgrep.json"
rm -f "$SOURCE/.semgrep-report.json"

# --- 4. Bandit (Python) ---
echo -e "\n[4/14] Bandit - SAST Python (eval, pickle, subprocess)..."
if find "$SOURCE" -name "*.py" | head -1 | grep -q .; then
  docker run --rm -v "$SOURCE:/src" cytopia/bandit -r /src -f json -o /src/.bandit-report.json 2>/dev/null || true
  cp "$SOURCE/.bandit-report.json" "$REPORT_DIR/bandit.json" 2>/dev/null || echo '{}' > "$REPORT_DIR/bandit.json"
  rm -f "$SOURCE/.bandit-report.json"
else
  echo "  [SKIP] Nenhum arquivo Python encontrado."
fi

# --- 5. Gosec (Go) ---
echo -e "\n[5/14] Gosec - SAST Go..."
if find "$SOURCE" -name "*.go" | head -1 | grep -q .; then
  docker run --rm -v "$SOURCE:/src" -w /src securego/gosec -fmt json -out /src/.gosec-report.json ./... 2>/dev/null || true
  cp "$SOURCE/.gosec-report.json" "$REPORT_DIR/gosec.json" 2>/dev/null || echo '{}' > "$REPORT_DIR/gosec.json"
  rm -f "$SOURCE/.gosec-report.json"
else
  echo "  [SKIP] Nenhum arquivo Go encontrado."
fi

# --- 6. SpotBugs + FindSecBugs (Java) ---
echo -e "\n[6/14] SpotBugs - SAST Java (bytecode analysis)..."
if find "$SOURCE" -name "*.java" -o -name "*.jar" -o -name "*.class" | head -1 | grep -q .; then
  docker run --rm -v "$SOURCE:/src" spotbugs/spotbugs spotbugs -textui -xml:withMessages -output /src/.spotbugs-report.xml /src 2>/dev/null || true
  cp "$SOURCE/.spotbugs-report.xml" "$REPORT_DIR/spotbugs.xml" 2>/dev/null || true
  rm -f "$SOURCE/.spotbugs-report.xml"
else
  echo "  [SKIP] Nenhum arquivo Java encontrado."
fi

# --- 7. Brakeman (Ruby on Rails) ---
echo -e "\n[7/14] Brakeman - SAST Ruby on Rails..."
if [ -f "$SOURCE/Gemfile" ] && grep -q "rails" "$SOURCE/Gemfile" 2>/dev/null; then
  docker run --rm -v "$SOURCE:/src" presidentbeef/brakeman -p /src -f json -o /src/.brakeman-report.json 2>/dev/null || true
  cp "$SOURCE/.brakeman-report.json" "$REPORT_DIR/brakeman.json" 2>/dev/null || echo '{}' > "$REPORT_DIR/brakeman.json"
  rm -f "$SOURCE/.brakeman-report.json"
else
  echo "  [SKIP] Não é um projeto Rails."
fi

# ===================== SCA =====================

# --- 8. Trivy (filesystem + deps) ---
echo -e "\n[8/14] Trivy - SCA + vulnerabilidades em dependências..."
docker run --rm -v "$SOURCE:/src" aquasec/trivy:latest fs --format json --output /src/.trivy-fs-report.json /src 2>/dev/null || true
cp "$SOURCE/.trivy-fs-report.json" "$REPORT_DIR/trivy-fs.json" 2>/dev/null || echo '{}' > "$REPORT_DIR/trivy-fs.json"
rm -f "$SOURCE/.trivy-fs-report.json"

# --- 9. Grype + Syft (SBOM + SCA) ---
echo -e "\n[9/14] Syft + Grype - SBOM e vulnerabilidades..."
docker run --rm -v "$SOURCE:/src" anchore/syft:latest /src -o json > "$REPORT_DIR/syft-sbom.json" 2>/dev/null || true
docker run --rm -v "$SOURCE:/src" anchore/grype:latest dir:/src -o json > "$REPORT_DIR/grype.json" 2>/dev/null || true

# --- 10. OSV-Scanner ---
echo -e "\n[10/14] OSV-Scanner - Vulnerabilidades (Google OSV database)..."
docker run --rm -v "$SOURCE:/src" ghcr.io/google/osv-scanner:latest --format json -r /src > "$REPORT_DIR/osv-scanner.json" 2>/dev/null || true

# ===================== CONTAINER SECURITY =====================

# --- 11. Hadolint + Dockle + Trivy Image ---
echo -e "\n[11/14] Container Security (Hadolint, Dockle, Trivy Image)..."

# Hadolint - Dockerfile lint
find "$SOURCE" -name "Dockerfile*" | while read -r df; do
  name=$(basename "$df")
  docker run --rm -i hadolint/hadolint < "$df" > "$REPORT_DIR/hadolint-${name}.txt" 2>/dev/null || true
done

# Dockle + Trivy image scan
if [[ -n "$DOCKER_IMAGE" ]]; then
  docker run --rm goodwithtech/dockle:latest --format json "$DOCKER_IMAGE" > "$REPORT_DIR/dockle.json" 2>/dev/null || true
  docker run --rm aquasec/trivy:latest image --format json "$DOCKER_IMAGE" > "$REPORT_DIR/trivy-image.json" 2>/dev/null || true
else
  echo "  [SKIP] Nenhuma imagem Docker informada. Use: --image <image:tag>"
fi

# ===================== IaC =====================

# --- 12. Checkov + KICS (IaC Security) ---
echo -e "\n[12/14] IaC Security (Checkov, KICS)..."

# Checkov
docker run --rm -v "$SOURCE:/src" bridgecrew/checkov -d /src --output json > "$REPORT_DIR/checkov.json" 2>/dev/null || true

# KICS
docker run --rm -v "$SOURCE:/src" checkmarx/kics:latest scan -p /src --output-path /src/.kics-results -t json 2>/dev/null || true
cp "$SOURCE/.kics-results/results.json" "$REPORT_DIR/kics.json" 2>/dev/null || true
rm -rf "$SOURCE/.kics-results"

# ===================== CODE QUALITY =====================

# --- 13. SonarQube ---
echo -e "\n[13/14] SonarQube - Qualidade de código..."
if curl -s http://localhost:9000/api/system/status 2>/dev/null | grep -q '"status":"UP"'; then
  PROJECT_KEY="secops-$(basename "$SOURCE")"
  docker run --rm --network host -v "$SOURCE:/usr/src" sonarsource/sonar-scanner-cli \
    -Dsonar.projectKey="$PROJECT_KEY" \
    -Dsonar.sources=/usr/src \
    -Dsonar.host.url=http://localhost:9000 \
    -Dsonar.login=admin -Dsonar.password=admin 2>/dev/null || true
  echo "  Dashboard: http://localhost:9000/dashboard?id=$PROJECT_KEY"
else
  echo "  [SKIP] SonarQube não está rodando."
fi

# ===================== DAST =====================

# --- 14. DAST (ZAP + Nuclei + Nikto + sqlmap) ---
echo -e "\n[14/14] DAST (ZAP, Nuclei, Nikto, sqlmap)..."
if [[ -n "$DAST_TARGET" ]]; then
  # OWASP ZAP
  docker run --rm --network host ghcr.io/zaproxy/zaproxy:stable zap-baseline.py \
    -t "$DAST_TARGET" -J /tmp/zap-report.json > /dev/null 2>&1 || true
  docker cp secops-zap:/zap/wrk/zap-report.json "$REPORT_DIR/zap.json" 2>/dev/null || true

  # Nuclei
  docker run --rm --network host projectdiscovery/nuclei:latest -u "$DAST_TARGET" -jsonl > "$REPORT_DIR/nuclei.json" 2>/dev/null || true

  # Nikto
  docker run --rm --network host secfigo/nikto -h "$DAST_TARGET" -Format json -output /dev/stdout > "$REPORT_DIR/nikto.json" 2>/dev/null || true

  # sqlmap (basic crawl)
  docker run --rm --network host paoloo/sqlmap --url "$DAST_TARGET" --crawl=2 --batch --output-dir=/tmp/sqlmap 2>/dev/null || true
  echo "  sqlmap: execução batch concluída"
else
  echo "  [SKIP] Nenhum target DAST informado. Use: --dast <url>"
fi

# ===================== DEFECTDOJO IMPORT =====================
echo -e "\n[+] Importando resultados no DefectDojo..."
if curl -s http://localhost:8888/api/v2/ 2>/dev/null | grep -q "engagements"; then
  bash "$SCRIPT_DIR/import-defectdojo.sh" "$REPORT_DIR" "$(basename "$SOURCE")"
else
  echo "  [SKIP] DefectDojo não está rodando."
fi

# ===================== RELATÓRIO HTML =====================
echo -e "\n[+] Gerando relatório HTML..."
bash "$SCRIPT_DIR/report-html.sh" "$REPORT_DIR"

# ===================== RESUMO =====================
echo -e "\n============================================"
echo " Scan completo!"
echo " Relatórios: $REPORT_DIR"
echo " HTML:       $REPORT_DIR/report.html"
echo "============================================"
echo ""
echo " Abra o relatório:"
echo "   xdg-open $REPORT_DIR/report.html"
echo "============================================"

# Cleanup
[[ -n "${WORK_DIR:-}" ]] && rm -rf "$WORK_DIR"
