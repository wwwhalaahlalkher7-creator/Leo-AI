# Leo Alpha v0.16.0 — source validation report

## Source-level checks

| Check | Result |
|---|---:|
| Python architecture/contract/evaluator suite | **85/85 passed** |
| Version policy and synchronized package metadata | Passed — `v0.16.0 / ALPHA` |
| J.A.R.V.I.R source archive SHA-256 | Passed |
| NEXUS source archive SHA-256 | Passed |
| JSON parse | 10 files |
| TOML parse | 8 files |
| YAML/YML parse | 5 files |
| CSV structural validation | 4 files |
| Voice evaluator CLI privacy smoke test | Passed |
| Final ZIP integrity and SHA-256 | Passed after packaging |

Commands run:

```bash
python scripts/sync_version.py
python scripts/check_version.py
python scripts/verify_sources.py
python -m unittest discover -s scripts/tests -q
```

The evaluator smoke test used temporary synthetic input only. It verifies the report generator and transcript-exclusion behavior; it is not a real ASR accuracy result.

## Toolchain availability

Available: Python 3, CMake. Not available: Flutter, Dart, Cargo, rustc, Android SDK/NDK and Windows MSVC build tools.

Not run:

- `dart format` / `flutter analyze`
- Flutter Dart unit/widget tests
- `cargo fmt`, `cargo test`, `cargo clippy`
- Android APK or Windows application build
- physical-device microphone, VAD, Qwen ASR or Supertonic TTS tests

## Accuracy and performance boundary

No recordings or real transcript corpus are included. No WER/CER, latency, RAM, dialect or voice-naturalness result is reported. Those must be measured on real devices with the documented fixed corpus before product-quality claims are made.
