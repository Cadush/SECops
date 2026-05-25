# SecOps - Pipeline Completo de Revisão de Código

Pipeline de orquestração de ferramentas de segurança para garantir que aplicações sejam publicadas sem vulnerabilidades conhecidas.

---

## Arquitetura do Pipeline

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SecOps Pipeline                               │
├─────────────┬──────────────┬──────────────┬────────────┬────────────┤
│   SECRETS   │     SAST     │     SCA      │ CONTAINER  │    DAST    │
├─────────────┼──────────────┼──────────────┼────────────┼────────────┤
│ Gitleaks    │ Semgrep      │ Trivy FS     │ Hadolint   │ OWASP ZAP │
│ TruffleHog  │ Bandit (Py)  │ Grype + Syft │ Dockle     │ Nuclei    │
│             │ Gosec (Go)   │ OSV-Scanner  │ Trivy Img  │ Nikto     │
│             │ SpotBugs (J) │              │ Checkov    │ sqlmap    │
│             │ Brakeman (Rb)│              │ KICS       │           │
├─────────────┴──────────────┴──────────────┴────────────┴────────────┤
│                    SonarQube (Code Quality)                          │
│                  Dependency-Track (SCA Dashboard)                    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Ferramentas por Camada

### 🔑 Detecção de Secrets

| Ferramenta | O que faz | Output |
|---|---|---|
| **Gitleaks** | Escaneia o histórico git procurando secrets (API keys, tokens, senhas) que foram commitados acidentalmente | `gitleaks.json` - lista de secrets com arquivo, linha e tipo |
| **TruffleHog** | Escaneia o filesystem com alta entropia e regex patterns para encontrar credentials expostas | `trufflehog.json` - secrets encontrados com contexto e verificação de validade |

**O que detectam:**
- AWS Access Keys, Secret Keys
- Tokens de API (GitHub, Slack, Stripe, etc.)
- Senhas hardcoded em código
- Chaves privadas (RSA, SSH, PGP)
- Connection strings de banco de dados

---

### 🔍 SAST (Static Application Security Testing)

| Ferramenta | Linguagem | O que faz | Output |
|---|---|---|---|
| **Semgrep** | Multi-linguagem | Análise estática com regras customizáveis. Detecta XSS, SQLi, RCE, SSRF, path traversal | `semgrep.json` - findings com severidade, CWE, e localização |
| **Bandit** | Python | Detecta padrões inseguros específicos de Python | `bandit.json` - issues com severidade e confiança |
| **Gosec** | Go | Análise de segurança para código Go | `gosec.json` - vulnerabilidades com CWE mapping |
| **SpotBugs + FindSecBugs** | Java | Análise de bytecode Java para bugs de segurança | `spotbugs.xml` - bugs categorizados por tipo |
| **Brakeman** | Ruby on Rails | Scanner específico para Rails | `brakeman.json` - vulnerabilidades web em Rails |

**O que detectam:**

| Vulnerabilidade | CWE | Ferramentas |
|---|---|---|
| SQL Injection | CWE-89 | Semgrep, Bandit, Brakeman |
| Cross-Site Scripting (XSS) | CWE-79 | Semgrep, Brakeman |
| Remote Code Execution (RCE) | CWE-94 | Semgrep, Bandit |
| Server-Side Request Forgery (SSRF) | CWE-918 | Semgrep |
| Path Traversal | CWE-22 | Semgrep, Bandit |
| Insecure Deserialization | CWE-502 | Bandit (pickle), SpotBugs |
| Command Injection | CWE-78 | Semgrep, Bandit, Gosec |
| Hardcoded Credentials | CWE-798 | Semgrep, Bandit |
| Uso de eval/exec | CWE-95 | Bandit |
| Race Conditions | CWE-362 | Gosec |
| Mass Assignment | CWE-915 | Brakeman |

---

### 📦 SCA (Software Composition Analysis)

