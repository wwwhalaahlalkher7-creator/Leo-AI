# ADR-0020: Optional VAD and Voice Runtime Diagnostics

- **Status:** Accepted for Leo Alpha v0.15.0
- **Date:** 2026-11-16

## Context

Leo v0.14.0 provides manual push-to-talk, local ASR/TTS, verified local model-pack baselines and robust playback cleanup. Users still have to stop every recording manually, while voice failures can originate from three distinct layers: the platform's native Sherpa library, model loading, or actual inference. There is also no user-visible way to gather comparable local performance measurements.

## Decision

1. Add Silero VAD as a separate, optional, user-imported model pack. The base app does not bundle the ONNX weights.
2. Run the VAD over fixed 512-sample Float32 windows at 16 kHz. A completed speech segment (including the configured silence endpoint) may request the existing stop-and-transcribe flow.
3. Preserve the manual stop action and 30-second hard recording limit regardless of VAD state. If the VAD pack is missing, invalid, or fails at runtime, continue in manual mode and surface a reason; do not fail microphone capture solely because VAD is unavailable.
4. Cancel an active recording when the app leaves the resumed lifecycle state and stop active playback. No microphone access is started in the background.
5. Add an optional, default-off metadata diagnostics store. It may retain ASR/TTS model-load duration, inference duration, process RSS high-watermark, runtime version strings, UTC completion time and a coarse error stage. It must not store audio, transcripts, prompts, model file paths or model contents.
6. Add an explicit native-runtime preflight action in the voice-model page. It reports the Sherpa and ONNX Runtime version strings or the load error.

## Consequences

### Positive

- Hands-free end-of-utterance behavior is available without changing the offline ASR model or the existing manual interaction.
- The optional VAD model is small and separately removable by replacing/removing its pack directory; no new mandatory download is introduced.
- Voice failures become easier to classify, and performance data is available only after user opt-in.
- Lifecycle cleanup reduces the chance that the microphone or speaker remains active after leaving the chat.

### Trade-offs and limitations

- VAD uses the same Sherpa native runtime and needs platform verification on both Android and Windows.
- The process RSS value is a process high-watermark, not an isolated per-inference allocation measurement. It may include unrelated process activity and platform-specific shared-memory accounting.
- VAD endpointing can be affected by microphone quality, noise, speech pauses and model threshold; users can disable it or stop manually.
- No partial transcript, wake word, background listening, streaming TTS or continuous assistant mode is introduced.
- Local SHA-256 manifests continue to be change-detection baselines, not upstream publisher authentication.

## Rejected alternatives

- Making VAD mandatory: rejected because manual push-to-talk must remain functional without downloading another model.
- Automatically uploading voice diagnostics: rejected because Leo's core voice processing remains local and diagnostic collection is opt-in/local only.
- Treating process-wide RSS high-watermark as per-request memory: rejected because the API reports a process high-watermark rather than a model-specific allocation.
- Keeping capture active when the app is backgrounded: rejected because no background microphone behavior is part of the Alpha scope.
