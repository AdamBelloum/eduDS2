#!/usr/bin/env bash
# ==============================================================================
# run_ke_snellius.sh
#
# SLURM job script — Knowledge Extraction (KE) on Snellius HPC.
# Starts Ollama on the compute node, runs main_ke.py, then cleans up.
#
# Submit:  sbatch scripts/run_ke_snellius.sh
# Or via:  manage-eduds-workflow.sh  (Step 3 — auto-submits this)
# ==============================================================================

#SBATCH --job-name=eduds-ke
#SBATCH --partition=gpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --gpus=1
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err
#SBATCH --mail-type=BEGIN,END,FAIL
## #SBATCH --mail-user=your@email.nl   # uncomment and set your email

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${ROOT_DIR}/venv"
OLLAMA_PORT=11434
OLLAMA_HOST="http://127.0.0.1:${OLLAMA_PORT}"
MODEL_NAME="${KE_MODEL:-llama3.1:8b}"
LOG_DIR="${ROOT_DIR}/logs"

export OLLAMA_HOST
export ROOT_DIR
export PYTHONPATH="${ROOT_DIR}/src"

mkdir -p "${LOG_DIR}"

# ── Logging helpers ───────────────────────────────────────────────────────────
function log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
function warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*"; }
function err()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; }

# ── Job header ────────────────────────────────────────────────────────────────
log "============================================================"
log "  eduDS — Knowledge Extraction (KE)"
log "  Job ID     : ${SLURM_JOB_ID:-local}"
log "  Node       : $(hostname)"
log "  Model      : ${MODEL_NAME}"
log "  ROOT_DIR   : ${ROOT_DIR}"
log "  PYTHONPATH : ${PYTHONPATH}"
log "  OLLAMA_HOST: ${OLLAMA_HOST}"
log "============================================================"

# ── Load modules (Snellius) ───────────────────────────────────────────────────
# Adjust module names to match what is available on your Snellius project.
# Run 'module avail' on the login node to check exact names.
if command -v module &>/dev/null; then
    log "Loading modules..."
    module purge
    module load 2022
    module load Python/3.10.4-GCCcore-11.3.0
    module load CUDA/11.7.0          # required for GPU-accelerated Ollama
    log "Modules loaded."
fi

# ── Activate virtual environment ──────────────────────────────────────────────
if [[ -f "${VENV_DIR}/bin/activate" ]]; then
    source "${VENV_DIR}/bin/activate"
    log "Activated venv: ${VENV_DIR}"
else
    err "Virtual environment not found at: ${VENV_DIR}"
    err "Create it on the login node first:"
    err "  python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
    exit 1
fi

# ── Install / verify Ollama binary ───────────────────────────────────────────
# Ollama is not a system module on Snellius — install to user home if missing.
OLLAMA_BIN="${HOME}/.local/bin/ollama"

if [[ ! -x "${OLLAMA_BIN}" ]]; then
    log "Ollama binary not found. Installing to ${HOME}/.local/bin/ ..."
    mkdir -p "${HOME}/.local/bin"
    curl -fsSL https://ollama.com/install.sh | OLLAMA_INSTALL_DIR="${HOME}/.local" sh
    log "Ollama installed."
fi

export PATH="${HOME}/.local/bin:${PATH}"

# ── Start Ollama server on compute node ───────────────────────────────────────
log "Starting Ollama server on compute node..."
OLLAMA_MODELS="${HOME}/.ollama/models"
export OLLAMA_MODELS

"${OLLAMA_BIN}" serve &>/dev/null &
OLLAMA_PID=$!
log "Ollama server started (PID: ${OLLAMA_PID})."

# Wait until server is ready (max 120s)
WAIT=0
until curl -s "${OLLAMA_HOST}/api/tags" > /dev/null 2>&1; do
    if (( WAIT >= 120 )); then
        err "Ollama server did not start within 120 seconds. Aborting."
        kill "${OLLAMA_PID}" 2>/dev/null || true
        exit 1
    fi
    log "Waiting for Ollama server... (${WAIT}s)"
    sleep 5
    (( WAIT += 5 ))
done
log "Ollama server is ready."

# ── Pull model if not cached ──────────────────────────────────────────────────
log "Ensuring model '${MODEL_NAME}' is available..."
"${OLLAMA_BIN}" pull "${MODEL_NAME}" \
    && log "Model '${MODEL_NAME}' ready." \
    || { err "Failed to pull model '${MODEL_NAME}'."; kill "${OLLAMA_PID}"; exit 1; }

# ── GPU info ──────────────────────────────────────────────────────────────────
if command -v nvidia-smi &>/dev/null; then
    log "GPU info:"
    nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader \
        | while IFS= read -r line; do log "  $line"; done
fi

# ── Run Knowledge Extraction ──────────────────────────────────────────────────
log "Starting Knowledge Extraction..."
log "Command: python3 src/main_ke.py --rag_model '${MODEL_NAME}'"

python3 src/main_ke.py --rag_model "${MODEL_NAME}"
KE_EXIT=$?

if [[ $KE_EXIT -eq 0 ]]; then
    log "Knowledge Extraction completed successfully."
    log "Results saved to: ${ROOT_DIR}/results/"
else
    err "Knowledge Extraction failed with exit code ${KE_EXIT}."
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────
log "Stopping Ollama server (PID: ${OLLAMA_PID})..."
kill "${OLLAMA_PID}" 2>/dev/null || true
wait "${OLLAMA_PID}" 2>/dev/null || true
log "Ollama server stopped."

log "============================================================"
log "  KE Job finished. Exit code: ${KE_EXIT}"
log "  Log: ${SLURM_JOB_NAME}_${SLURM_JOB_ID:-local}.out"
log "============================================================"

exit ${KE_EXIT}

