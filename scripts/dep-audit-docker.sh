#!/bin/bash
set -euo pipefail

# === SecOps Dep-Audit (Container) ===
# Roda dentro do Docker - análise de dependências para CI/CD
# Uso: dep-audit /src [--snyk-token <token>] [--output /reports] [--fail-on <severity>]

show_help() {
  echo "SecOps Dependency Audit"
  echo ""
  echo "Uso: dep-audit <source_path> [opções]"
  echo ""
  echo "Opções:"
  echo "  --snyk-token <token>   Token do Snyk (https://app.snyk.io/account)"
  echo "  --output <dir>         Diretório de saída (default: /reports)"
  echo "  --fail-on <severity>   Falha se encontrar >= severity (critical|high|medium|low)"
  echo "  --help                 Mostra esta ajuda"
  echo ""
  echo "Exemplo:"
  echo "  dep-audit /src --snyk-token xxx --fail-on high"
}

SOURCE=""
SNYK_TOKEN="${SNYK_TOKEN:-}"
OUTPUT="/reports"
FAIL_ON=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --snyk-token) SNYK_TOKEN="$2"; shift 2;;
    --output) OUTPUT="$2"; shift 2;;
    --fail-on) FAIL_ON="$2"; shift 2;;
    --help) show_help; exit 0;;
    -*) echo "Opção desconhecida: $1"; exit 1;;
    *) SOURCE="$1"; shift;;
  esac
done

if [[ -z "$SOURCE" ]]; then
  show_help
  exit 1
fi

mkdir -p "$OUTPUT"

echo "============================================"
echo " SecOps Dependency Audit"
echo " Source: $SOURCE"
echo " Output: $OUTPUT"
echo "============================================"

# Contadores para exit code
CRITICAL=0
HIGH=0
MEDIUM=0
LOW=0

# Detectar ecossistemas
HAS_NODE=false; HAS_PYTHON=false; HAS_RUBY=false; HAS_JAVA=false; HAS_GO=false; HAS_PHP=false
[[ -f "$SOURCE/package.json" || -f "$SOURCE/package-lock.json" || -f "$SOURCE/yarn.lock" ]] && HAS_NODE=true
[[ -f "$SOURCE/requirements.txt" || -f "$SOURCE/Pipfile" || -f "$SOURCE/pyproject.toml" ]] && HAS_PYTHON=true
[[ -f "$SOURCE/Gemfile" || -f "$SOURCE/Gemfile.lock" ]] && HAS_RUBY=true
[[ -f "$SOURCE/pom.xml" || -f "$SOURCE/build.gradle" || -f "$SOURCE/build.gradle.kts" ]] && HAS_JAVA=true
[[ -f "$SOURCE/go.mod" ]] && HAS_GO=true
[[ -f "$SOURCE/composer.json" ]] && HAS_PHP=true

echo ""
echo "Ecossistemas: $(
  $HAS_NODE && echo -n "node "
  $HAS_PYTHON && echo -n "python "
  $HAS_RUBY && echo -n "ruby "
  $HAS_JAVA && echo -n "java "
  $HAS_GO && echo -n "go "
  $HAS_PHP && echo -n "php "
)"

# ===================== 1. NATIVE AUDITS =====================
echo -e "\n[1/4] Auditoria nativa..."

if $HAS_NODE; then
  echo "  → npm audit..."
  cd "$SOURCE"
  npm install --package-lock-only 2>/dev/null || true
  npm audit --json > "$OUTPUT/npm-audit.json" 2>/dev/null || true
  if [[ -s "$OUTPUT/npm-audit.json" ]]; then
    C=$(jq '.metadata.vulnerabilities.critical // 0' "$OUTPUT/npm-audit.json" 2>/dev/null || echo 0)
    H=$(jq '.metadata.vulnerabilities.high // 0' "$OUTPUT/npm-audit.json" 2>/dev/null || echo 0)
    M=$(jq '.metadata.vulnerabilities.moderate // 0' "$OUTPUT/npm-audit.json" 2>/dev/null || echo 0)
    L=$(jq '.metadata.vulnerabilities.low // 0' "$OUTPUT/npm-audit.json" 2>/dev/null || echo 0)
    CRITICAL=$((CRITICAL + C)); HIGH=$((HIGH + H)); MEDIUM=$((MEDIUM + M)); LOW=$((LOW + L))
    echo "    Critical: $C | High: $H | Medium: $M | Low: $L"
  fi
fi

if $HAS_PYTHON; then
  echo "  → pip-audit..."
  cd "$SOURCE"
  if [[ -f "requirements.txt" ]]; then
    pip-audit -r requirements.txt --format json > "$OUTPUT/pip-audit.json" 2>/dev/null || true
  else
    pip-audit --format json > "$OUTPUT/pip-audit.json" 2>/dev/null || true
  fi
  if [[ -s "$OUTPUT/pip-audit.json" ]]; then
    V=$(jq 'length' "$OUTPUT/pip-audit.json" 2>/dev/null || echo 0)
    echo "    Vulnerabilidades: $V"
    HIGH=$((HIGH + V))
  fi
fi

if $HAS_RUBY; then
  echo "  → bundle-audit..."
  cd "$SOURCE"
  bundle-audit check --format json > "$OUTPUT/bundle-audit.json" 2>/dev/null || true
fi

if $HAS_GO; then
  echo "  → govulncheck..."
  cd "$SOURCE"
  govulncheck -json ./... > "$OUTPUT/govulncheck.json" 2>/dev/null || true
fi