| Ferramenta | O que faz | Output |
|---|---|---|
| **Trivy (filesystem)** | Escaneia lockfiles e manifests para encontrar dependências com CVEs conhecidas | `trivy-fs.json` - CVEs por dependência com severidade e fix version |
| **Grype** | SCA focado com matching preciso de vulnerabilidades | `grype.json` - vulnerabilidades com CVSS score |
| **Syft** | Gera SBOM (Software Bill of Materials) completo do projeto | `syft-sbom.json` - inventário completo de dependências |
| **OSV-Scanner** | Consulta o banco Google OSV que agrega múltiplas fontes (NVD, GitHub Advisories, etc.) | `osv-scanner.json` - vulnerabilidades com links para advisories |

**O que detectam:**
- Dependências com CVEs conhecidas (críticas a baixas)
- Versões desatualizadas com patches de segurança disponíveis
- Licenças incompatíveis
- Dependências transitivas vulneráveis
- Supply chain risks

**Ecossistemas suportados:**
- npm/yarn (JavaScript)
- pip/poetry/pipenv (Python)
- go.mod (Go)
- Maven/Gradle (Java)
- Gemfile (Ruby)
- Cargo (Rust)
- Composer (PHP)

---

### 🐳 Container Security

| Ferramenta | O que faz | Output |
|---|---|---|
| **Hadolint** | Lint de Dockerfile - verifica best practices e padrões inseguros | `hadolint-Dockerfile.txt` - warnings e erros por regra |
| **Dockle** | Verifica imagem Docker contra CIS Benchmark e best practices | `dockle.json` - findings categorizados (FATAL, WARN, INFO) |
| **Trivy (image)** | Escaneia imagem Docker para CVEs no OS e pacotes instalados | `trivy-image.json` - CVEs na imagem com fix disponível |
| **Checkov** | Escaneia IaC (Terraform, CloudFormation, K8s, Dockerfile) | `checkov.json` - misconfigurations com remediação |
| **KICS** | Scanner multi-IaC para detectar misconfigurations de segurança | `kics.json` - findings com severidade e expected value |

**O que detectam:**

| Problema | Ferramenta |
|---|---|
| Container rodando como root | Hadolint, Dockle, Checkov |
| Imagem base com CVEs | Trivy image |
| Secrets em layers da imagem | Dockle, Trivy |
| Dockerfile usando :latest | Hadolint |
| Portas desnecessárias expostas | Checkov, KICS |
| Security groups abertos (0.0.0.0/0) | Checkov, KICS |
| S3 buckets públicos | Checkov, KICS |
| Encryption desabilitada | Checkov, KICS |
| IAM policies permissivas | Checkov, KICS |
| K8s pods sem security context | Checkov, KICS |

---

### 🌐 DAST (Dynamic Application Security Testing)

| Ferramenta | O que faz | Output |
|---|---|---|
| **OWASP ZAP** | Spider + active scan contra aplicação rodando. Testa OWASP Top 10 | `zap.json` - alertas com risco, URL, evidência e solução |
| **Nuclei** | Scanner rápido com templates community-driven para CVEs conhecidos e misconfigs | `nuclei.json` - findings com template ID, severidade e matched URL |
| **Nikto** | Scanner de web server para misconfigurations e arquivos expostos | `nikto.json` - issues no servidor web |
| **sqlmap** | Ferramenta especializada em detectar e explorar SQL Injection | Output no terminal - confirma SQLi exploráveis |

**O que detectam:**

| Vulnerabilidade | Ferramentas |
|---|---|
| XSS (Reflected, Stored, DOM) | ZAP, Nuclei |
| SQL Injection | ZAP, sqlmap |
| CSRF | ZAP |
| Directory Traversal | ZAP, Nikto |
| Information Disclosure | ZAP, Nuclei, Nikto |
| Security Headers ausentes | ZAP, Nuclei |
| CVEs conhecidos em serviços | Nuclei |
| Default credentials | Nuclei |
| Open redirects | ZAP, Nuclei |
| Server misconfigurations | Nikto |

---

### 📊 Code Quality & Dashboards

| Ferramenta | O que faz | Acesso |
|---|---|---|
| **SonarQube Community** | Análise contínua de qualidade - code smells, bugs, vulnerabilidades, cobertura, duplicação | http://localhost:9000 |
| **Dependency-Track** | Dashboard de SCA com tracking contínuo de vulnerabilidades em dependências | http://localhost:8080 |

