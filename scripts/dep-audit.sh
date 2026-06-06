#!/bin/bash
set -euo pipefail

# === SecOps Dependency Audit ===
# Análise profunda de libs/dependências com múltiplas ferramentas
# Uso: ./dep-audit.sh <repo_path> [--snyk-token <token>]
#
# Ferramentas:
#   1. npm audit / pip-audit / bundle-audit (nativos)
#   2. OWASP Dependency-Check (NVD database)
#   3. Snyk (banco proprietário + remediação)
#   4. Dependabot config generator

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORTS_DIR="$(cd "$SCRIPT_DIR/../reports" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_DIR="${REPORTS_DIR}/dep-audit_${TIMESTAMP}"
mkdir -p "$REPORT_DIR"

SOURCE="${1:?Uso: $0 <repo_path> [--snyk-token <token>]}"
SOURCE="$(realpath "$SOURCE")"
SNYK_TOKEN=""

shift || true
while [[ $# -gt 0 ]]; do
  case $1 in
    --snyk-token) SNYK_TOKEN="$2"; shift 2;;
    *) shift;;
  esac
done

echo "============================================"
echo " SecOps Dependency Audit - $TIMESTAMP"
echo " Target: $SOURCE"
echo "============================================"

# Detectar ecossistemas presentes
HAS_NODE=false; HAS_PYTHON=false; HAS_RUBY=false; HAS_JAVA=false; HAS_GO=false; HAS_PHP=false
[[ -f "$SOURCE/package.json" || -f "$SOURCE/package-lock.json" || -f "$SOURCE/yarn.lock" ]] && HAS_NODE=true
[[ -f "$SOURCE/requirements.txt" || -f "$SOURCE/Pipfile" || -f "$SOURCE/pyproject.toml" || -f "$SOURCE/setup.py" ]] && HAS_PYTHON=true
[[ -f "$SOURCE/Gemfile" || -f "$SOURCE/Gemfile.lock" ]] && HAS_RUBY=true
[[ -f "$SOURCE/pom.xml" || -f "$SOURCE/build.gradle" || -f "$SOURCE/build.gradle.kts" ]] && HAS_JAVA=true
[[ -f "$SOURCE/go.mod" ]] && HAS_GO=true
[[ -f "$SOURCE/composer.json" || -f "$SOURCE/composer.lock" ]] && HAS_PHP=true

echo ""
echo "Ecossistemas detectados:"
$HAS_NODE && echo "  ✓ Node.js (npm/yarn)"
$HAS_PYTHON && echo "  ✓ Python (pip/pipenv/poetry)"
$HAS_RUBY && echo "  ✓ Ruby (bundler)"
$HAS_JAVA && echo "  ✓ Java (Maven/Gradle)"
$HAS_GO && echo "  ✓ Go (go mod)"
$HAS_PHP && echo "  ✓ PHP (composer)"

# ===================== 1. NATIVE AUDITS =====================
echo -e "\n[1/4] Auditoria nativa por ecossistema..."

# --- npm audit ---
if $HAS_NODE; then
  echo "  → npm audit..."
  docker run --rm -v "$SOURCE:/src" -w /src node:lts-alpine sh -c \
    "npm install --package-lock-only 2>/dev/null; npm audit --json 2>/dev/null" \
    > "$REPORT_DIR/npm-audit.json" || true

  # Resumo
  if [[ -s "$REPORT_DIR/npm-audit.json" ]]; then
    VULNS=$(cat "$REPORT_DIR/npm-audit.json" | grep -o '"total":[0-9]*' | head -1 | cut -d: -f2)
    echo "    Vulnerabilidades: ${VULNS:-0}"
  fi
fi

# --- pip-audit ---
if $HAS_PYTHON; then
  echo "  → pip-audit..."
  docker run --rm -v "$SOURCE:/src" -w /src python:3-slim sh -c \
    "pip install pip-audit -q 2>/dev/null && pip-audit -r requirements.txt --format json 2>/dev/null || pip-audit --format json 2>/dev/null" \
    > "$REPORT_DIR/pip-audit.json" 2>/dev/null || true
fi

# --- bundle-audit ---
if $HAS_RUBY; then
  echo "  → bundle-audit..."
  docker run --rm -v "$SOURCE:/src" -w /src ruby:3-slim sh -c \
    "gem install bundler-audit -q 2>/dev/null && bundle-audit check --format json 2>/dev/null" \
    > "$REPORT_DIR/bundle-audit.json" 2>/dev/null || true
fi

# --- go vulncheck ---
if $HAS_GO; then
  echo "  → govulncheck..."
  docker run --rm -v "$SOURCE:/src" -w /src golang:latest sh -c \
    "go install golang.org/x/vuln/cmd/govulncheck@latest 2>/dev/null && govulncheck -json ./... 2>/dev/null" \
    > "$REPORT_DIR/govulncheck.json" 2>/dev/null || true
fi

