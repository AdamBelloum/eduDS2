#!/usr/bin/env bash
# ==============================================================================
# Scripts/run_ke_local.sh — Knowledge Extraction (local / desktop)
#
# Works on:  macOS (Intel & Apple Silicon), Linux desktop, no GPU required.
# Requires:  Ollama installed and on PATH  (https://ollama.com)
#            Python venv at ${HOME}/.venv  (or set VENV_PATH)
#
# Usage (direct):
#   ./Scripts/run_ke_local.sh                        # uses default model
#   ./Scripts/run_ke_local.sh qwen2.5:7b             # override model
#   VENV_PATH=./.venv ./Scripts/run_ke_local.sh      # custom venv location
#
# Called by:
#   Scripts/eduds-helper.sh --eduds-knowledge-extraction
# ==============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
DEFAULT_MODEL="llama3.1:8b"
MODEL_NAME="${1:-$DEFAULT_MODEL}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:${OLLAMA_PORT}}"
VENV_PATH="${VENV_PATH:-${HOME}/.venv}"

# Repo root = two levels up from this script (Scripts/ → repo root)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "======================================================"
echo " eduDS — Knowledge Extraction (local)"
echo "======================================================"
echo "  Model     : ${MODEL_NAME}"
echo "  Ollama    : ${OLLAMA_HOST}"
echo "  ROOT_DIR  : ${ROOT_DIR}"
echo "  VENV      : ${VENV_PATH}"
echo "======================================================"

# ── Activate virtual environment ───────────────────────────────────────────────
if [[ -f "${VENV_PATH}/bin/activate" ]]; then
    # shellcheck source=/dev/null
    source "${VENV_PATH}/bin/activate"
    echo "[INFO] Activated venv: ${VENV_PATH}"
else
    echo "[ERROR] Virtual environment not found at ${VENV_PATH}"
    echo "        Create one with: python3 -m venv ${VENV_PATH}"
    echo "        Then install:    pip install -r requirements.txt"
    exit 1
fi

# ── Ollama server management ───────────────────────────────────────────────────
OLLAMA_PID=""

if curl -sf "${OLLAMA_HOST}/api/tags" > /dev/null 2>&1; then
    echo "[INFO] Ollama already running at ${OLLAMA_HOST} — skipping start."
else
    echo "[INFO] Ollama not detected. Starting server..."

    if ! command -v ollama &> /dev/null; then
        echo "[ERROR] 'ollama' not found on PATH."
        echo "        Install from: https://ollama.com/download"
        exit 1
    fi

    ollama serve &
    OLLAMA_PID=$!
    echo "[INFO] Ollama server started (PID: ${OLLAMA_PID})"

    echo "[INFO] Waiting for Ollama to be ready..."
    WAIT=0
    until curl -sf "${OLLAMA_HOST}/api/tags" > /dev/null 2>&1; do
        sleep 3
        WAIT=$((WAIT + 3))
        if [[ $WAIT -ge 60 ]]; then
            echo "[ERROR] Ollama did not become ready within 60 seconds."
            kill "${OLLAMA_PID}" 2>/dev/null || true
            exit 1
        fi
    done
    echo "[INFO] Ollama is ready."
fi

# ── Model preparation ──────────────────────────────────────────────────────────
echo "[INFO] Ensuring model '${MODEL_NAME}' is available..."
ollama pull "${MODEL_NAME}"

# ── Run Knowledge Extraction ───────────────────────────────────────────────────
echo "[INFO] Starting Knowledge Extraction..."

export PYTHONPATH="${ROOT_DIR}/src"
export ROOT_DIR
export OLLAMA_HOST

python3 "${ROOT_DIR}/src/main_ke.py" --rag_model "${MODEL_NAME}"

echo "[INFO] Knowledge Extraction completed."

# ── Cleanup ────────────────────────────────────────────────────────────────────
if [[ -n "${OLLAMA_PID}" ]]; then
    echo "[INFO] Stopping Ollama server (PID: ${OLLAMA_PID})."
    kill "${OLLAMA_PID}" 2>/dev/null || true
    wait "${OLLAMA_PID}" 2>/dev/null || true
else
    echo "[INFO] Ollama was already running — leaving it running."
fi

echo "[INFO] All tasks finished."
