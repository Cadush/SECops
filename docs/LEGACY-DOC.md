# Legacy Doc - Documentacao Automatica de Codigo Legado

Ferramenta que analisa um codebase sem documentacao (ou mal documentado) e gera documentacao completa automaticamente usando LLMs.

---

## Problema

Codigo legado tipicamente tem:
- Zero documentacao ou docs desatualizadas
- Ninguem sabe o que cada parte faz
- Onboarding de novos devs leva semanas
- Riscos de seguranca escondidos que ninguem conhece

---

## O que gera

| Documento | Conteudo |
|---|---|
| README.md | O que o projeto faz, como instalar, como rodar |
| ARCHITECTURE.md | Arquitetura, componentes, fluxo de dados, padroes |
| SECURITY-REVIEW.md | Riscos de seguranca, padroes inseguros, recomendacoes |
| file-tree.txt | Lista de todos os arquivos do projeto |
| stack.txt | Stack tecnologica detectada automaticamente |
| signatures.txt | Funcoes, classes e metodos extraidos |
| endpoints.txt | Rotas/APIs encontradas no codigo |
| INDEX.md | Indice com links para todos os docs gerados |

---

## Como funciona

```
1. Mapeia estrutura do projeto (arquivos, diretorios)
2. Detecta stack (package.json, requirements.txt, go.mod, etc)
3. Extrai assinaturas (funcoes, classes, metodos)
4. Extrai endpoints (rotas HTTP, APIs)
5. Envia contexto para LLM com prompts especificos
6. Gera README, ARCHITECTURE e SECURITY-REVIEW
```

---

## Como rodar

### Opcao 1: OpenAI (recomendado)

```bash
export OPENAI_API_KEY=sk-xxx

# Gerar docs para um projeto
make legacy-doc REPO=./codigo-legado

# Usar modelo especifico
make legacy-doc REPO=./codigo-legado MODEL=gpt-4o
```

### Opcao 2: Ollama (local, sem custo)

Roda 100% local. Precisa do Ollama instalado com um modelo baixado.

```bash
# Instalar Ollama (se nao tiver)
curl -fsSL https://ollama.com/install.sh | sh

# Baixar modelo
ollama pull llama3.1

# Rodar
make legacy-doc REPO=./codigo-legado PROVIDER=ollama MODEL=llama3.1
```

### Opcao 3: AWS Bedrock

Usa Claude via AWS Bedrock. Precisa de AWS CLI configurada com acesso ao Bedrock.

```bash
make legacy-doc REPO=./codigo-legado PROVIDER=bedrock MODEL=anthropic.claude-3-haiku-20240307-v1:0
```

### Opcao 4: Script direto

```bash
# OpenAI
OPENAI_API_KEY=sk-xxx bash scripts/legacy-doc.sh ./codigo-legado

# Ollama
LEGACY_DOC_PROVIDER=ollama LEGACY_DOC_MODEL=llama3.1 bash scripts/legacy-doc.sh ./codigo-legado

# Com output customizado
bash scripts/legacy-doc.sh ./codigo-legado --output ./minha-doc --provider openai --model gpt-4o
```

---

## Providers suportados

| Provider | Modelo default | Custo | Qualidade |
|---|---|---|---|
| openai | gpt-4o-mini | ~$0.01 por projeto | Alta |
| ollama | llama3.1 | Gratis (local) | Media-Alta |
| bedrock | claude-3-haiku | ~$0.005 por projeto | Alta |

Para projetos grandes, gpt-4o ou claude-3-sonnet produzem resultacao melhor mas custam mais (~$0.10 por projeto).

---

## Variaveis de ambiente

| Variavel | Descricao | Default |
|---|---|---|
| OPENAI_API_KEY | API key da OpenAI | (obrigatorio se provider=openai) |
| LEGACY_DOC_PROVIDER | Provider LLM | openai |
| LEGACY_DOC_MODEL | Modelo a usar | gpt-4o-mini |
| OLLAMA_URL | URL do Ollama | http://localhost:11434 |

---

## Linguagens suportadas

A ferramenta detecta e documenta projetos em:
- Python
- JavaScript / TypeScript
- Go
- Java
- Ruby
- PHP
- Rust
- C / C++

---

## Limitacoes

- Arquivos muito grandes sao truncados (primeiras 100 linhas por arquivo)
- Maximo de 15 arquivos analisados por chamada LLM (para nao estourar contexto)
- A documentacao gerada por IA pode conter imprecisoes - revise manualmente
- Projetos com 500+ arquivos podem precisar de rodar mais de uma vez focando em subdiretorios
- Ollama local depende da capacidade da maquina (precisa de 8GB+ RAM)

---

## Exemplo de uso

```bash
# Clonar um projeto legado
git clone https://github.com/alguem/projeto-antigo ./legado

# Gerar documentacao
export OPENAI_API_KEY=sk-xxx
make legacy-doc REPO=./legado

# Ver resultado
cat ./legado/docs/generated/INDEX.md
cat ./legado/docs/generated/README.md
cat ./legado/docs/generated/ARCHITECTURE.md
cat ./legado/docs/generated/SECURITY-REVIEW.md
```

---

## Integracao com SecOps

O SECURITY-REVIEW.md gerado complementa o pipeline de seguranca:

```
1. legacy-doc analisa o codigo e documenta riscos conhecidos
2. scan.sh roda ferramentas automatizadas (Semgrep, Trivy, etc)
3. DefectDojo agrega tudo num dashboard

Resultado: visao completa do estado do codigo legado
```