# --- composer audit ---
if $HAS_PHP; then
  echo "  → composer audit..."
  docker run --rm -v "$SOURCE:/src" -w /src composer:latest sh -c \
    "composer audit --format json 2>/dev/null" \
    > "$REPORT_DIR/composer-audit.json" 2>/dev/null || true
fi

# ===================== 2. OWASP DEPENDENCY-CHECK =====================
echo -e "\n[2/4] OWASP Dependency-Check (NVD database)..."
docker run --rm \
  -v "$SOURCE:/src" \
  -v "$REPORT_DIR:/report" \
  -v "secops-depcheck-data:/usr/share/dependency-check/data" \
  owasp/dependency-check:latest \
  --scan /src \
  --format JSON \
  --format HTML \
  --out /report \
  --project "$(basename "$SOURCE")" \
  --enableExperimental \
  2>/dev/null || true

# Renomear outputs
[[ -f "$REPORT_DIR/dependency-check-report.json" ]] && mv "$REPORT_DIR/dependency-check-report.json" "$REPORT_DIR/owasp-depcheck.json"
[[ -f "$REPORT_DIR/dependency-check-report.html" ]] && mv "$REPORT_DIR/dependency-check-report.html" "$REPORT_DIR/owasp-depcheck.html"

if [[ -f "$REPORT_DIR/owasp-depcheck.json" ]]; then
  DEPCHECK_VULNS=$(grep -c '"severity"' "$REPORT_DIR/owasp-depcheck.json" 2>/dev/null || echo "0")
  echo "  Vulnerabilidades encontradas: $DEPCHECK_VULNS"
  echo "  Relatório HTML: $REPORT_DIR/owasp-depcheck.html"
fi

# ===================== 3. SNYK =====================
echo -e "\n[3/4] Snyk - Análise de dependências..."
if [[ -n "$SNYK_TOKEN" ]]; then
  docker run --rm \
    -v "$SOURCE:/src" \
    -e SNYK_TOKEN="$SNYK_TOKEN" \
    -w /src \
    snyk/snyk:linux sh -c \
    "snyk test --json > /src/.snyk-report.json 2>/dev/null; snyk monitor 2>/dev/null" || true

  cp "$SOURCE/.snyk-report.json" "$REPORT_DIR/snyk.json" 2>/dev/null || echo '{}' > "$REPORT_DIR/snyk.json"
  rm -f "$SOURCE/.snyk-report.json"

  if [[ -s "$REPORT_DIR/snyk.json" ]]; then
    SNYK_VULNS=$(grep -c '"id"' "$REPORT_DIR/snyk.json" 2>/dev/null || echo "0")
    echo "  Vulnerabilidades: $SNYK_VULNS"
    echo "  Monitor ativado (Snyk vai alertar sobre novas CVEs)"
  fi
else
  echo "  [SKIP] Token não informado. Use: --snyk-token <token>"
  echo "  Obter token: https://app.snyk.io/account"
fi

# ===================== 4. DEPENDABOT CONFIG =====================
echo -e "\n[4/4] Gerando configuração Dependabot..."
DEPENDABOT_CONFIG="$REPORT_DIR/dependabot.yml"

cat > "$DEPENDABOT_CONFIG" <<EOF
# Gerado automaticamente pelo SecOps Dependency Audit
# Copiar para: .github/dependabot.yml
version: 2
updates:
EOF

if $HAS_NODE; then
  cat >> "$DEPENDABOT_CONFIG" <<EOF
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    labels:
      - "dependencies"
      - "security"
EOF
fi

if $HAS_PYTHON; then
  cat >> "$DEPENDABOT_CONFIG" <<EOF
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    labels:
      - "dependencies"
      - "security"
EOF
fi

if $HAS_RUBY; then
  cat >> "$DEPENDABOT_CONFIG" <<EOF
  - package-ecosystem: "bundler"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
EOF
fi

if $HAS_JAVA; then
  cat >> "$DEPENDABOT_CONFIG" <<EOF
  - package-ecosystem: "maven"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
EOF
fi

if $HAS_GO; then
  cat >> "$DEPENDABOT_CONFIG" <<EOF
  - package-ecosystem: "gomod"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
EOF
fi

if $HAS_PHP; then
  cat >> "$DEPENDABOT_CONFIG" <<EOF
  - package-ecosystem: "composer"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
EOF
fi

# Sempre incluir Docker e GitHub Actions
cat >> "$DEPENDABOT_CONFIG" <<EOF
  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
EOF

echo "  Config gerada: $DEPENDABOT_CONFIG"
echo "  Copie para .github/dependabot.yml no seu repositório"

# ===================== RESUMO =====================
echo ""
echo "============================================"
echo " Dependency Audit Completo!"
echo " Relatórios: $REPORT_DIR"
echo "============================================"
echo ""
echo " Relatórios gerados:"
ls -1 "$REPORT_DIR" | sed 's/^/   - /'
echo ""
echo " Ações recomendadas:"
echo "   1. Revisar owasp-depcheck.html no navegador"
echo "   2. Copiar dependabot.yml para .github/dependabot.yml"
echo "   3. Atualizar dependências com CVEs críticas"
echo "============================================"
