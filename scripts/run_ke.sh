#!/usr/bin/env bash
# ==============================================================================
# Scripts/run_sg_local.sh — Story Generation (local / desktop)
#
# Works on:  macOS (Intel & Apple Silicon), Linux desktop, no GPU required.
# Requires:  Ollama installed and on PATH  (https://ollama.com)
#            Python venv at ${HOME}/.venv  (or set VENV_PATH)
#
# Usage (direct):
#   ./Scripts/run_sg_local.sh                              # uses default models
#   ./Scripts/run_sg_local.sh qwen2.5:7b                   # override both models
#   ./Scripts/run_sg_local.sh llama3.1:8b qwen2.5:7b       # rag_model  sy_model
#   VENV_PATH=./.venv ./Scripts/run_sg_local.sh            # custom venv location
#
# Called by:
#   Scripts/eduds-helper.sh --eduds-story-generation
# ==============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
DEFAULT_RAG_MODEL="llama3.1:8b"
DEFAULT_SY_MODEL="llama3.1:8b"
RAG_MODEL="${1:-$DEFAULT_RAG_MODEL}"
SY_MODEL="${2:-$DEFAULT_SY_MODEL}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:${OLLAMA_PORT}}"
VENV_PATH="${VENV_PATH:-${HOME}/.venv}"

# Repo root = two levels up from this script (Scripts/ → repo root)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "======================================================"
echo " eduDS — Story Generation (local)"
echo "======================================================"
echo "  RAG model   : ${RAG_MODEL}"
echo "  Story model : ${SY_MODEL}"
echo "  Ollama      : ${OLLAMA_HOST}"
echo "  ROOT_DIR    : ${ROOT_DIR}"
echo "  VENV        : ${VENV_PATH}"
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
echo "[INFO] Ensuring RAG model '${RAG_MODEL}' is available..."
ollama pull "${RAG_MODEL}"

if [[ "${SY_MODEL}" != "${RAG_MODEL}" ]]; then
    echo "[INFO] Ensuring story model '${SY_MODEL}' is available..."
    ollama pull "${SY_MODEL}"
fi

# ── Run Story Generation ───────────────────────────────────────────────────────
echo "[INFO] Starting Story Generation..."

export PYTHONPATH="${ROOT_DIR}/src"
export ROOT_DIR
export OLLAMA_HOST

python3 "${ROOT_DIR}/src/main_sg.py" \
    --rag_model "${RAG_MODEL}" \
    --sy_model  "${SY_MODEL}"

echo "[INFO] Story Generation completed."

# ── Cleanup ────────────────────────────────────────────────────────────────────
if [[ -n "${OLLAMA_PID}" ]]; then
    echo "[INFO] Stopping Ollama server (PID: ${OLLAMA_PID})."
    kill "${OLLAMA_PID}" 2>/dev/null || true
    wait "${OLLAMA_PID}" 2>/dev/null || true
else
    echo "[INFO] Ollama was already running — leaving it running."
fi

echo "[INFO] All tasks finished."
