#!/usr/bin/env bash
# ==============================================================================
# manage-eduds-workflow.sh
#
# Interactive guided menu for the eduDS pipeline.
# Auto-detects environment: Local Mac | HPC+GPU | HPC CPU-only
#
# Usage: bash manage-eduds-workflow.sh
# ==============================================================================

set -euo pipefail
trap 'echo -e "\n${YELLOW}Interrupted. Exiting.${NC}"; exit 0' INT

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NC="\033[0m"

# ── Paths ─────────────────────────────────────────────────────────────────────
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${ROOT_DIR}/venv"
SCRIPTS_DIR="${ROOT_DIR}/scripts"
MD_INPUT_DIR="${ROOT_DIR}/docs/materials_md"
QUERY_DIR="${ROOT_DIR}/docs/query"
RESULTS_DIR="${ROOT_DIR}/results"

KE_SCRIPT="${SCRIPTS_DIR}/run_ke_local.sh"
SG_SCRIPT="${SCRIPTS_DIR}/run_sg_local.sh"
WEBAPP_SCRIPT="${SCRIPTS_DIR}/run_webapp_local.sh"
KE_SBATCH="${SCRIPTS_DIR}/run_ke_slurm.sh"
SG_SBATCH="${SCRIPTS_DIR}/run_sg_slurm.sh"

# ── Print helpers ─────────────────────────────────────────────────────────────
function header() {
    echo -e "\n${CYAN}${BOLD}=====================================================${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}=====================================================${NC}"
}
function ok()   { echo -e "  ${GREEN}[OK]  $1${NC}"; }
function warn() { echo -e "  ${YELLOW}[!!]  $1${NC}"; }
function err()  { echo -e "  ${RED}[XX]  $1${NC}"; }
function info() { echo -e "  ${CYAN}[--]  $1${NC}"; }

# ── Environment Auto-Detection ────────────────────────────────────────────────
# Sets ENV_MODE to one of: local_mac | hpc_gpu | hpc_cpu
function detect_environment() {
    # Inside a running SLURM job — most reliable signal
    if [[ -n "${SLURM_JOB_ID:-}" ]]; then
        if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null 2>&1; then
            ENV_MODE="hpc_gpu"
        else
            ENV_MODE="hpc_cpu"
        fi
    # sbatch in PATH but not inside a job → login node
    elif command -v sbatch &>/dev/null; then
        ENV_MODE="hpc_login"
    # macOS
    elif [[ "$(uname)" == "Darwin" ]]; then
        ENV_MODE="local_mac"
    # Generic Linux, no SLURM
    else
        ENV_MODE="local_linux"
    fi
    export ENV_MODE
    export OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
}

function env_label() {
    case "$ENV_MODE" in
        local_mac) echo "Local (macOS / MPS)" ;;
        hpc_gpu)   echo "HPC — GPU (HPC-slurm)" ;;
        hpc_cpu)   echo "HPC — CPU only" ;;
    esac
}

# ── Status checks ─────────────────────────────────────────────────────────────
function is_ollama_running()  { curl -s "${OLLAMA_HOST}/api/tags" > /dev/null 2>&1; }
function is_venv_active()     { [[ -f "${VENV_DIR}/bin/activate" ]]; }
function has_markdown_input() { find "${MD_INPUT_DIR}" -maxdepth 2 -name "*.md"   -type f 2>/dev/null | grep -q .; }
function has_query_file()     { find "${QUERY_DIR}"    -maxdepth 1 -name "*.json" -type f 2>/dev/null | grep -q .; }
function has_ke_results()     { find "${RESULTS_DIR}"  -name "*.json"             -type f 2>/dev/null | grep -q .; }

function slurm_job_status() {
    # Returns last submitted job status if squeue is available
    if command -v squeue &>/dev/null && [[ -n "${LAST_JOB_ID:-}" ]]; then
        squeue -j "$LAST_JOB_ID" -h -o "%T" 2>/dev/null || echo "UNKNOWN"
    else
        echo "N/A"
    fi
}

