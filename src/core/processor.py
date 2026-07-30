"""
processor.py — Smart Document Processor

Loads Markdown documents, applies semantic chunking, then re-splits
by content type (code / table / normal). URL-only chunks are dropped.

Device (cpu / mps / cuda) is passed in from the caller so this module
works on any hardware without modification.
"""

import re
import logging
from pathlib import Path

from langchain_community.document_loaders import DirectoryLoader, TextLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_experimental.text_splitter import SemanticChunker
from langchain_huggingface import HuggingFaceEmbeddings

logger = logging.getLogger(__name__)

# ── Chunk size constants ───────────────────────────────────────────────────────
_CHUNK_CODE   = (384, 128)   # (chunk_size, chunk_overlap)
_CHUNK_TABLE  = (512, 128)
_CHUNK_NORMAL = (384, 64)

# ── Semantic chunker threshold ────────────────────────────────────────────────
_BREAKPOINT_THRESHOLD = 82


class SmartDocumentProcessor:
    """
    Loads Markdown documents and produces typed, size-bounded chunks
    ready for ingestion into a vector store.

    Processing pipeline:
      1. Load all .md files from docs_dir
      2. Semantic chunking (sentence-transformer embeddings)
      3. Per-chunk content-type detection (code / table / url / normal)
      4. URL chunks dropped; others re-split to target chunk sizes
      5. Metadata enriched with chunk_id and content_type

    Args:
        embedding_model_name: HuggingFace model name for semantic chunking.
        docs_dir:             Path to the directory containing .md files.
                              Defaults to docs/materials_md/parsed/ relative
                              to the repository root.
        device:               Compute device — 'cuda', 'mps', or 'cpu'.
                              Defaults to 'cpu' (safe for all machines).
    """

    def __init__(
        self,
        embedding_model_name: str | None = None,
        docs_dir: str | None = None,
        device: str = "cpu",
    ) -> None:
        self.docs_dir = docs_dir or "docs/materials_md/parsed/"
        self.device = device

        logger.info(
            "Initialising SmartDocumentProcessor | model=%s | device=%s | docs=%s",
            embedding_model_name, device, self.docs_dir,
        )

        self.embed_model = HuggingFaceEmbeddings(
            model_name=embedding_model_name,
            model_kwargs={
                "device": device,
                "trust_remote_code": True,
            },
            encode_kwargs={"batch_size": 16},
        )

    # ── Content-type detection ─────────────────────────────────────────────────

    def _detect_content_type(self, text: str) -> str:
        """
        Classify a text chunk into one of four content types.

        Args:
            text: The chunk's page content.

        Returns:
            One of: 'code', 'table', 'url', 'normal'.
        """
        if re.search(r"\bdef \b|\bimport \b|print\(|\bclass \b", text):
            return "code"
        if (
            re.search(r"\|.+\|", text)
            or re.search(r"<table\b[^>]*>", text)
            or re.search(r"<table.*?>.*?</table>", text, re.DOTALL)
        ):
            return "table"
        if re.search(r"https?://", text):
            return "url"
        return "normal"

    # ── Document loading and chunking ──────────────────────────────────────────

    def process_documents(self) -> list:
        """
        Load documents and return a list of typed, size-bounded chunks.

        Returns:
            List of LangChain Document objects with metadata keys:
            chunk_id, content_type, source.

        Raises:
            FileNotFoundError: If docs_dir does not exist.
        """
        docs_path = Path(self.docs_dir)
        if not docs_path.exists():
            raise FileNotFoundError(
                f"Document directory not found: {docs_path.resolve()}\n"
                "Place your Markdown files in that directory before running."
            )

        # ── Load ───────────────────────────────────────────────────────────────
        loader = DirectoryLoader(
            str(docs_path),
            glob="**/*.md",
            loader_cls=TextLoader,
        )
        documents = loader.load()
        logger.info("Loaded %d document(s) from %s", len(documents), self.docs_dir)

        if not documents:
            logger.warning("No .md files found in %s — returning empty chunk list.", self.docs_dir)
            return []

        # ── Semantic chunking ──────────────────────────────────────────────────
        logger.info("Running semantic chunker (threshold=%d)...", _BREAKPOINT_THRESHOLD)
        chunker = SemanticChunker(
            embeddings=self.embed_model,
            breakpoint_threshold_amount=_BREAKPOINT_THRESHOLD,
            add_start_index=True,
        )
        base_chunks = chunker.split_documents(documents)
        logger.info("Semantic chunker produced %d base chunks.", len(base_chunks))

        # ── Per-type re-splitting ──────────────────────────────────────────────
        final_chunks = []
        skipped_url = 0

        for chunk in base_chunks:
            content_type = self._detect_content_type(chunk.page_content)

            if content_type == "url":
                skipped_url += 1
                continue

            if content_type == "code":
                size, overlap = _CHUNK_CODE
            elif content_type == "table":
                size, overlap = _CHUNK_TABLE
            else:
                size, overlap = _CHUNK_NORMAL

            splitter = RecursiveCharacterTextSplitter(
                chunk_size=size,
                chunk_overlap=overlap,
            )
            final_chunks.extend(splitter.split_documents([chunk]))

        logger.info(
            "Final chunks: %d (skipped %d url-only chunks).",
            len(final_chunks), skipped_url,
        )

        # ── Enrich metadata ────────────────────────────────────────────────────
        for i, chunk in enumerate(final_chunks):
            chunk.metadata.update({
                "chunk_id":    f"chunk_{i}",
                "content_type": self._detect_content_type(chunk.page_content),
            })

        return final_chunks

