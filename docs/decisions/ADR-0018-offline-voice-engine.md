# ADR-0018: Offline voice runtime and optional model packs

- Status: Accepted for Alpha v0.13.0
- Date: 2026-11-16

## Context

Leo needs offline Arabic/English voice input and output on Android and Windows without embedding multi-hundred-megabyte model weights in its installer.

## Decision

Use sherpa-onnx 2.0.1 for local ASR/TTS; use Qwen3-ASR 0.6B INT8 for multilingual transcription and Supertonic 3 INT8 for speech synthesis. Capture with `record` and play generated audio with `audioplayers`. Store models in app-private support storage and let users import extracted files from the upstream releases.

## Permission decision

Microphone access is requested only when the user presses the mic button. Leo consent and OS permission remain independent. Android uses the OS runtime permission. Windows displays the OS microphone privacy page on first use and relies on Windows to enforce access at actual capture; the selected recorder plugin does not offer a Windows permission-query API.

## Consequences

- Small base installer; models are optional and separately downloaded/imported.
- The feature is offline after model import.
- Qwen3-ASR pack is about 0.94 GB; low-memory phones may be slow or unsuitable.
- Push-to-talk is used, capped at 30 seconds. ASR is post-capture, and TTS produces a complete WAV before playback.
- No wake word, continuous background capture or partial ASR/TTS stream is claimed in this release.
- Model origin is not cryptographically verified by the import screen; upstream source and licensing must be respected.
