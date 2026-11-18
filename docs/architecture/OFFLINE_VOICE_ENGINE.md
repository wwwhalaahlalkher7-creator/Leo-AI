# Leo Offline Voice Engine — Alpha 0.17.0

## Scope

The first voice foundation provides manual push-to-talk capture, offline transcription, local speech synthesis and local playback on Android and Windows. It is intentionally not an always-listening assistant.

## Runtime components

- `sherpa_onnx: 2.0.1`: offline ASR/TTS runtime with Flutter bindings for Android and Windows.
- `record: 7.2.0`: microphone capture as 16 kHz mono PCM16 stream.
- `audioplayers: 6.8.1`: local playback of generated WAV files.
- `VoicePackStore`: validates required filenames and non-zero file lengths, imports via bounded streaming into app-private storage, computes per-file SHA-256 during import, writes a versioned local manifest, stages a complete pack, then atomically swaps it into place with rollback. A manual re-check hashes the installed files and detects changes against the local manifest.
- `LeoVoiceService`: captures up to 30 seconds, optionally feeds fixed 512-sample windows into Silero VAD, performs Qwen3-ASR decoding in a worker isolate, and creates Supertonic-3 WAV output in a worker isolate. Playback generation identifiers prevent an older synthesis from completing a newer playback request; the player is initialized only when TTS is first used. A pure-Dart PCM16 WAV writer avoids platform-native path-encoding differences. If VAD is absent or fails, manual stop remains available.

## Models

### ASR — Qwen3-ASR 0.6B INT8

Required files: `conv_frontend.onnx`, `encoder.int8.onnx`, `decoder.int8.onnx`, `tokenizer/merges.txt`, `tokenizer/tokenizer_config.json`, `tokenizer/vocab.json`. The recognizer uses a 16 kHz sample rate and 128-dimensional feature configuration. Model pack size is approximately 0.94 GB using the documented model file sizes; the base Leo installer does not contain these weights. The upstream model list includes Arabic, English and 28 other languages; Leo advertises the full list in its model catalog, but the current TTS language selector only chooses Arabic or English.

### TTS — Supertonic 3 INT8

Required files: `duration_predictor.int8.onnx`, `text_encoder.int8.onnx`, `vector_estimator.int8.onnx`, `vocoder.int8.onnx`, `tts.json`, `unicode_indexer.bin`, `voice.bin`. The model supports 31 languages, while this Leo build enables only Arabic and English. The service detects Arabic characters and chooses `ar`; otherwise it uses `en`. Mixed-language and other-language speech is therefore currently treated as Arabic if any Arabic character is present, or English otherwise. Speaker ID 0 is selected, matching the upstream Supertonic example configuration. Audio is synthesized into a temporary WAV then played locally.

### VAD — Silero VAD ONNX

Required file: `silero_vad.onnx`. The official sherpa-onnx model listing describes the standard model as approximately 629 KB and 16 kHz-only; an 8-bit alternative is also listed upstream, but Leo currently imports the standard filename. The model is separately user-imported, stored in app-private voice-pack storage and is not bundled. VAD is opt-in. The current endpointing settings use a 512-sample window, a 0.8-second minimum silence duration, a 0.25-second minimum speech duration and a 30-second maximum speech duration. A completed VAD segment requests the same existing stop-and-transcribe flow; it does not replace the captured PCM sent to ASR.

## Data and network boundaries

- Audio capture and model inference are local; no audio is uploaded by this implementation.
- Imported model files live under the app's private application-support folder.
- Model weights are not bundled or silently downloaded. The user opens upstream download/documentation pages via the existing external-link permission/approval flow and imports extracted files through the system picker. Qwen ASR uses two picker rounds because its three ONNX files are in the model root and its tokenizer files are in the nested `tokenizer/` directory.
- Import checks filenames, sizes, non-empty files, aggregate size and complete pack structure, while hashing each streamed file into `.leo-voice-pack.json`. A manual SHA-256 audit re-reads the installed pack and marks mismatched files as failed. This is a local SHA-256 integrity baseline only: it detects changes relative to bytes already imported into Leo; it does not authenticate the publisher, validate a publisher signature, or compare against official upstream checksums. Users must use upstream sources. Legacy packs without a manifest remain usable as unverified until the user creates a local baseline.
- ASR text is inserted into the chat composer. It is not sent automatically.
- TTS strips code blocks and mathematical delimiters to avoid reading raw markup. It is capped at 3,000 input characters.

## Permissions

- No microphone permission is requested at install/startup.
- Android: first user microphone action opens Leo's own explanation/consent; only after acceptance does Leo request Android `RECORD_AUDIO` permission. Capture checks the plugin permission again.
- Windows: the `record` permission-check API does not implement a Windows runtime permission query. First use records Leo consent and opens `ms-settings:privacy-microphone`; the user enables microphone access and desktop-app access. The OS then enforces actual Media Foundation capture. Leo does not report Windows OS permission as independently verified.
- Recording is visible in the chat composer and is automatically stopped after 30 seconds; the local sample buffer also enforces the same hard cap. When the user enables VAD and the VAD pack is valid, detected silence may end a recording sooner. Manual stop remains available. A VAD load/runtime failure falls back to manual stop. Any non-resumed app lifecycle state cancels active microphone capture and stops playback. No background microphone service or wake word is present.

