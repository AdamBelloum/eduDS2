"""
DataStorytellingEngine.py — Lesson Package Generator

Orchestrates a three-step pipeline to transform structured knowledge
(produced by EnhancedRAG) into a complete, teacher-facing lesson package
in Markdown format:

  Step 1 — Lesson Plan Outline
  Step 2 — Core Concept Story Module  (one per concept)
  Step 3 — Interactive Activity Module (one per concept)
"""

import json
import logging

from langchain_ollama import ChatOllama

from core.prompts import PromptTemplateManager

logger = logging.getLogger(__name__)


class DataStorytellingEngine:
    """
    Generates a structured lesson package from a knowledge base dict.

    Args:
        model_name: Ollama model name to use for generation,
                    e.g. 'qwen2.5:7b'.
    """

    def __init__(self, model_name: str | None = None) -> None:
        self.prompt_manager = PromptTemplateManager()
        self.model = ChatOllama(
            model=model_name,
            temperature=0.7,
            top_p=0.9,
            max_new_tokens=4096,
        )
        logger.info("DataStorytellingEngine initialised | model=%s", model_name)

    def generate_lesson_package(self, knowledge_base: dict) -> str:
        """
        Orchestrate the three-step pipeline to generate a full lesson package.

        Args:
            knowledge_base: Structured knowledge dict produced by EnhancedRAG.
                            Expected keys: Question, Knowledge_Topic,
                            Overall_Summary, Core_Concepts.

        Returns:
            A complete teacher-facing lesson package as a single Markdown string.
            Returns an error message string if Step 1 fails.
        """
        logger.info("Starting Lesson Package Generation Pipeline")
        final_document_parts: list[str] = []

        # ── Step 1: Lesson Plan Outline ────────────────────────────────────────
        logger.info("[Step 1/3] Generating Lesson Plan Outline...")
        try:
            concept_names = [
                concept.get("Concept", "Unnamed Concept")
                for concept in knowledge_base.get("Core_Concepts", [])
            ]
            outline_prompt = self.prompt_manager.get_prompt(
                task="lesson_plan_outline",
                question=knowledge_base.get("Question", "N/A"),
                knowledge_topic=knowledge_base.get("Knowledge_Topic", "N/A"),
                overall_summary=knowledge_base.get("Overall_Summary", "N/A"),
                concept_names_list=", ".join(concept_names),
            )
            response = self.model.invoke(outline_prompt)
            final_document_parts.append(response.content)
            logger.info("[Step 1/3] Lesson Plan Outline created.")

        except Exception as e:
            logger.exception("[Step 1/3] Failed to create Lesson Plan Outline: %s", e)
            return "Error: Failed to create the lesson plan outline."

        # ── Steps 2 & 3: Per-concept Story and Activity modules ────────────────
        core_concepts = knowledge_base.get("Core_Concepts", [])
        n = len(core_concepts)
        logger.info("[Steps 2&3] Generating modules for %d concept(s)...", n)

        if not core_concepts:
            logger.warning("No core concepts found in the knowledge base.")

        for i, concept in enumerate(core_concepts):
            concept_name = concept.get("Concept", f"Concept {i + 1}")
            logger.info("Processing concept %d/%d: %s", i + 1, n, concept_name)

            # ── Step 2: Story Module ───────────────────────────────────────────
            try:
                logger.debug("Generating story module for '%s'...", concept_name)
                story_prompt = self.prompt_manager.get_prompt(
                    task="core_concept_story",
                    core_concept_json=json.dumps(concept, indent=2),
                    concept_name=concept_name,
                )
                response = self.model.invoke(story_prompt)
                final_document_parts.append(
                    f"\n\n---\n\n## Teaching Module: {concept_name}"
                )
                final_document_parts.append(response.content)
                logger.info("Story module created for '%s'.", concept_name)

            except Exception as e:
                logger.exception(
                    "Failed to generate story module for '%s': %s", concept_name, e
                )
                final_document_parts.append(
                    f"\n\n> *Error: Could not generate story module for {concept_name}.*"
                )

            # ── Step 3: Activity Module ────────────────────────────────────────
            try:
                logger.debug("Generating activity module for '%s'...", concept_name)
                activity_prompt = self.prompt_manager.get_prompt(
                    task="activity_discussion",
                    concept_name=concept_name,
                    strengths=concept.get("Strengths", "N/A"),
                    weaknesses=concept.get("Weaknesses", "N/A"),
                )
                response = self.model.invoke(activity_prompt)
                final_document_parts.append(
                    f"\n### Interactive Activities for {concept_name}"
                )
                final_document_parts.append(response.content)
                logger.info("Activity module created for '%s'.", concept_name)

            except Exception as e:
                logger.exception(
                    "Failed to generate activity module for '%s': %s", concept_name, e
                )
                final_document_parts.append(
                    f"\n\n> *Error: Could not generate activities for {concept_name}.*"
                )

        logger.info("Lesson Package Generation complete. %d part(s) assembled.", len(final_document_parts))
        return "\n".join(final_document_parts)

