# Voice runtime and model licensing notes

- `sherpa_onnx` 2.0.1 is sourced from `k2-fsa/sherpa-onnx` and distributed under Apache License 2.0. The upstream license text is copied to `licenses/sherpa-onnx-Apache-2.0.txt`.
- `record` and `audioplayers` are external Flutter plugins; their licenses must be retained from the resolved pub packages in any redistributable notices bundle.
- Qwen3-ASR and Supertonic 3 weights are not included in Leo's source package or base installers. The user imports them from the upstream model releases. Their model-card/weight terms are distinct from the sherpa-onnx runtime license; verify the exact license from the model release before any redistribution.
- No model files are downloaded automatically by Leo. The UI opens upstream links only after the user approves the external handoff.
