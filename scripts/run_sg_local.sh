#!/bin/bash
## ----------------------------------------------------
## Story Generation (SG) — local run script
## Usage: ./scripts/run_sg_local.sh [model_name]
## ----------------------------------------------------

set -e

# --- 1. Configuration ---
DEFAULT_MODEL="llama3.1:8b"
MODEL_NAME=${1:-$DEFAULT_MODEL}
OLLAMA_PORT=11434
ROOT_DIR=$(pwd)
VENV="$ROOT_DIR/venv"

echo "======================================================"
echo " eduDS — Story Generation (local)"
echo "======================================================"
echo "  RAG model   : $MODEL_NAME"
echo "  Story model : $MODEL_NAME"
echo "  Ollama      : http://127.0.0.1:${OLLAMA_PORT}"
echo "  ROOT_DIR    : $ROOT_DIR"
echo "  VENV        : $VENV"
echo "======================================================"

# --- 2. Activate venv ---
if [[ -f "$VENV/bin/activate" ]]; then
    source "$VENV/bin/activate"
    echo "[INFO] Activated venv: $VENV"
else
    echo "[ERROR] venv not found at $VENV" >&2
    exit 1
fi

# --- 3. Check Ollama server ---
export OLLAMA_HOST="http://127.0.0.1:${OLLAMA_PORT}"

if curl -s "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; then
    echo "[INFO] Ollama already running at $OLLAMA_HOST — skipping start."
    OLLAMA_PID=0
else
    echo "[INFO] Starting Ollama server..."
    ollama serve &
    OLLAMA_PID=$!
    until curl -s "$OLLAMA_HOST/api/tags" > /dev/null 2>&1; do
        echo "[INFO] Waiting for Ollama server..."
        sleep 3
    done
    echo "[INFO] Ollama server ready (PID: $OLLAMA_PID)."
fi

# --- 4. Set environment ---
export PYTHONPATH="$ROOT_DIR/src"
export ROOT_DIR="$ROOT_DIR"
export OLLAMA_HOST="http://127.0.0.1:${OLLAMA_PORT}"

echo "[INFO] OLLAMA_HOST = $OLLAMA_HOST"
echo "[INFO] PYTHONPATH  = $PYTHONPATH"

# --- 5. Run Story Generation ---
echo "--- Running Story Generation (src/main_sg.py) ---"
python3 src/main_sg.py --rag_model "$MODEL_NAME" --sy_model "$MODEL_NAME"
echo "--- Story Generation Completed ---"

# --- 6. Cleanup ---
if [ "$OLLAMA_PID" -ne 0 ]; then
    echo "[INFO] Stopping Ollama server (PID: $OLLAMA_PID)."
    kill "$OLLAMA_PID"
    wait "$OLLAMA_PID" 2>/dev/null
fi

echo "All tasks finished."

