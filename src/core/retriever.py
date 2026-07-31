"""
retriever.py — Hybrid BM25 + vector retriever with cross-encoder reranking.

The device for embeddings and the reranker is passed in explicitly so
this module works on CPU (macOS Intel), MPS (Apple Silicon), and CUDA (GPU).
"""

import logging

import torch
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_community.vectorstores import Chroma
from langchain_community.retrievers import BM25Retriever
from langchain.retrievers import EnsembleRetriever
from sentence_transformers import CrossEncoder

logger = logging.getLogger(__name__)

_RERANKER_MODEL = "BAAI/bge-reranker-v2-m3"


class HybridRetriever:
    """
    Two-stage retriever:
      1. Ensemble of BM25 + ChromaDB vector search (recall stage).
      2. Cross-encoder reranker (precision stage).

    Args:
        chunks:               List of LangChain Document objects.
        embedding_model_name: HuggingFace model name for vector embeddings.
        persist_dir:          ChromaDB persistence directory.
        device:               Compute device — 'cuda', 'mps', or 'cpu'.
                              Defaults to auto-detection via torch.
    """

    def __init__(
        self,
        chunks: list,
        embedding_model_name: str | None = None,
        persist_dir: str = "../../vector_db",
        device: str | None = None,
    ) -> None:
        if device is None:
            device = "cuda" if torch.cuda.is_available() else "cpu"

        logger.info(
            "Initialising HybridRetriever | embeddings=%s | device=%s | chunks=%d",
            embedding_model_name, device, len(chunks),
        )

        self.vector_db = Chroma.from_documents(
            chunks,
            embedding=HuggingFaceEmbeddings(
                model_name=embedding_model_name,
                model_kwargs={
                    "device": device,
                    "trust_remote_code": True,
                },
                encode_kwargs={"batch_size": 16},
            ),
            persist_directory=persist_dir,
        )
        logger.info("ChromaDB vector store built.")

        self.bm25_retriever = BM25Retriever.from_documents(chunks, k=16)
        logger.info("BM25 retriever built.")

        self.ensemble_retriever = EnsembleRetriever(
            retrievers=[
                self.vector_db.as_retriever(search_kwargs={"k": 8}),
                self.bm25_retriever,
            ],
            weights=[0.6, 0.4],
        )

        logger.info("Loading reranker: %s on %s ...", _RERANKER_MODEL, device)
        self.reranker = CrossEncoder(_RERANKER_MODEL, device=device)
        logger.info("HybridRetriever ready.")

    def retrieve(self, query: str, top_k: int = 5) -> list:
        """
        Retrieve and rerank the most relevant document chunks.

        Args:
            query: The search query string.
            top_k: Number of top documents to return after reranking.

        Returns:
            List of LangChain Document objects, ranked by relevance.
        """
        logger.debug("Retrieving for query: %s", query)
        docs = self.ensemble_retriever.get_relevant_documents(query)
        logger.debug("Ensemble retrieved %d docs, reranking to top %d.", len(docs), top_k)

        pairs = [[query, doc.page_content] for doc in docs]
        scores = self.reranker.predict(pairs)
        ranked_docs = sorted(zip(docs, scores), key=lambda x: x[1], reverse=True)

        top_docs = [doc for doc, _ in ranked_docs[:top_k]]
        logger.debug("Reranking complete, returning %d docs.", len(top_docs))
        return top_docs
