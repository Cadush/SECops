#!/bin/bash
set -uo pipefail

# === Vault Setup & Operations ===
# Uso: ./vault.sh <command>
# Comandos: setup, put, get, list, inject

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-secops-dev-token}"

export VAULT_ADDR VAULT_TOKEN

command="${1:-help}"
shift 2>/dev/null || true

case "$command" in
  setup)
    echo "[*] Configurando Vault para SecOps..."

    # Habilitar secrets engine KV v2
    docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$VAULT_TOKEN \
      secops-vault vault secrets enable -path=secops kv-v2 2>/dev/null || true

    # Criar policy para pipeline
    docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$VAULT_TOKEN \
      secops-vault sh -c 'vault policy write secops-pipeline - <<EOF
path "secops/data/*" {
  capabilities = ["read", "list"]
}
path "secops/metadata/*" {
  capabilities = ["list"]
}
EOF'

    # Criar policy para admin
    docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$VAULT_TOKEN \
      secops-vault sh -c 'vault policy write secops-admin - <<EOF
path "secops/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF'

    # Criar token para pipeline (read-only)
    PIPELINE_TOKEN=$(docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$VAULT_TOKEN \
      secops-vault vault token create -policy=secops-pipeline -ttl=720h -format=json 2>/dev/null \
      | grep -o '"client_token":"[^"]*"' | cut -d'"' -f4)

    echo ""
    echo "Vault configurado!"
    echo ""
    echo "  URL:            $VAULT_ADDR"
    echo "  Admin Token:    $VAULT_TOKEN (dev mode)"
    echo "  Pipeline Token: ${PIPELINE_TOKEN:-<erro ao gerar>}"
    echo ""
    echo "  Próximos passos:"
    echo "    ./vault.sh put api/github token=ghp_xxx"
    echo "    ./vault.sh put db/production host=db.example.com user=app password=s3cr3t"
    ;;

  put)
    # ./vault.sh put <path> key=value key2=value2
    secret_path="${1:?Uso: $0 put <path> key=value ...}"
    shift
    echo "[*] Salvando secret em secops/$secret_path..."
    docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$VAULT_TOKEN \
      secops-vault vault kv put "secops/$secret_path" "$@"
    echo "Secret salvo."
    ;;

  get)
    # ./vault.sh get <path>
    secret_path="${1:?Uso: $0 get <path>}"
    docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$VAULT_TOKEN \
      secops-vault vault kv get "secops/$secret_path"
    ;;

  list)
    # ./vault.sh list [path]
    secret_path="${1:-}"
    docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$VAULT_TOKEN \
      secops-vault vault kv list "secops/$secret_path"
    ;;

  inject)
    # ./vault.sh inject <path> <env_file>
    # Gera .env a partir de secrets do Vault
    secret_path="${1:?Uso: $0 inject <path> <env_file>}"
    env_file="${2:-.env}"
    echo "[*] Gerando $env_file a partir de secops/$secret_path..."

    json_output=$(docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$VAULT_TOKEN \
      secops-vault vault kv get -format=json "secops/$secret_path" 2>/dev/null)

    if command -v jq &>/dev/null; then
      echo "$json_output" | jq -r '.data.data | to_entries[] | "\(.key)=\(.value)"' > "$env_file"
    else
      # Fallback sem jq - extrai key=value do output tabular
      docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=$VAULT_TOKEN \
        secops-vault vault kv get -format=table "secops/$secret_path" \
        | grep -E "^\w" | grep -v "^---" | grep -v "^Key" \
        | awk '{print $1"="$2}' > "$env_file"
    fi

    echo "Arquivo $env_file gerado. NÃO commitar!"
    ;;

  *)
    echo "SecOps Vault Manager"
    echo ""
    echo "Uso: $0 <command>"
    echo ""
    echo "Comandos:"
    echo "  setup   - Configura Vault (engines, policies, tokens)"
    echo "  put     - Salvar secret (ex: $0 put db/prod password=s3cr3t)"
    echo "  get     - Ler secret (ex: $0 get db/prod)"
    echo "  list    - Listar secrets (ex: $0 list)"
    echo "  inject  - Gerar .env a partir do Vault (ex: $0 inject app/prod .env)"
    ;;
esac