# ── Prerequisite check ────────────────────────────────────────────────────────
function check_prerequisites() {
    local all_ok=true

    if ! command -v python3 &>/dev/null; then
        err "python3 not found in PATH."; all_ok=false
    fi

    if ! is_venv_active; then
        err "Virtual environment not found at: ${VENV_DIR}"
        err "Create it with: python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
        all_ok=false
    fi

    # On HPC: check sbatch scripts exist
    if [[ "$ENV_MODE" == hpc_* ]]; then
        for script in "$KE_SBATCH" "$SG_SBATCH"; do
            if [[ ! -f "$script" ]]; then
                err "Missing HPC sbatch script: $script"; all_ok=false
            fi
        done
    else
        # Local: check local run scripts exist
        for script in "$KE_SCRIPT" "$SG_SCRIPT" "$WEBAPP_SCRIPT"; do
            if [[ ! -f "$script" ]]; then
                err "Missing local script: $script"; all_ok=false
            fi
        done
    fi

    if [[ "$all_ok" == false ]]; then
        err "One or more prerequisites are missing. Please fix the issues above."
        exit 1
    fi
}

# ── Status dashboard ──────────────────────────────────────────────────────────
function print_status() {
    echo -e "\n  ${BOLD}Environment   : $(env_label)${NC}"
    echo -e "  ${BOLD}Current Status:${NC}"

    if is_ollama_running; then
        echo -e "  Ollama Server  : ${GREEN}RUNNING${NC}  (${OLLAMA_HOST})"
    else
        echo -e "  Ollama Server  : ${RED}STOPPED${NC}"
    fi

    if is_venv_active; then
        echo -e "  Python venv    : ${GREEN}FOUND${NC}"
    else
        echo -e "  Python venv    : ${RED}MISSING${NC}"
    fi

    if has_markdown_input; then
        echo -e "  Markdown Input : ${GREEN}READY${NC}"
    else
        echo -e "  Markdown Input : ${YELLOW}MISSING${NC}  → ${MD_INPUT_DIR}"
    fi

    if has_query_file; then
        echo -e "  Query File     : ${GREEN}READY${NC}"
    else
        echo -e "  Query File     : ${YELLOW}MISSING${NC}  → ${QUERY_DIR}"
    fi

    if has_ke_results; then
        echo -e "  KE Results     : ${GREEN}READY${NC}"
    else
        echo -e "  KE Results     : ${YELLOW}NOT YET RUN${NC}"
    fi

    # Show last SLURM job status on HPC
    if [[ "$ENV_MODE" == hpc_* ]] && [[ -n "${LAST_JOB_ID:-}" ]]; then
        local jstatus
        jstatus=$(slurm_job_status)
        echo -e "  Last SLURM Job : ${CYAN}${LAST_JOB_ID}${NC} — ${jstatus}"
    fi
}

# ── Step 1: Manage Ollama ─────────────────────────────────────────────────────
function step_ollama() {
    header "Step 1 — Manage Ollama AI Server"

    case "$ENV_MODE" in
        local_mac)
            info "Ollama runs locally on your Mac."
            ;;
        hpc_gpu)
            info "On HPC: Ollama will be started inside the SLURM compute job (GPU node)."
            info "You do not need to start it manually — Steps 3 & 4 handle this."
            info "If you need to test connectivity: curl ${OLLAMA_HOST}/api/tags"
            echo ""
            read -r -p "  Press Enter to return to menu..." _
            return 0
            ;;
        hpc_cpu)
            info "On HPC (CPU): Ollama will be started inside the SLURM compute job."
            info "CPU inference is slower — consider using a smaller model (e.g. llama3.2:3b)."
            echo ""
            read -r -p "  Press Enter to return to menu..." _
            return 0
            ;;
    esac

    echo ""
    if is_ollama_running; then
        ok "Ollama is already running at ${OLLAMA_HOST}."
        echo ""
        echo "  (1)  Stop Ollama server"
        echo "  (2)  Back to main menu"
        read -r -p "  Enter choice [1-2]: " SUB
        case "$SUB" in
            1)
                pkill -f "ollama serve" 2>/dev/null \
                    && ok "Ollama stopped." \
                    || warn "Could not stop Ollama (may not be managed by this script)."
                ;;
            *) info "Back to main menu." ;;
        esac
    else
        warn "Ollama is not running."
        echo ""
        echo "  (1)  Start Ollama server"
        echo "  (2)  Back to main menu"
        read -r -p "  Enter choice [1-2]: " SUB
        case "$SUB" in
            1)
                info "Starting Ollama server in background..."
                ollama serve &>/dev/null &
                sleep 3
                if is_ollama_running; then
                    ok "Ollama server started at ${OLLAMA_HOST}."
                else
                    err "Ollama failed to start. Run 'ollama serve' manually to debug."
                fi
                ;;
            *) info "Back to main menu." ;;
        esac
    fi
}

