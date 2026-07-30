"""
rag.py — Enhanced RAG pipeline.

Combines HybridRetriever (BM25 + vector search) with an Ollama-served
LLM to extract structured knowledge from educational documents.
"""

import logging

from langchain_ollama import ChatOllama

from core.prompts import PromptTemplateManager
from core.processor import SmartDocumentProcessor
from core.retriever import HybridRetriever
from core.utils import contexts_extraction

logger = logging.getLogger(__name__)


class EnhancedRAG:
    """
    RAG pipeline that retrieves relevant document chunks and uses an
    Ollama LLM to extract structured knowledge as JSON.

    Args:
        embedding_model_name: HuggingFace model name for vector embeddings.
        model_name:           Ollama LLM model name, e.g. 'qwen2.5:7b'.
        persist_dir:          Directory for ChromaDB persistence.
        device:               Compute device — 'cuda', 'mps', or 'cpu'.
                              Defaults to 'cpu' (safe for all machines).
        docs_dir:             Path to the directory containing .md files.
                              Defaults to docs/materials_md/parsed/.
    """

    def __init__(
        self,
        embedding_model_name: str | None = None,
        model_name: str | None = None,
        persist_dir: str | None = None,
        device: str = "cpu",
        docs_dir: str | None = None,
    ) -> None:
        logger.info(
            "Initialising EnhancedRAG | model=%s | embeddings=%s | device=%s",
            model_name, embedding_model_name, device,
        )

        self.prompt_manager = PromptTemplateManager()

        # Pass device and docs_dir through to the processor
        processor = SmartDocumentProcessor(
            embedding_model_name=embedding_model_name,
            docs_dir=docs_dir,
            device=device,
        )
        chunks = processor.process_documents()
        logger.info("Document processor produced %d chunks.", len(chunks))

        self.retriever = HybridRetriever(
            chunks,
            embedding_model_name=embedding_model_name,
            persist_dir=persist_dir,
            device=device,
        )

        self.model = ChatOllama(
            model=model_name,
            temperature=0,
            top_p=0.95,
            max_new_tokens=2048,
            format="json",
        )
        logger.info("EnhancedRAG ready.")

    def ask(self, question: str) -> dict:
        """
        Retrieve relevant context and generate a structured JSON answer.

        Args:
            question: The user's question string.

        Returns:
            Parsed dict with keys: Question, Knowledge_Topic,
            Core_Concepts, Overall_Summary, Source_Context.
        """
        logger.debug("Retrieving context for: %s", question)
        contexts = self.retriever.retrieve(question)

        prompt = self.prompt_manager.get_prompt(
            task="rag_extract",
            question=question,
            context="\n\n".join([
                f"[Source: {doc.metadata['source']}, "
                f"Type: {doc.metadata['content_type']}]\n{doc.page_content}"
                for doc in contexts
            ]),
        )

        response = self.model.invoke(prompt)
        answer_text = response.content
        logger.debug("Raw LLM answer: %s", answer_text)

        parsed_data = self.prompt_manager.parse(answer_text)
        logger.debug("Parsed data: %s", parsed_data)

        parsed_data["Source_Context"] = contexts_extraction(contexts)
        return parsed_data

