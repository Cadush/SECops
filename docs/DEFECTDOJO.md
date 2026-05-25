# DefectDojo - Agregador de Vulnerabilidades

## O que é

DefectDojo é uma plataforma que **centraliza todos os findings** de todas as ferramentas do pipeline num único dashboard. Sem ele, você tem 20 JSONs separados. Com ele, você tem:

- Visão unificada de todas as vulnerabilidades
- Deduplicação automática (mesmo finding de ferramentas diferentes = 1 entry)
- Tracking de status (aberto, em correção, falso positivo, resolvido)
- Métricas e tendências ao longo do tempo
- Integração com Jira/GitHub Issues para assign de correções

## Acesso

- URL: http://localhost:8888
- Login: `admin` / `admin`

## Arquitetura

```
┌─────────────────────────────────────────┐
│              DefectDojo                   │
├──────────┬──────────┬───────────────────┤
│ Products │ Engage-  │    Findings       │
│          │ ments    │                   │
│ SecOps   │ Pipeline │ ┌───────────────┐ │
│ App-X    │ 2025-01  │ │ Semgrep: 12   │ │
│ App-Y    │ 2025-02  │ │ Trivy: 5      │ │
│          │          │ │ ZAP: 3        │ │
│          │          │ │ Gitleaks: 1   │ │
│          │          │ └───────────────┘ │
└──────────┴──────────┴───────────────────┘
```

## Conceitos

| Conceito | O que é |
|---|---|
| **Product** | Seu projeto/aplicação (ex: "meu-app") |
| **Engagement** | Uma execução do pipeline (ex: "Pipeline 2025-01-15") |
| **Test** | Resultado de uma ferramenta (ex: "Semgrep JSON Report") |
| **Finding** | Uma vulnerabilidade individual |

## Como funciona no pipeline

O script `import-defectdojo.sh` roda automaticamente ao final de cada scan:

1. Cria um Product (se não existir) com o nome do repo
2. Cria um Engagement para esta execução
3. Importa cada JSON como um Test dentro do Engagement
4. DefectDojo faz dedup e classifica por severidade

## Ferramentas suportadas na importação

| Arquivo | Scan Type no DefectDojo |
|---|---|
| semgrep.json | Semgrep JSON Report |
| bandit.json | Bandit Scan |
| trivy-fs.json | Trivy Scan |
| trivy-image.json | Trivy Scan |
| gitleaks.json | Gitleaks Scan |
| trufflehog.json | Trufflehog Scan |
| grype.json | Anchore Grype |
| osv-scanner.json | OSV Scan |
| checkov.json | Checkov Scan |
| kics.json | KICS Scan |
| zap.json | ZAP Scan |
| nuclei.json | Nuclei Scan |
| nikto.json | Nikto Scan |
| spotbugs.xml | SpotBugs Scan |
| gosec.json | Gosec Scanner |
| brakeman.json | Brakeman Scan |
| dockle.json | Dockle Scan |
| syft-sbom.json | CycloneDX Scan |

## Uso manual

```bash
# Importar relatórios de um scan específico
bash scripts/import-defectdojo.sh reports/20250115_120000 meu-app

# Com token customizado
DEFECTDOJO_TOKEN=xxx bash scripts/import-defectdojo.sh reports/20250115_120000 meu-app
```

## API

DefectDojo tem API REST completa:

```bash
# Listar findings críticos
curl -s http://localhost:8888/api/v2/findings/?severity=Critical \
  -H "Authorization: Token <token>"

# Marcar finding como falso positivo
curl -X PATCH http://localhost:8888/api/v2/findings/<id>/ \
  -H "Authorization: Token <token>" \
  -H "Content-Type: application/json" \
  -d '{"false_p": true}'
```

## Métricas disponíveis

- Total de findings por severidade (Critical, High, Medium, Low)
- Findings abertos vs fechados ao longo do tempo
- Mean Time to Remediate (MTTR)
- Top ferramentas com mais findings
- Top CWEs encontrados
- Findings por produto/equipe
