#!/bin/bash
set -euo pipefail

# === SecOps Legacy Doc Generator ===
# Analisa codigo legado e gera documentacao automatica
# Uso: ./legacy-doc.sh <repo_path> [--output <dir>] [--provider <openai|ollama|bedrock>]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="${1:?Uso: $0 <repo_path> [--output <dir>] [--provider <openai|ollama|bedrock>]}"
SOURCE="$(realpath "$SOURCE")"
OUTPUT=""
PROVIDER="${LEGACY_DOC_PROVIDER:-ollama}"
API_KEY="${OPENAI_API_KEY:-${BEDROCK_API_KEY:-${OPENROUTER_API_KEY:-}}}"
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
MODEL="${LEGACY_DOC_MODEL:-}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"

# Default model por provider
if [[ -z "$MODEL" ]]; then
  case "$PROVIDER" in
    ollama) MODEL="qwen2.5-coder:14b";;
    openai) MODEL="gpt-4o-mini";;
    openrouter) MODEL="moonshotai/kimi-k2.6";;
    bedrock) MODEL="anthropic.claude-3-haiku-20240307-v1:0";;
  esac
fi

shift || true
while [[ $# -gt 0 ]]; do
  case $1 in
    --output) OUTPUT="$2"; shift 2;;
    --provider) PROVIDER="$2"; shift 2;;
    --model) MODEL="$2"; shift 2;;
    --api-key) API_KEY="$2"; shift 2;;
    *) shift;;
  esac
done

[[ -z "$OUTPUT" ]] && OUTPUT="$SOURCE/docs/generated"
mkdir -p "$OUTPUT"

echo "============================================"
echo " SecOps Legacy Doc Generator"
echo " Source:   $SOURCE"
echo " Output:   $OUTPUT"
echo " Provider: $PROVIDER ($MODEL)"
echo "============================================"

# --- Funcao: chamar LLM ---
call_llm() {
  local prompt="$1"
  local output_file="$2"

  case "$PROVIDER" in
    openai)
      if [[ -z "$API_KEY" ]]; then
        echo "  [ERRO] OPENAI_API_KEY nao definida" >&2
        return 1
      fi
      curl -s https://api.openai.com/v1/chat/completions \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg model "$MODEL" --arg prompt "$prompt" '{
          model: $model,
          messages: [{role: "user", content: $prompt}],
          temperature: 0.2
        }')" | jq -r '.choices[0].message.content' > "$output_file"
      ;;

    openrouter)
      if [[ -z "$OPENROUTER_API_KEY" ]]; then
        echo "  [ERRO] OPENROUTER_API_KEY nao definida" >&2
        return 1
      fi
      curl -s https://openrouter.ai/api/v1/chat/completions \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg model "$MODEL" --arg prompt "$prompt" '{
          model: $model,
          messages: [{role: "user", content: $prompt}],
          temperature: 0.2
        }')" | jq -r '.choices[0].message.content' > "$output_file"
      ;;

    ollama)
      curl -s "$OLLAMA_URL/api/generate" \
        -d "$(jq -n --arg model "$MODEL" --arg prompt "$prompt" '{
          model: $model,
          prompt: $prompt,
          stream: false
        }')" | jq -r '.response' > "$output_file"
      ;;

    bedrock)
      if command -v aws &>/dev/null; then
        aws bedrock-runtime invoke-model \
          --model-id "$MODEL" \
          --content-type "application/json" \
          --body "$(jq -n --arg prompt "$prompt" '{
            anthropic_version: "bedrock-2023-05-31",
            messages: [{role: "user", content: $prompt}],
            max_tokens: 4096
          }')" \
          "$output_file.raw" 2>/dev/null
        jq -r '.content[0].text' "$output_file.raw" > "$output_file" 2>/dev/null
        rm -f "$output_file.raw"
      else
        echo "  [ERRO] AWS CLI nao instalada para Bedrock" >&2
        return 1
      fi
      ;;
  esac
}

# --- 1. Mapeamento da estrutura ---
echo -e "\n[1/6] Mapeando estrutura do projeto..."

