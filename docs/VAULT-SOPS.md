# Secrets Management - Vault + SOPS

## Problema

Detectar secrets é só metade do trabalho. Você precisa de uma forma segura de:
- Armazenar secrets (API keys, passwords, tokens)
- Distribuir secrets para aplicações
- Rotacionar secrets sem downtime
- Commitar configurações com secrets sem expor valores

## Solução: Vault + SOPS

| Ferramenta | Quando usar |
|---|---|
| **HashiCorp Vault** | Secrets dinâmicos, runtime, aplicações em produção |
| **Mozilla SOPS** | Secrets em arquivos (YAML/JSON) que precisam ir pro git |

---

## HashiCorp Vault

### O que é

Vault é um servidor centralizado de secrets. Aplicações pedem secrets via API em vez de ler de .env ou variáveis hardcoded.

### Acesso

- URL: http://localhost:8200
- Token (dev): `secops-dev-token`

### Setup

```bash
# Subir Vault
make up

# Configurar (cria engines, policies, tokens)
make vault-setup

# Ou diretamente:
bash scripts/vault.sh setup
```

### Operações

```bash
# Salvar secrets
bash scripts/vault.sh put db/production host=db.example.com user=app password=s3cr3t
bash scripts/vault.sh put api/github token=ghp_xxxxxxxxxxxx
bash scripts/vault.sh put aws/credentials access_key=AKIA... secret_key=...

# Ler secrets
bash scripts/vault.sh get db/production

# Listar
bash scripts/vault.sh list

# Gerar .env a partir do Vault (para dev local)
bash scripts/vault.sh inject app/dev .env
```

### Integração com aplicações

```python
# Python - hvac library
import hvac

client = hvac.Client(url='http://localhost:8200', token='<pipeline-token>')
secret = client.secrets.kv.v2.read_secret_version(path='db/production', mount_point='secops')
db_password = secret['data']['data']['password']
```

```javascript
// Node.js - node-vault
const vault = require("node-vault")({ endpoint: "http://localhost:8200", token: "<pipeline-token>" });
const { data } = await vault.read("secops/data/db/production");
const dbPassword = data.data.password;
```

```go
// Go - vault SDK
client, _ := vault.New(vault.WithAddress("http://localhost:8200"), vault.WithToken("<pipeline-token>"))
secret, _ := client.KVv2("secops").Get(ctx, "db/production")
password := secret.Data["password"].(string)
```

### Policies (controle de acesso)

| Policy | Permissão |
|---|---|
| `secops-admin` | CRUD em todos os secrets |
| `secops-pipeline` | Apenas leitura (para CI/CD) |

### Produção

Para produção, **NÃO use dev mode**. Configure:
- Storage backend (Consul, PostgreSQL, Raft)
- Auto-unseal (AWS KMS, GCP KMS)
- Audit logging
- TLS

---

## Mozilla SOPS

### O que é

SOPS encripta **valores** dentro de arquivos YAML/JSON, mantendo as **chaves** legíveis. Isso permite commitar secrets no git de forma segura.

### Antes vs Depois

```yaml
# ANTES (PERIGO - nunca commitar assim)
database:
  password: super-secret-123

# DEPOIS (encriptado com SOPS - seguro para git)
database:
  password: ENC[AES256_GCM,data:abc123...,iv:xyz...,tag:...]
```

### Setup

```bash
# Instalar age + sops e gerar chave
make sops-setup

# Ou diretamente:
bash scripts/sops.sh setup
```

### Operações

```bash
# Criar template de exemplo
bash scripts/sops.sh create-example

# Encriptar arquivo (seguro para git)
bash scripts/sops.sh encrypt secrets.yml

# Decriptar (mostra no stdout)
bash scripts/sops.sh decrypt secrets.yml

# Editar (decripta → editor → re-encripta)
bash scripts/sops.sh edit secrets.yml
```

### Fluxo de trabalho

```
1. Dev cria secrets.yml com valores reais
2. Dev encripta: ./scripts/sops.sh encrypt secrets.yml
3. Dev commita secrets.yml (encriptado, seguro)
4. CI/CD decripta com a chave (armazenada no Vault ou variável protegida)
5. Aplicação usa os valores decriptados
```

### Compartilhando a chave

A chave privada (`~/.config/sops/age/keys.txt`) precisa estar em:
- Máquina de cada dev que precisa decriptar
- CI/CD (como variável de ambiente `SOPS_AGE_KEY`)
- Vault (para centralizar)

```bash
# No CI/CD (GitHub Actions)
env:
  SOPS_AGE_KEY: ${{ secrets.SOPS_AGE_KEY }}

# Decriptar no pipeline
sops -d secrets.yml > secrets-decrypted.yml
```

---

## Quando usar qual?

| Cenário | Ferramenta |
|---|---|
| Secrets de aplicação em runtime | **Vault** |
| Secrets em arquivos de config no git | **SOPS** |
| Secrets de CI/CD pipeline | **Vault** (ou SOPS) |
| Rotação automática de credentials | **Vault** |
| Secrets de Terraform/IaC | **SOPS** |
| Database credentials dinâmicos | **Vault** (dynamic secrets) |

---

## Integração com o Pipeline SecOps

```
┌─────────────────────────────────────────────────┐
│                  Fluxo Completo                   │
├─────────────────────────────────────────────────┤
│                                                   │
│  1. Dev salva secrets no Vault                   │
│     └── bash scripts/vault.sh put api/key ...    │
│                                                   │
│  2. Config files encriptados com SOPS            │
│     └── bash scripts/sops.sh encrypt secrets.yml │
│                                                   │
│  3. Pipeline detecta se alguém expôs secrets     │
│     └── Gitleaks + TruffleHog                    │
│                                                   │
│  4. Aplicação lê secrets do Vault (não de .env)  │
│     └── SDK do Vault na aplicação                │
│                                                   │
│  5. Resultado: zero secrets no código ✅          │
│                                                   │
└─────────────────────────────────────────────────┘
```
