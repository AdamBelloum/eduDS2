# Web Interface — User Guide

Edu-Genius includes a browser-based interface built with Streamlit. It lets you upload documents, ask questions, and download generated lesson plans — without using the terminal.

---

## Starting the webapp

**Local machine:**
```bash
bash webapp/run.sh
```

**HPC cluster:**
```bash
sbatch webapp/run.sh
```

Then open your browser at **http://localhost:8501**.

### Connecting from HPC

When running on a cluster, the webapp runs on a compute node. To access it from your local browser:

1. Check the job log for the SSH tunnel command:
   ```bash
   cat log/webapp_<JOBID>.out
   ```

2. Run the SSH tunnel command shown in the log on your **local machine**:
   ```bash
   ssh -L 8501:<compute-node>:<port> <username>@<hpc-login-node>
   ```

3. Open **http://localhost:8501** in your browser.

---

## Before you start

Make sure Ollama is running and the models you want to use are already pulled:

```bash
ollama pull qwen2.5:7b
ollama pull llama3.1:8b
```

---

## Step-by-step usage

### 1. Choose AI models (sidebar)

Two dropdowns in the sidebar let you select:
- **Knowledge Extraction model** — reads your documents and extracts knowledge
- **Story Generation model** — writes the lesson plan

The defaults are set in `config.yaml`. The embedding model is fixed and shown as a caption.

> Models must be pulled in Ollama before they appear usable. If a model is not pulled, generation will fail.

---

### 2. Upload your documents (sidebar)

Click the upload area and select one or more **Markdown (`.md`) files** — these are your lecture notes.

> If you have PDFs, convert them to Markdown first using **Step 4** in the main workflow menu (`bash manage-eduds-workflow.sh`).

Uploaded files are saved to:
```
docs/materials_md/parsed/
```

---

### 3. Load the system (sidebar)

After uploading, click **"Process Documents & Load Models"**.

This indexes your documents and loads the AI models into memory. It runs once per session. Click it again after uploading new files.

---

### 4. Manage uploaded files (sidebar)

The bottom of the sidebar lists all currently loaded files. Select one or more and click **"Delete Selected"** to remove them. The system re-indexes automatically.

---

### 5. Ask your question (main area)

Type a question about your uploaded material in the text box. For example:

> *"What are the main differences between RISC and CISC architectures?"*

---

### 6. Generate the lesson

Click **"🚀 Generate Lesson Plan"**. The app runs two steps:

| Step | What happens | Time |
|------|-------------|------|
| Step 1 / 2 | AI extracts knowledge from your documents | 1–5 min |
| Step 2 / 2 | AI writes the structured lesson plan | 1–3 min |

A spinner shows progress. Do not close the browser tab while generating.

---

## Results

When generation is complete, two panels appear:

| Panel | Contents |
|-------|----------|
| 🔬 Extracted Knowledge Base | Raw structured knowledge in JSON format |
| 📖 Generated Lesson Plan | Complete lesson in readable Markdown |

Use the **"⬇️ Download Lesson Plan (.md)"** button to save the lesson to your computer.

---

## Tips

- You only need to click **"Process Documents & Load Models"** once per session, or after uploading new files.
- You can ask multiple questions in the same session without reloading.
- If the app shows a blank screen or an error on startup, check that Ollama is running: `ollama list`
- If you change `config.yaml`, restart the webapp for changes to take effect.