# ── Step 2: PDF → Markdown ────────────────────────────────────────────────────
function step_convert_pdf() {
    header "Step 2 — Convert PDF Notes to Markdown"
    info "Place your PDF files in a folder and run MinerU to convert them."
    info "Or place .md files directly in: ${MD_INPUT_DIR}"
    echo ""

    if command -v magic-pdf &>/dev/null; then
        info "MinerU (magic-pdf) found."
        read -r -p "  Enter path to your PDF folder: " PDF_DIR
        if [[ ! -d "$PDF_DIR" ]]; then
            err "Directory not found: $PDF_DIR"
            return 1
        fi
        mkdir -p "${MD_INPUT_DIR}"
        magic-pdf -p "$PDF_DIR" -o "${MD_INPUT_DIR}" -m auto \
            && ok "Conversion complete. Files saved to: ${MD_INPUT_DIR}" \
            || err "Conversion failed. Check MinerU installation."
    else
        warn "MinerU (magic-pdf) not found in PATH."
        info "Manual option: place your .md files directly in:"
        info "  ${MD_INPUT_DIR}"
        info "Install MinerU: pip install magic-pdf"
    fi
}

# ── Shared prereq checker for KE and SG ──────────────────────────────────────
function check_pipeline_prereqs() {
    local mode="$1"   # "ke" or "sg"
    local ok_flag=true

    # Ollama: only check locally — on HPC it starts inside the job
    if [[ "$ENV_MODE" == "local_mac" ]]; then
        if is_ollama_running; then
            ok "Ollama server is running."
        else
            err "Ollama server is NOT running. Please start it via Step 1."
            ok_flag=false
        fi
    else
        info "HPC mode: Ollama will start inside the SLURM job."
    fi

    if [[ "$mode" == "ke" ]]; then
        if has_markdown_input; then
            ok "Markdown input files found."
        else
            err "No .md files found in: ${MD_INPUT_DIR}"
            err "Add .md files or run Step 2 to convert PDFs."
            ok_flag=false
        fi
        if has_query_file; then
            ok "Query file found."
        else
            err "No query .json found in: ${QUERY_DIR}"
            err 'Create query01.json: [ { "Question": "Your question here" } ]'
            ok_flag=false
        fi
    fi

    if [[ "$mode" == "sg" ]]; then
        if has_ke_results; then
            ok "KE results found in: ${RESULTS_DIR}/"
        else
            err "No KE results found. Please complete Step 3 first."
            ok_flag=false
        fi
    fi

    [[ "$ok_flag" == true ]]
}

# ── Step 3: Knowledge Extraction ──────────────────────────────────────────────
function step_knowledge_extraction() {
    header "Step 3 — Knowledge Extraction"
    info "The AI reads your documents and extracts structured knowledge."
    echo ""

    if ! check_pipeline_prereqs "ke"; then
        echo ""
        err "Prerequisites not met. Resolve the issues above and try again."
        return 1
    fi

    echo ""
    info "All prerequisites met. Starting Knowledge Extraction..."
    echo ""

    case "$ENV_MODE" in
        local_mac)
            bash "${KE_SCRIPT}" \
                && ok "Knowledge Extraction complete. Results: ${RESULTS_DIR}/" \
                || err "Knowledge Extraction failed. See output above."
            ;;
        hpc_gpu)
            info "Submitting KE job to SLURM (GPU partition)..."
            LAST_JOB_ID=$(sbatch --parsable "${KE_SBATCH}")
            export LAST_JOB_ID
            ok "Job submitted: ${LAST_JOB_ID}"
            info "Monitor with: squeue -j ${LAST_JOB_ID}"
            info "Logs: ${ROOT_DIR}/logs/ke_${LAST_JOB_ID}.out"
            ;;
        hpc_cpu)
            info "Submitting KE job to SLURM (CPU partition)..."
            LAST_JOB_ID=$(sbatch --parsable --partition=cpu "${KE_SBATCH}")
            export LAST_JOB_ID
            ok "Job submitted: ${LAST_JOB_ID}"
            info "Monitor with: squeue -j ${LAST_JOB_ID}"
            info "Logs: ${ROOT_DIR}/logs/ke_${LAST_JOB_ID}.out"
            ;;
    esac
}

