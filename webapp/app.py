"""
app.py — Edu-Genius: AI Lesson Generator (Streamlit Web UI)

Provides a browser-based interface to the eduDS pipeline.
Users upload Markdown documents, ask a question, and receive
a structured knowledge base and a complete lesson plan.

Runs on HPC via:  sbatch webapp/run.sh
Runs locally via: streamlit run webapp/src/app.py
"""

import sys
import os
import logging
from pathlib import Path

# ── Shared core — import from src/core/, not a local copy ─────────────────────
# webapp/src/app.py  →  ../../src  =  repo root / src
_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(_REPO_ROOT / "src"))

import streamlit as st

from config import load_config
from core.utils_hardware import setup_hardware, log_hardware_summary
from core.rag import EnhancedRAG
from core.DataStorytellingEngine import DataStorytellingEngine

# ── Logging ────────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

# ── Load config ────────────────────────────────────────────────────────────────
cfg = load_config()

# Paths — resolved relative to repo root so the app works from any directory
UPLOAD_DIR   = _REPO_ROOT / "docs" / "materials_md" / "parsed"
VECTOR_DB    = _REPO_ROOT / "webapp" / "vector_db_app"

# Models — read from config.yaml; can be overridden via Streamlit sidebar
DEFAULT_RAG_MODEL       = cfg.models.default_rag_model
DEFAULT_STORY_MODEL     = cfg.models.default_story_model
DEFAULT_EMBEDDING_MODEL = cfg.models.embedding_model


# ── Backend initialisation (cached — runs once per session) ───────────────────

@st.cache_resource(show_spinner=False)
def setup_backend(rag_model: str, story_model: str, embedding_model: str):
    """
    Initialise the RAG and Storytelling engines.
    Cached by Streamlit so models are only loaded once.

    Args:
        rag_model:       Ollama model name for knowledge extraction.
        story_model:     Ollama model name for story generation.
        embedding_model: HuggingFace embedding model name.

    Returns:
        Tuple of (EnhancedRAG, DataStorytellingEngine) or (None, None) on error.
    """
    with st.spinner("Initialising AI systems — this takes a moment on first run..."):
        try:
            # Hardware detection
            hw = setup_hardware(
                requested_device=cfg.hardware.device,
                num_cpu_threads=cfg.hardware.num_cpu_threads,
            )
            log_hardware_summary(hw)
            logger.info(
                "Backend init | device=%s | rag=%s | story=%s | embed=%s",
                hw.device.value, rag_model, story_model, embedding_model,
            )

            # Ensure upload directory exists
            UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
            VECTOR_DB.mkdir(parents=True, exist_ok=True)

            # Check documents are present
            md_files = list(UPLOAD_DIR.glob("*.md"))
            if not md_files:
                st.warning(
                    "No Markdown documents found. "
                    "Please upload files using the sidebar before asking a question.",
                    icon="⚠️",
                )
                return None, None

            # Initialise RAG
            rag_system = EnhancedRAG(
                embedding_model_name=embedding_model,
                model_name=rag_model,
                persist_dir=str(VECTOR_DB),
                device=hw.device.value,
            )

            # Initialise storytelling engine
            story_engine = DataStorytellingEngine(model_name=story_model)

            st.success(f"AI systems ready — {len(md_files)} document(s) loaded.")
            return rag_system, story_engine

        except Exception as e:
            logger.exception("Backend initialisation failed: %s", e)
            st.error(f"Failed to initialise backend: {e}")
            return None, None


# ── Streamlit UI ───────────────────────────────────────────────────────────────

