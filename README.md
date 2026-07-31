# Edu-Genius — Turn your lecture notes into lesson plans

Edu-Genius reads your lecture notes and automatically creates a structured lesson
plan and teaching activities. You don’t need to write code or edit scripts.

---

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