# ── Step 4: Story Generation ──────────────────────────────────────────────────
function step_story_generation() {
    header "Step 4 — Story and Lesson Generation"
    info "The AI transforms extracted knowledge into a full lesson package."
    echo ""

    if ! check_pipeline_prereqs "sg"; then
        echo ""
        err "Prerequisites not met. Resolve the issues above and try again."
        return 1
    fi

    echo ""
    info "All prerequisites met. Starting Story Generation..."
    echo ""

    case "$ENV_MODE" in
        local_mac)
            bash "${SG_SCRIPT}" \
                && ok "Lesson generation complete. Output: ${RESULTS_DIR}/" \
                || err "Story Generation failed. See output above."
            ;;
        hpc_gpu)
            info "Submitting SG job to SLURM (GPU partition)..."
            LAST_JOB_ID=$(sbatch --parsable "${SG_SBATCH}")
            export LAST_JOB_ID
            ok "Job submitted: ${LAST_JOB_ID}"
            info "Monitor with: squeue -j ${LAST_JOB_ID}"
            info "Logs: ${ROOT_DIR}/logs/sg_${LAST_JOB_ID}.out"
            ;;
        hpc_cpu)
            info "Submitting SG job to SLURM (CPU partition)..."
            LAST_JOB_ID=$(sbatch --parsable --partition=cpu "${SG_SBATCH}")
            export LAST_JOB_ID
            ok "Job submitted: ${LAST_JOB_ID}"
            info "Monitor with: squeue -j ${LAST_JOB_ID}"
            info "Logs: ${ROOT_DIR}/logs/sg_${LAST_JOB_ID}.out"
            ;;
    esac
}

# ── Step 5: Launch Webapp (local only) ───────────────────────────────────────
function step_webapp() {
    header "Step 5 — Launch Web Application"

    if [[ "$ENV_MODE" == hpc_* ]]; then
        warn "The Streamlit webapp is designed for local use."
        info "On HPC, forward port 8501 via SSH tunnel:"
        info "  ssh -L 8501:localhost:8501 <your-hpc-login>"
        info "Then run the webapp on the login node (not recommended for production)."
        echo ""
        read -r -p "  Launch anyway on this node? (y/N): " CONFIRM
        [[ "$CONFIRM" =~ ^[Yy]$ ]] || return 0
    fi

    if ! is_ollama_running; then
        warn "Ollama is not running. The webapp may not work correctly."
        read -r -p "  Continue anyway? (y/N): " CONFIRM
        [[ "$CONFIRM" =~ ^[Yy]$ ]] || return 0
    fi

    info "Starting webapp..."
    bash "${WEBAPP_SCRIPT}"
}

# ── Step 6: Check SLURM Job Status ───────────────────────────────────────────
function step_job_status() {
    header "Step 6 — SLURM Job Status"

    if [[ "$ENV_MODE" == "local_mac" ]]; then
        info "SLURM is not available in local mode."
        return 0
    fi

    echo ""
    info "Your running/pending jobs:"
    squeue -u "$(whoami)" 2>/dev/null || warn "Could not reach SLURM scheduler."
    echo ""
    info "Recent job history (last 5):"
    sacct -u "$(whoami)" --format=JobID,JobName,State,Elapsed,Start -X 2>/dev/null | head -7 \
        || warn "sacct not available."
    echo ""
    read -r -p "  Press Enter to return to menu..." _
}

