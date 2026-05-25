#!/bin/bash
set -uo pipefail

# === SecOps Config Audit ===
# Verifica .env expostos, .gitignore, arquivos sensíveis, etc.

SOURCE="${1:?Uso: $0 <path_do_repo>}"
REPORT_FILE="${2:-/dev/stdout}"

# Usar arquivo temporário para acumular findings (evita bug de subshell em pipes)
FINDINGS_TMP=$(mktemp)
echo -n "" > "$FINDINGS_TMP"

add_finding() {
  local severity="$1" category="$2" file="$3" detail="$4"
  if [[ -s "$FINDINGS_TMP" ]]; then
    echo "," >> "$FINDINGS_TMP"
  fi
  printf '{"severity":"%s","category":"%s","file":"%s","detail":"%s"}' \
    "$severity" "$category" "$file" "$detail" >> "$FINDINGS_TMP"
}

echo "[*] Auditando configurações de segurança em: $SOURCE"

# --- 1. Arquivos .env commitados ---
echo -e "\n[1] Verificando .env expostos..."
while IFS= read -r f; do
  [[ -n "$f" ]] && add_finding "HIGH" "secrets/env-exposed" "$f" "Arquivo .env presente no repositório"
done < <(find "$SOURCE" \( -name "*.env" -o -name ".env" -o -name ".env.*" \) | grep -v node_modules)

# --- 2. .gitignore ausente ou fraco ---
echo "[2] Verificando .gitignore..."
if [ ! -f "$SOURCE/.gitignore" ]; then
  add_finding "MEDIUM" "config/no-gitignore" ".gitignore" "Arquivo .gitignore ausente"
else
  for pattern in ".env" "*.pem" "*.key" "*.p12" "*.jks" "node_modules" "credentials"; do
    if ! grep -q "$pattern" "$SOURCE/.gitignore" 2>/dev/null; then
      add_finding "MEDIUM" "config/gitignore-missing-pattern" ".gitignore" "Padrão '$pattern' não está no .gitignore"
    fi
  done
fi

# --- 3. Chaves privadas e certificados ---
echo "[3] Verificando chaves/certificados expostos..."
while IFS= read -r f; do
  [[ -n "$f" ]] && add_finding "CRITICAL" "secrets/private-key" "$f" "Chave privada ou certificado exposto"
done < <(find "$SOURCE" \( -name "*.pem" -o -name "*.key" -o -name "*.p12" -o -name "*.jks" -o -name "*.pfx" -o -name "id_rsa" -o -name "id_ed25519" \) | grep -v node_modules)

# --- 4. Hardcoded secrets em código ---
echo "[4] Verificando secrets hardcoded..."
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  file=$(echo "$line" | cut -d: -f1)
  lineno=$(echo "$line" | cut -d: -f2)
  add_finding "HIGH" "secrets/hardcoded" "$file:$lineno" "Possível secret hardcoded"
done < <(grep -rn --include="*.py" --include="*.js" --include="*.ts" --include="*.java" --include="*.go" --include="*.rb" --include="*.php" \
  -iE "(password|secret|api_key|apikey|token|aws_access_key)\s*[=:]\s*['\"][^'\"]{4,}" "$SOURCE" 2>/dev/null | grep -v node_modules | head -50)

# --- 5. Padrões de XSS ---
echo "[5] Verificando padrões de XSS..."
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  file=$(echo "$line" | cut -d: -f1)
  lineno=$(echo "$line" | cut -d: -f2)
  add_finding "HIGH" "vuln/xss" "$file:$lineno" "Possível XSS - output sem sanitização"
done < <(grep -rn --include="*.py" --include="*.js" --include="*.ts" --include="*.jsx" --include="*.tsx" --include="*.php" --include="*.html" \
  -iE "(innerHTML|dangerouslySetInnerHTML|document\.write|v-html|\|safe|mark_safe|\{\{\{)" "$SOURCE" 2>/dev/null | grep -v node_modules | head -50)

# --- 6. Padrões de SQL Injection ---
echo "[6] Verificando padrões de SQL Injection..."
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  file=$(echo "$line" | cut -d: -f1)
  lineno=$(echo "$line" | cut -d: -f2)
  add_finding "CRITICAL" "vuln/sqli" "$file:$lineno" "Possível SQL Injection - query com concatenação"
done < <(grep -rn --include="*.py" --include="*.js" --include="*.ts" --include="*.java" --include="*.go" --include="*.rb" --include="*.php" \
  -iE "(execute\(.*(%s|%d|\+|f\"|format|{}).*\)|query\(.*\+|\"SELECT.*\+|\"INSERT.*\+|\"UPDATE.*\+|\"DELETE.*\+)" "$SOURCE" 2>/dev/null | grep -v node_modules | head -50)

# --- 7. Dockerfile inseguro ---
echo "[7] Verificando Dockerfiles..."
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if grep -q "FROM.*:latest" "$f"; then
    add_finding "LOW" "config/docker-latest-tag" "$f" "Dockerfile usando tag :latest (não determinístico)"
  fi
  if grep -q "USER root" "$f" || ! grep -q "USER" "$f"; then
    add_finding "MEDIUM" "config/docker-root" "$f" "Container pode rodar como root"
  fi
done < <(find "$SOURCE" -name "Dockerfile*")

# --- 8. Dependências com vulnerabilidades conhecidas (check básico) ---
echo "[8] Verificando lockfiles..."
for lockfile in "package-lock.json" "yarn.lock" "Pipfile.lock" "poetry.lock" "go.sum" "Gemfile.lock"; do
  if find "$SOURCE" -name "$lockfile" 2>/dev/null | grep -q .; then
    add_finding "INFO" "sca/lockfile-present" "$lockfile" "Lockfile encontrado - será analisado pelo Trivy/Grype"
  fi
done

# Gerar JSON final
echo "{\"findings\":[" > "$REPORT_FILE"
cat "$FINDINGS_TMP" >> "$REPORT_FILE"
echo "]}" >> "$REPORT_FILE"
rm -f "$FINDINGS_TMP"

echo -e "\n[*] Auditoria concluída."