if $HAS_PHP; then
  echo "  → composer audit..."
  cd "$SOURCE"
  composer audit --format json > "$OUTPUT/composer-audit.json" 2>/dev/null || true
fi

# ===================== 2. OWASP DEPENDENCY-CHECK =====================
echo -e "\n[2/4] OWASP Dependency-Check..."
dependency-check.sh \
  --scan "$SOURCE" \
  --format JSON \
  --format HTML \
  --out "$OUTPUT" \
  --project "dep-audit" \
  --enableExperimental \
  2>/dev/null || true

[[ -f "$OUTPUT/dependency-check-report.json" ]] && mv "$OUTPUT/dependency-check-report.json" "$OUTPUT/owasp-depcheck.json"
[[ -f "$OUTPUT/dependency-check-report.html" ]] && mv "$OUTPUT/dependency-check-report.html" "$OUTPUT/owasp-depcheck.html"

if [[ -f "$OUTPUT/owasp-depcheck.json" ]]; then
  DC_CRIT=$(jq '[.dependencies[]?.vulnerabilities[]? | select(.severity == "CRITICAL")] | length' "$OUTPUT/owasp-depcheck.json" 2>/dev/null || echo 0)
  DC_HIGH=$(jq '[.dependencies[]?.vulnerabilities[]? | select(.severity == "HIGH")] | length' "$OUTPUT/owasp-depcheck.json" 2>/dev/null || echo 0)
  CRITICAL=$((CRITICAL + DC_CRIT)); HIGH=$((HIGH + DC_HIGH))
  echo "  Critical: $DC_CRIT | High: $DC_HIGH"
fi

# ===================== 3. SNYK =====================
echo -e "\n[3/4] Snyk..."
if [[ -n "$SNYK_TOKEN" ]]; then
  cd "$SOURCE"
  snyk auth "$SNYK_TOKEN" 2>/dev/null || true
  snyk test --json > "$OUTPUT/snyk.json" 2>/dev/null || true

  if [[ -s "$OUTPUT/snyk.json" ]]; then
    S_CRIT=$(jq '[.vulnerabilities[]? | select(.severity == "critical")] | length' "$OUTPUT/snyk.json" 2>/dev/null || echo 0)
    S_HIGH=$(jq '[.vulnerabilities[]? | select(.severity == "high")] | length' "$OUTPUT/snyk.json" 2>/dev/null || echo 0)
    CRITICAL=$((CRITICAL + S_CRIT)); HIGH=$((HIGH + S_HIGH))
    echo "  Critical: $S_CRIT | High: $S_HIGH"
  fi

  # Monitor (registra projeto para alertas contínuos)
  snyk monitor 2>/dev/null || true
  echo "  Monitor ativado"
else
  echo "  [SKIP] Sem token. Use --snyk-token ou env SNYK_TOKEN"
fi

# ===================== 4. DEPENDABOT CONFIG =====================
echo -e "\n[4/4] Gerando dependabot.yml..."
cat > "$OUTPUT/dependabot.yml" <<EOF
version: 2
updates:
EOF

$HAS_NODE && cat >> "$OUTPUT/dependabot.yml" <<EOF
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
EOF

$HAS_PYTHON && cat >> "$OUTPUT/dependabot.yml" <<EOF
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
EOF

$HAS_RUBY && cat >> "$OUTPUT/dependabot.yml" <<EOF
  - package-ecosystem: "bundler"
    directory: "/"
    schedule:
      interval: "weekly"
EOF

$HAS_JAVA && cat >> "$OUTPUT/dependabot.yml" <<EOF
  - package-ecosystem: "maven"
    directory: "/"
    schedule:
      interval: "weekly"
EOF

$HAS_GO && cat >> "$OUTPUT/dependabot.yml" <<EOF
  - package-ecosystem: "gomod"
    directory: "/"
    schedule:
      interval: "weekly"
EOF

$HAS_PHP && cat >> "$OUTPUT/dependabot.yml" <<EOF
  - package-ecosystem: "composer"
    directory: "/"
    schedule:
      interval: "weekly"
EOF

cat >> "$OUTPUT/dependabot.yml" <<EOF
  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
EOF

# ===================== RESUMO =====================
echo ""
echo "============================================"
echo " RESUMO"
echo "============================================"
echo " Critical: $CRITICAL"
echo " High:     $HIGH"
echo " Medium:   $MEDIUM"
echo " Low:      $LOW"
echo ""
echo " Relatórios: $OUTPUT/"
ls -1 "$OUTPUT" | sed 's/^/   - /'
echo "============================================"

# Exit code baseado em --fail-on
if [[ -n "$FAIL_ON" ]]; then
  case "$FAIL_ON" in
    critical) [[ $CRITICAL -gt 0 ]] && { echo "❌ FALHA: $CRITICAL critical encontradas"; exit 1; } ;;
    high)     [[ $((CRITICAL + HIGH)) -gt 0 ]] && { echo "❌ FALHA: $CRITICAL critical + $HIGH high encontradas"; exit 1; } ;;
    medium)   [[ $((CRITICAL + HIGH + MEDIUM)) -gt 0 ]] && { echo "❌ FALHA: vulnerabilidades >= medium encontradas"; exit 1; } ;;
    low)      [[ $((CRITICAL + HIGH + MEDIUM + LOW)) -gt 0 ]] && { echo "❌ FALHA: vulnerabilidades encontradas"; exit 1; } ;;
  esac
  echo "✅ Nenhuma vulnerabilidade >= $FAIL_ON encontrada"
fi
