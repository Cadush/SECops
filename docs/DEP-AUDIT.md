# Dependency Audit - Análise Profunda de Libs

Ferramenta dedicada para análise de segurança de dependências/bibliotecas, complementando o SCA do pipeline principal com ferramentas especializadas.

---

## Diferença do SCA principal

O pipeline principal (Trivy, Grype, OSV-Scanner) faz scan rápido de dependências. O **Dependency Audit** vai mais fundo:

| Aspecto | Pipeline principal | Dependency Audit |
|---|---|---|
| Velocidade | Rápido (segundos) | Completo (minutos) |
| Banco de dados | OSV, GitHub Advisories | NVD + Snyk DB + npm/pip nativos |
| Remediação | Lista CVEs | Sugere fix + versão segura |
| Monitoramento | Pontual | Contínuo (Snyk monitor + Dependabot) |
| Auto-fix | Não | Sim (Dependabot PRs + Snyk fix PRs) |

---

## Ferramentas

### 1. Auditoria Nativa (npm audit, pip-audit, bundle-audit, govulncheck)

| Ferramenta | Ecossistema | O que faz |
|---|---|---|
| **npm audit** | Node.js | Consulta o registro npm por advisories conhecidas |
| **pip-audit** | Python | Consulta PyPI + OSV por vulnerabilidades |
| **bundle-audit** | Ruby | Verifica Gemfile.lock contra ruby-advisory-db |
| **govulncheck** | Go | Análise estática — só alerta se a função vulnerável é *realmente usada* |
| **composer audit** | PHP | Consulta packagist por advisories |

**Output**: JSON com lista de vulnerabilidades, pacote afetado, versão fixa

**Diferencial**: São os scanners **oficiais** de cada ecossistema. Podem detectar coisas que scanners genéricos (Trivy/Grype) não pegam, pois consultam diretamente os registros nativos.

---

### 2. OWASP Dependency-Check

| | |
|---|---|
| **Banco de dados** | NVD (National Vulnerability Database) + RetireJS + npm advisories |
| **Como funciona** | Identifica CPEs (Common Platform Enumeration) das dependências e cruza com CVEs |
| **Diferencial** | Análise mais profunda que Trivy para Java (JARs, WARs, classes) e C/C++ |
| **Output** | JSON + **HTML visual** com gráficos e detalhes por CVE |

**Quando é melhor que Trivy/Grype:**
- Projetos Java complexos (multi-module Maven/Gradle)
- Dependências sem lockfile (identifica por hash/nome de arquivo)
- Precisa de relatório visual (HTML) para auditoria
- Requer compliance com NIST/NVD especificamente

**Exemplo de output HTML:**
```
┌─────────────────────────────────────────────┐
│  OWASP Dependency-Check Report              │
│  Project: meu-app                           │
│  Date: 2025-01-15                           │
├─────────────────────────────────────────────┤
│  Dependencies Scanned: 142                  │
│  Vulnerabilities Found: 23                  │
│    Critical: 3 | High: 8 | Medium: 12      │
├─────────────────────────────────────────────┤
│  Top findings:                              │
│  - lodash 4.17.20  → CVE-2021-23337 (HIGH) │
│  - jackson 2.9.8   → CVE-2019-12086 (CRIT) │
│  - spring 5.2.0    → CVE-2020-5421 (HIGH)  │
└─────────────────────────────────────────────┘
```

---

### 3. Snyk

| | |
|---|---|
| **Banco de dados** | Snyk Vulnerability DB (proprietário, mais completo que NVD em muitos casos) |
| **Como funciona** | Analisa dependency tree completo (transitivas), sugere upgrades mínimos |
| **Diferencial** | Remediação automática, monitoramento contínuo, reachability analysis |
| **Output** | JSON com vulnerabilidades + fix sugerido |

**Funcionalidades exclusivas:**
- **Fix PRs automáticos**: Snyk abre PRs com a atualização mínima necessária
- **Monitoramento contínuo**: `snyk monitor` registra seu projeto — Snyk avisa quando nova CVE afeta suas deps
- **Reachability**: Indica se a função vulnerável é realmente chamada no seu código
- **License compliance**: Detecta libs com licenças incompatíveis (GPL em projeto comercial, etc.)

**Setup:**
1. Criar conta gratuita: https://app.snyk.io
2. Obter token: https://app.snyk.io/account
3. Usar no scan: `make dep-audit REPO=./app SNYK_TOKEN=<token>`

**Plano gratuito inclui:**
- 200 testes/mês (open source)
- Monitoramento de até 1 projeto
- Fix PRs no GitHub

