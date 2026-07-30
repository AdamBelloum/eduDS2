"""
conftest.py — Shared pytest configuration.

Adds src/ to sys.path so tests can import core modules
without needing pip install -e .
"""

import sys
from pathlib import Path

# src/ directory
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

