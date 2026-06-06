# SecOps Orchestrator

Orquestracao de **20+ ferramentas open source** de seguranca para analise completa de repositorios. Um unico comando escaneia secrets, vulnerabilidades, dependencias, containers, IaC e aplicacoes web.

Todos os direitos reservados a Carlos Eduardo.

---

## O que faz

```
Repositorio --> SecOps Orchestrator --> Relatorio HTML + JSON + DefectDojo
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

Alem do pipeline de scan, o projeto inclui:

- **Dependency Audit** - analise profunda de libs com Snyk, OWASP Dependency-Check, npm audit, Dependabot
- **Legacy Doc** - documentacao automatica de codigo legado usando LLM (Ollama local, open source)
- **DefectDojo** - dashboard centralizado que agrega todos os findings com tracking ao longo do tempo
- **Vault + SOPS** - gerenciamento de secrets (nao so detectar, mas proteger)
- **Deploy EC2** - servidor centralizado para equipes

---

## Dashboards

| Servico | URL | Credenciais |
|---|---|---|
| DefectDojo | http://localhost:8888 | admin / admin |
| SonarQube | http://localhost:9000 | admin / admin |
| Dependency-Track | http://localhost:8080 | (setup inicial) |
| Vault | http://localhost:8200 | token: secops-dev-token |
| ZAP API | http://localhost:8090 | - |

---

## Quick Start

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
| `make dep-audit REPO=<path>` | Analise profunda de dependencias |
| `make dep-audit-build` | Constroi imagem do dep-audit para CI |
| `make dep-audit-docker REPO=<path>` | Dep-audit via container unico |
| `make legacy-doc REPO=<path>` | Documenta codigo legado com LLM |
| `make ollama-setup` | Instala Ollama + modelos open source |
| `make ollama-up` | Sobe Ollama em container Docker |
| `make scan-remote REPO=<path> SERVER=<ip>` | Scan remoto (envia para EC2) |
| `make vault-setup` | Configura HashiCorp Vault |
| `make sops-setup` | Configura SOPS + age para encriptacao |
| `make report DIR=reports/<ts>` | Regenera relatorio HTML de um scan anterior |
| `make clear` | Remove TODOS os dados Docker (libera ~15GB) |

---

## Dependency Audit (analise de libs)

Ferramenta dedicada para revisao profunda de dependencias. Roda localmente ou em CI/CD.

```bash
# Scan basico (open source)
make dep-audit REPO=./meu-projeto

# Com Snyk (monitoramento + fix PRs)
make dep-audit REPO=./meu-projeto SNYK_TOKEN=xxx

# Via container (para pipelines)
make dep-audit-build
make dep-audit-docker REPO=./meu-projeto FAIL_ON=high
```

Ferramentas: npm audit, pip-audit, bundle-audit, govulncheck, OWASP Dependency-Check, Snyk, Dependabot config.

Templates CI prontos em `ci/` para Bitbucket, GitHub Actions e GitLab.

---

## Legacy Doc (documentacao de codigo legado)

Analisa um codebase sem documentacao e gera docs automaticamente usando LLM. Roda 100% local e open source com Ollama.

```bash
# Setup (uma vez - instala Ollama + modelos)
make ollama-setup

# Gerar documentacao
make legacy-doc REPO=./codigo-legado

# Modelo menor (8GB RAM)
make legacy-doc REPO=./codigo-legado MODEL=qwen2.5-coder:7b
```

Gera: README.md, ARCHITECTURE.md, SECURITY-REVIEW.md

Tambem suporta OpenAI, OpenRouter e AWS Bedrock se preferir.

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

## Deploy Centralizado (EC2)

Sobe o SecOps Orchestrator numa EC2 para centralizar findings de todos os projetos da equipe ao longo do tempo.

```bash
# Via Terraform
cd infra/ && terraform apply

# Via script (SSH na EC2)
bash infra/setup-ec2.sh

# Scan remoto (dev local -> EC2)
make scan-remote REPO=./meu-app SERVER=<IP_DA_EC2>
```

DefectDojo na EC2 acumula findings e gera metricas: MTTR, tendencias, findings por sprint.

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

## Resultado esperado

Apos executar `make scan REPO=./test-vulnerable-app`, o pipeline gera:

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

---

## Exportar PDF

1. Abra o `report.html` no navegador
2. Clique no botao "Exportar PDF"
3. No dialogo de impressao, selecione "Salvar como PDF"
4. O PDF gerado pode ser armazenado para auditoria

---

## Limpeza

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

Para o legacy-doc com Ollama:
- ~16GB RAM (modelo 14B) ou ~8GB RAM (modelo 7B)
- GPU NVIDIA opcional (acelera geracao)

---

## Estrutura do Projeto

```
SECops/
├── config/
│   ├── semgrep-rules.yml       # Regras custom SAST
│   ├── .sops.yaml              # Config de encriptacao SOPS
│   └── oh-my-openagent.json    # Config multi-agente para legacy-doc
├── ci/
│   ├── bitbucket-pipelines.yml # Template Bitbucket
│   ├── github-actions.yml      # Template GitHub Actions
│   └── gitlab-ci.yml           # Template GitLab CI
├── docs/                       # Documentacao completa
├── scripts/
│   ├── scan.sh                 # Orquestrador principal (14 etapas)
│   ├── scan-local.sh           # Orquestrador (container unico)
│   ├── scan-remote.sh          # Scan remoto (envia para EC2)
│   ├── audit-config.sh         # Auditoria de .env, .gitignore
│   ├── dep-audit.sh            # Analise profunda de dependencias
│   ├── dep-audit-docker.sh     # Dep-audit (entrypoint container)
│   ├── legacy-doc.sh           # Documentacao de codigo legado
│   ├── setup-ollama.sh         # Setup Ollama + modelos
│   ├── import-defectdojo.sh    # Importa reports no DefectDojo
│   ├── report-html.sh          # Gerador de relatorio HTML
│   ├── vault.sh                # Operacoes com Vault
│   ├── sops.sh                 # Operacoes com SOPS
│   ├── clear.sh                # Limpeza completa do Docker
│   └── pre-commit              # Git hook de seguranca
├── infra/
│   ├── main.tf                 # Terraform para EC2
│   └── setup-ec2.sh            # Bootstrap da EC2
├── reports/                    # Output dos scans
├── docker-compose.yml          # Infra (SonarQube, DefectDojo, Vault)
├── docker-compose.ollama.yml   # Ollama (LLM local)
├── Dockerfile.dep-audit        # Imagem dep-audit para CI
└── Makefile                    # Atalhos
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
| [docs/DEP-AUDIT.md](docs/DEP-AUDIT.md) | Analise profunda de dependencias |
| [docs/LEGACY-DOC.md](docs/LEGACY-DOC.md) | Documentacao de codigo legado |