STRUCTURE=$(find "$SOURCE" -type f \
  \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.java" \
     -o -name "*.go" -o -name "*.rb" -o -name "*.php" -o -name "*.rs" \
     -o -name "*.c" -o -name "*.cpp" -o -name "*.h" \
     -o -name "Dockerfile*" -o -name "docker-compose*" \
     -o -name "Makefile" -o -name "*.yml" -o -name "*.yaml" \
     -o -name "*.toml" -o -name "*.json" -o -name "*.md" \) \
  | grep -v node_modules | grep -v __pycache__ | grep -v .git \
  | grep -v vendor | grep -v .venv \
  | sort)

echo "$STRUCTURE" > "$OUTPUT/file-tree.txt"
FILE_COUNT=$(echo "$STRUCTURE" | wc -l)
echo "  $FILE_COUNT arquivos encontrados"

# --- 2. Detectar stack e dependencias ---
echo -e "\n[2/6] Detectando stack tecnologica..."

STACK_INFO=""
[[ -f "$SOURCE/package.json" ]] && STACK_INFO+="Node.js: $(cat "$SOURCE/package.json" | jq -r '.dependencies // {} | keys | join(", ")' 2>/dev/null)\n"
[[ -f "$SOURCE/requirements.txt" ]] && STACK_INFO+="Python: $(head -20 "$SOURCE/requirements.txt" | tr '\n' ', ')\n"
[[ -f "$SOURCE/go.mod" ]] && STACK_INFO+="Go: $(grep -v '^module\|^go\|^$' "$SOURCE/go.mod" | head -10 | tr '\n' ', ')\n"
[[ -f "$SOURCE/Gemfile" ]] && STACK_INFO+="Ruby: $(grep "gem " "$SOURCE/Gemfile" | head -10 | awk '{print $2}' | tr '\n' ', ')\n"
[[ -f "$SOURCE/pom.xml" ]] && STACK_INFO+="Java (Maven)\n"
[[ -f "$SOURCE/build.gradle" ]] && STACK_INFO+="Java (Gradle)\n"
[[ -f "$SOURCE/Cargo.toml" ]] && STACK_INFO+="Rust\n"

echo -e "$STACK_INFO" | tee "$OUTPUT/stack.txt"

# --- 3. Extrair assinaturas de funcoes/classes ---
echo -e "\n[3/6] Extraindo assinaturas de funcoes e classes..."

SIGNATURES_FILE="$OUTPUT/signatures.txt"
echo "" > "$SIGNATURES_FILE"

# Python
grep -rn --include="*.py" -E "^(class |def |async def )" "$SOURCE" 2>/dev/null \
  | grep -v node_modules | grep -v __pycache__ | head -200 >> "$SIGNATURES_FILE" || true

# JavaScript/TypeScript
grep -rn --include="*.js" --include="*.ts" --include="*.jsx" --include="*.tsx" \
  -E "^(export |)(function |class |const \w+ = |async function )" "$SOURCE" 2>/dev/null \
  | grep -v node_modules | head -200 >> "$SIGNATURES_FILE" || true

# Go
grep -rn --include="*.go" -E "^func " "$SOURCE" 2>/dev/null \
  | grep -v vendor | head -200 >> "$SIGNATURES_FILE" || true

# Java
grep -rn --include="*.java" -E "^\s*(public|private|protected).*\(" "$SOURCE" 2>/dev/null \
  | head -200 >> "$SIGNATURES_FILE" || true

# Ruby
grep -rn --include="*.rb" -E "^(class |module |def )" "$SOURCE" 2>/dev/null \
  | head -200 >> "$SIGNATURES_FILE" || true

SIG_COUNT=$(wc -l < "$SIGNATURES_FILE")
echo "  $SIG_COUNT assinaturas extraidas"

# --- 4. Extrair endpoints/rotas ---
echo -e "\n[4/6] Extraindo endpoints e rotas..."

ENDPOINTS_FILE="$OUTPUT/endpoints.txt"
echo "" > "$ENDPOINTS_FILE"

# Express/Fastify (JS)
grep -rn --include="*.js" --include="*.ts" \
  -E "\.(get|post|put|patch|delete|use)\s*\(" "$SOURCE" 2>/dev/null \
  | grep -v node_modules | head -100 >> "$ENDPOINTS_FILE" || true

# Flask/FastAPI/Django (Python)
grep -rn --include="*.py" \
  -E "(@app\.(route|get|post|put|delete)|@router\.|path\(|url\()" "$SOURCE" 2>/dev/null \
  | grep -v __pycache__ | head -100 >> "$ENDPOINTS_FILE" || true

# Go (gin/echo/mux)
grep -rn --include="*.go" \
  -E "\.(GET|POST|PUT|DELETE|PATCH|Handle|HandleFunc)\(" "$SOURCE" 2>/dev/null \
  | head -100 >> "$ENDPOINTS_FILE" || true

# Java (Spring)
grep -rn --include="*.java" \
  -E "@(GetMapping|PostMapping|PutMapping|DeleteMapping|RequestMapping)" "$SOURCE" 2>/dev/null \
  | head -100 >> "$ENDPOINTS_FILE" || true

ENDPOINT_COUNT=$(grep -c "" "$ENDPOINTS_FILE" 2>/dev/null || echo 0)
echo "  $ENDPOINT_COUNT endpoints encontrados"

# --- 5. Gerar documentacao com LLM ---
echo -e "\n[5/6] Gerando documentacao com LLM ($PROVIDER)..."

# Pegar arquivos principais para contexto (limitar a ~50KB para nao estourar tokens)
CONTEXT=""
for f in $(echo "$STRUCTURE" | grep -E "\.(py|js|ts|go|java|rb)$" | head -15); do
  FILE_CONTENT=$(head -100 "$f" 2>/dev/null || true)
  if [[ -n "$FILE_CONTENT" ]]; then
    REL_PATH="${f#$SOURCE/}"
    CONTEXT+="--- $REL_PATH ---\n$FILE_CONTENT\n\n"
  fi
done

# Prompt para gerar README
README_PROMPT="Voce e um documentador de codigo. Analise este projeto e gere um README.md completo em portugues.

Estrutura do projeto:
$(cat "$OUTPUT/file-tree.txt" | sed "s|$SOURCE/||g" | head -50)

Stack:
$(cat "$OUTPUT/stack.txt")

Assinaturas principais:
$(head -50 "$SIGNATURES_FILE" | sed "s|$SOURCE/||g")

Endpoints:
$(head -30 "$ENDPOINTS_FILE" | sed "s|$SOURCE/||g")

Codigo fonte (primeiros arquivos):
$(echo -e "$CONTEXT" | head -500)

Gere um README.md com:
1. Nome e descricao do projeto (o que faz)
2. Stack tecnologica
3. Como instalar e rodar
4. Estrutura de diretorios explicada
5. Endpoints/APIs disponiveis (se houver)
6. Variaveis de ambiente necessarias
7. Dependencias principais e o que cada uma faz"

call_llm "$README_PROMPT" "$OUTPUT/README.md"
echo "  README.md gerado"

# Prompt para gerar doc de arquitetura
ARCH_PROMPT="Voce e um arquiteto de software. Analise este projeto e gere um documento ARCHITECTURE.md em portugues explicando a arquitetura.

Estrutura:
$(cat "$OUTPUT/file-tree.txt" | sed "s|$SOURCE/||g" | head -50)

Assinaturas:
$(head -80 "$SIGNATURES_FILE" | sed "s|$SOURCE/||g")

Endpoints:
$(head -30 "$ENDPOINTS_FILE" | sed "s|$SOURCE/||g")

Gere ARCHITECTURE.md com:
1. Visao geral da arquitetura (monolito, microservicos, MVC, etc)
2. Diagrama de componentes em texto (ASCII ou mermaid)
3. Fluxo de dados principal
4. Camadas (controller, service, repository, etc)
5. Integrações externas (banco, APIs, filas)
6. Padroes de design utilizados"

call_llm "$ARCH_PROMPT" "$OUTPUT/ARCHITECTURE.md"
echo "  ARCHITECTURE.md gerado"

# Prompt para gerar changelog de seguranca
SEC_PROMPT="Voce e um analista de seguranca. Analise este codigo legado e gere um documento SECURITY-REVIEW.md em portugues.

Assinaturas:
$(head -50 "$SIGNATURES_FILE" | sed "s|$SOURCE/||g")

Codigo:
$(echo -e "$CONTEXT" | head -300)

Gere SECURITY-REVIEW.md com:
1. Riscos de seguranca identificados no codigo
2. Dependencias que podem estar desatualizadas
3. Padroes inseguros encontrados (hardcoded secrets, SQL raw, eval, etc)
4. Recomendacoes de melhoria
5. Prioridade de correcao (critico, alto, medio, baixo)"

call_llm "$SEC_PROMPT" "$OUTPUT/SECURITY-REVIEW.md"
echo "  SECURITY-REVIEW.md gerado"

# --- 6. Gerar indice ---
echo -e "\n[6/6] Gerando indice..."

cat > "$OUTPUT/INDEX.md" <<EOF
# Documentacao Gerada - $(basename "$SOURCE")

Documentacao gerada automaticamente pelo SecOps Legacy Doc Generator.
Data: $(date +%Y-%m-%d)

## Arquivos gerados

| Documento | Conteudo |
|---|---|
| [README.md](README.md) | Descricao do projeto, como instalar e rodar |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Arquitetura, componentes, fluxo de dados |
| [SECURITY-REVIEW.md](SECURITY-REVIEW.md) | Analise de seguranca do codigo legado |
| [file-tree.txt](file-tree.txt) | Lista completa de arquivos do projeto |
| [stack.txt](stack.txt) | Stack tecnologica detectada |
| [signatures.txt](signatures.txt) | Funcoes, classes e metodos encontrados |
| [endpoints.txt](endpoints.txt) | Rotas e endpoints da API |

## Como foi gerado

Provider: $PROVIDER
Model: $MODEL
Source: $(basename "$SOURCE")

## Limitacoes

- A documentacao e gerada por IA e pode conter imprecisoes
- Revise manualmente antes de considerar como documentacao oficial
- Arquivos muito grandes sao truncados (primeiras 100 linhas)
- Maximo de 15 arquivos de codigo analisados por vez
EOF

echo ""
echo "============================================"
echo " Documentacao gerada!"
echo " Output: $OUTPUT"
echo "============================================"
echo ""
echo " Arquivos:"
ls -1 "$OUTPUT" | sed 's/^/   - /'
echo ""
echo " Abrir: cat $OUTPUT/INDEX.md"
echo "============================================"
