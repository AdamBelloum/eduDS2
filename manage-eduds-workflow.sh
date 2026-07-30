#!/usr/bin/env bash
# ==============================================================================
# manage-eduds-workflow.sh
#
# Interactive guided menu for non-technical users.
# Walks through the full eduDS pipeline step by step.
#
# Requirements: Docker Desktop, git, bash >= 4
# Usage:        bash manage-eduds-workflow.sh
# ==============================================================================

set -euo pipefail

# Clean exit on Ctrl+C
trap 'echo -e "\n${YELLOW}Interrupted. Exiting.${NC}"; exit 0' INT

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NC="\033[0m"

# ── Configuration ─────────────────────────────────────────────────────────────
DOCKER_IMAGE_APP="eduds-app"
DOCKER_IMAGE_MINERU="mineru"
CONTAINER_NAME_OLLAMA="ollama-server"
CONTAINER_NAME_APP="eduds_runner"

REPO_URL="https://github.com/AdamBelloum/eduDS2.git"
REPO_DIR="eduDS2"

SCRIPT_DIR="$PWD/Scripts"

MD_TARGET_DIR="${REPO_DIR}/docs/materials_md/parsed"
MD_SOURCE_DIR="MinerU_output/Lecturenotes/auto/"
QUERY_DIR="${REPO_DIR}/docs/query"
RESULTS_DIR="${REPO_DIR}/results"

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

# ── Ensure a helper script exists before calling it ───────────────────────────
function ensure_script_exists() {
    local path="${SCRIPT_DIR}/$1"
    if [[ ! -f "$path" ]]; then
        err "Missing required helper script: $path"
        err "Please ensure all files in the Scripts/ folder are present."
        exit 1
    fi
}

# ── Status checks ─────────────────────────────────────────────────────────────
function is_docker_running()     { docker info &>/dev/null; }
function is_ollama_running()     { docker ps -q --filter "name=${CONTAINER_NAME_OLLAMA}" | grep -q .; }
function is_app_running()        { docker ps -q --filter "name=${CONTAINER_NAME_APP}"    | grep -q .; }
function is_app_image_built()    { docker image inspect "${DOCKER_IMAGE_APP}"    &>/dev/null; }
function is_mineru_image_built() { docker image inspect "${DOCKER_IMAGE_MINERU}" &>/dev/null; }

function has_markdown_input() {
    find "${MD_TARGET_DIR}" -maxdepth 1 -name "*.md" -type f 2>/dev/null | grep -q .
}

function has_query_file() {
    find "${QUERY_DIR}" -maxdepth 1 -name "*.json" -type f 2>/dev/null | grep -q .
}

function has_ke_results() {
    find "${RESULTS_DIR}" -name "*.json" -type f 2>/dev/null | grep -q .
}

# ── Prerequisite check — runs once at startup ─────────────────────────────────
function check_prerequisites() {
    header "Checking Prerequisites"
    local all_ok=true

    if command -v docker &>/dev/null; then
        ok "Docker is installed."
    else
        err "Docker is not installed or not in PATH."
        err "Install Docker Desktop from: https://www.docker.com/products/docker-desktop"
        all_ok=false
    fi

    if is_docker_running; then
        ok "Docker daemon is running."
    else
        err "Docker daemon is not running. Please start Docker Desktop first."
        all_ok=false
    fi

    if command -v git &>/dev/null; then
        ok "git is installed."
    else
        err "git is not installed. Install from: https://git-scm.com"
        all_ok=false
    fi

    ensure_script_exists "ollama-helper.sh"
    ensure_script_exists "mineru-helper.sh"
    ensure_script_exists "eduds-helper.sh"
    ok "All helper scripts found in Scripts/."

    if [[ "$all_ok" == false ]]; then
        echo ""
        err "One or more prerequisites are missing."
        err "Please fix the issues above and re-run this script."
        exit 1
    fi

    echo ""
    ok "All prerequisites met. Starting menu..."
    sleep 1
}

