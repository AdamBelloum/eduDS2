"""
utils.py — Shared utility functions.

Covers JSON extraction/reconstruction from LLM responses,
document context formatting, and base64 image encoding.
"""

import re
import json
import base64
import logging
from typing import Any

logger = logging.getLogger(__name__)


def extract_json_from_llm(response_text: str) -> str | None:
    """
    Extract a JSON string from raw LLM output.

    Tries (in order):
      1. Fenced code block: ```json ... ```
      2. First '{' to last '}' in the response.
      3. The full response text as-is.

    Args:
        response_text: Raw string output from the LLM.

    Returns:
        A JSON string, or None if extraction fails.
    """
    json_str_to_parse: str | None = None

    # 1. Fenced code block
    match = re.search(r"```(?:json)?\s*(\{[\s\S]*?\})\s*```", response_text, re.DOTALL)
    if match:
        json_str_to_parse = match.group(1).strip()

    # 2. Brace scan
    if not json_str_to_parse:
        first = response_text.find("{")
        last = response_text.rfind("}")
        if first != -1 and last != -1 and last > first:
            json_str_to_parse = response_text[first : last + 1].strip()
        else:
            json_str_to_parse = response_text.strip()

    try:
        json.loads(json_str_to_parse)   # validate — raises if invalid
        return json_str_to_parse
    except (json.JSONDecodeError, TypeError) as e:
        snippet = (json_str_to_parse or "")[:120]
        logger.error("extract_json_from_llm: JSONDecodeError: %s | snippet: %s", e, snippet)
        return None


def reconstruct_core_concepts(raw_concepts: list) -> list:
    """
    Normalise a list of raw concept dicts into a consistent schema.

    Args:
        raw_concepts: List of dicts from the LLM's parsed output.

    Returns:
        List of normalised concept dicts.
    """
    reconstructed = []
    for idx, item in enumerate(raw_concepts):
        if not isinstance(item, dict):
            logger.warning("Skipping invalid concept at index %d (not a dict).", idx)
            continue

        key_points = item.get("Key_Points", [])
        if not isinstance(key_points, list) or not all(isinstance(k, str) for k in key_points):
            logger.warning("Resetting Key_Points at index %d — expected list of strings.", idx)
            key_points = []

        concept = item.get("Concept", "")
        definition = item.get("Definition", "")

        if not isinstance(concept, str):
            logger.warning("Concept at index %d is not a string — resetting.", idx)
            concept = ""
        if not isinstance(definition, str):
            logger.warning("Definition at index %d is not a string — resetting.", idx)
            definition = ""

        reconstructed.append({
            "Concept":            concept,
            "Definition":         definition,
            "Key_Points":         key_points,
            "Significance_Detail": item.get("Significance_Detail"),
            "Strengths":          item.get("Strengths"),
            "Weaknesses":         item.get("Weaknesses"),
        })

    return reconstructed


def reconstruct_specific_json(
    parsed_data: dict | None,
    indent_level: int = 4,
) -> tuple[dict, str]:
    """
    Rebuild a canonical output dict from parsed LLM data and serialise to JSON.

    Args:
        parsed_data:  Dict from the LLM parser (may be None or partial).
        indent_level: JSON indentation level.

    Returns:
        Tuple of (output_dict, json_string).
    """
    logger.debug("Reconstructing output JSON...")

    output_data: dict[str, Any] = {
        "Question":       "",
        "Knowledge_Topic": "",
        "Core_Concepts":  [],
        "Overall_Summary": "",
        "Source_Context": [],
    }

    if isinstance(parsed_data, dict):
        output_data["Question"]        = parsed_data.get("Question") or None
        output_data["Knowledge_Topic"] = parsed_data.get("Knowledge_Topic") or None
        output_data["Overall_Summary"] = parsed_data.get("Overall_Summary") or None

        core_concepts = parsed_data.get("Core_Concepts")
        if isinstance(core_concepts, list):
            output_data["Core_Concepts"] = reconstruct_core_concepts(core_concepts)

        source_context = parsed_data.get("Source_Context")
        if isinstance(source_context, list):
            output_data["Source_Context"] = source_context
    else:
        logger.warning("reconstruct_specific_json received non-dict input: %s", type(parsed_data))

    return output_data, json.dumps(output_data, ensure_ascii=False, indent=indent_level)


def sanitize_json_string(json_str: str) -> str:
    """
    Fix unescaped backslashes in a JSON string that would cause parse errors.

    Args:
        json_str: Potentially malformed JSON string.

    Returns:
        Sanitised JSON string.
    """
    return re.sub(r'\\(?!["\\/bfnrtu])', r"\\\\", json_str)


def encode_image_to_base64(image_path: str) -> str:
    """
    Read an image file and return its Base64-encoded string.

    Args:
        image_path: Path to the image file.

    Returns:
        Base64-encoded string of the image bytes.
    """
    with open(image_path, "rb") as img_file:
        return base64.b64encode(img_file.read()).decode("utf-8")


def contexts_extraction(docs: list) -> list[dict]:
    """
    Convert a list of LangChain Documents into serialisable dicts.

    Args:
        docs: List of LangChain Document objects.

    Returns:
        List of dicts with keys: source, content_type, page_content.
    """
    return [
        {
            "source":       doc.metadata["source"],
            "content_type": doc.metadata["content_type"],
            "page_content": doc.page_content,
        }
        for doc in docs
    ]

