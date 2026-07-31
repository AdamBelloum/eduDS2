# Edu-Genius — Turn your lecture notes into lesson plans

Edu-Genius reads your lecture notes and automatically creates a structured lesson
plan and teaching activities. You don’t need to write code or edit scripts.

---

There's a persistent session issue blocking artifact creation. Here's the content directly — you can copy it into a `docs/USER_GUIDE.md` file:

---

## What happens under the hood?

### Stage 1 — Knowledge Extraction (KE) ⏱ slow · GPU recommended
The AI reads through all your Markdown documents and answers each of your questions by retrieving the most relevant passages. This is the most computationally intensive step.

- **What it does:** For each question in your query file, the AI searches your documents and extracts the key knowledge needed to answer it.
- **Output:** Structured JSON files saved in `results/`.
- **Time:** A few minutes per question on GPU; significantly longer on CPU.
- **GPU impact:** A GPU can make this 5–10× faster.

### Stage 2 — Story & Lesson Generation (SG) ⏱ moderate · GPU recommended
The AI takes the extracted knowledge and turns it into a complete, readable lesson with explanations, examples, and a narrative structure.

- **Output:** Lesson files saved in `results/`, viewable in the web app.
- **GPU impact:** Speeds up text generation noticeably for longer lessons.

---

## Step-by-step overview

| Step | What you do | Time | GPU needed? |
|------|-------------|------|-------------|
| 1. Manage Ollama | Start the local AI server | Seconds | No |
| 2. Convert PDFs | Convert lecture PDFs to Markdown (optional) | 1–5 min per PDF | No |
| 3. Knowledge Extraction | AI reads documents and extracts knowledge | ⏱ Minutes–hours | ✅ Strongly recommended |
| 4. Story Generation | AI writes the lesson from extracted knowledge | ⏱ Minutes | ✅ Recommended |
| 5. Web Application | Browse and read your generated lessons | Instant | No |

---

## Tips

- **Steps 1 & 2** are quick setup tasks — no GPU needed.
- **Steps 3 & 4** are the heavy AI work. Use an HPC cluster with a GPU if available.
- On a **local laptop**, Step 3 can take a while depending on document and question count. Running overnight is fine.
- On **HPC**, Steps 3 & 4 run as background jobs — you can close your terminal and check back later via Step 6 (SLURM job status).
- You only need to redo **Step 3** if you change documents or questions. To regenerate the lesson style only, re-run **Step 4**.


## What you need

On your own computer (laptop or desktop):

1. **Git**
   - On macOS: installed via Xcode command line tools
   - On Linux: `sudo apt install git` (or similar)

2. **Python 3.10 or higher**

3. **Docker Desktop**
   - Download and install from: https://www.docker.com/products/docker-desktop

If you use an HPC cluster, you only need git and Python there.
Docker Desktop is only for your own computer.

---

## One simple starting point

After you cloned the project, **always start with**:

```bash
bash manage-eduds-workflow.sh
```

This opens a guided menu that:

- Checks if everything is installed
- Helps you start/stop the AI server (Ollama)
- Helps you convert PDFs to text (MinerU)
- Helps you run Knowledge Extraction and Story Generation
- Shows you the status of inputs and outputs

You can run everything by following the numbered options in this menu.

## Quick start (your first run)

- Clone the project
```bash
git clone https://github.com/AdamBelloum/eduDS2
cd eduDS2
```
- Create and activate a virtual environment
```bash
python3 -m venv .venv
source .venv/bin/activate   # macOS / Linux
# .venv\Scripts\activate    # Windows
```

- Install the software
```bash
pip install -r webapp/requirements.txt
```
- Start the guided menu

```bash
bash manage-eduds-workflow.sh
```
-Follow the menu steps
  - Step 1: Start the Ollama AI server (if not already running)
  - Step 2: Build the PDF converter (MinerU) — do this once
  - Step 3: Build the main eduDS application — do this once
  - Step 4: Convert your PDF notes to Markdown (or skip if you already have .md files)
  - Step 5: Run Knowledge Extraction
  - Step 6: Run Story & Lesson Generation

The menu will tell you what is ready and what is missing at every step.

## Where to put your files
The system expects your teaching materials in a specific folder.

- Markdown lecture notes (.md files):
```text
docs/materials_md/parsed/
```
- Your questions (what you want the lesson to answer):
```text
docs/query/query01.json
```
Example content:
```json
[
  { "Question": "What is pipelining in computer architecture?" },
  { "Question": "Explain cache coherence." }
]
```
You can either:

Upload .md files via the web interface, or
Place them directly into docs/materials_md/parsed/ on the filesystem.

## Using the web interface (optional, but recommended)
For an interactive browser interface:

Submit the webapp job on the HPC cluster:
```bash
sbatch webapp/run.sh
```
Once the job starts, open the log file:
```bash
cat webapp/log/app_<JOBID>.out
```
It will show you an SSH command and a URL to open.

On your local computer, run the SSH command shown in the log to create a tunnel.

Open your browser at:
```text
http://localhost:8501
```
From there you can:

- Upload documents
- Ask questions
- Download the generated lesson plan as a Markdown file

## What you get
- After running Steps 5 and 6 (Knowledge Extraction + Story Generation) you will get:

- A structured knowledge base (JSON)
- A complete lesson package in Markdown:
- Lesson plan outline
- Teaching module per concept
- Interactive activities and discussion prompts

You can open the Markdown file in any editor or learning management system.

## More detailed information
If you are a developer or want to understand the internals:

- See DEVELOPER.md for:
- Full architecture
- All scripts
- Hardware details
- Tests and modules

For the web interface details:

- See webapp/README.md.
