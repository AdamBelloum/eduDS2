# Edu-Genius — AI Lesson Generator (Web Interface)

A browser-based interface to the eduDS pipeline.
Upload your lecture notes, ask a question, and get a structured lesson plan —
no programming knowledge required.

---

## What it does

```
Your browser
    │
    │  (SSH tunnel from your laptop)
    │
Streamlit UI  ←→  Ollama AI server  ←→  src/core/ pipeline
    │
    ▼
Lesson plan (.md) — downloadable from the browser
```

**Sidebar:**
1. Select AI models (defaults from `config.yaml`)
2. Upload Markdown lecture notes (`.md` files)
3. Reload the system after uploading new files
4. Delete uploaded files

**Main area:**
- Type a question about your documents
- Click **Generate Lesson Plan**
- View the extracted knowledge base (JSON) and lesson plan (Markdown) side by side
- Download the lesson plan as a `.md` file

---

## Structure

```
webapp/
├── src/
│   ├── app.py          ← Streamlit UI (imports from ../../src/core/)
│   ├── main_ke.py      ← KE entry point (CLI use only)
│   └── main_sg.py      ← SG entry point (CLI use only)
├── vector_db_app/      ← ChromaDB vector store (auto-created, git-ignored)
├── log/                ← SLURM job logs (auto-created, git-ignored)
├── requirements.txt    ← streamlit + root requirements
└── run.sh              ← SLURM job script (HPC)
```

The webapp shares `src/core/` with the main pipeline — there is no duplicate code.

---

## Running on HPC (Snellius / SLURM)

### 1. Install dependencies (once)

```bash
python3 -m venv ~/.venv
source ~/.venv/bin/activate
pip install -r webapp/requirements.txt
```

### 2. Submit the job

From the repo root:

```bash
sbatch webapp/run.sh
```

### 3. Connect from your laptop

Once the job starts, open the log file to find the connection instructions:

```bash
cat webapp/log/app_<JOBID>.out
```

You will see something like:

```
#####################################################################
###           YOUR INTERACTIVE APP IS READY TO CONNECT           ###
#####################################################################

  Job running on : gpu-node-12
  Streamlit port : 57029

  STEP 1 — Open a NEW terminal on your LOCAL machine and run:
  ssh -L 8501:gpu-node-12:57029 <YOUR_USERNAME>@snellius.surf.nl

  STEP 2 — Open your browser and go to:
  http://localhost:8501
```

Run the `ssh` command in a new terminal on your laptop, then open `http://localhost:8501` in your browser.

### 4. Stop the app

Closing the browser does **not** stop the job. To release GPU resources:

```bash
scancel <JOBID>
```

---

## Running locally (desktop, no GPU)

Requires Ollama running locally. See the root `README.md` for setup.

```bash
source ~/.venv/bin/activate
pip install -r webapp/requirements.txt

# From the repo root:
streamlit run webapp/src/app.py
```

Then open `http://localhost:8501` in your browser.

---

## Configuration

Models and hardware settings are read from `config.yaml` at the repo root.
You can also change models interactively in the app sidebar without editing any files.

Key settings:

```yaml
models:
  default_rag_model: "llama3.1:8b"
  default_story_model: "llama3.1:8b"
  embedding_model: "BAAI/bge-large-en-v1.5"

hardware:
  device: "auto"   # auto-detects GPU / MPS / CPU
```

---

## Preparing your documents

The app expects Markdown (`.md`) files. If you have PDFs:

1. Convert them using MinerU (Step 4 in `manage-eduds-workflow.sh`)
2. Or upload `.md` files directly via the sidebar

---

## Notes

- The vector database (`vector_db_app/`) is rebuilt automatically when you click
  **Process Documents & Load Models**. It is git-ignored.
- The app runs for 4 hours by default (set in `run.sh` `#SBATCH --time`).
  Increase this if you need longer sessions.
- SLURM logs are saved to `webapp/log/app_<JOBID>.out` and `.err`.

