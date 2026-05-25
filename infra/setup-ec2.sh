#!/bin/bash
set -euo pipefail

# === SecOps EC2 Setup ===
# Roda em uma EC2 Ubuntu 22.04+ (t3.large ou maior)
# Uso: curl -sSL <raw_url> | bash

echo "============================================"
echo " SecOps - Setup EC2"
echo "============================================"

# --- 1. Instalar Docker ---
echo -e "\n[1/5] Instalando Docker..."
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  sudo systemctl enable docker
  sudo systemctl start docker
fi

# --- 2. Instalar Docker Compose ---
echo -e "\n[2/5] Instalando Docker Compose..."
if ! docker compose version &>/dev/null; then
  sudo apt-get install -y docker-compose-plugin
fi

# --- 3. Instalar ferramentas auxiliares ---
echo -e "\n[3/5] Instalando jq, git..."
sudo apt-get update -qq
sudo apt-get install -y jq git

# --- 4. Clonar projeto ---
echo -e "\n[4/5] Clonando SecOps..."
if [ ! -d "/opt/secops" ]; then
  sudo git clone https://github.com/Cadush/SECops.git /opt/secops
  sudo chown -R "$USER:$USER" /opt/secops
fi
cd /opt/secops

# --- 5. Subir serviços ---
echo -e "\n[5/5] Subindo serviços..."
docker compose up -d

# --- Aguardar DefectDojo inicializar ---
echo -e "\n[*] Aguardando DefectDojo inicializar (pode levar 2-3 min)..."
for i in $(seq 1 60); do
  if curl -s http://localhost:8888/api/v2/ 2>/dev/null | grep -q "engagements"; then
    echo "  ✅ DefectDojo pronto!"
    break
  fi
  echo "  Aguardando... ($i/60)"
  sleep 5
done

# --- Resumo ---
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")

echo ""
echo "============================================"
echo " SecOps instalado com sucesso!"
echo "============================================"
echo ""
echo " Dashboards:"
echo "   DefectDojo:       http://$PUBLIC_IP:8888 (admin/admin)"
echo "   SonarQube:        http://$PUBLIC_IP:9000 (admin/admin)"
echo "   Dependency-Track: http://$PUBLIC_IP:8080"
echo "   Vault:            http://$PUBLIC_IP:8200 (token: secops-dev-token)"
echo ""
echo " Para rodar scan remoto:"
echo "   export DEFECTDOJO_URL=http://$PUBLIC_IP:8888"
echo "   make scan REPO=./meu-projeto"
echo ""
echo " Logs: docker compose logs -f"
echo "============================================"
