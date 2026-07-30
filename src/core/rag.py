"""
main_ke.py — Knowledge Extraction entry point.

Runs the RAG pipeline over all query JSON files found in <ROOT_DIR>/docs/query/
and writes structured knowledge JSON to <ROOT_DIR>/results/<model>/knowledge_extraction/.

Supports: HPC (SLURM + GPU), desktop with GPU, desktop CPU-only (macOS Intel/ARM).
Hardware is detected automatically unless overridden in config.yaml.
"""

import json
import logging
import shutil
import argparse
from glob import glob
from pathlib import Path

from core.config import load_config
from core.utils_hardware import setup_hardware, log_hardware_summary
from core.rag import EnhancedRAG
from core.utils import reconstruct_specific_json


def _setup_logging(level: str, log_file: Path | None) -> None:
    """Configure root logger with console + optional file handler."""
    handlers = [logging.StreamHandler()]
    if log_file:
        log_file.parent.mkdir(parents=True, exist_ok=True)
        handlers.append(logging.FileHandler(log_file))

    logging.basicConfig(
        level=getattr(logging, level.upper(), logging.INFO),
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        handlers=handlers,
    )


def main(rag_model: str | None, embedding_model: str | None) -> None:
    """
    Run knowledge extraction for all query files.

    Args:
        rag_model:       Ollama LLM model name (overrides config if provided).
        embedding_model: HuggingFace embedding model name (overrides config if provided).
    """
    # ── Load config ───────────────────────────────────────────────────────────
    cfg = load_config()

    # ── Logging ───────────────────────────────────────────────────────────────
    _setup_logging(cfg.logging.level, cfg.logging.log_file)
    logger = logging.getLogger(__name__)

    # ── Hardware detection ────────────────────────────────────────────────────
    hw = setup_hardware(
        requested_device=cfg.hardware.device,
        num_cpu_threads=cfg.hardware.num_cpu_threads,
        cuda_device_index=cfg.hardware.cuda_device_index,
    )
    log_hardware_summary(hw)

    # ── Resolve models (CLI args override config) ─────────────────────────────
    resolved_rag_model = rag_model or cfg.models.default_rag_model
    resolved_emb_model = embedding_model or cfg.models.embedding_model

    logger.info("RAG model       : %s", resolved_rag_model)
    logger.info("Embedding model : %s", resolved_emb_model)
    logger.info("ROOT_DIR        : %s", cfg.paths.root_dir)

    # ── Build directory paths ─────────────────────────────────────────────────
    output_dir_ke = (
        cfg.paths.results_dir
        / resolved_rag_model.replace("/", "_").replace(":", "_")
        / "knowledge_extraction"
    )
    persist_dir = (
        cfg.paths.vector_db_dir
        / resolved_emb_model.replace("/", "_").replace(":", "_")
    )

    if output_dir_ke.exists():
        shutil.rmtree(output_dir_ke)
    output_dir_ke.mkdir(parents=True)

    if persist_dir.exists():
        shutil.rmtree(persist_dir)

    # ── Initialise RAG ────────────────────────────────────────────────────────
    logger.info("Initialising RAG pipeline...")
    rag = EnhancedRAG(
        embedding_model_name=resolved_emb_model,
        model_name=resolved_rag_model,
        persist_dir=str(persist_dir),
    )

    # ── Process query files ───────────────────────────────────────────────────
    query_files = sorted(glob(str(cfg.paths.query_dir / "query*.json")))
    if not query_files:
        logger.warning("No query files found in %s", cfg.paths.query_dir)
        return

    for qfile in query_files:
        qfile = Path(qfile)
        logger.info("Processing: %s", qfile.name)

        with open(qfile, "r", encoding="utf-8") as f:
            queries_data = json.load(f)

        output_subdir_ke = output_dir_ke / qfile.stem
        if output_subdir_ke.exists():
            shutil.rmtree(output_subdir_ke)
        output_subdir_ke.mkdir(parents=True)

        for idx, item in enumerate(queries_data):
            query = item.get("Question", "")
            logger.info("  Q%d: %s", idx + 1, query)

            answer_json = None  # explicit init — prevents UnboundLocalError

            try:
                parsed_data = rag.ask(query)
                _, final_json = reconstruct_specific_json(parsed_data)
                logger.debug("  Raw JSON: %s", final_json)
                answer_json = json.loads(final_json)
            except json.JSONDecodeError as e:
                logger.error("  JSON parse error for Q%d: %s", idx + 1, e)
            except Exception as e:
                logger.error("  Unexpected error for Q%d: %s", idx + 1, e)

            if answer_json is None:
                logger.warning("  Skipping Q%d — no valid output produced.", idx + 1)
                continue

            output_file = output_subdir_ke / f"q{idx + 1:02d}.json"
            with open(output_file, "w", encoding="utf-8") as f_out:
                json.dump(answer_json, f_out, indent=2, ensure_ascii=False)
            logger.info("  Saved: %s", output_file)

        logger.info("Finished: %s -> %s", qfile.name, output_subdir_ke)

    logger.info("All knowledge extraction tasks complete.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Run knowledge extraction. Values from config.yaml are used "
                    "unless overridden by CLI arguments."
    )
    parser.add_argument(
        "--rag_model",
        type=str,
        default=None,
        help="Ollama LLM model name, e.g. 'qwen2.5:7b'. Overrides config.yaml.",
    )
    parser.add_argument(
        "--embedding_model",
        type=str,
        default=None,
        help="HuggingFace embedding model name. Overrides config.yaml.",
    )
    args = parser.parse_args()
    main(args.rag_model, args.embedding_model)

