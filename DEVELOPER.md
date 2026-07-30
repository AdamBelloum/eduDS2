# Small Language Models for Educational Data Storytelling

An AI-driven pipeline that transforms educational materials (Markdown/PDF) into
structured lesson packages using hybrid RAG and a Data Storytelling Engine.

> **Based on the original graduation project by Junming Ye (yip-jm)**
> Original repo: https://github.com/yip-jm/eduDS
> Original thesis: available in `Thesis.pdf`
>
> This repository extends the original work with software engineering best practices:
> portable configuration, hardware auto-detection (CPU / GPU / Apple MPS),
> guided workflow menu, Streamlit web interface, structured logging, and unit tests.

---

## Two ways to use this project

| Interface | Best for | How to start |
|---|---|---|
| **Web UI (Edu-Genius)** | Non-technical users, interactive use | `sbatch webapp/run.sh` then open browser |
| **Command line** | Batch processing, HPC, scripting | `bash manage-eduds-workflow.sh` |

---

## Pipeline Overview

```
[Markdown / PDF]
      |
      v
Stage 1 . Pre-processing
  PDF to Markdown via MinerU (optional)
  Semantic chunking + content-type detection
      |
      v
Stage 2 . Knowledge Extraction   <--  scripts/run_ke_local.sh  /  scripts/run_ke.sh (HPC)
  Hybrid retrieval: BM25 + ChromaDB vector search
  Cross-encoder reranking
  Ollama LLM -> structured JSON (Question, Core_Concepts, Summary)
      |
      v
Stage 3 . Story and Lesson Generation  <--  scripts/run_sg_local.sh  /  scripts/run_sg.sh (HPC)
  Lesson Plan Outline
  Core Concept Story Modules
  Interactive Activity Modules
      |
      v
[Complete Lesson Package -- Markdown]
```

---

## Repository Structure

```
eduDS2/
|-- src/                              <- pipeline + shared core
|   |-- core/
|   |   |-- config.py                 # Config loader (reads config.yaml)
|   |   |-- rag.py                    # EnhancedRAG pipeline
|   |   |-- retriever.py              # HybridRetriever (BM25 + vector + reranker)
|   |   |-- processor.py              # SmartDocumentProcessor
|   |   |-- DataStorytellingEngine.py # Lesson package generator
|   |   |-- prompts.py                # PromptTemplateManager
|   |   |-- utils.py                  # JSON utilities
|   |   `-- utils_hardware.py         # GPU / MPS / CPU auto-detection
|   |-- tests/                        # Unit tests (pytest)
|   |-- main_ke.py                    # Knowledge Extraction entry point
|   `-- main_sg.py                    # Story Generation entry point
|
|-- webapp/                           <- Edu-Genius browser interface
|   |-- src/
|   |   `-- app.py                    # Streamlit UI (imports from src/core/)
|   |-- vector_db_app/                # ChromaDB persistence (git-ignored)
|   |-- requirements.txt              # streamlit + root requirements
|   |-- run.sh                        # SLURM job: start Ollama + Streamlit
|   `-- README.md                     # Webapp-specific instructions
|
|-- scripts/                          <- all shell scripts
|   |-- ollama-helper.sh              # Manage Ollama server
|   |-- mineru-helper.sh              # PDF to Markdown conversion
|   |-- eduds-helper.sh               # Build image, run KE/SG
|   |-- run_ke_local.sh               # KE on desktop (no GPU needed)
|   |-- run_sg_local.sh               # SG on desktop
|   |-- run_ke.sh                     # KE on HPC (sbatch)
|   `-- run_sg.sh                     # SG on HPC (sbatch)
|
|-- docs/
|   |-- query/                        # Input: query JSON files
|   `-- materials_md/parsed/          # Input: Markdown documents
|
|-- manage-eduds-workflow.sh          # <- Interactive guided menu (start here)
|-- config.yaml                       # <- Central configuration (edit this)
`-- requirements.txt                  # Pipeline dependencies
```

---

## Requirements

| Requirement | Version |
|---|---|
| Python | >= 3.10 |
| [Ollama](https://ollama.com) | latest |
| CUDA (optional) | 12.x -- auto-detected |

---

## Installation

### 1. Clone

```bash
git clone https://github.com/AdamBelloum/eduDS2
cd eduDS2
```

### 2. Create a virtual environment

```bash
python3 -m venv .venv
source .venv/bin/activate        # macOS / Linux
# .venv\Scripts\activate         # Windows
```

### 3. Install dependencies

```bash
# Pipeline only
pip install -r requirements.txt