---

### 4. Dependabot (GitHub)

| | |
|---|---|
| **Como funciona** | Roda semanalmente no GitHub, verifica dependências e abre PRs de atualização |
| **Diferencial** | Zero manutenção — 100% automático depois de configurar |
| **Output** | Pull Requests com changelog, compatibility score e release notes |

**O que o script gera:**
- Arquivo `dependabot.yml` pronto para copiar para `.github/dependabot.yml`
- Detecta automaticamente os ecossistemas do projeto
- Inclui Docker e GitHub Actions por padrão

**Exemplo de PR do Dependabot:**
```
Bump express from 4.17.1 to 4.18.2

CVE-2022-24999 (High)
- Fixes: Open Redirect vulnerability
- Release notes: https://github.com/expressjs/express/releases/tag/4.18.2
- Compatibility: 98% (based on CI pass rate)
```

---

## Quick Start

```bash
# Scan básico (npm audit + OWASP Dependency-Check)
make dep-audit REPO=./meu-projeto

# Com Snyk (análise mais completa + monitoramento)
make dep-audit REPO=./meu-projeto SNYK_TOKEN=<seu-token>

# Ativar Dependabot
cp reports/dep-audit_*/dependabot.yml .github/dependabot.yml
git add .github/dependabot.yml && git push
```

---

## Relatórios Gerados

```
reports/dep-audit_20250115_120000/
├── npm-audit.json           # npm audit (Node.js)
├── pip-audit.json           # pip-audit (Python)
├── bundle-audit.json        # bundle-audit (Ruby)
├── govulncheck.json         # govulncheck (Go)
├── composer-audit.json      # composer audit (PHP)
├── owasp-depcheck.json      # OWASP Dependency-Check (JSON)
├── owasp-depcheck.html      # OWASP Dependency-Check (visual)
├── snyk.json                # Snyk (se token fornecido)
└── dependabot.yml           # Config pronta para GitHub
```

---

## Comparação das 4 ferramentas

| Critério | npm audit / pip-audit | OWASP Dep-Check | Snyk | Dependabot |
|---|---|---|---|---|
| **Custo** | Gratuito | Gratuito | Free tier / Pago | Gratuito |
| **Banco de dados** | Registro nativo | NVD | Snyk DB (maior) | GitHub Advisory DB |
| **Transitivas** | Sim | Sim | Sim (melhor) | Sim |
| **Fix automático** | ❌ | ❌ | ✅ (PR) | ✅ (PR) |
| **Monitoramento** | ❌ | ❌ | ✅ | ✅ |
| **Reachability** | ❌ | ❌ | ✅ | ❌ |
| **HTML report** | ❌ | ✅ | ❌ | ❌ |
| **CI/CD** | ✅ | ✅ | ✅ | GitHub only |
| **Offline** | ❌ | ✅ (NVD cache) | ❌ | ❌ |
| **Java (JARs)** | N/A | ✅ (melhor) | ✅ | ✅ |

---

## Quando usar qual

| Cenário | Ferramenta recomendada |
|---|---|
| Scan rápido no CI | npm audit / pip-audit |
| Relatório para auditoria/compliance | OWASP Dependency-Check |
| Remediação automática + monitoramento | Snyk |
| Atualizações automáticas sem esforço | Dependabot |
| Projeto Java complexo | OWASP Dependency-Check + Snyk |
| Análise de reachability | Snyk |
| Precisa funcionar offline | OWASP Dependency-Check |

---

## Integração com o Pipeline Principal

O `dep-audit.sh` é **independente** do `scan.sh`. Você pode:

1. **Rodar junto**: O pipeline principal já roda Trivy/Grype/OSV como SCA rápido
2. **Rodar separado**: `make dep-audit` para análise profunda sob demanda
3. **Agendar**: Cron semanal para `dep-audit` (libs podem ganhar CVEs novos sem mudança de código)

```bash
# Cron semanal (exemplo)
0 8 * * 1 cd /opt/secops && make dep-audit REPO=/app SNYK_TOKEN=xxx
```

---

## Referências

| Ferramenta | Documentação |
|---|---|
| npm audit | https://docs.npmjs.com/cli/v10/commands/npm-audit |
| pip-audit | https://github.com/pypa/pip-audit |
| OWASP Dependency-Check | https://owasp.org/www-project-dependency-check/ |
| Snyk | https://docs.snyk.io/ |
| Dependabot | https://docs.github.com/en/code-security/dependabot |
| govulncheck | https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck |
| bundle-audit | https://github.com/rubysec/bundler-audit |
