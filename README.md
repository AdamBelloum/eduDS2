# Edu-Genius — AI Lesson Generator

> Turn your lecture notes into structured lesson plans using local AI.

Edu-Genius reads your Markdown documents, answers your questions about the material, and produces a complete lesson package — ready to use in any editor or learning management system. No programming knowledge required.

---

## How it works

```
Your PDFs / notes  →  Knowledge Extraction  →  Story Generation  →  Lesson Plan
```

1. **Knowledge Extraction** — the AI reads your documents and extracts structured knowledge for each question you ask.
2. **Story Generation** — the AI turns that knowledge into a complete, readable lesson with explanations, examples, and activities.

>  Both steps are computationally intensive. A GPU makes them 5–10× faster. See [INSTALL.md](docs/INSTALL.md) for hardware requirements.

---

## Requirements

| Tool | Version | Notes |
|------|---------|-------|
| Python | 3.10+ | |
| Git | any | |
| Docker Desktop | latest | For MinerU PDF converter |
| Ollama | latest | Local AI server — installed automatically |

On an **HPC cluster**, Docker Desktop is not needed. Ollama is managed by the workflow scripts.

---

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/AdamBelloum/eduDS2
cd eduDS2

# 2. Create and activate a virtual environment
python3 -m venv venv
source venv/bin/activate        # macOS / Linux

# 3. Install dependencies
pip install -r requirements.txt

# 4. Launch the guided menu
bash manage-eduds-workflow.sh
```

The menu checks your setup, starts the AI server, and walks you through every step. **This is the only command you need to remember.**

---

## Workflow steps

| Step | What happens | Time | GPU? |
|------|-------------|------|------|
| 1 — Start Ollama | Starts the local AI server | Seconds | No |
| 2 — Build MinerU | Builds the PDF converter (once only) | 2–5 min | No |
| 3 — Build eduDS | Builds the main app (once only) | 2–5 min | No |
| 4 — Convert PDFs | Converts your lecture PDFs to Markdown | 1–5 min/PDF | No |
| 5 — Knowledge Extraction | AI reads documents and extracts knowledge | ⏱ Minutes–hours |  Recommended |
| 6 — Story Generation | AI writes the lesson plan | ⏱ Minutes |  Recommended |

Steps 2 and 3 only need to run once. Steps 5 and 6 can be re-run any time with new documents or questions.

---

## Where to put your files

**Lecture notes** (Markdown `.md` files):
```
docs/materials_md/parsed/
```

**Your questions** — create `docs/query/query01.json`:
```json
[
  { "Question": "What is pipelining in computer architecture?" },
  { "Question": "Explain cache coherence." }
]
```

You can also upload files directly through the web interface.

---

## Web interface

For an interactive browser-based experience, start the webapp:

```bash
# Local
bash webapp/run.sh

# HPC (SLURM)
sbatch webapp/run.sh
```

Then open **http://localhost:8501** in your browser.

For full usage instructions see [docs/WEBAPP.md](docs/WEBAPP.md).

---

## Output

After running Steps 5 and 6 you will find in `results/`:

- A structured **knowledge base** (JSON)
- A complete **lesson package** (Markdown) including:
  - Lesson plan outline
  - Teaching module per concept
  - Discussion prompts and activities

---

## Documentation

| File | Contents |
|------|----------|
| [INSTALL.md](docs/INSTALL.md) | Full installation guide — local and HPC |
| [docs/WEBAPP.md](docs/WEBAPP.md) | Web interface user guide |
| [DEVELOPER.md](DEVELOPER.md) | Architecture, scripts, modules, tests |

---

## License

MIT

## Citation

If you use Edu-Genius in your work, please cite:

**Paper**
> Junming Ye  et al. (2026). *Affordable AI for the Classroom: Small Language Models Can Support Effective Data Storytelling*. DOI: [10.14293/FFL26.000014.v1](https://doi.org/10.14293/FFL26.000014.v1)

**MSc Thesis**
> Junming Ye (2025). [*Investigating the Application of Small Language Models for Educational Data Storytelling*](https://staff.fnwi.uva.nl/a.s.z.belloum/MSctheses/MScthesis_JunmingYe.pdf) 
