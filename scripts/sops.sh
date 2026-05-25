#!/bin/bash
set -uo pipefail

# === SOPS (Secrets OPerationS) Manager ===
# Encripta secrets para commitar com segurança no git
# Uso: ./sops.sh <command>

command="${1:-help}"
shift 2>/dev/null || true

SOPS_CONFIG="$(cd "$(dirname "$0")/../config" && pwd)/.sops.yaml"

case "$command" in
  setup)
    echo "[*] Configurando SOPS + age..."

    # Instalar age se não tiver
    if ! command -v age &>/dev/null; then
      echo "  Instalando age..."
      sudo apt-get install -y age 2>/dev/null || brew install age 2>/dev/null || {
        echo "  Baixando age..."
        curl -sL https://github.com/FiloSottile/age/releases/latest/download/age-v1.1.1-linux-amd64.tar.gz | sudo tar xz -C /usr/local/bin --strip-components=1
      }
    fi

    # Instalar sops se não tiver
    if ! command -v sops &>/dev/null; then
      echo "  Instalando sops..."
      curl -sLo /tmp/sops https://github.com/getsops/sops/releases/latest/download/sops-v3.8.1.linux.amd64
      sudo install /tmp/sops /usr/local/bin/sops
    fi

    # Gerar chave age
    KEY_FILE="$HOME/.config/sops/age/keys.txt"
    if [[ ! -f "$KEY_FILE" ]]; then
      mkdir -p "$(dirname "$KEY_FILE")"
      age-keygen -o "$KEY_FILE" 2>&1
      echo ""
      echo "Chave age gerada em: $KEY_FILE"
      echo ""
      PUBLIC_KEY=$(grep "public key:" "$KEY_FILE" | awk '{print $NF}')
      echo "  Chave pública: $PUBLIC_KEY"
      echo ""
      echo "  IMPORTANTE: Atualize config/.sops.yaml com esta chave pública!"
      echo "  Substitua 'age1xxx...' por: $PUBLIC_KEY"
    else
      echo "  Chave age já existe em: $KEY_FILE"
      PUBLIC_KEY=$(grep "public key:" "$KEY_FILE" | awk '{print $NF}')
      echo "  Chave pública: $PUBLIC_KEY"
    fi
    ;;

  encrypt)
    # ./sops.sh encrypt <arquivo>
    file="${1:?Uso: $0 encrypt <arquivo.yml>}"
    echo "[*] Encriptando $file..."
    sops --config "$SOPS_CONFIG" -e -i "$file"
    echo "Arquivo encriptado. Seguro para commitar."
    ;;

  decrypt)
    # ./sops.sh decrypt <arquivo>
    file="${1:?Uso: $0 decrypt <arquivo.yml>}"
    echo "[*] Decriptando $file..."
    sops --config "$SOPS_CONFIG" -d "$file"
    ;;

  edit)
    # ./sops.sh edit <arquivo> - abre editor com arquivo decriptado temporariamente
    file="${1:?Uso: $0 edit <arquivo.yml>}"
    sops --config "$SOPS_CONFIG" "$file"
    ;;

  create-example)
    # Cria arquivo de exemplo para secrets
    cat > secrets.example.yml <<'EOF'
# Exemplo de arquivo de secrets (encriptar com: ./scripts/sops.sh encrypt secrets.yml)
database:
  host: db.example.com
  port: 5432
  username: app_user
  password: CHANGE_ME

api_keys:
  github_token: ghp_xxxxxxxxxxxx
  slack_webhook: https://hooks.slack.com/xxx

aws:
  access_key_id: AKIAXXXXXXXX
  secret_access_key: CHANGE_ME
  region: us-east-1
EOF
    echo "Criado secrets.example.yml"
    echo "  1. Copie para secrets.yml"
    echo "  2. Preencha os valores reais"
    echo "  3. Encripte: ./scripts/sops.sh encrypt secrets.yml"
    echo "  4. Commite o secrets.yml (encriptado)"
    ;;

  *)
    echo "SecOps SOPS Manager - Encriptação de secrets para git"
    echo ""
    echo "Uso: $0 <command>"
    echo ""
    echo "Comandos:"
    echo "  setup           - Instala age + sops e gera chave"
    echo "  encrypt <file>  - Encripta arquivo (seguro para git)"
    echo "  decrypt <file>  - Decripta arquivo (mostra no stdout)"
    echo "  edit <file>     - Edita arquivo encriptado no editor"
    echo "  create-example  - Cria template de secrets"
    echo ""
    echo "Fluxo:"
    echo "  1. ./sops.sh setup"
    echo "  2. Atualizar config/.sops.yaml com chave pública"
    echo "  3. ./sops.sh encrypt secrets.yml"
    echo "  4. git add secrets.yml (encriptado, seguro)"
    ;;
esac