---

## Quick Start

```bash
# 1. Baixar todas as imagens (primeira vez)
make pull

# 2. Subir infraestrutura (SonarQube, Dependency-Track, ZAP)
make up

# 3. Scan completo em um repositório
make scan REPO=https://github.com/org/repo

# 4. Scan com DAST (app rodando)
make scan REPO=./meu-app DAST=http://localhost:3000

# 5. Scan com análise de imagem Docker
make scan REPO=./meu-app IMAGE=meu-app:latest

# 6. Scan completo (tudo junto)
make scan REPO=./meu-app DAST=http://localhost:3000 IMAGE=meu-app:latest
```

---

## Relatórios Gerados

Todos os relatórios ficam em `reports/<timestamp>/`:

```
reports/20250101_120000/
├── audit-config.json     # Auditoria de .env, .gitignore, keys
├── gitleaks.json         # Secrets no git
├── trufflehog.json       # Secrets no filesystem
├── semgrep.json          # SAST multi-linguagem
├── bandit.json           # SAST Python
├── gosec.json            # SAST Go
├── spotbugs.xml          # SAST Java
├── brakeman.json         # SAST Rails
├── trivy-fs.json         # SCA filesystem
├── grype.json            # SCA vulnerabilidades
├── syft-sbom.json        # SBOM completo
├── osv-scanner.json      # SCA (Google OSV)
├── hadolint-*.txt        # Dockerfile lint
├── dockle.json           # Container CIS benchmark
├── trivy-image.json      # CVEs na imagem
├── checkov.json          # IaC security
├── kics.json             # IaC misconfigs
├── zap.json              # DAST ZAP
├── nuclei.json           # DAST Nuclei
└── nikto.json            # DAST Nikto
```

---

## Requisitos

- Docker + Docker Compose
- ~6GB RAM disponível (SonarQube + Dependency-Track + scans paralelos)
- ~15GB disco (imagens Docker das ferramentas)

---

## Fluxo Recomendado

```
1. Desenvolvedor faz push
2. Pipeline executa:
   ├── Secrets (Gitleaks + TruffleHog)     → BLOQUEIA se encontrar
   ├── SAST (Semgrep + linguagem-specific) → BLOQUEIA se HIGH/CRITICAL
   ├── SCA (Trivy + Grype + OSV)           → BLOQUEIA se CRITICAL
   ├── Container (Hadolint + Trivy image)  → WARN
   ├── IaC (Checkov + KICS)                → BLOQUEIA se HIGH
   └── DAST (ZAP + Nuclei)                 → BLOQUEIA se HIGH
3. Se tudo passar → Deploy permitido
```

---

## Referências

| Ferramenta | Documentação |
|---|---|
| Semgrep | https://semgrep.dev/docs |
| SonarQube | https://docs.sonarqube.org |
| TruffleHog | https://trufflesecurity.com/trufflehog |
| Gitleaks | https://github.com/gitleaks/gitleaks |
| Dependency-Track | https://docs.dependencytrack.org |
| OWASP ZAP | https://www.zaproxy.org/docs |
| Trivy | https://aquasecurity.github.io/trivy |
| Grype | https://github.com/anchore/grype |
| Syft | https://github.com/anchore/syft |
| OSV-Scanner | https://google.github.io/osv-scanner |
| Bandit | https://bandit.readthedocs.io |
| Gosec | https://github.com/securego/gosec |
| SpotBugs | https://spotbugs.github.io |
| Brakeman | https://brakemanscanner.org |
| Hadolint | https://github.com/hadolint/hadolint |
| Dockle | https://github.com/goodwithtech/dockle |
| Checkov | https://www.checkov.io/1.Welcome/Quick%20Start.html |
| KICS | https://docs.kics.io |
| Nuclei | https://docs.projectdiscovery.io/tools/nuclei |
| Nikto | https://github.com/sullo/nikto |
| sqlmap | https://sqlmap.org |
