#!/usr/bin/env bash
# ==============================================================================
# Scripts/ollama-helper.sh
#
# Manages the Ollama AI server Docker container.
# Called by manage-eduds-workflow.sh (Step 1) or directly.
#
# Usage:
#   bash Scripts/ollama-helper.sh              # interactive menu
#   bash Scripts/ollama-helper.sh --stop-only  # stop container and exit
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
OLLAMA_IMAGE="ollama/ollama:latest"
CONTAINER_NAME="ollama-server"
OLLAMA_PORT="11434"
OLLAMA_HOST="http://127.0.0.1:${OLLAMA_PORT}"

# Volume to persist downloaded models between runs
OLLAMA_VOLUME="ollama_models"

# Default model to pull if user requests it
DEFAULT_MODEL="llama3.1:8b"

# ── Status helpers ────────────────────────────────────────────────────────────
function is_container_running() {
    docker ps -q --filter "name=^${CONTAINER_NAME}$" | grep -q .
}

function is_container_stopped() {
    docker ps -aq --filter "name=^${CONTAINER_NAME}$" --filter "status=exited" | grep -q .
}

function is_ollama_ready() {
    curl -sf "${OLLAMA_HOST}/api/tags" >/dev/null 2>&1
}

function print_status() {
    echo -e "\n  ${BOLD}Ollama Status:${NC}"
    if is_container_running; then
        echo -e "  Container : ${GREEN}RUNNING${NC}  (${CONTAINER_NAME})"
        if is_ollama_ready; then
            echo -e "  API       : ${GREEN}READY${NC}   (${OLLAMA_HOST})"
        else
            echo -e "  API       : ${YELLOW}STARTING...${NC}"
        fi
    elif is_container_stopped; then
        echo -e "  Container : ${YELLOW}STOPPED${NC}  (${CONTAINER_NAME})"
        echo -e "  API       : ${RED}OFFLINE${NC}"
    else
        echo -e "  Container : ${RED}NOT CREATED${NC}"
        echo -e "  API       : ${RED}OFFLINE${NC}"
    fi
}

# ── Actions ───────────────────────────────────────────────────────────────────

function pull_image() {
    header "Pull Ollama Image from Docker Hub"
    info "Pulling image: ${OLLAMA_IMAGE}"
    info "This may take a few minutes on first run..."
    docker pull "${OLLAMA_IMAGE}" \
        || { err "Failed to pull image. Check your internet connection."; return 1; }
    ok "Image pulled: ${OLLAMA_IMAGE}"
}

function start_container() {
    header "Start Ollama Server"

    if is_container_running; then
        ok "Ollama container is already running."
        return 0
    fi

    # Create persistent volume if it doesn't exist
    docker volume inspect "${OLLAMA_VOLUME}" &>/dev/null \
        || docker volume create "${OLLAMA_VOLUME}" >/dev/null

    if is_container_stopped; then
        info "Restarting existing stopped container ..."
        docker start "${CONTAINER_NAME}" >/dev/null
    else
        info "Starting new Ollama container ..."
        docker run -d \
            --name "${CONTAINER_NAME}" \
            --restart unless-stopped \
            -p "${OLLAMA_PORT}:11434" \
            -v "${OLLAMA_VOLUME}:/root/.ollama" \
            "${OLLAMA_IMAGE}" >/dev/null
    fi

    # Wait for API to become ready (max 60 s)
    info "Waiting for Ollama API to be ready ..."
    local waited=0
    until is_ollama_ready; do
        sleep 3
        waited=$((waited + 3))
        if [[ $waited -ge 60 ]]; then
            err "Ollama did not become ready within 60 seconds."
            err "Try running: docker logs ${CONTAINER_NAME}"
            return 1
        fi
        echo -n "."
    done
    echo ""

    ok "Ollama server is running and ready at ${OLLAMA_HOST}"
}

function stop_container() {
    header "Stop Ollama Server"
    if is_container_running; then
        info "Stopping container: ${CONTAINER_NAME} ..."
        docker stop "${CONTAINER_NAME}" >/dev/null
        ok "Ollama container stopped."
    else
        warn "Ollama container is not running."
    fi
}

function pull_model() {
    header "Pull an AI Model"

    if ! is_ollama_ready; then
        err "Ollama server is not running. Please start it first (option 2)."
        return 1
    fi

    echo ""
    info "Available models in config.yaml:"
    info "  llama3.1:8b   (recommended for most machines)"
    info "  qwen2.5:7b"
    info "  gemma:7b"
    info "  phi4:14b      (requires more RAM)"
    echo ""
    read -r -p "  Enter model name to pull [default: ${DEFAULT_MODEL}]: " MODEL_INPUT
    local model="${MODEL_INPUT:-$DEFAULT_MODEL}"

    info "Pulling model: ${model}"
    info "This may take several minutes depending on your internet speed..."
    docker exec "${CONTAINER_NAME}" ollama pull "${model}" \
        || { err "Failed to pull model '${model}'."; return 1; }

    ok "Model '${model}' is ready."
}

function list_models() {
    header "List Downloaded Models"
    if ! is_ollama_ready; then
        err "Ollama server is not running. Please start it first (option 2)."
        return 1
    fi
    info "Models currently available on this machine:"
    echo ""
    docker exec "${CONTAINER_NAME}" ollama list
}

function remove_container() {
    header "Remove Ollama Container"
    warn "This removes the container but keeps downloaded models."
    read -r -p "  Are you sure? (y/N): " CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { info "Cancelled."; return 0; }

    if is_container_running; then
        docker stop "${CONTAINER_NAME}" >/dev/null
    fi
    docker rm "${CONTAINER_NAME}" 2>/dev/null || true
    ok "Container removed. Downloaded models are preserved."
}

# ── CLI flag handling (called from master menu) ───────────────────────────────
if [[ "${1:-}" == "--stop-only" ]]; then
    stop_container
    exit 0
fi

# ── Interactive menu ──────────────────────────────────────────────────────────
while true; do
    echo -e "\n${BOLD}${CYAN}=====================================================${NC}"
    echo -e "${BOLD}${CYAN}     Ollama AI Server Manager                        ${NC}"
    echo -e "${BOLD}${CYAN}=====================================================${NC}"

    print_status

    echo ""
    echo    "  (1)  Pull Ollama image from Docker Hub"
    echo    "  (2)  Start Ollama server"
    echo    "  (3)  Stop Ollama server"
    echo    "  (4)  Pull an AI model"
    echo    "  (5)  List downloaded models"
    echo    "  (6)  Remove Ollama container"
    echo    "  (7)  Back to main menu"
    echo ""
    read -r -p "  Enter your choice [1-7]: " CHOICE

    case "$CHOICE" in
        1) pull_image ;;
        2) start_container ;;
        3) stop_container ;;
        4) pull_model ;;
        5) list_models ;;
        6) remove_container ;;
        7) exit 0 ;;
        *) warn "Invalid choice. Enter a number between 1 and 7." ;;
    esac
done