# Pipeline + web interface
pip install -r webapp/requirements.txt
```

### 4. Install Ollama (desktop only)

Download from https://ollama.com/download and install for your OS.
Then pull the model you want to use:

```bash
ollama pull llama3.1:8b          # or any model listed in config.yaml
```

---

## Configuration

All parameters live in **`config.yaml`** at the repo root.
Edit it before running -- no code changes needed.

```yaml
models:
  default_rag_model: "qwen2.5:7b"      # LLM for knowledge extraction
  default_story_model: "qwen2.5:7b"    # LLM for story generation
  embedding_model: "BAAI/bge-large-en-v1.5"

hardware:
  device: "auto"     # auto | gpu | cpu
  num_cpu_threads: 8

ollama:
  host: "http://127.0.0.1"
  port: 11434
```

`device: "auto"` detects CUDA then Apple MPS then CPU in that order.
Set `device: "cpu"` to force CPU on any machine.

---

## Prepare Your Input

1. Place your documents (**Markdown format**) in:
   ```
   docs/materials_md/parsed/
   ```

2. Place your query file (**JSON format**) in:
   ```
   docs/query/query01.json
   ```

   Format:
   ```json
   [
     { "Question": "What is pipelining in computer architecture?" },
     { "Question": "Explain cache coherence." }
   ]
   ```

---

## Running -- Guided Menu (recommended for all users)

The interactive menu handles everything -- Ollama, MinerU, the pipeline, and the
web app -- with step-by-step guidance and live status checks.

```bash
bash manage-eduds-workflow.sh
```

---

## Running -- Desktop CLI (macOS / Linux, no GPU needed)

Make the scripts executable once:

```bash
chmod +x scripts/run_ke_local.sh scripts/run_sg_local.sh
```

**Step 1 -- Knowledge Extraction:**

```bash
# Uses default model from config.yaml
./scripts/run_ke_local.sh

# Override model
./scripts/run_ke_local.sh qwen2.5:7b

# Custom venv location
VENV_PATH=./.venv ./scripts/run_ke_local.sh
```

**Step 2 -- Story Generation:**

```bash
./scripts/run_sg_local.sh

# Separate RAG and story models
./scripts/run_sg_local.sh llama3.1:8b qwen2.5:7b
```

Results are written to `results/<model_name>/`.

---

## Running -- Web Interface (Edu-Genius)

Runs on HPC via SLURM. Accessible from your laptop through an SSH tunnel.

```bash
sbatch webapp/run.sh
```

Once the job starts, check the log for connection instructions:

```bash
cat webapp/log/app_<JOBID>.out
```

Then open `http://localhost:8501` in your browser.
See `webapp/README.md` for full details including local desktop usage.

---

## Running -- HPC Batch (SLURM + Singularity + GPU)

```bash
sbatch scripts/run_ke.sh
# wait for completion, then:
sbatch scripts/run_sg.sh
```

The HPC scripts use:
- `gpu_a100` partition
- Singularity container for Ollama
- CUDA 12.1 + cuDNN 8.9

Edit the `#SBATCH` directives at the top of each script to match your cluster.

---

## Running Tests

```bash
source .venv/bin/activate
pip install pytest

pytest src/tests/ -v
```

Tests cover `utils.py` and `utils_hardware.py` with 30 tests.
No GPU, no LLM, and no file I/O required -- all external dependencies are mocked.

---

## Hardware Support Matrix

| Environment | Device | Script |
|---|---|---|
| macOS Intel | CPU | `scripts/run_ke_local.sh` |
| macOS Apple Silicon | MPS (Metal) | `scripts/run_ke_local.sh` |
| Linux desktop with NVIDIA GPU | CUDA | `scripts/run_ke_local.sh` |
| HPC cluster (SLURM) | CUDA (A100) | `scripts/run_ke.sh` (sbatch) |
| HPC -- interactive web UI | CUDA (H100) | `webapp/run.sh` (sbatch) |

Hardware is auto-detected at runtime via `src/core/utils_hardware.py`.

---

## Improvements Over Original Repo

| Area | Original | This repo |
|---|---|---|
| Portability | HPC-only (`sbatch`) | Desktop + HPC + Web UI |
| User interface | None | Guided menu + Streamlit web app |
| Configuration | Hardcoded in scripts | Central `config.yaml` |
| Hardware | `device="cuda"` hardcoded | Auto-detect CPU / MPS / CUDA |
| Error handling | Silent `except` + `print` | Typed exceptions + `logging` |
| `ROOT_DIR` | Crashes if env var missing | Falls back to repo root |
| Shell scripts | `~` unexpanded, no venv | Fixed, venv-aware, in `scripts/` |
| Code duplication | `core/` copied into webapp | Single `src/core/` shared by all |
| Tests | None | 30 unit tests (pytest) |
| `.gitignore` | None | Full Python + ML ignore rules |

---

## Attribution

Original work by **Junming Ye** -- MSc graduation project, VU Amsterdam & University of Amsterdam, 2025.
Original repository: https://github.com/yip-jm/eduDS

