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

### Opcao 1: Ollama local (open source, gratuito)

Tudo roda na sua maquina, sem API externa, sem custo. Usa modelos open source.

```bash
# Setup (instala Ollama + baixa modelos)
make ollama-setup

# Gerar docs
make legacy-doc REPO=./codigo-legado

# Usar modelo menor (mais rapido, menos RAM)
make legacy-doc REPO=./codigo-legado MODEL=qwen2.5-coder:7b
```

Modelos recomendados (open source):

| Modelo | Tamanho | RAM minima | Qualidade |
|---|---|---|---|
| qwen2.5-coder:14b | ~9GB | 16GB | Alta (default) |
| qwen2.5-coder:7b | ~4.5GB | 8GB | Media-Alta |
| llama3.1:8b | ~4.7GB | 8GB | Media |
| codellama:13b | ~7GB | 16GB | Media |
| deepseek-coder-v2:16b | ~9GB | 16GB | Alta |

Se tiver GPU NVIDIA, roda muito mais rapido. Sem GPU funciona em CPU (mais lento).

### Opcao 2: Ollama via Docker

Se nao quiser instalar Ollama no host:

```bash
# Subir Ollama em container
make ollama-up

# Baixar modelo
docker compose -f docker-compose.ollama.yml exec ollama ollama pull qwen2.5-coder:14b

# Rodar
make legacy-doc REPO=./codigo-legado
```

---

## Providers suportados

| Provider | Modelo default | Custo | Qualidade |
|---|---|---|---|
| ollama | qwen2.5-coder:14b | Gratis (local) | Alta |
| openrouter | moonshotai/kimi-k2.6 | Variavel | Alta |
| openai | gpt-4o-mini | ~$0.01 por projeto | Alta |
| bedrock | claude-3-haiku | ~$0.005 por projeto | Alta |

Para projetos grandes, gpt-4o ou claude-3-sonnet produzem resultacao melhor mas custam mais (~$0.10 por projeto).

---

### Opcao 3: OpenAI / OpenRouter / Bedrock (pago, melhor qualidade)

Se preferir usar APIs externas:

```bash
# OpenAI
OPENAI_API_KEY=sk-xxx make legacy-doc REPO=./codigo-legado PROVIDER=openai

# OpenRouter (acesso a varios modelos)
OPENROUTER_API_KEY=sk-or-xxx make legacy-doc REPO=./codigo-legado PROVIDER=openrouter MODEL=moonshotai/kimi-k2.6

# AWS Bedrock
make legacy-doc REPO=./codigo-legado PROVIDER=bedrock MODEL=anthropic.claude-3-haiku-20240307-v1:0
```

---

## Integracao com oh-my-openagent (open source)

O projeto inclui uma config pronta para o oh-my-openagent em `config/oh-my-openagent.json`. Ele usa um sistema de agentes especializados via OpenRouter:

| Agente | Modelo | Funcao |
|---|---|---|
| sisyphus | kimi-k2.6 | Orquestrador principal, delega tarefas |
| hephaestus | kimi-k2.6 | Escreve e refatora codigo |
| librarian | kimi-k2.6 | Le documentacao e extrai insights |
| explore | glm-5.1 | Mapeia estrutura de arquivos |
| prometheus | qwen3.5-397b | Cria planos de execucao |
| atlas | qwen3.5-397b | Valida implementacoes |
| oracle | glm-5.1 | Responde questoes tecnicas |
| momus | minimax-m2.7 | Advogado do diabo, encontra edge cases |

Para usar:

```bash
# Instalar oh-my-openagent
pip install oh-my-openagent

# Copiar config
cp config/oh-my-openagent.json .oh-my-openagent.json

# Definir chave OpenRouter
export OPENROUTER_API_KEY=sk-or-xxx

# Usar para documentar codigo legado
oh-my-openagent "Documente este projeto: explique arquitetura, funcoes principais, endpoints e riscos de seguranca"
```

O fluxo do oh-my-openagent e:
1. explore - mapeia a estrutura do workspace
2. librarian - le e analisa o codigo
3. prometheus - cria plano de documentacao
4. hephaestus - gera os arquivos .md
5. atlas - valida se a documentacao esta completa

---

## Variaveis de ambiente

| Variavel | Descricao | Default |
|---|---|---|
| LEGACY_DOC_PROVIDER | Provider LLM | ollama |
| LEGACY_DOC_MODEL | Modelo a usar | qwen2.5-coder:14b (ollama) |
| OLLAMA_URL | URL do Ollama | http://localhost:11434 |
| OPENAI_API_KEY | API key da OpenAI | (se provider=openai) |
| OPENROUTER_API_KEY | API key do OpenRouter | (se provider=openrouter) |

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
