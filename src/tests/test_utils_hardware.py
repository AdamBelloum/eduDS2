"""
test_utils.py — Unit tests for core/utils.py

Tests pure logic only — no LLM, no GPU, no file I/O required.
Run with:  pytest src/tests/test_utils.py -v
"""

import json
import pytest
import sys
from pathlib import Path

# Ensure src/ is on the path when running from repo root
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from core.utils import (
    extract_json_from_llm,
    reconstruct_core_concepts,
    reconstruct_specific_json,
    sanitize_json_string,
    contexts_extraction,
)


# ── extract_json_from_llm ─────────────────────────────────────────────────────

class TestExtractJsonFromLlm:

    def test_fenced_json_block(self):
        text = '```json\n{"key": "value"}\n```'
        result = extract_json_from_llm(text)
        assert result is not None
        assert json.loads(result) == {"key": "value"}

    def test_fenced_block_no_language_tag(self):
        text = '```\n{"key": "value"}\n```'
        result = extract_json_from_llm(text)
        assert result is not None
        assert json.loads(result) == {"key": "value"}

    def test_bare_json_in_text(self):
        text = 'Here is the answer: {"Question": "What is X?", "Answer": "Y"} end.'
        result = extract_json_from_llm(text)
        assert result is not None
        parsed = json.loads(result)
        assert parsed["Question"] == "What is X?"

    def test_plain_json_string(self):
        text = '{"a": 1, "b": [1, 2, 3]}'
        result = extract_json_from_llm(text)
        assert result is not None
        assert json.loads(result)["b"] == [1, 2, 3]

    def test_invalid_json_returns_none(self):
        text = "This is not JSON at all."
        result = extract_json_from_llm(text)
        assert result is None

    def test_empty_string_returns_none(self):
        result = extract_json_from_llm("")
        assert result is None


# ── reconstruct_core_concepts ─────────────────────────────────────────────────

class TestReconstructCoreConcepts:

    def _make_concept(self, **overrides):
        base = {
            "Concept": "Pipelining",
            "Definition": "A technique to overlap instruction execution.",
            "Key_Points": ["Increases throughput", "Reduces idle time"],
            "Significance_Detail": "Critical for modern CPUs.",
            "Strengths": "Improves IPC.",
            "Weaknesses": "Hazards can stall the pipeline.",
        }
        base.update(overrides)
        return base

    def test_valid_concept_passes_through(self):
        concepts = [self._make_concept()]
        result = reconstruct_core_concepts(concepts)
        assert len(result) == 1
        assert result[0]["Concept"] == "Pipelining"
        assert result[0]["Key_Points"] == ["Increases throughput", "Reduces idle time"]

    def test_non_dict_item_is_skipped(self):
        concepts = ["not a dict", self._make_concept()]
        result = reconstruct_core_concepts(concepts)
        assert len(result) == 1
        assert result[0]["Concept"] == "Pipelining"

    def test_invalid_key_points_reset_to_empty(self):
        concept = self._make_concept(Key_Points=["valid", 42])  # 42 is not a str
        result = reconstruct_core_concepts([concept])
        assert result[0]["Key_Points"] == []

    def test_non_string_concept_reset_to_empty(self):
        concept = self._make_concept(Concept=123)
        result = reconstruct_core_concepts([concept])
        assert result[0]["Concept"] == ""

    def test_non_string_definition_reset_to_empty(self):
        concept = self._make_concept(Definition=None)
        result = reconstruct_core_concepts([concept])
        assert result[0]["Definition"] == ""

    def test_optional_fields_preserved_as_none(self):
        concept = self._make_concept(Strengths=None, Weaknesses=None)
        result = reconstruct_core_concepts([concept])
        assert result[0]["Strengths"] is None
        assert result[0]["Weaknesses"] is None

    def test_empty_list_returns_empty(self):
        assert reconstruct_core_concepts([]) == []

    def test_multiple_concepts(self):
        concepts = [self._make_concept(Concept=f"C{i}") for i in range(3)]
        result = reconstruct_core_concepts(concepts)
        assert len(result) == 3
        assert [r["Concept"] for r in result] == ["C0", "C1", "C2"]


# ── reconstruct_specific_json ─────────────────────────────────────────────────

