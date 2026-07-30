#!/usr/bin/env bash
# ==============================================================================
# Scripts/mineru-helper.sh
#
# Builds the MinerU Docker image and converts PDF files to Markdown.
# Called by manage-eduds-workflow.sh (Steps 2 and 4) or directly.
#
# Usage:
#   bash Scripts/mineru-helper.sh                  # interactive menu
#   bash Scripts/mineru-helper.sh --prepare-input  # convert PDFs and exit
# ==============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"
CYAN="\033[0;36m";  BOLD="\033[1m";      NC="\033[0m"

function header() {
    echo -e "\n${CYAN}${BOLD}=====================================================${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}=====================================================${NC}"
}
function ok()   { echo -e "  ${GREEN}[OK]  $1${NC}"; }
function warn() { echo -e "  ${YELLOW}[!!]  $1${NC}"; }
function err()  { echo -e "  ${RED}[XX]  $1${NC}"; }
function info() { echo -e "  ${CYAN}[--]  $1${NC}"; }

# ── Configuration ─────────────────────────────────────────────────────────────
DOCKER_IMAGE="mineru"
DOCKERFILE_DIR="$PWD/Dockerfiles"
DOCKERFILE_PATH="${DOCKERFILE_DIR}/Dockerfile.mineru"

# Where converted Markdown files will be written
OUTPUT_DIR="$PWD/MinerU_output"

# Where the eduDS pipeline expects Markdown input
EDUDS_MD_DIR="$PWD/eduDS2/docs/materials_md/parsed"

# ── Status helpers ────────────────────────────────────────────────────────────
function is_image_built() {
    docker image inspect "${DOCKER_IMAGE}" &>/dev/null
}