## Alpha 0.15.0 voice endpointing and diagnostics

- Qwen3-ASR runs after stop; partial live transcripts are not emitted.
- Supertonic synthesis is not streamed; a full temporary PCM16 WAV is generated before playback. A generation-scoped playback completer prevents an older synthesis from completing a newer playback request. WAV encoding is implemented in Dart rather than delegated to the native writeWave helper.
- Arabic and English are model-supported, but accuracy, Sudanese dialect recognition, latency, memory, thermal and battery behavior must be validated on actual hardware. The current app language heuristic selects only `ar` or `en`; additional supported TTS languages are not yet selectable from the UI.
- Windows CMake runner preparation sets minimum CMake 3.15 and CMP0091-compatible policy range for the audioplayers Windows package.
- Flutter/Dart/Rust/native compilation is delegated to CI because these SDKs are not installed in the current workspace environment.


### Integrity states

- `legacyUnverified`: complete pre-manifest pack; it remains usable, but Leo cannot compare its contents to a prior local baseline.
- `baseline`: SHA-256 digests were captured during import or generated once for a legacy pack.
- `verified`: an explicit user-triggered re-check found all current file digests matched the local manifest.
- `failed`: a digest or recorded file size mismatched; the pack is disabled until re-imported.

The manifest is stored with the model pack and is not a signed provenance statement. It is not a cryptographic certificate from the upstream publisher.


## Runtime diagnostics and measurements

- The voice-model page can run an explicit native-library preflight and displays Sherpa/ONNX Runtime version strings or the load error. It does not initialize the runtime at app startup.
- Optional metrics are disabled by default. When enabled, the latest ASR/TTS records include model-load time, inference time, process RSS high-watermark, runtime version strings, UTC completion time and a coarse error stage. Disabling metrics clears the stored records.
- No audio, transcription, prompt, file path or model data is persisted in diagnostics. The RSS high-watermark is process-wide, may include unrelated activity and is not a per-inference memory delta.
- VAD/diagnostic code is source-integrated against `sherpa_onnx 2.0.1`, whose Flutter package documents VAD support on Android and Windows. Package documentation and upstream model inventory still do not replace CI compilation and device tests.
- Flutter/Dart/Rust/native compilation is delegated to CI because these SDKs are not installed in the current workspace environment.


## Alpha 0.16.0 — evaluation and session safety

- `LeoVoiceService` now rejects a second capture while an ASR transcription is still running. Each capture has a generation value; cancellation increments it, and the recognizer result is checked against that generation after each asynchronous boundary before it can be returned to the chat composer.
- App lifecycle changes cancel both a recording and a capture/transcription preparation in progress. A transcription isolate cannot be force-killed, so the service waits for its result to become stale and discards it; the busy guard remains active until cleanup completes.
- `scripts/voice_eval.py` evaluates externally supplied local transcript pairs. It reports corpus WER/CER, language breakdown, inference/model-load percentiles and maximum process RSS. The report excludes transcript contents, and its strict input schema rejects audio paths, prompts and raw audio fields.
- `config/voice_eval_template.json` is only a template. It is not an accuracy benchmark and contains no real user recording. Evaluation instructions are in `docs/testing/VOICE_QUALITY_EVALUATION.md`.
- Arabic scoring normalization removes diacritics/tatweel, maps common alef variants and ya/alef-maqsura variants, and preserves taa marbuta. These normalization rules are intended for repeatable comparisons, not linguistic equivalence judgments.
- No recognition result, dialect score or device-performance claim is published until real, consented phrase sets are evaluated on physical Android and Windows devices.


## Resource-aware operation (Alpha v0.17.0)

- VAD, Qwen3-ASR and Supertonic workers now select CPU thread counts from the logical processor count. Voice work reserves one logical processor where possible and is capped at two threads so it is less likely to starve the foreground UI.
- Before microphone capture, Chat checks whether a local GGUF chat model is already loaded. If so, it asks the user before proceeding because loading the approximately 0.94 GB Qwen3-ASR pack may increase process memory pressure. The user may cancel or continue; Leo never unloads the chat model without an explicit separate action.
- ASR/TTS remain explicitly CPU-provider workloads in this milestone. No GPU provider is selected or inferred as available.
- Runtime RSS displayed in the model library is process-wide. It must not be interpreted as the ASR/TTS model's own allocation or as free physical RAM.
- If the resource-state query is unavailable, voice capture is not silently blocked; the user-facing ASR loader still reports model-load or inference failures. Real-device low-memory behavior remains a validation requirement.