class TestReconstructSpecificJson:

    def _full_parsed(self):
        return {
            "Question": "What is pipelining?",
            "Knowledge_Topic": "Computer Architecture",
            "Core_Concepts": [
                {
                    "Concept": "Pipelining",
                    "Definition": "Overlapping instruction execution.",
                    "Key_Points": ["Increases throughput"],
                    "Significance_Detail": "Key for performance.",
                    "Strengths": "Better IPC.",
                    "Weaknesses": "Hazards.",
                }
            ],
            "Overall_Summary": "Pipelining improves CPU throughput.",
            "Source_Context": [{"source": "doc1.md", "content_type": "normal", "page_content": "..."}],
        }

    def test_returns_tuple_of_dict_and_string(self):
        output_dict, json_str = reconstruct_specific_json(self._full_parsed())
        assert isinstance(output_dict, dict)
        assert isinstance(json_str, str)

    def test_json_string_is_valid(self):
        _, json_str = reconstruct_specific_json(self._full_parsed())
        parsed = json.loads(json_str)
        assert parsed["Question"] == "What is pipelining?"

    def test_all_expected_keys_present(self):
        output_dict, _ = reconstruct_specific_json(self._full_parsed())
        for key in ("Question", "Knowledge_Topic", "Core_Concepts", "Overall_Summary", "Source_Context"):
            assert key in output_dict

    def test_none_input_returns_empty_structure(self):
        output_dict, json_str = reconstruct_specific_json(None)
        assert output_dict["Core_Concepts"] == []
        assert output_dict["Source_Context"] == []
        assert json.loads(json_str) is not None

    def test_empty_dict_input(self):
        output_dict, _ = reconstruct_specific_json({})
        assert output_dict["Question"] is None
        assert output_dict["Core_Concepts"] == []

    def test_core_concepts_normalised(self):
        parsed = self._full_parsed()
        parsed["Core_Concepts"][0]["Concept"] = 999  # invalid
        output_dict, _ = reconstruct_specific_json(parsed)
        assert output_dict["Core_Concepts"][0]["Concept"] == ""

    def test_source_context_preserved(self):
        output_dict, _ = reconstruct_specific_json(self._full_parsed())
        assert len(output_dict["Source_Context"]) == 1
        assert output_dict["Source_Context"][0]["source"] == "doc1.md"

    def test_custom_indent_level(self):
        _, json_str = reconstruct_specific_json(self._full_parsed(), indent_level=2)
        # 2-space indent means lines start with "  " not "    "
        assert '  "Question"' in json_str


# ── sanitize_json_string ──────────────────────────────────────────────────────

class TestSanitizeJsonString:

    def test_valid_json_unchanged(self):
        s = '{"key": "value with \\"quotes\\""}'
        result = sanitize_json_string(s)
        # valid escape sequences should not be doubled
        assert '\\"' in result

    def test_bare_backslash_escaped(self):
        s = '{"path": "C:\\Users\\adam"}'
        result = sanitize_json_string(s)
        # bare \U and \a are invalid JSON escapes — should be escaped
        assert result.count("\\\\") >= 1

    def test_newline_escape_preserved(self):
        s = '{"text": "line1\\nline2"}'
        result = sanitize_json_string(s)
        assert "\\n" in result


# ── contexts_extraction ───────────────────────────────────────────────────────

class TestContextsExtraction:

    class _FakeDoc:
        def __init__(self, content, source, content_type):
            self.page_content = content
            self.metadata = {"source": source, "content_type": content_type}

    def test_basic_extraction(self):
        docs = [
            self._FakeDoc("text1", "doc1.md", "normal"),
            self._FakeDoc("text2", "doc2.md", "code"),
        ]
        result = contexts_extraction(docs)
        assert len(result) == 2
        assert result[0] == {"source": "doc1.md", "content_type": "normal", "page_content": "text1"}
        assert result[1]["content_type"] == "code"

    def test_empty_list(self):
        assert contexts_extraction([]) == []

    def test_output_is_list_of_dicts(self):
        docs = [self._FakeDoc("x", "f.md", "normal")]
        result = contexts_extraction(docs)
        assert isinstance(result, list)
        assert isinstance(result[0], dict)
        assert set(result[0].keys()) == {"source", "content_type", "page_content"}

