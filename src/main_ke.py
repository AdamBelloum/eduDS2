"""
main_ke.py — Knowledge Extraction entry point.

Runs the RAG pipeline over all query JSON files found in <ROOT_DIR>/docs/query/
and writes structured knowledge JSON to <ROOT_DIR>/results/<model>/knowledge_extraction/.
"""

import os
import json
import shutil
import logging
import argparse
from pathlib import Path
from glob import glob

from core.rag import EnhancedRAG
from core.utils import reconstruct_specific_json

# ── Logging setup ─────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

# ── Constants ─────────────────────────────────────────────────────────────────
DEFAULT_EMBEDDING_MODEL = "BAAI/bge-large-en-v1.5"


def main(rag_model: str, embedding_model: str = DEFAULT_EMBEDDING_MODEL) -> None:
    """
    Run knowledge extraction for all query files.

    Args:
        rag_model: Ollama model name, e.g. 'qwen2.5:7b'.
        embedding_model: HuggingFace embedding model name.
    """
    # ── Resolve ROOT_DIR ──────────────────────────────────────────────────────
    # Falls back to the repo root (two levels up from this file) when the
    # environment variable is not set, enabling local/desktop use.
    root_dir = Path(
        os.environ.get("ROOT_DIR", Path(__file__).resolve().parent.parent)
    )
    logger.info("ROOT_DIR: %s", root_dir)

    # ── Build directory paths ─────────────────────────────────────────────────
    input_dir = root_dir / "docs" / "query"
    output_dir_ke = (
        root_dir
        / "results"
        / rag_model.replace("/", "_").replace(":", "_")
        / "knowledge_extraction"
    )
    persist_dir = (
        root_dir / "vector_db" / embedding_model.replace("/", "_").replace(":", "_")
    )

    # ── Prepare output directories ────────────────────────────────────────────
    if output_dir_ke.exists():
        shutil.rmtree(output_dir_ke)
    output_dir_ke.mkdir(parents=True)

    if persist_dir.exists():
        shutil.rmtree(persist_dir)

    # ── Initialise RAG ────────────────────────────────────────────────────────
    logger.info("Initialising RAG | LLM: %s | Embeddings: %s", rag_model, embedding_model)
    rag = EnhancedRAG(
        embedding_model_name=embedding_model,
        model_name=rag_model,
        persist_dir=str(persist_dir),
    )

    # ── Process query files ───────────────────────────────────────────────────
    query_files = sorted(glob(str(input_dir / "query*.json")))
    if not query_files:
        logger.warning("No query files found in %s", input_dir)
        return

    for qfile in query_files:
        qfile = Path(qfile)
        logger.info("Processing file: %s", qfile.name)

        with open(qfile, "r", encoding="utf-8") as f:
            queries_data = json.load(f)

        ques_prefix = qfile.stem                          # e.g. "query01"
        output_subdir_ke = output_dir_ke / ques_prefix
        if output_subdir_ke.exists():
            shutil.rmtree(output_subdir_ke)
        output_subdir_ke.mkdir(parents=True)

        for idx, item in enumerate(queries_data):
            query = item.get("Question", "")
            logger.info("  Q%d: %s", idx + 1, query)

            answer_json = None  # explicit initialisation — prevents UnboundLocalError

            try:
                parsed_data = rag.ask(query)
                knowledge_base, final_json = reconstruct_specific_json(parsed_data)
                logger.debug("  Raw JSON: %s", final_json)
                answer_json = json.loads(final_json)
            except json.JSONDecodeError as e:
                logger.error("  JSON parse error for Q%d: %s", idx + 1, e)
            except Exception as e:
                logger.error("  Unexpected error for Q%d: %s", idx + 1, e)

            # Skip writing if extraction failed
            if answer_json is None:
                logger.warning("  Skipping Q%d — no valid output produced.", idx + 1)
                continue

            output_file = output_subdir_ke / f"q{idx + 1:02d}.json"
            with open(output_file, "w", encoding="utf-8") as f_out:
                json.dump(answer_json, f_out, indent=2, ensure_ascii=False)
            logger.info("  Saved: %s", output_file)

        logger.info("Finished: %s -> %s", qfile.name, output_subdir_ke)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Run knowledge extraction with a specified RAG model."
    )
    parser.add_argument(
        "--rag_model",
        type=str,
        required=True,
        help="Ollama LLM model name, e.g. 'qwen2.5:7b' or 'llama3.1:8b'",
    )
    parser.add_argument(
        "--embedding_model",
        type=str,
        default=DEFAULT_EMBEDDING_MODEL,
        help=f"HuggingFace embedding model name (default: {DEFAULT_EMBEDDING_MODEL})",
    )
    args = parser.parse_args()
    main(args.rag_model, args.embedding_model)

