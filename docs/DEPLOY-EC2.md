# Deploy na AWS EC2 - SecOps Centralizado

## Arquitetura

```
┌─────────────────────────────────────────────────────────┐
│                    EC2 (t3.large)                         │
│                                                           │
│  ┌─────────────┐  ┌──────────┐  ┌───────────────────┐  │
│  │ DefectDojo  │  │ SonarQube│  │ Dependency-Track   │  │
│  │ :8888       │  │ :9000    │  │ :8080              │  │
│  └─────────────┘  └──────────┘  └───────────────────┘  │
│  ┌─────────────┐                                         │
│  │   Vault     │  ← Todos em Docker Compose              │
│  │   :8200     │                                         │
│  └─────────────┘                                         │
└─────────────────────────────────────────────────────────┘
        ↑                    ↑                    ↑
        │                    │                    │
   Dev Local            CI/CD Pipeline       Outro Dev
   (scan-remote.sh)     (GitHub Actions)     (scan-remote.sh)
```

Os devs rodam scans localmente e enviam os resultados para o DefectDojo centralizado na EC2. Isso permite:

- **Histórico**: ver evolução de vulnerabilidades ao longo do tempo
- **Métricas**: MTTR, findings por sprint, tendências
- **Centralização**: todos os projetos num lugar só
- **Tracking**: assign findings para devs, marcar como resolvido/falso positivo

---

## Opção 1: Deploy Manual (SSH)

### Requisitos
- EC2 **t3.large** (2 vCPU, 8GB RAM) mínimo
- Ubuntu 22.04 LTS
- 50GB disco (gp3)
- Security Group com portas: 22, 8080, 8081, 8200, 8888, 9000

### Passos

```bash
# 1. Criar EC2 no console AWS (ou CLI)
aws ec2 run-instances \
  --image-id ami-0c7217cdde317cfec \
  --instance-type t3.large \
  --key-name sua-key \
  --security-groups secops-server \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":50,"VolumeType":"gp3"}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=secops-server}]'

# 2. SSH na instância
ssh -i ~/.ssh/sua-key.pem ubuntu@<IP_PUBLICO>

# 3. Rodar setup
curl -sSL https://raw.githubusercontent.com/Cadush/SECops/main/infra/setup-ec2.sh | bash

# 4. Verificar
docker compose ps
curl http://localhost:8888/api/v2/
```

---

## Opção 2: Deploy com Terraform

```bash
cd infra/

# Configurar variáveis
cat > terraform.tfvars <<EOF
region       = "us-east-1"
key_name     = "sua-key-pair"
allowed_cidr = "SEU_IP/32"  # Restringir acesso!
EOF

# Deploy
terraform init
terraform plan
terraform apply

# Output mostra IP e URLs
# defectdojo_url = "http://X.X.X.X:8888"
# ssh_command = "ssh -i ~/.ssh/sua-key.pem ubuntu@X.X.X.X"
```

---

## Uso: Scan Remoto (dev local → EC2)

Depois que a EC2 estiver rodando:

```bash
# Scan local que envia resultados para o servidor
bash scripts/scan-remote.sh ./meu-projeto --server <IP_DA_EC2>

# Ou configurar variável de ambiente
export DEFECTDOJO_URL=http://<IP_DA_EC2>:8888
make scan REPO=./meu-projeto
```

---

## Uso: CI/CD (GitHub Actions → EC2)

```yaml
# .github/workflows/secops.yml
name: SecOps Scan

on: [push, pull_request]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run SecOps Pipeline
        env:
          DEFECTDOJO_URL: ${{ secrets.DEFECTDOJO_URL }}
          DEFECTDOJO_TOKEN: ${{ secrets.DEFECTDOJO_TOKEN }}
        run: |
          # Instalar ferramentas CLI
          docker pull semgrep/semgrep:latest
          docker pull aquasec/trivy:latest
          docker pull zricethezav/gitleaks:latest

          # Rodar scans
          docker run --rm -v $PWD:/src semgrep/semgrep:latest \
            semgrep scan --config auto --json -o /src/semgrep.json /src || true
          docker run --rm -v $PWD:/src aquasec/trivy:latest \
            fs --format json -o /src/trivy.json /src || true
          docker run --rm -v $PWD:/src zricethezav/gitleaks:latest \
            detect --source /src --report-format json --report-path /src/gitleaks.json || true

          # Enviar para DefectDojo
          TOKEN=$(curl -s -X POST "$DEFECTDOJO_URL/api/v2/api-token-auth/" \
            -H "Content-Type: application/json" \
            -d '{"username":"admin","password":"admin"}' | jq -r '.token')

          for report in semgrep.json trivy.json gitleaks.json; do
            [ -f "$report" ] && curl -X POST "$DEFECTDOJO_URL/api/v2/import-scan/" \
              -H "Authorization: Token $TOKEN" \
              -F "scan_type=Semgrep JSON Report" \
              -F "file=@$report" \
              -F "engagement=1" \
              -F "active=true"
          done
```

---

## Security Groups (portas necessárias)

| Porta | Serviço | Quem acessa |
|---|---|---|
| 22 | SSH | Seu IP |
| 8080 | Dependency-Track | Seu IP / VPN |
| 8081 | Dependency-Track API | Interno |
| 8200 | Vault | Seu IP / VPN |
| 8888 | DefectDojo | Seu IP / VPN / CI |
| 9000 | SonarQube | Seu IP / VPN |

⚠️ **IMPORTANTE**: Em produção, restrinja `allowed_cidr` para seu IP ou VPN. Nunca deixe `0.0.0.0/0`.

---

## Custos estimados (us-east-1)

| Recurso | Spec | Custo/mês |
|---|---|---|
| EC2 t3.large | 2 vCPU, 8GB RAM | ~$60 |
| EBS gp3 50GB | Storage | ~$4 |
| **Total** | | **~$64/mês** |

Para economizar:
- Use **Spot Instance** (~$20/mês) se tolerar interrupções
- Use **t3.medium** (4GB) se rodar só DefectDojo (sem SonarQube)
- Desligue fora do horário com Lambda scheduled

---

## Backup

```bash
# Backup dos dados (rodar na EC2)
docker compose stop
tar czf /tmp/secops-backup-$(date +%Y%m%d).tar.gz \
  /var/lib/docker/volumes/secops_defectdojo_db \
  /var/lib/docker/volumes/secops_sonarqube_data
docker compose start

# Enviar para S3
aws s3 cp /tmp/secops-backup-*.tar.gz s3://seu-bucket/backups/
```

---

## Monitoramento

Para saber se os serviços estão saudáveis:

```bash
# Health check simples (cron a cada 5 min)
curl -sf http://localhost:8888/api/v2/ > /dev/null || echo "DefectDojo DOWN" | mail -s "SecOps Alert" seu@email.com
curl -sf http://localhost:9000/api/system/status > /dev/null || echo "SonarQube DOWN" | mail -s "SecOps Alert" seu@email.com
```
