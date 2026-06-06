#!/bin/bash
set -euo pipefail

# === SecOps Ollama Setup ===
# Instala Ollama e baixa modelos para documentacao de codigo

echo "============================================"
echo " SecOps - Setup Ollama (LLM Local)"
echo "============================================"

# Detectar se tem GPU NVIDIA
HAS_GPU=false
if command -v nvidia-smi &>/dev/null; then
  HAS_GPU=true
  echo "[*] GPU NVIDIA detectada"
else
  echo "[*] Sem GPU - vai rodar em CPU (mais lento)"
fi

# Opcao 1: Ollama nativo (mais rapido, recomendado)
if command -v ollama &>/dev/null; then
  echo "[*] Ollama ja instalado"
else
  echo "[*] Instalando Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
fi

# Iniciar Ollama se nao estiver rodando
if ! curl -s http://localhost:11434/api/tags &>/dev/null; then
  echo "[*] Iniciando Ollama..."
  ollama serve &>/dev/null &
  sleep 3
fi

# Baixar modelos recomendados
echo ""
echo "[*] Baixando modelos..."
echo "    Isso pode levar alguns minutos na primeira vez."
echo ""

# Modelo principal para documentacao (bom em codigo, 14B params)
echo "[1/3] qwen2.5-coder:14b (~9GB) - documentacao de codigo..."
ollama pull qwen2.5-coder:14b

# Modelo leve para tarefas rapidas (7B params)
echo "[2/3] qwen2.5-coder:7b (~4.5GB) - tarefas rapidas..."
ollama pull qwen2.5-coder:7b

# Modelo para analise de seguranca
echo "[3/3] llama3.1:8b (~4.7GB) - analise geral..."
ollama pull llama3.1:8b

echo ""
echo "============================================"
echo " Ollama pronto!"
echo "============================================"
echo ""
echo " Modelos disponiveis:"
ollama list
echo ""
echo " Uso:"
echo "   make legacy-doc REPO=./codigo-legado"
echo "   make legacy-doc REPO=./codigo-legado MODEL=qwen2.5-coder:7b"
echo ""
echo " Testar:"
echo "   ollama run qwen2.5-coder:14b 'Explique o que faz: def hello(): print(1)'"
echo "============================================"