def render_sidebar() -> tuple[str, str, str]:
    """
    Render the sidebar and return the selected model names.

    Returns:
        Tuple of (rag_model, story_model, embedding_model).
    """
    with st.sidebar:
        st.header("⚙️ Setup")

        # ── 1. Model selection ─────────────────────────────────────────────────
        st.subheader("1. AI Models")
        st.caption("Models must be pulled in Ollama before use.")

        rag_model = st.selectbox(
            "Knowledge Extraction model",
            options=["llama3.1:8b", "qwen2.5:7b", "gemma:7b", "phi4:14b", "deepseek-llm:7b"],
            index=["llama3.1:8b", "qwen2.5:7b", "gemma:7b", "phi4:14b", "deepseek-llm:7b"]
                  .index(DEFAULT_RAG_MODEL)
                  if DEFAULT_RAG_MODEL in ["llama3.1:8b", "qwen2.5:7b", "gemma:7b", "phi4:14b", "deepseek-llm:7b"]
                  else 0,
        )

        story_model = st.selectbox(
            "Story Generation model",
            options=["llama3.1:8b", "qwen2.5:7b", "gemma:7b", "phi4:14b", "deepseek-llm:7b"],
            index=["llama3.1:8b", "qwen2.5:7b", "gemma:7b", "phi4:14b", "deepseek-llm:7b"]
                  .index(DEFAULT_STORY_MODEL)
                  if DEFAULT_STORY_MODEL in ["llama3.1:8b", "qwen2.5:7b", "gemma:7b", "phi4:14b", "deepseek-llm:7b"]
                  else 0,
        )

        embedding_model = DEFAULT_EMBEDDING_MODEL
        st.caption(f"Embedding model: `{embedding_model}` (set in config.yaml)")

        st.divider()

        # ── 2. Document upload ─────────────────────────────────────────────────
        st.subheader("2. Upload Documents")
        st.caption("Upload Markdown (.md) files converted from your lecture notes.")

        uploaded_files = st.file_uploader(
            "Upload .md files",
            type=["md"],
            accept_multiple_files=True,
            help="Convert PDFs to Markdown first using MinerU (Step 4 in the main menu).",
        )

        if uploaded_files:
            UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
            for f in uploaded_files:
                dest = UPLOAD_DIR / f.name
                dest.write_bytes(f.getbuffer())
            st.success(f"{len(uploaded_files)} file(s) uploaded to `docs/materials_md/parsed/`")

        # ── 3. Re-initialise ───────────────────────────────────────────────────
        st.subheader("3. Load / Reload System")
        if st.button("Process Documents & Load Models", use_container_width=True):
            st.cache_resource.clear()
            st.success("System will re-index documents on the next action.")
            st.rerun()
        st.caption("Click this after uploading new files.")

        st.divider()

        # ── 4. Manage uploaded files ───────────────────────────────────────────
        st.subheader("4. Manage Uploaded Files")
        if UPLOAD_DIR.exists():
            md_files = sorted([f.name for f in UPLOAD_DIR.glob("*.md")])
            if not md_files:
                st.info("No files uploaded yet.")
            else:
                st.caption(f"{len(md_files)} file(s) currently loaded:")
                files_to_delete = st.multiselect("Select files to delete:", options=md_files)
                if st.button("Delete Selected", type="primary", use_container_width=True):
                    if not files_to_delete:
                        st.warning("Select at least one file first.")
                    else:
                        for fname in files_to_delete:
                            try:
                                (UPLOAD_DIR / fname).unlink()
                            except Exception as e:
                                st.error(f"Could not delete {fname}: {e}")
                        st.success(f"Deleted {len(files_to_delete)} file(s).")
                        st.cache_resource.clear()
                        st.rerun()

    return rag_model, story_model, embedding_model


def main() -> None:
    st.set_page_config(
        page_title="Edu-Genius",
        page_icon="📚",
        layout="wide",
    )

    st.title("📚 Edu-Genius — AI Lesson Generator")
    st.markdown(
        "Upload your lecture notes, ask a question, and get a "
        "structured knowledge base and a complete lesson plan."
    )

    # ── Sidebar ────────────────────────────────────────────────────────────────
    rag_model, story_model, embedding_model = render_sidebar()

    # ── Backend ────────────────────────────────────────────────────────────────
    rag_system, story_engine = setup_backend(rag_model, story_model, embedding_model)

    # ── Main content ───────────────────────────────────────────────────────────
    if rag_system and story_engine:
        st.header("💬 Ask Your Question")
        query = st.text_input(
            "Enter your question about the uploaded documents:",
            placeholder="e.g. What are the main differences between RISC and CISC?",
        )

        if st.button("🚀 Generate Lesson Plan", use_container_width=True):
            if not query.strip():
                st.error("Please enter a question before generating.")
            else:
                with st.spinner("🧠 Generating — this can take a few minutes..."):
                    try:
                        # Step 1: Knowledge Extraction
                        st.write("**Step 1 / 2** — Extracting knowledge from documents...")
                        knowledge_base = rag_system.ask(query)
                        st.session_state["knowledge_base"] = knowledge_base
                        logger.info("Knowledge extraction complete for query: %s", query)

                        # Step 2: Story Generation
                        st.write("**Step 2 / 2** — Generating lesson plan...")
                        lesson_plan = story_engine.generate_lesson_package(knowledge_base)
                        st.session_state["lesson_plan"] = lesson_plan
                        logger.info("Lesson plan generation complete.")

                        st.success("✅ Generation complete!")

                    except Exception as e:
                        logger.exception("Generation failed: %s", e)
                        st.error(f"An error occurred: {e}")
                        st.exception(e)
    else:
        st.info(
            "Upload documents and click **Process Documents & Load Models** "
            "in the sidebar to begin."
        )

    # ── Results ────────────────────────────────────────────────────────────────
    if "lesson_plan" in st.session_state:
        st.divider()
        st.header("🎉 Your Generated Content")

        col1, col2 = st.columns(2)

        with col1:
            st.subheader("🔬 Extracted Knowledge Base")
            st.json(st.session_state.get("knowledge_base", {}))

        with col2:
            st.subheader("📖 Generated Lesson Plan")
            lesson = st.session_state.get("lesson_plan", "")
            st.markdown(lesson)

            # Download button
            st.download_button(
                label="⬇️ Download Lesson Plan (.md)",
                data=lesson,
                file_name="lesson_plan.md",
                mime="text/markdown",
                use_container_width=True,
            )


if __name__ == "__main__":
    main()