function print_status() {
    echo -e "\n  ${BOLD}MinerU Status:${NC}"
    if is_image_built; then
        echo -e "  Docker Image : ${GREEN}BUILT${NC}  (${DOCKER_IMAGE})"
    else
        echo -e "  Docker Image : ${RED}NOT BUILT${NC}"
    fi

    local md_count
    md_count=$(find "${EDUDS_MD_DIR}" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$md_count" -gt 0 ]]; then
        echo -e "  Markdown Files : ${GREEN}${md_count} file(s) ready${NC} in ${EDUDS_MD_DIR}"
    else
        echo -e "  Markdown Files : ${YELLOW}NONE${NC} in ${EDUDS_MD_DIR}"
    fi
}

# ── Actions ───────────────────────────────────────────────────────────────────

function build_image() {
    header "Build MinerU Docker Image"

    if [[ ! -f "${DOCKERFILE_PATH}" ]]; then
        err "Dockerfile not found at: ${DOCKERFILE_PATH}"
        err "Please ensure Dockerfiles/Dockerfile.mineru exists."
        return 1
    fi

    info "Building image '${DOCKER_IMAGE}' from ${DOCKERFILE_PATH} ..."
    info "This may take several minutes on first run."
    docker build \
        -t "${DOCKER_IMAGE}" \
        -f "${DOCKERFILE_PATH}" \
        "${DOCKERFILE_DIR}" \
        || { err "Docker build failed. See output above."; return 1; }

    ok "MinerU image '${DOCKER_IMAGE}' built successfully."
}

function convert_pdfs() {
    header "Convert PDF Files to Markdown"

    if ! is_image_built; then
        err "MinerU image '${DOCKER_IMAGE}' not found."
        err "Please build it first (option 1)."
        return 1
    fi

    # Ask user for PDF source folder
    echo ""
    info "Where are your PDF lecture notes stored?"
    info "Press Enter to use the default, or type a full path."
    read -r -p "  PDF folder [default: $HOME/Downloads]: " PDF_INPUT
    local pdf_dir="${PDF_INPUT:-$HOME/Downloads}"

    if [[ ! -d "$pdf_dir" ]]; then
        err "Folder not found: $pdf_dir"
        return 1
    fi

    local pdf_count
    pdf_count=$(find "$pdf_dir" -maxdepth 1 -name "*.pdf" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$pdf_count" -eq 0 ]]; then
        warn "No PDF files found in: $pdf_dir"
        warn "Please place your PDF lecture notes there and try again."
        return 1
    fi

    ok "Found ${pdf_count} PDF file(s) in: $pdf_dir"

    # Create output directory
    mkdir -p "${OUTPUT_DIR}"

    info "Running MinerU conversion ..."
    info "Input  : $pdf_dir"
    info "Output : ${OUTPUT_DIR}"
    echo ""

    docker run --rm \
        -v "${pdf_dir}:/input:ro" \
        -v "${OUTPUT_DIR}:/output" \
        "${DOCKER_IMAGE}" \
        magic-pdf -p /input -o /output -m auto \
        || { err "MinerU conversion failed. See output above."; return 1; }

    ok "Conversion complete. Markdown files saved to: ${OUTPUT_DIR}"

    # Copy results into the eduDS input directory
    copy_to_eduds
}

function copy_to_eduds() {
    header "Copy Markdown Files to eduDS Input"

    local md_count
    md_count=$(find "${OUTPUT_DIR}" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$md_count" -eq 0 ]]; then
        warn "No Markdown files found in: ${OUTPUT_DIR}"
        warn "Run the PDF conversion first (option 2)."
        return 1
    fi

    info "Copying ${md_count} Markdown file(s) to: ${EDUDS_MD_DIR}"
    mkdir -p "${EDUDS_MD_DIR}"
    find "${OUTPUT_DIR}" -name "*.md" -type f -exec cp {} "${EDUDS_MD_DIR}/" \;

    ok "Copied ${md_count} file(s) to: ${EDUDS_MD_DIR}"
    ok "eduDS is ready to process these documents."
}

function remove_image() {
    header "Remove MinerU Docker Image"
    warn "This will delete the MinerU image. You will need to rebuild it."
    read -r -p "  Are you sure? (y/N): " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Cancelled."; return 0; }

    docker rmi "${DOCKER_IMAGE}" 2>/dev/null \
        && ok "Image '${DOCKER_IMAGE}' removed." \
        || warn "Image not found or already removed."
}

function show_output_files() {
    header "Show Converted Markdown Files"
    local md_count
    md_count=$(find "${EDUDS_MD_DIR}" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$md_count" -eq 0 ]]; then
        warn "No Markdown files found in: ${EDUDS_MD_DIR}"
    else
        info "${md_count} file(s) ready for processing:"
        echo ""
        find "${EDUDS_MD_DIR}" -maxdepth 1 -name "*.md" -type f \
            | sort \
            | while read -r f; do
                echo "    $(basename "$f")"
              done
    fi
}

# ── CLI flag handling (called from master menu) ───────────────────────────────
if [[ "${1:-}" == "--prepare-input" ]]; then
    convert_pdfs
    exit 0
fi

# ── Interactive menu ──────────────────────────────────────────────────────────
while true; do
    echo -e "\n${BOLD}${CYAN}=====================================================${NC}"
    echo -e "${BOLD}${CYAN}     MinerU  —  PDF to Markdown Converter            ${NC}"
    echo -e "${BOLD}${CYAN}=====================================================${NC}"

    print_status

    echo ""
    echo    "  (1)  Build MinerU Docker image"
    echo    "  (2)  Convert PDF files to Markdown"
    echo    "  (3)  Copy Markdown files to eduDS input folder"
    echo    "  (4)  Show files ready for processing"
    echo    "  (5)  Remove MinerU Docker image"
    echo    "  (6)  Back to main menu"
    echo ""
    read -r -p "  Enter your choice [1-6]: " CHOICE

    case "$CHOICE" in
        1) build_image ;;
        2) convert_pdfs ;;
        3) copy_to_eduds ;;
        4) show_output_files ;;
        5) remove_image ;;
        6) exit 0 ;;
        *) warn "Invalid choice. Enter a number between 1 and 6." ;;
    esac
done