# ── Live status dashboard — shown at the top of every menu ───────────────────
function print_status() {
    echo -e "\n  ${BOLD}Current Status:${NC}"

    if is_ollama_running; then
        echo -e "  Ollama Server  : ${GREEN}RUNNING${NC}"
    else
        echo -e "  Ollama Server  : ${RED}STOPPED${NC}"
    fi

    if is_app_running; then
        echo -e "  eduDS App      : ${GREEN}RUNNING${NC}"
    else
        echo -e "  eduDS App      : ${RED}STOPPED${NC}"
    fi

    if has_markdown_input; then
        echo -e "  Markdown Input : ${GREEN}READY${NC}"
    else
        echo -e "  Markdown Input : ${YELLOW}MISSING${NC}"
    fi

    if has_query_file; then
        echo -e "  Query File     : ${GREEN}READY${NC}"
    else
        echo -e "  Query File     : ${YELLOW}MISSING${NC}"
    fi

    if has_ke_results; then
        echo -e "  KE Results     : ${GREEN}READY${NC}"
    else
        echo -e "  KE Results     : ${YELLOW}NOT YET RUN${NC}"
    fi
}

# ── Step 1: Ollama ────────────────────────────────────────────────────────────
function step_ollama() {
    header "Step 1 — Manage Ollama AI Server"
    info "Ollama runs the AI language model locally on your machine."
    info "You must start the Ollama server before running Steps 5 or 6."
    echo ""
    info "Delegating to ollama-helper.sh ..."
    bash "${SCRIPT_DIR}/ollama-helper.sh"
}

# ── Step 2: MinerU ────────────────────────────────────────────────────────────
function step_build_mineru() {
    header "Step 2 — Build MinerU (PDF Converter)"
    info "MinerU converts your PDF lecture notes into text the AI can read."
    info "This only needs to be done once."
    echo ""

    if is_mineru_image_built; then
        ok "MinerU Docker image '${DOCKER_IMAGE_MINERU}' is already built."
        read -r -p "  Rebuild it anyway? (y/N): " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            info "Skipping rebuild."
            return 0
        fi
    fi

    info "Delegating to mineru-helper.sh ..."
    bash "${SCRIPT_DIR}/mineru-helper.sh" \
        || { err "MinerU build failed. See output above."; return 1; }

    ok "MinerU image built successfully."
}

# ── Step 3: eduDS App ─────────────────────────────────────────────────────────
function step_build_app() {
    header "Step 3 — Build eduDS Application"
    info "This builds the main AI pipeline application."
    info "This only needs to be done once."
    echo ""

    # Clone the repo if not already present
    if [[ ! -d "${REPO_DIR}" ]]; then
        info "Cloning eduDS2 repository from GitHub ..."
        git clone "${REPO_URL}" "${REPO_DIR}" \
            || { err "Git clone failed. Check your internet connection."; return 1; }
        ok "Repository cloned to ./${REPO_DIR}"
    else
        ok "Repository already exists at ./${REPO_DIR}"
    fi

    # Skip build if image already exists
    if is_app_image_built; then
        ok "eduDS App image '${DOCKER_IMAGE_APP}' is already built."
        read -r -p "  Rebuild it anyway? (y/N): " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            info "Skipping rebuild."
            return 0
        fi
    fi

    # Ensure input directories exist
    mkdir -p "${MD_TARGET_DIR}" "${QUERY_DIR}"

    info "Delegating to eduds-helper.sh --eduds-only ..."
    bash "${SCRIPT_DIR}/eduds-helper.sh" --eduds-only \
        || { err "Build failed. See output above."; return 1; }

    ok "eduDS App image built successfully."
}

