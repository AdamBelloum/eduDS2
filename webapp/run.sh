#!/usr/bin/env bash
# ==============================================================================
# webapp/run.sh
#
# Launch the eduDS Streamlit webapp.
# Auto-detects environment: local (Mac/Linux) or HPC SLURM job.
#
# Local usage:  bash webapp/run.sh
# HPC usage:    sbatch webapp/run.sh
# ==============================================================================

#SBATCH --job-name=eduds-webapp
#SBATCH --output=log/webapp_%j.out
#SBATCH --error=log/webapp_%j.err
#SBATCH --time=04:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gpus=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --partition=gpu
## #SBATCH --mail-type=BEGIN,END,FAIL
## #SBATCH --mail-user=your@email.nl

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${ROOT_DIR}/venv"
APP_PATH="${ROOT_DIR}/webapp/app.py"
LOG_DIR="${ROOT_DIR}/log"

mkdir -p "${LOG_DIR}"

# ── Logging helpers ───────────────────────────────────────────────────────────
function log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
function warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*"; }
function err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; }

log "============================================================"
log "  eduDS — Streamlit Web Application"
log "  Job ID  : ${SLURM_JOB_ID:-local}"
log "  Node    : $(hostname)"
log "  ROOT    : ${ROOT_DIR}"
log "============================================================"

# ── Environment detection ─────────────────────────────────────────────────────
if [[ -n "${SLURM_JOB_ID:-}" ]]; then
    ON_HPC=true
else
    ON_HPC=false
fi

# ── Load modules (HPC only) ───────────────────────────────────────────────────
if [[ "$ON_HPC" == true ]] && command -v module &>/dev/null; then
    log "Loading HPC modules..."
    module purge
    module load 2023
    module load Python/3.11.3-GCCcore-12.3.0
    module load CUDA/12.1.1
    log "Modules loaded."
fi

# ── Activate virtual environment ──────────────────────────────────────────────
if [[ ! -f "${VENV_DIR}/bin/activate" ]]; then
    err "Virtual environment not found at: ${VENV_DIR}"
    err "Create it with:"
    err "  python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
    exit 1
fi

source "${VENV_DIR}/bin/activate"
log "Activated venv: ${VENV_DIR}"
log "Python: $(which python3)"

# ── Verify streamlit ──────────────────────────────────────────────────────────
if ! command -v streamlit &>/dev/null; then
    err "Streamlit not found. Run: pip install streamlit"
    exit 1
fi

# ── Clear conflicting env vars ────────────────────────────────────────────────
unset STREAMLIT_SERVER_PORT
unset STREAMLIT_SERVER_HEADLESS
unset STREAMLIT_SERVER_ADDRESS

# ── Port selection ────────────────────────────────────────────────────────────
# On HPC: find a free port dynamically to avoid conflicts between jobs.
# Locally: use default 8501 or WEBAPP_PORT if set.
if [[ "$ON_HPC" == true ]]; then
    STREAMLIT_PORT=$(python3 -c \
        'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')
    OLLAMA_PORT=$(python3 -c \
        'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')
else
    STREAMLIT_PORT="${WEBAPP_PORT:-8501}"
    OLLAMA_PORT="${OLLAMA_PORT:-11434}"
fi

export OLLAMA_HOST="http://127.0.0.1:${OLLAMA_PORT}"
export PYTHONPATH="${ROOT_DIR}/src:${PYTHONPATH:-}"
export ROOT_DIR

log "Streamlit port : ${STREAMLIT_PORT}"
log "Ollama port    : ${OLLAMA_PORT}"
log "OLLAMA_HOST    : ${OLLAMA_HOST}"

# ── Start Ollama (HPC only — local users manage Ollama via the main menu) ─────
OLLAMA_PID=0

if [[ "$ON_HPC" == true ]]; then
    OLLAMA_BIN="${HOME}/.local/bin/ollama"

    # Install Ollama if missing
    if [[ ! -x "${OLLAMA_BIN}" ]]; then
        log "Installing Ollama to ${HOME}/.local/bin/ ..."
        mkdir -p "${HOME}/.local/bin"
        curl -fsSL https://ollama.com/install.sh | OLLAMA_INSTALL_DIR="${HOME}/.local" sh
    fi

    export PATH="${HOME}/.local/bin:${PATH}"
    OLLAMA_MODELS="${HOME}/.ollama/models"
    export OLLAMA_MODELS

    log "Starting Ollama server on port ${OLLAMA_PORT}..."
    OLLAMA_HOST="0.0.0.0:${OLLAMA_PORT}" "${OLLAMA_BIN}" serve &>/dev/null &
    OLLAMA_PID=$!
    log "Ollama started (PID: ${OLLAMA_PID})."

    # Wait for Ollama to be ready (max 120s)
    WAIT=0
    until curl -s "${OLLAMA_HOST}/api/tags" > /dev/null 2>&1; do
        if (( WAIT >= 120 )); then
            err "Ollama did not start within 120 seconds."
            kill "${OLLAMA_PID}" 2>/dev/null || true
            exit 1
        fi
        log "Waiting for Ollama... (${WAIT}s)"
        sleep 5
        (( WAIT += 5 ))
    done
    log "Ollama is ready."

    # Pull required models
    MODELS_TO_PULL=("llama3.1:8b" "qwen2.5:7b")
    for MODEL in "${MODELS_TO_PULL[@]}"; do
        log "Pulling model: ${MODEL}"
        "${OLLAMA_BIN}" pull "${MODEL}" && log "Model ready: ${MODEL}" \
            || warn "Could not pull ${MODEL} — continuing anyway."
    done
fi

# ── Cleanup trap ──────────────────────────────────────────────────────────────
function cleanup() {
    if [[ "${OLLAMA_PID}" -ne 0 ]]; then
        log "Stopping Ollama server (PID: ${OLLAMA_PID})..."
        kill "${OLLAMA_PID}" 2>/dev/null || true
        wait "${OLLAMA_PID}" 2>/dev/null || true
        log "Ollama stopped."
    fi
}
trap cleanup EXIT

# ── Print connection instructions (HPC only) ──────────────────────────────────
if [[ "$ON_HPC" == true ]]; then
    COMPUTE_NODE=$(hostname)
    LOGIN_NODE="${SLURM_SUBMIT_HOST:-<your-hpc-login-node>}"
    echo ""
    echo "###################################################################"
    echo "###          YOUR WEBAPP IS STARTING — HOW TO CONNECT          ###"
    echo "###################################################################"
    echo ""
    echo "  Compute node : ${COMPUTE_NODE}"
    echo "  Streamlit    : port ${STREAMLIT_PORT}"
    echo ""
    echo "  STEP 1 — Open a NEW terminal on your local machine and run:"
    echo "    ssh -L 8501:${COMPUTE_NODE}:${STREAMLIT_PORT} <username>@${LOGIN_NODE}"
    echo ""
    echo "  STEP 2 — Open your browser and go to:"
    echo "    http://localhost:8501"
    echo ""
    echo "  To stop: scancel ${SLURM_JOB_ID}"
    echo "###################################################################"
    echo ""
fi

# ── Launch Streamlit ──────────────────────────────────────────────────────────
log "Launching Streamlit..."

streamlit run "${APP_PATH}" \
    --server.port "${STREAMLIT_PORT}" \
    --server.headless true \
    --server.address 0.0.0.0 \
    --server.enableCORS false \
    --browser.gatherUsageStats false