# ── Step 7: Cleanup ───────────────────────────────────────────────────────────
function step_cleanup() {
    header "Step 7 — Clean Up Results"
    warn "This will delete all generated results in: ${RESULTS_DIR}/"
    warn "Your input files (Markdown, queries) will NOT be deleted."
    echo ""
    read -r -p "  Are you sure? (y/N): " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Cleanup cancelled."; return 0; }
    rm -rf "${RESULTS_DIR:?}"/*
    ok "Results folder cleared."
}

# ── Step 8: First-time guidance ───────────────────────────────────────────────
function display_guidance() {
    header "First-Time User Guide"
    cat <<GUIDE

  Welcome! This tool turns your lecture notes into structured
  lesson packages using AI.

  ---------------------------------------------------------------
  ENVIRONMENT: $(env_label)
  ---------------------------------------------------------------

  FIRST TIME SETUP
  ---------------------------------------------------------------
  Local Mac:
    1. Install Ollama:  https://ollama.com/download
    2. Pull a model:    ollama pull llama3.1:8b
    3. Create venv:     python3 -m venv venv
                        source venv/bin/activate
                        pip install -r requirements.txt

  HPC (Snellius):
    1. Clone repo:      git clone https://github.com/AdamBelloum/eduDS2.git
    2. Create venv:     python3 -m venv venv
                        source venv/bin/activate
                        pip install -r requirements.txt
    3. Ensure sbatch scripts exist in scripts/:
                        run_ke_slurm.sh
                        run_sg_slurm.sh

  ---------------------------------------------------------------
  EACH TIME YOU WANT TO GENERATE A LESSON
  ---------------------------------------------------------------
  Step 1  Manage Ollama (local) or verify HPC setup
  Step 2  Add input files:
          - Markdown notes  →  docs/materials_md/
          - Query file      →  docs/query/query01.json
            Format: [ { "Question": "Your question here" } ]
  Step 3  Run Knowledge Extraction
  Step 4  Run Story and Lesson Generation
  Step 5  Launch Webapp (local) or SSH-tunnel (HPC)

  Results are saved in: results/

  ---------------------------------------------------------------
  HPC TIPS
  ---------------------------------------------------------------
  - Steps 3 & 4 submit sbatch jobs automatically.
  - Use Step 6 to monitor SLURM job status.
  - Ollama starts inside the compute job — no manual start needed.
  - GPU jobs go to the gpu partition; CPU jobs to the cpu partition.

GUIDE
}

# ── Main ──────────────────────────────────────────────────────────────────────
detect_environment
check_prerequisites

while true; do

    echo -e "\n${BOLD}${CYAN}=====================================================${NC}"
    echo -e "${BOLD}${CYAN}     eduDS  --  AI Lesson Generator                 ${NC}"
    echo -e "${BOLD}${CYAN}=====================================================${NC}"

    print_status

    echo ""
    echo -e "  ${BOLD}-- Setup -------------------------------------${NC}"
    echo    "  (1)  Manage Ollama AI Server"
    echo    "  (2)  Convert PDF Notes to Markdown  (optional)"
    echo ""
    echo -e "  ${BOLD}-- Generate a lesson -------------------------${NC}"
    echo    "  (3)  Run Knowledge Extraction"
    echo    "  (4)  Run Story and Lesson Generation"
    echo    "  (5)  Launch Web Application"
    echo ""
    echo -e "  ${BOLD}-- Utilities ---------------------------------${NC}"

    if [[ "$ENV_MODE" == hpc_* ]]; then
        echo "  (6)  Check SLURM Job Status"
    else
        echo "  (6)  [SLURM — not available in local mode]"
    fi

    echo    "  (7)  Clean Up Results"
    echo    "  (8)  Show First-Time Guide"
    echo    "  (9)  Exit"
    echo -e "  ${BOLD}----------------------------------------------${NC}"
    echo ""
    read -r -p "  Enter your choice [1-9]: " CHOICE

    case "$CHOICE" in
        1) step_ollama ;;
        2) step_convert_pdf ;;
        3) step_knowledge_extraction ;;
        4) step_story_generation ;;
        5) step_webapp ;;
        6) step_job_status ;;
        7) step_cleanup ;;
        8) display_guidance ;;
        9) echo -e "\n${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) warn "Invalid choice. Please enter a number between 1 and 9." ;;
    esac

done