# ── Step 4: PDF → Markdown ────────────────────────────────────────────────────
function step_convert_pdf() {
    header "Step 4 — Convert PDF Notes to Markdown"
    info "Converts your PDF lecture notes into text files the AI can process."
    info "You can skip this step if you already have Markdown (.md) files."
    echo ""

    if ! is_mineru_image_built; then
        err "MinerU Docker image '${DOCKER_IMAGE_MINERU}' not found."
        err "Please complete Step 2 first."
        return 1
    fi

    info "Delegating to mineru-helper.sh --prepare-input ..."
    bash "${SCRIPT_DIR}/mineru-helper.sh" --prepare-input \
        || { err "PDF conversion failed. See output above."; return 1; }

    ok "Conversion complete."
    ok "Markdown files are ready in: ${MD_TARGET_DIR}"
}

# ── Step 5: Knowledge Extraction ──────────────────────────────────────────────
function step_knowledge_extraction() {
    header "Step 5 — Knowledge Extraction"
    info "The AI reads your documents and extracts structured knowledge."
    echo ""

    local prereqs_ok=true

    # Check 1: Ollama must be running
    if is_ollama_running; then
        ok "Ollama server is running."
    else
        err "Ollama server is NOT running."
        err "Please go to Step 1 and start the Ollama server first."
        prereqs_ok=false
    fi

    # Check 2: Markdown input must exist
    if has_markdown_input; then
        ok "Markdown input files found in: ${MD_TARGET_DIR}"
    else
        warn "No Markdown (.md) files found in: ${MD_TARGET_DIR}"
        warn "Option A: Run Step 4 to convert your PDF notes."
        warn "Option B: Place .md files manually in that folder."
        prereqs_ok=false
    fi

    # Check 3: Query file must exist
    if has_query_file; then
        ok "Query file found in: ${QUERY_DIR}"
    else
        err "No query file (.json) found in: ${QUERY_DIR}"
        err "Please create a file called query01.json with this content:"
        err '  [ { "Question": "Your question about the material here" } ]'
        prereqs_ok=false
    fi

    if [[ "$prereqs_ok" == false ]]; then
        echo ""
        err "Prerequisites not met. Please resolve the issues above and try again."
        return 1
    fi

    echo ""
    info "All prerequisites met. Starting Knowledge Extraction ..."
    bash "${SCRIPT_DIR}/eduds-helper.sh" --eduds-knowledge-extraction \
        || { err "Knowledge Extraction failed. See output above."; return 1; }

    echo ""
    ok "Knowledge Extraction complete."
    ok "Results saved to: ${RESULTS_DIR}/"
}

# ── Step 6: Story Generation ──────────────────────────────────────────────────
function step_story_generation() {
    header "Step 6 — Story and Lesson Generation"
    info "The AI transforms the extracted knowledge into a full lesson package."
    echo ""

    local prereqs_ok=true

    # Check 1: Ollama must be running
    if is_ollama_running; then
        ok "Ollama server is running."
    else
        err "Ollama server is NOT running."
        err "Please go to Step 1 and start the Ollama server first."
        prereqs_ok=false
    fi

    # Check 2: Knowledge Extraction must have been run
    if has_ke_results; then
        ok "Knowledge Extraction results found."
    else
        err "No Knowledge Extraction results found in: ${RESULTS_DIR}/"
        err "Please complete Step 5 first."
        prereqs_ok=false
    fi

    if [[ "$prereqs_ok" == false ]]; then
        echo ""
        err "Prerequisites not met. Please resolve the issues above and try again."
        return 1
    fi

    echo ""
    info "All prerequisites met. Starting Story and Lesson Generation ..."
    bash "${SCRIPT_DIR}/eduds-helper.sh" --eduds-story-generation \
        || { err "Story Generation failed. See output above."; return 1; }

    echo ""
    ok "Lesson package generation complete."
    ok "Output saved to: ${RESULTS_DIR}/"
}

