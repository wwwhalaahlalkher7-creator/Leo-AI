#!/usr/bin/env python3
"""Evaluate offline ASR transcripts locally using corpus WER/CER and latency stats.

Input contains text transcripts only; no audio is read or uploaded. Reports omit
reference/hypothesis text and retain only aggregate scores plus opaque sample IDs.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
ALLOWED_SAMPLE_KEYS = {
    "id", "language", "reference", "hypothesis", "inference_ms",
    "model_load_ms", "process_peak_rss_bytes",
}
FORBIDDEN_SAMPLE_KEYS = {
    "audio", "audio_path", "recording_path", "file_path", "prompt",
    "messages", "raw_audio", "waveform",
}
ARABIC_DIACRITICS = {"\u0670"}


def normalize_transcript(value: str) -> str:
    """Normalize Arabic/English text for robust, reproducible scoring."""
    value = unicodedata.normalize("NFKC", value).casefold()
    value = value.replace("\u0640", "")  # tatweel
    value = value.translate(str.maketrans({
        "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا", "ى": "ي",
    }))
    chars: list[str] = []
    for char in value:
        category = unicodedata.category(char)
        if category.startswith("M") or char in ARABIC_DIACRITICS:
            continue
        if category.startswith("P"):
            chars.append(" ")
        else:
            chars.append(char)
    return re.sub(r"\s+", " ", "".join(chars)).strip()


def edit_distance(reference: list[str], hypothesis: list[str]) -> int:
    """Levenshtein distance with O(min(n, m)) memory."""
    if len(reference) < len(hypothesis):
        reference, hypothesis = hypothesis, reference
    previous = list(range(len(hypothesis) + 1))
    for row_index, ref_token in enumerate(reference, start=1):
        current = [row_index]
        for column_index, hyp_token in enumerate(hypothesis, start=1):
            substitution = previous[column_index - 1] + (ref_token != hyp_token)
            insertion = current[column_index - 1] + 1
            deletion = previous[column_index] + 1
            current.append(min(substitution, insertion, deletion))
        previous = current
    return previous[-1]


def _number(sample: dict[str, Any], field: str, sample_id: str) -> int | None:
    value = sample.get(field)
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"Sample '{sample_id}': {field} must be a non-negative number.")
    if not math.isfinite(float(value)) or value < 0:
        raise ValueError(f"Sample '{sample_id}': {field} must be a non-negative number.")
    return int(value)


def _percentile(values: list[int], percentile: float) -> int | None:
    if not values:
        return None
    ordered = sorted(values)
    index = max(0, math.ceil(percentile * len(ordered)) - 1)
    return ordered[index]


def _score_group(samples: list[dict[str, Any]]) -> dict[str, Any]:
    total_word_errors = total_reference_words = 0
    total_char_errors = total_reference_chars = 0
    inference: list[int] = []
    load: list[int] = []
    memory: list[int] = []
    details: list[dict[str, Any]] = []

    for sample in samples:
        reference = normalize_transcript(sample["reference"])
        hypothesis = normalize_transcript(sample["hypothesis"])
        ref_words = reference.split() if reference else []
        hyp_words = hypothesis.split() if hypothesis else []
        ref_chars = list(reference.replace(" ", ""))
        hyp_chars = list(hypothesis.replace(" ", ""))
        if not ref_words or not ref_chars:
            raise ValueError(
                f"Sample '{sample['id']}': reference becomes empty after normalization."
            )
        word_errors = edit_distance(ref_words, hyp_words)
        char_errors = edit_distance(ref_chars, hyp_chars)
        total_word_errors += word_errors
        total_reference_words += len(ref_words)
        total_char_errors += char_errors
        total_reference_chars += len(ref_chars)

        inference_ms = _number(sample, "inference_ms", sample["id"])
        model_load_ms = _number(sample, "model_load_ms", sample["id"])
        peak_rss = _number(sample, "process_peak_rss_bytes", sample["id"])
        if inference_ms is not None:
            inference.append(inference_ms)
        if model_load_ms is not None:
            load.append(model_load_ms)
        if peak_rss is not None:
            memory.append(peak_rss)
        details.append({
            "id": sample["id"],
            "language": sample["language"],
            "word_errors": word_errors,
            "reference_words": len(ref_words),
            "wer": word_errors / len(ref_words),
            "character_errors": char_errors,
            "reference_characters": len(ref_chars),
            "cer": char_errors / len(ref_chars),
        })

    return {
        "sample_count": len(samples),
        "word_errors": total_word_errors,
        "reference_words": total_reference_words,
        "wer": total_word_errors / total_reference_words if total_reference_words else None,
        "character_errors": total_char_errors,
        "reference_characters": total_reference_chars,
        "cer": total_char_errors / total_reference_chars if total_reference_chars else None,
        "inference_ms": {
            "count": len(inference),
            "median": int(statistics.median(inference)) if inference else None,
            "p95": _percentile(inference, 0.95),
        },
        "model_load_ms": {
            "count": len(load),
            "median": int(statistics.median(load)) if load else None,
            "p95": _percentile(load, 0.95),
        },
        "process_peak_rss_bytes_max": max(memory) if memory else None,
        "samples": details,
    }


def evaluate_dataset(dataset: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(dataset, dict) or dataset.get("schema_version") != 1:
        raise ValueError("Input must be a JSON object with schema_version: 1.")
    samples = dataset.get("samples")
    if not isinstance(samples, list) or not samples:
        raise ValueError("Input must contain a non-empty 'samples' array.")

    seen: set[str] = set()
    normalized_samples: list[dict[str, Any]] = []
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            raise ValueError(f"Sample at index {index} must be an object.")
        forbidden = FORBIDDEN_SAMPLE_KEYS.intersection(sample)
        if forbidden:
            raise ValueError(
                f"Sample at index {index} contains disallowed fields: {', '.join(sorted(forbidden))}."
            )
        unknown = set(sample) - ALLOWED_SAMPLE_KEYS
        if unknown:
            raise ValueError(
                f"Sample at index {index} contains unsupported fields: {', '.join(sorted(unknown))}."
            )
        sample_id = sample.get("id")
        language = sample.get("language")
        reference = sample.get("reference")
        hypothesis = sample.get("hypothesis")
        if not isinstance(sample_id, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", sample_id):
            raise ValueError(f"Sample at index {index} must have an opaque alphanumeric id (max 64 chars).")
        if sample_id in seen:
            raise ValueError(f"Duplicate sample id: {sample_id}.")
        seen.add(sample_id)
        if not isinstance(language, str) or language not in {"ar", "en", "mixed"}:
            raise ValueError(f"Sample '{sample_id}': language must be ar, en, or mixed.")
        if not isinstance(reference, str) or not isinstance(hypothesis, str):
            raise ValueError(f"Sample '{sample_id}': reference and hypothesis must be strings.")
        if len(reference) > 10000 or len(hypothesis) > 10000:
            raise ValueError(f"Sample '{sample_id}': transcript fields exceed 10,000 characters.")
        normalized_samples.append(sample)

    by_language: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for sample in normalized_samples:
        by_language[sample["language"]].append(sample)

    metadata = dataset.get("metadata", {})
    if not isinstance(metadata, dict):
        raise ValueError("metadata must be an object when present.")
    forbidden_metadata = FORBIDDEN_SAMPLE_KEYS.intersection(metadata)
    if forbidden_metadata:
        raise ValueError(
            f"metadata contains disallowed fields: {', '.join(sorted(forbidden_metadata))}."
        )
    safe_metadata: dict[str, str | int] = {}
    app_version = metadata.get("app_version")
    if isinstance(app_version, str) and re.fullmatch(r"v\d+\.\d+\.\d+", app_version):
        safe_metadata["app_version"] = app_version
    platform = metadata.get("platform")
    if isinstance(platform, str) and platform in {"android", "windows"}:
        safe_metadata["platform"] = platform
    device_class = metadata.get("device_class")
    if isinstance(device_class, str) and device_class in {"low", "mid", "high", "windows-desktop", "other"}:
        safe_metadata["device_class"] = device_class
    model = metadata.get("model")
    if isinstance(model, str) and re.fullmatch(r"[A-Za-z0-9._-]{1,64}", model):
        safe_metadata["model"] = model
    sample_rate = metadata.get("sample_rate_hz")
    if isinstance(sample_rate, int) and not isinstance(sample_rate, bool) and 8000 <= sample_rate <= 192000:
        safe_metadata["sample_rate_hz"] = sample_rate
    return {
        "schema_version": 1,
        "metadata": safe_metadata,
        "overall": _score_group(normalized_samples),
        "by_language": {
            language: _score_group(group)
            for language, group in sorted(by_language.items())
        },
        "privacy": {
            "transcripts_included": False,
            "audio_included": False,
            "note": "Only opaque sample IDs and aggregate error/latency metrics are retained.",
        },
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path, help="Local ASR evaluation JSON file")
    parser.add_argument("--output", required=True, type=Path, help="Report JSON output path")
    args = parser.parse_args(argv)
    try:
        dataset = json.loads(args.input.read_text(encoding="utf-8"))
        report = evaluate_dataset(dataset)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    overall = report["overall"]
    print(
        f"PASS: {overall['sample_count']} samples; "
        f"WER={overall['wer']:.3f}; CER={overall['cer']:.3f}; "
        f"report={args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
