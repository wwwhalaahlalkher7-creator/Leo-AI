# Offline voice quality evaluation

## Purpose

The evaluator makes ASR quality and device performance measurable without uploading audio. It computes corpus-level word error rate (WER), character error rate (CER), per-language scores, inference/model-load latency percentiles and a process RSS high-watermark summary.

It does **not** run Qwen itself, invent reference transcripts or claim the accuracy of a model. Developers must collect a small, consented, representative set of spoken phrases on the target device, transcribe the exact reference independently, and enter only the reference and Leo's recognized text in a local JSON file.

## Dataset shape

Copy `config/voice_eval_template.json` to a private working location and replace the placeholders. The accepted schema is version 1:

- `metadata`: optional `app_version`, `platform`, `device_class`, `model` and `sample_rate_hz`.
- `samples`: non-empty array of records containing a unique opaque `id`, `language` (`ar`, `en` or `mixed`), `reference` and `hypothesis`.
- Optional non-negative metrics: `inference_ms`, `model_load_ms` and `process_peak_rss_bytes`.

Do not include a person's name, account identifier, contact details, recording path, audio bytes, prompts or conversation messages. The evaluator rejects known audio/path/prompt fields and unsupported fields. Keep the input dataset local; it contains transcript text by design.

## Run

From the repository root:

```bash
python scripts/voice_eval.py \
  --input /path/to/private-voice-evaluation.json \
  --output /path/to/private-voice-evaluation-report.json
```

The report excludes reference and recognized text. It keeps opaque alphanumeric sample IDs with per-sample error counts, aggregate WER/CER and optional latency/memory statistics. Report metadata is strictly allow-listed and constrained to coarse platform/device/model values; arbitrary metadata fields are not copied.

## Metric interpretation

- **WER** = (substitutions + deletions + insertions) / reference words, aggregated across the corpus rather than averaging utterance percentages.
- **CER** uses the same edit-distance formula over normalized non-space characters.
- Arabic normalization removes combining marks/diacritics and tatweel, maps common alef variants to alef and maps alef maqsura to ya. Punctuation is treated as a token boundary; taa marbuta is not rewritten. English is case-folded.
- Inference/model-load p95 uses nearest-rank percentile. Values must come from the same device run; omit fields that were not measured.
- The RSS number is the process high-watermark, not memory attributable only to ASR.

## Minimum evaluation protocol

1. Use the same fixed script of phrases for every device/model run. Include Modern Standard Arabic, Sudanese Arabic only when a native speaker has checked the reference, English and code-switching as separate categories.
2. Include short commands, names only when fictional/test-safe, numbers, punctuation, long sentences and quiet/noisy conditions. Avoid real personal data.
3. Record device class, platform, Leo version, model quantization and Sherpa/ONNX Runtime versions in the test notes; only allow-listed metadata is written to the report.
4. Run each phrase consistently. Do not compare a cold model-load run on one device against warm-only runs on another without labelling the distinction.
5. Report WER/CER and latency distributions by language and device. Do not make a Sudanese-dialect quality claim from a few phrases or from model language support alone.
6. Keep the original dataset under local/private storage. Share only aggregate reports after removing device identifiers if publication is needed.

## Automated checks

```bash
python -m unittest scripts.tests.test_voice_evaluation -v
```

The repository contains no real voice recordings or transcript corpus. Passing the evaluator tests validates the measurement tool, not Leo's recognition accuracy.
