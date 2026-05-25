# SecOps - Pipeline de Revisao de Codigo

Orquestracao de **20+ ferramentas open source** de seguranca para analise completa de repositorios. Um unico comando escaneia secrets, vulnerabilidades, dependencias, containers, IaC e aplicacoes web.

Todos os direitos reservados a Carlos Eduardo.

---

## O que faz

```
Repositorio --> SecOps Pipeline --> Relatorio HTML + JSON
```

O pipeline analisa codigo em **6 camadas**:

| Camada | O que verifica | Ferramentas |
|---|---|---|
| Secrets | API keys, tokens, senhas expostas | Gitleaks, TruffleHog |
| SAST | XSS, SQLi, RCE, command injection | Semgrep, Bandit, Gosec, SpotBugs, Brakeman |
| SCA | Dependencias com CVEs conhecidas | Trivy, Grype, Syft, OSV-Scanner |
| Container | Dockerfile inseguro, imagem com CVEs | Hadolint, Dockle, Trivy, Checkov, KICS |
| DAST | Vulnerabilidades em app rodando | OWASP ZAP, Nuclei, Nikto, sqlmap |
| Quality | Code smells, bugs, duplicacao | SonarQube |

---

## Quick Start

Existem duas formas de usar o SECops:

### Opcao 1: Container unico (recomendado)

Todas as ferramentas empacotadas numa unica imagem Docker. Sem dependencias externas.

```bash
# Construir a imagem (uma vez, ~3GB)
make build

# Executar scan completo + relatorio HTML
make scan-docker REPO=./meu-projeto

# Abrir relatorio no navegador
xdg-open reports/<timestamp>/report.html
```

### Opcao 2: Ferramentas separadas (modo completo)

Cada ferramenta roda em seu proprio container. Necessario baixar ~15GB de imagens.

```bash
# Baixar imagens (primeira vez)
make pull

# Subir infraestrutura (SonarQube, DefectDojo, Vault, ZAP)
make up

# Executar scan
make scan REPO=https://github.com/seu-org/seu-repo

# Scan com DAST (app rodando)
make scan REPO=./meu-projeto DAST=http://localhost:3000

# Scan com analise de imagem Docker
make scan REPO=./meu-projeto IMAGE=meu-app:latest

# Parar infraestrutura
make down
```

---

## Comandos disponiveis (Makefile)

| Comando | Descricao |
|---|---|
| `make build` | Constroi imagem unica com todas as ferramentas |
| `make scan-docker REPO=<path>` | Scan completo usando container unico |
| `make scan REPO=<path>` | Scan usando ferramentas separadas |
| `make up` | Sobe infraestrutura (SonarQube, DefectDojo, Vault, ZAP) |
| `make down` | Para infraestrutura |
| `make pull` | Baixa todas as imagens Docker |
| `make status` | Mostra status dos containers |
| `make report DIR=reports/<ts>` | Regenera relatorio HTML de um scan anterior |
| `make clear` | Remove TODOS os dados Docker (libera ~15GB) |
| `make vault-setup` | Configura HashiCorp Vault |
| `make sops-setup` | Configura SOPS + age para encriptacao |

---

## Resultado esperado

Apos executar `make scan-docker REPO=./test-vulnerable-app` ou `make scan REPO=./test-vulnerable-app`, o pipeline gera:

```
reports/20260525_093216/
├── report.html            <-- Relatorio visual (abrir no navegador)
├── audit-config.json      # .env expostos, .gitignore, chaves privadas
├── gitleaks.json          # Secrets no historico git
├── trufflehog.json        # Secrets no filesystem
├── semgrep.json           # SAST (XSS, SQLi, RCE)
├── bandit.json            # SAST Python
├── trivy-fs.json          # SCA (CVEs em dependencias)
├── grype.json             # SCA
├── syft-sbom.json         # SBOM (inventario de dependencias)
├── osv-scanner.json       # CVEs (Google OSV database)
├── checkov.json           # IaC (Terraform, Dockerfile)
├── hadolint-Dockerfile.txt # Lint de Dockerfile
└── ...
```

### Relatorio HTML

O relatorio HTML inclui:

- Grafico de pizza com distribuicao de severidades (Critical, High, Medium, Low)
- Data do scan e usuario que executou
- Secao de Configuracao e Secrets Expostos (com arquivo e linha)
- Secao SAST com vulnerabilidades no codigo (SQLi, Command Injection, etc.)
- Secao SCA com CVEs em dependencias (pacote, versao, fix disponivel)
- Secao de Secrets detectados (TruffleHog, Gitleaks)
- Secao de Container (Hadolint)
- Secao de IaC (Checkov)
- Botao para exportar como PDF

### Exemplo de resultado (test-vulnerable-app)

| Metrica | Valor |
|---|---|
| Total de findings | 131 |
| Critical | 12 |
| High | 48 |
| Medium | 57 |
| Low | 14 |

Ferramentas que detectaram problemas:

- **Bandit**: 18 findings (SQLi, Command Injection, hardcoded passwords, debug=True, pickle, MD5)
- **Trivy**: 98 CVEs em dependencias (django, cryptography, pillow, urllib3, werkzeug, jinja2)
- **TruffleHog**: 3 secrets (Stripe key, Slack webhook, MongoDB URI)
- **Hadolint**: 3 findings (tag latest, versoes nao fixadas, pacotes extras)
- **Audit-config**: 15 findings (.env exposto, chave privada, SQLi com linha exata)

---

## Exportar PDF

1. Abra o `report.html` no navegador
2. Clique no botao "Exportar PDF"
3. No dialogo de impressao, selecione "Salvar como PDF"
4. O PDF gerado pode ser armazenado para auditoria

---

## Limpeza

Quando terminar de usar, libere espaco em disco:

```bash
make clear
```

Remove todos os containers, volumes e imagens (~15GB liberados). Para usar novamente, execute `make build` ou `make pull`.

---

## Requisitos

- Docker + Docker Compose
- ~8GB RAM disponivel (se usar `make up` com SonarQube + DefectDojo)
- ~3GB disco (se usar `make build` com container unico)
- ~15GB disco (se usar `make pull` com ferramentas separadas)
- Git
- jq (para geracao do relatorio HTML)

---

## Estrutura do Projeto

```
SECops/
├── config/
│   ├── semgrep-rules.yml       # Regras custom SAST
│   └── .sops.yaml              # Config de encriptacao SOPS
├── docs/                       # Documentacao adicional
├── scripts/
│   ├── scan.sh                 # Orquestrador (ferramentas separadas)
│   ├── scan-local.sh           # Orquestrador (container unico)
│   ├── report-html.sh          # Gerador de relatorio HTML
│   ├── audit-config.sh         # Auditoria de .env, .gitignore
│   ├── import-defectdojo.sh    # Importa reports no DefectDojo
│   ├── vault.sh                # Operacoes com Vault
│   ├── sops.sh                 # Operacoes com SOPS
│   ├── clear.sh                # Limpeza completa do Docker
│   └── pre-commit              # Git hook de seguranca
├── test-vulnerable-app/        # App vulneravel para testes
├── reports/                    # Output dos scans
├── infra/                      # Terraform para deploy EC2
├── docker-compose.yml          # Infra (SonarQube, DefectDojo, Vault)
├── Dockerfile.scanner          # Imagem unica com todas as ferramentas
└── Makefile                    # Atalhos
```

---

## Secrets Management

### Vault (secrets em runtime)
```bash
make vault-setup
bash scripts/vault.sh put db/prod password=s3cr3t
bash scripts/vault.sh get db/prod
bash scripts/vault.sh inject app/dev .env
```

### SOPS (secrets encriptados no git)
```bash
make sops-setup
bash scripts/sops.sh encrypt secrets.yml
bash scripts/sops.sh decrypt secrets.yml
```

---

## Integracao com VSCode

- Semgrep sublinha XSS/SQLi enquanto digita
- SonarLint mostra code smells inline
- Pre-commit hook bloqueia commits com secrets

```bash
cp scripts/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

---

## Documentacao

| Doc | Conteudo |
|---|---|
| [docs/FERRAMENTAS.md](docs/FERRAMENTAS.md) | Detalhes de cada ferramenta |
| [docs/DEFECTDOJO.md](docs/DEFECTDOJO.md) | Dashboard agregador |
| [docs/VAULT-SOPS.md](docs/VAULT-SOPS.md) | Gerenciamento de secrets |
| [docs/VSCODE-INTEGRACAO.md](docs/VSCODE-INTEGRACAO.md) | Integracao com IDE |
| [docs/DEPLOY-EC2.md](docs/DEPLOY-EC2.md) | Deploy na AWS EC2 |
