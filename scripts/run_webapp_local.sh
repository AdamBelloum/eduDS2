#!/bin/bash
ROOT_DIR=$(pwd)
source "$ROOT_DIR/venv/bin/activate"
export PYTHONPATH="$ROOT_DIR/src"
export ROOT_DIR="$ROOT_DIR"
export OLLAMA_HOST="http://127.0.0.1:11434"

streamlit run webapp/app.py \
  --server.port 8501 \
  --server.headless false
