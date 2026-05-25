# Integração VSCode - SecOps para Desenvolvedores

Guia para os devs terem feedback de segurança **em tempo real** enquanto programam.

---

## Setup Rápido (1 minuto)

```bash
# 1. Abrir o projeto no VSCode
code /caminho/do/seu/projeto

# 2. Instalar extensões recomendadas
# VSCode vai sugerir automaticamente (popup no canto inferior)
# Ou: Ctrl+Shift+P → "Extensions: Show Recommended Extensions"

# 3. Instalar pre-commit hook
cp scripts/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

---

## Extensões e o que fazem

| Extensão | O que faz no VSCode | Equivalente no Pipeline |
|---|---|---|
| **Semgrep** | Sublinha vulnerabilidades (XSS, SQLi, RCE) em tempo real enquanto digita | Semgrep CLI |
| **SonarLint** | Mostra code smells, bugs e vulnerabilidades inline | SonarQube |
| **Checkov** | Marca misconfigurations em Terraform/Docker/K8s | Checkov CLI |
| **Hadolint** | Lint de Dockerfile com warnings inline | Hadolint CLI |
| **ShellCheck** | Erros e vulnerabilidades em scripts bash | - |
| **Snyk** | Vulnerabilidades em dependências (package.json, requirements.txt) | Trivy/Grype |

---

## Como funciona na prática

### Semgrep (SAST em tempo real)
- Escaneia **ao salvar** o arquivo
- Mostra squiggly lines vermelhas/amarelas no código vulnerável
- Hover mostra a explicação + CWE + fix sugerido
- Usa as mesmas regras custom do pipeline (`config/semgrep-rules.yml`)

### SonarLint (qualidade + segurança)
- Análise local sem precisar do servidor
- Se conectar ao SonarQube local, sincroniza regras do projeto
- Detecta: SQLi, XSS, hardcoded passwords, code smells

### Checkov (IaC)
- Marca problemas em arquivos Terraform, Dockerfile, K8s YAML
- Ex: "S3 bucket sem encryption", "Container rodando como root"

---

## Tasks (Ctrl+Shift+P → "Run Task")

Scans sob demanda direto do VSCode:

| Task | O que faz |
|---|---|
| `SecOps: Scan Completo` | Roda pipeline inteiro no workspace |
| `SecOps: Semgrep (arquivo atual)` | Escaneia só o arquivo aberto |
| `SecOps: Gitleaks` | Verifica secrets no repo |
| `SecOps: TruffleHog` | Verifica secrets no filesystem |
| `SecOps: Bandit (Python)` | SAST Python |
| `SecOps: Trivy (dependências)` | Checa CVEs nas deps |
| `SecOps: Checkov (IaC)` | Escaneia IaC |
| `SecOps: Hadolint (Dockerfile)` | Lint do Dockerfile aberto |

---

## Pre-commit Hook

Bloqueia commits automaticamente se detectar:
- ❌ Secrets (Gitleaks)
- ❌ Vulnerabilidades críticas (Semgrep)
- ❌ Arquivos `.env` sendo commitados

```bash
# Instalar
cp scripts/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# Testar
git add . && git commit -m "test"
# Se tiver problema → commit bloqueado com explicação
```

---

## Fluxo do Desenvolvedor

```
1. Dev escreve código
   └── Semgrep + SonarLint mostram problemas INLINE (tempo real)

2. Dev salva arquivo
   └── Semgrep re-escaneia automaticamente

3. Dev faz commit
   └── Pre-commit hook bloqueia se tiver secrets ou vulns críticas

4. Dev faz push
   └── Pipeline CI/CD roda scan completo (14 ferramentas)
```

---

## Configuração do SonarLint com SonarQube local

1. Subir SonarQube: `make up`
2. Acessar http://localhost:9000 → login `admin/admin`
3. Gerar token: My Account → Security → Generate Token
4. No VSCode settings.json, adicionar o token:

```json
"sonarlint.connectedMode.connections.sonarqube": [
  {
    "connectionId": "secops-local",
    "serverUrl": "http://localhost:9000",
    "token": "<seu-token-aqui>"
  }
]
```

5. Ctrl+Shift+P → "SonarLint: Bind to SonarQube project"

---

## Atalhos úteis

| Ação | Atalho |
|---|---|
| Ver problemas do arquivo | `Ctrl+Shift+M` |
| Quick fix (sugestão) | `Ctrl+.` |
| Rodar task | `Ctrl+Shift+P` → "Run Task" |
| Ver output do scan | `Ctrl+Shift+U` (Output panel) |
