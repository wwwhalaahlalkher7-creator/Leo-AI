# ADR-0019 — Voice-pack integrity baseline and portable WAV output

- Status: Accepted for Alpha v0.14.0
- Date: 2026-11-16

## Context

Alpha v0.13.0 imported large ONNX model packs using bounded streaming and staged replacement, but it only checked required filenames, non-zero sizes and total byte limits. A file could be changed after import without Leo noticing. The TTS worker also delegated WAV writing to the sherpa native helper, coupling temporary audio-file writing to native path behavior. Concurrent TTS requests shared one playback completer, which allowed a stale request's `finally` block to complete a newer playback.

## Decision

1. During import, calculate SHA-256 incrementally from the same byte stream being copied; do not buffer model files in memory.
2. Store per-file relative path, copied byte count and SHA-256 in a versioned `.leo-voice-pack.json` manifest in app-private storage.
3. Preserve complete legacy packs without a manifest as `legacyUnverified`; do not force a multi-gigabyte re-import just to upgrade the UI. A user can explicitly create a local hash baseline.
4. Add an explicit integrity audit that re-reads installed files and compares their SHA-256 values to the local manifest. Mismatch marks the pack failed and prevents runtime use until re-import.
5. Clearly state that a local hash baseline does not prove publisher identity or compare against official upstream checksums.
6. Encode mono PCM16 WAV using pure Dart so file output is independent of native helper path handling.
7. Make audio-player creation lazy, and scope playback completion to a generation identifier so stale synthesis cleanup cannot complete a newer request.

## Consequences

- Import and manual re-verification perform sequential streaming I/O without holding whole model files in memory.
- Re-verifying the approximately 0.94 GB Qwen pack can take time and produce substantial disk I/O; it is user-triggered, never performed on every chat message.
- A generated baseline records the current bytes as the reference point; it is not proof the selected files are authentic or safe.
- Older complete packs continue to work as unverified until the user chooses to create a baseline.
- A user who modifies a model file after verification must re-run the audit to detect same-size changes.
- WAV conversion adds a small predictable Dart CPU pass and removes a native path-writing dependency.
