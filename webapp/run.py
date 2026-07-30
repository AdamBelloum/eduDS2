#!/bin/bash
# ==============================================================================
# webapp/run.sh — Edu-Genius Web App (HPC / SLURM)
#
# Starts the Ollama AI server and the Streamlit web interface on an HPC node.
# Once running, connect from your laptop via an SSH tunnel (instructions below).
#
# Usage:
#   sbatch webapp/run.sh
#
# Then follow the SSH tunnel instructions printed in:
#   webapp/log/app_<JOBID>.out
# ==============================================================================

#SBATCH --job-name=eduds_webapp
#SBATCH --output=webapp/log/app_%j.out
#SBATCH --error=webapp/log/app_%j.err
#SBATCH --time=04:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32GB
#SBATCH --partition=gpu_h100

set -euo pipefail

# ── 1. Resolve paths ──────────────────────────────────────────────────────────
# webapp/run.sh is one level below the repo root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEBAPP_DIR="${ROOT_DIR}/webapp"
APP_PY="${WEBAPP_DIR}/src/app.py"
LOG_DIR="${WEBAPP_DIR}/log"
SIF_PATH="${ROOT_DIR}/ollama_latest.sif"

export ROOT_DIR
mkdir -p "${LOG_DIR}"

echo "============================================================"
echo " Edu-Genius Web App"
echo " Job ID   : ${SLURM_JOB_ID}"
echo " Node     : $(hostname)"
echo " Started  : $(date)"
echo " ROOT_DIR : ${ROOT_DIR}"
echo "============================================================"

# ── 2. Load HPC modules ───────────────────────────────────────────────────────
module purge
module load 2023
module load Python/3.11.3-GCCcore-12.3.0
module load CUDA/12.1.1

# ── 3. Activate virtual environment ───────────────────────────────────────────
if [[ -f "${HOME}/.venv/bin/activate" ]]; then
    source "${HOME}/.venv/bin/activate"
    echo "[INFO] Activated venv: ${HOME}/.venv"
else
    echo "[ERROR] Virtual environment not found at ${HOME}/.venv" >&2
    echo "        Create: python3 -m venv ~/.venv && pip install -r requirements.txt" >&2
    exit 1
fi

# ── 4. GPU environment variables ──────────────────────────────────────────────
export PATH="${HOME}/.venv/bin:${PATH}"
export CUDA_VISIBLE_DEVICES=0
export OLLAMA_FORCE_CUDA=1
export OLLAMA_NUM_GPU=1
export OLLAMA_ACCELERATE=1
export OLLAMA_LLM_LIBRARY=cublas
export OLLAMA_PRECISION=fp16
export OMP_NUM_THREADS=8
export MKL_NUM_THREADS=8

# ── 5. Find free ports dynamically ────────────────────────────────────────────
# Using Python to find two unused ports — avoids conflicts on shared nodes
OLLAMA_PORT=$(python3 -c \
    'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')
STREAMLIT_PORT=$(python3 -c \
    'import socket; s=socket.socket(); s.bind(("",0)); print(s.getsockname()[1]); s.close()')
HOSTNAME=$(hostname)

export OLLAMA_HOST="http://127.0.0.1:${OLLAMA_PORT}"
export PYTHONPATH="${ROOT_DIR}/src"

echo "[INFO] Ollama port   : ${OLLAMA_PORT}"
echo "[INFO] Streamlit port: ${STREAMLIT_PORT}"
echo "[INFO] Hostname      : ${HOSTNAME}"

# ── 6. Pull Singularity image if needed ───────────────────────────────────────
if [[ ! -f "${SIF_PATH}" ]]; then
    echo "[INFO] Pulling Ollama Singularity image..."
    singularity pull "${SIF_PATH}" docker://ollama/ollama
fi

# ── 7. Start Ollama server ────────────────────────────────────────────────────
OLLAMA_DIR="${HOME}/OLLAMA_DIR/ollama_app_${SLURM_JOB_ID}"
mkdir -p "${OLLAMA_DIR}"

echo "[INFO] Starting Ollama server..."
SINGULARITYENV_OLLAMA_HOST="0.0.0.0:${OLLAMA_PORT}" \
singularity exec --nv \
    --bind "${OLLAMA_DIR}:/root/.ollama" \
    "${SIF_PATH}" ollama serve &
OLLAMA_PID=$!

# Cleanup on job exit — always kill Ollama when the job ends
cleanup() {
    echo "[INFO] Shutting down Ollama server (PID: ${OLLAMA_PID})..."
    kill "${OLLAMA_PID}" 2>/dev/null || true
    wait "${OLLAMA_PID}" 2>/dev/null || true
    echo "[INFO] Cleanup complete."
}
trap cleanup EXIT

# Wait for Ollama to be ready (max 120 s)
echo "[INFO] Waiting for Ollama to be ready..."
WAIT=0
until curl -sf "http://localhost:${OLLAMA_PORT}/api/tags" > /dev/null 2>&1; do
    sleep 3
    WAIT=$((WAIT + 3))
    if [[ $WAIT -ge 120 ]]; then
        echo "[ERROR] Ollama did not become ready within 120 seconds." >&2
        exit 1
    fi
done
echo "[INFO] Ollama server is ready."

# ── 8. Pull required models ───────────────────────────────────────────────────
# Models are read from config.yaml — adjust the list below to match
declare -a MODELS_TO_PULL=("phi4:14b" "qwen2.5:7b" "llama3.1:8b")

for model in "${MODELS_TO_PULL[@]}"; do
    echo "[INFO] Pulling model: ${model}"
    SINGULARITYENV_OLLAMA_HOST="0.0.0.0:${OLLAMA_PORT}" \
    singularity exec --nv \
        --bind "${OLLAMA_DIR}:/root/.ollama" \
        "${SIF_PATH}" ollama pull "${model}"
done
echo "[INFO] All models ready."

# ── 9. Print SSH tunnel instructions ─────────────────────────────────────────
echo ""
echo "#####################################################################"
echo "###           YOUR INTERACTIVE APP IS READY TO CONNECT           ###"
echo "#####################################################################"
echo ""
echo "  Job running on : ${HOSTNAME}"
echo "  Streamlit port : ${STREAMLIT_PORT}"
echo ""
echo "  STEP 1 — Open a NEW terminal on your LOCAL machine and run:"
echo "  ssh -L 8501:${HOSTNAME}:${STREAMLIT_PORT} <YOUR_USERNAME>@snellius.surf.nl"
echo ""
echo "  STEP 2 — Open your browser and go to:"
echo "  http://localhost:8501"
echo ""
echo "  To stop the app: scancel ${SLURM_JOB_ID}"
echo "#####################################################################"
echo ""

# ── 10. Start Streamlit ───────────────────────────────────────────────────────
echo "[INFO] Starting Streamlit..."
streamlit run "${APP_PY}" \
    --server.port "${STREAMLIT_PORT}" \
    --server.headless true \
    --server.address 0.0.0.0 \
    --server.enableCORS false

# cleanup() runs automatically on exit