# ── Step 7: Cleanup ───────────────────────────────────────────────────────────
function step_cleanup() {
    header "Step 7 — Clean Up Docker Resources"
    warn "This will stop all running eduDS and Ollama containers."
    warn "Your generated results in ${RESULTS_DIR}/ will NOT be deleted."
    echo ""
    read -r -p "  Are you sure you want to continue? (y/N): " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        info "Cleanup cancelled."
        return 0
    fi

    info "Stopping eduDS containers ..."
    bash "${SCRIPT_DIR}/eduds-helper.sh"  --full-reset 2>/dev/null || true

    info "Stopping Ollama server ..."
    bash "${SCRIPT_DIR}/ollama-helper.sh" --stop-only  2>/dev/null || true

    echo ""
    ok "Cleanup complete."
}

# ── Step 8: First-time guidance ───────────────────────────────────────────────
function display_guidance() {
    header "First-Time User Guide"
    cat <<'GUIDE'

  Welcome! This tool turns your PDF lecture notes into structured
  lesson packages using AI. No programming knowledge required.

  ---------------------------------------------------------------
  FIRST TIME SETUP  (do these steps once)
  ---------------------------------------------------------------
  Step 1  Start the Ollama AI server
  Step 2  Build the PDF converter (MinerU)
  Step 3  Build the eduDS application

  ---------------------------------------------------------------
  EACH TIME YOU WANT TO GENERATE A LESSON
  ---------------------------------------------------------------
  Step 4  Convert your PDF notes to text  (optional)
          OR place Markdown (.md) files directly in:
          eduDS2/docs/materials_md/parsed/

          ALSO add your question as a JSON file here:
          eduDS2/docs/query/query01.json

          The file should look like this:
          [
            { "Question": "What is pipelining?" },
            { "Question": "Explain cache coherence." }
          ]

  Step 5  Run Knowledge Extraction
          The AI reads your documents and extracts key concepts.

  Step 6  Run Story and Lesson Generation
          The AI produces a complete lesson package in Markdown.

  Results are saved in: eduDS2/results/

  ---------------------------------------------------------------
  TIPS
  ---------------------------------------------------------------
  - The status panel at the top of the menu shows what is ready.
  - Each step checks its own prerequisites automatically.
  - If a step fails, read the error message — it tells you what
    to fix and which step to run first.
  - Step 7 cleans up Docker containers. Your results are safe.
  - You can run Steps 5 and 6 again with different questions
    without rebuilding anything.

GUIDE
}

# ── Main menu loop ────────────────────────────────────────────────────────────
check_prerequisites

while true; do

    echo -e "\n${BOLD}${CYAN}=====================================================${NC}"
    echo -e "${BOLD}${CYAN}     eduDS  --  AI Lesson Generator Menu             ${NC}"
    echo -e "${BOLD}${CYAN}=====================================================${NC}"

    print_status

    echo ""
    echo -e "  ${BOLD}-- First-time setup (do once) ----------------${NC}"
    echo    "  (1)  Manage Ollama AI Server"
    echo    "  (2)  Build MinerU  (PDF to Text Converter)"
    echo    "  (3)  Build eduDS Application"
    echo ""
    echo -e "  ${BOLD}-- Generate a lesson -------------------------${NC}"
    echo    "  (4)  Convert PDF Notes to Markdown  (optional)"
    echo    "  (5)  Run Knowledge Extraction"
    echo    "  (6)  Run Story and Lesson Generation"
    echo ""
    echo -e "  ${BOLD}-- Utilities ---------------------------------${NC}"
    echo    "  (7)  Clean Up Docker Resources"
    echo    "  (8)  Show First-Time Guide"
    echo    "  (9)  Exit"
    echo -e "  ${BOLD}----------------------------------------------${NC}"
    echo ""
    read -r -p "  Enter your choice [1-9]: " CHOICE

    case "$CHOICE" in
        1) step_ollama ;;
        2) step_build_mineru ;;
        3) step_build_app ;;
        4) step_convert_pdf ;;
        5) step_knowledge_extraction ;;
        6) step_story_generation ;;
        7) step_cleanup ;;
        8) display_guidance ;;
        9) echo -e "\n${GREEN}Goodbye!${NC}"; exit 0 ;;
        *) warn "Invalid choice. Please enter a number between 1 and 9." ;;
    esac

done

