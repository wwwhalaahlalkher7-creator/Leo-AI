"""Formatting-independent matching for contract tests that inspect Dart source.

`dart format` reflows long expressions, adds trailing commas and moves arguments
onto separate lines. The contract tests care about the code's meaning, not its
layout, so both the expected snippet and the source are flattened identically
before comparison.
"""
from __future__ import annotations

import re


def flat(text: str) -> str:
    """Collapse layout so equivalent Dart code compares equal after formatting."""
    value = re.sub(r"\s+", " ", text)
    value = re.sub(r"([(\[{]) ", r"\1", value)  # space after an opening bracket
    value = re.sub(r" ([)\]}])", r"\1", value)  # space before a closing bracket
    value = re.sub(r",([)\]}])", r"\1", value)  # trailing comma before a closer
    return value.strip()
