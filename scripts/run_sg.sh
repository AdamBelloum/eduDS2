#!/bin/bash
# ==============================================================================
# Scripts/run_ke.sh — Knowledge Extraction (HPC / SLURM)
#
# Runs the full KE experiment sweep across all models in config.yaml.
# Submits via SLURM on a GPU A100 node using Singularity for Ollama.
#
# Usage:
#   sbatch Scripts/run_ke.sh
#
# Requirements:
#   - SLURM cluster with gpu_a100 partition
#   - Singularity (apptainer) available as a module
#   - Python venv at ${HOME}/.venv with requirements installed
# ==============================================================================

#SBATCH --job-name=eduds_ke
#SBATCH --output=log/%j_ke.out
#SBATCH --error=log/%j_ke.err
#SBATCH --time=3-00:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32GB
#SBATCH --partition=gpu_a100

set -euo pipefail

echo "============================================================"
echo " eduDS — Knowledge Extraction (HPC)"
echo " Job ID   : ${SLURM_JOB_ID}"
echo " Node     : $(hostname)"
echo " Started  : $(date)"
echo "============================================================"
echo "CPUs allocated : ${SLURM_JOB_CPUS_PER_NODE}"
echo "CPUs per task  : ${SLURM_CPUS_PER_TASK}"

# ── 1. Resolve ROOT_DIR ───────────────────────────────────────────────────────
# Scripts/ is one level below the repo root
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT_DIR
echo "[INFO] ROOT_DIR = ${ROOT_DIR}"

# Ensure log directory exists
mkdir -p "${ROOT_DIR}/log"

# ── 2. Load HPC modules ───────────────────────────────────────────────────────
module purge
module load 2023
module load Python/3.11.3-GCCcore-12.3.0
module load CUDA/12.1.1
module load cuDNN/8.9.2.26-CUDA-12.1.1

# ── 3. Activate virtual environment ───────────────────────────────────────────
if [[ -f "${HOME}/.venv/bin/activate" ]]; then
    source "${HOME}/.venv/bin/activate"
    echo "[INFO] Activated venv: ${HOME}/.venv"
    echo "[INFO] Python: $(which python3)"
else
    echo "[ERROR] Virtual environment not found at ${HOME}/.venv" >&2
    echo "        Create one with: python3 -m venv ~/.venv" >&2
    echo "        Then install:    pip install -r requirements.txt" >&2
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
export OLLAMA_BATCH_SIZE=32
export OLLAMA_NUM_THREAD=16
export OMP_NUM_THREADS=16
export MKL_NUM_THREADS=16
export OLLAMA_USE_CUDA_GRAPHS=1
export OLLAMA_CONTEXT_SIZE=8192
export OLLAMA_KEEP_LOADED=1
export OLLAMA_MAX_LOADED_MODELS=4

# ── 5. Pull Singularity image (once per job) ──────────────────────────────────
SIF_PATH="${ROOT_DIR}/ollama_latest.sif"

if [[ ! -f "${SIF_PATH}" ]]; then
    echo "[INFO] Pulling Ollama Singularity image..."
    singularity pull "${SIF_PATH}" docker://ollama/ollama
    echo "[INFO] Singularity image saved to: ${SIF_PATH}"
else
    echo "[INFO] Singularity image already exists: ${SIF_PATH}"
fi

# Verify GPU access inside Singularity
echo "[INFO] Verifying GPU access inside Singularity..."
singularity exec --nv "${SIF_PATH}" nvidia-smi | head -20

# ── 6. Model sweep ────────────────────────────────────────────────────────────
# Model list — keep in sync with config.yaml models.rag_models
rag_models=(
    "deepseek-llm:7b"
    "gemma:7b"
    "qwen2.5:7b"
    "openchat:7b"
    "llama3.1:8b"
    "olmo2:7b"
    "phi4:14b"
)

for rag_model in "${rag_models[@]}"; do
    echo ""
    echo "============================================================"
    echo " Experiment: RAG model = ${rag_model}"
    echo "============================================================"

    # Use a unique port per job to avoid conflicts on shared nodes
    PORT=$((11434 + (SLURM_JOB_ID % 1000)))

    # Isolated model storage directory per job
    OLLAMA_DIR="${HOME}/OLLAMA_DIR/ollama_${SLURM_JOB_ID}"
    mkdir -p "${OLLAMA_DIR}"

    # ── Start Ollama server ───────────────────────────────────────
    echo "[INFO] Starting Ollama server on port ${PORT}..."
    SINGULARITYENV_OLLAMA_HOST="0.0.0.0:${PORT}" \
    singularity exec --nv \
        --bind "${OLLAMA_DIR}:/root/.ollama" \
        "${SIF_PATH}" ollama serve &
    OLLAMA_PID=$!

    # Wait for server to be ready (max 120 s)
    echo "[INFO] Waiting for Ollama to be ready..."
    WAIT=0
    until curl -sf "http://localhost:${PORT}/api/tags" > /dev/null 2>&1; do
        sleep 5
        WAIT=$((WAIT + 5))
        if [[ $WAIT -ge 120 ]]; then
            echo "[ERROR] Ollama did not become ready within 120 seconds." >&2
            kill "${OLLAMA_PID}" 2>/dev/null || true
            exit 1
        fi
    done
    echo "[INFO] Ollama server is ready on port ${PORT}."

    # ── Pull model ────────────────────────────────────────────────
    echo "[INFO] Pulling model: ${rag_model}"
    SINGULARITYENV_OLLAMA_HOST="0.0.0.0:${PORT}" \
    singularity exec --nv \
        --bind "${OLLAMA_DIR}:/root/.ollama" \
        "${SIF_PATH}" ollama pull "${rag_model}"
    echo "[INFO] Model ready: ${rag_model}"

    # ── Run Knowledge Extraction ──────────────────────────────────
    export PYTHONPATH="${ROOT_DIR}/src"
    export OLLAMA_HOST="http://127.0.0.1:${PORT}"

    echo "[INFO] Running Knowledge Extraction with model: ${rag_model}"
    python3 "${ROOT_DIR}/src/main_ke.py" --rag_model "${rag_model}"

    echo "[INFO] Experiment complete for: ${rag_model}"
    echo "[INFO] Finished at: $(date)"

    # ── Cleanup Ollama server ─────────────────────────────────────
    echo "[INFO] Stopping Ollama server (PID: ${OLLAMA_PID})..."
    kill "${OLLAMA_PID}" 2>/dev/null || true
    wait "${OLLAMA_PID}" 2>/dev/null || true
    echo "[INFO] Ollama server stopped."

done

echo ""
echo "============================================================"
echo " All Knowledge Extraction experiments complete."
echo " Finished : $(date)"
echo "============================================================"
