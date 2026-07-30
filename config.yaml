"""
config.py — Central configuration loader.

Reads config.yaml from the repo root and exposes a typed AppConfig
dataclass. All other modules should import `load_config()` rather
than reading environment variables or hardcoding values directly.

Usage:
    from core.config import load_config
    cfg = load_config()
    print(cfg.models.embedding_model)
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional

import yaml

logger = logging.getLogger(__name__)

# Repo root = two levels up from this file (src/core/config.py → repo/)
_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
_DEFAULT_CONFIG_PATH = _REPO_ROOT / "config.yaml"


# ── Dataclasses (one per config section) ──────────────────────────────────────

@dataclass
class PathsConfig:
    root_dir: Path
    docs_dir: Path
    query_dir: Path
    materials_md_dir: Path
    results_dir: Path
    vector_db_dir: Path
    log_dir: Path


@dataclass
class ModelsConfig:
    embedding_model: str
    default_rag_model: str
    default_story_model: str
    rag_models: List[str]
    story_models: List[str]


@dataclass
class OllamaConfig:
    host: str
    port: int
    context_size: int
    max_loaded_models: int
    keep_loaded: bool
    precision: str
    batch_size: int
    num_threads: int

    @property
    def base_url(self) -> str:
        return f"{self.host}:{self.port}"


@dataclass
class HardwareConfig:
    device: str          # "auto" | "gpu" | "cpu"
    num_cpu_threads: int
    cuda_device_index: int

    @property
    def resolved_device(self) -> str:
        """Return 'cuda' or 'cpu' after auto-detection."""
        if self.device == "cpu":
            return "cpu"
        if self.device == "gpu":
            return "cuda"
        # auto
        try:
            import torch
            return "cuda" if torch.cuda.is_available() else "cpu"
        except ImportError:
            return "cpu"


@dataclass
class RagConfig:
    top_k: int
    hybrid_alpha: float
    chunk_size: int
    chunk_overlap: int


@dataclass
class LoggingConfig:
    level: str
    log_file: Optional[Path]


@dataclass
class AppConfig:
    paths: PathsConfig
    models: ModelsConfig
    ollama: OllamaConfig
    hardware: HardwareConfig
    rag: RagConfig
    logging: LoggingConfig


# ── Loader ────────────────────────────────────────────────────────────────────

def load_config(config_path: Optional[Path] = None) -> AppConfig:
    """
    Load and validate config.yaml.

    Args:
        config_path: Path to config.yaml. Defaults to <repo_root>/config.yaml.

    Returns:
        Populated AppConfig dataclass.
    """
    path = Path(config_path) if config_path else _DEFAULT_CONFIG_PATH

    if not path.exists():
        raise FileNotFoundError(
            f"Config file not found: {path}\n"
            f"Expected at repo root: {_DEFAULT_CONFIG_PATH}"
        )

    with open(path, "r", encoding="utf-8") as f:
        raw = yaml.safe_load(f)

    # ── Resolve root_dir ──────────────────────────────────────────
    # Priority: config.yaml > ROOT_DIR env var > auto-detected repo root
    raw_root = raw.get("paths", {}).get("root_dir")
    env_root = os.environ.get("ROOT_DIR")

    if raw_root:
        root_dir = Path(raw_root).resolve()
    elif env_root:
        root_dir = Path(env_root).resolve()
    else:
        root_dir = _REPO_ROOT

    logger.debug("Resolved root_dir: %s", root_dir)

    p = raw.get("paths", {})
    paths = PathsConfig(
        root_dir=root_dir,
        docs_dir=root_dir / p.get("docs_dir", "docs"),
        query_dir=root_dir / p.get("query_dir", "docs/query"),
        materials_md_dir=root_dir / p.get("materials_md_dir", "docs/materials_md"),
        results_dir=root_dir / p.get("results_dir", "results"),
        vector_db_dir=root_dir / p.get("vector_db_dir", "vector_db"),
        log_dir=root_dir / p.get("log_dir", "log"),
    )

    m = raw.get("models", {})
    models = ModelsConfig(
        embedding_model=m.get("embedding_model", "BAAI/bge-large-en-v1.5"),
        default_rag_model=m.get("default_rag_model", "qwen2.5:7b"),
        default_story_model=m.get("default_story_model", "qwen2.5:7b"),
        rag_models=m.get("rag_models", []),
        story_models=m.get("story_models", []),
    )

    o = raw.get("ollama", {})
    ollama = OllamaConfig(
        host=o.get("host", "http://127.0.0.1"),
        port=o.get("port", 11434),
        context_size=o.get("context_size", 8192),
        max_loaded_models=o.get("max_loaded_models", 4),
        keep_loaded=o.get("keep_loaded", True),
        precision=o.get("precision", "fp16"),
        batch_size=o.get("batch_size", 32),
        num_threads=o.get("num_threads", 16),
    )

    h = raw.get("hardware", {})
    hardware = HardwareConfig(
        device=h.get("device", "auto"),
        num_cpu_threads=h.get("num_cpu_threads", 8),
        cuda_device_index=h.get("cuda_device_index", 0),
    )

    r = raw.get("rag", {})
    rag = RagConfig(
        top_k=r.get("top_k", 5),
        hybrid_alpha=r.get("hybrid_alpha", 0.5),
        chunk_size=r.get("chunk_size", 512),
        chunk_overlap=r.get("chunk_overlap", 64),
    )

    lc = raw.get("logging", {})
    log_file_raw = lc.get("log_file")
    log_cfg = LoggingConfig(
        level=lc.get("level", "INFO"),
        log_file=root_dir / log_file_raw if log_file_raw else None,
    )

    return AppConfig(
        paths=paths,
        models=models,
        ollama=ollama,
        hardware=hardware,
        rag=rag,
        logging=log_cfg,
    )

