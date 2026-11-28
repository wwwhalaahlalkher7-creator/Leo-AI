from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from dart_source import flat  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]


def source(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


class OfflineVoiceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads(source("config/voice_models/catalog.json"))
        cls.pubspec = source("apps/leo_app/pubspec.yaml")
        cls.voice_service = source("apps/leo_app/lib/core/voice/leo_voice_service.dart")
        cls.pack_store = source("apps/leo_app/lib/core/voice/voice_pack_store.dart")
        cls.voice_page = source("apps/leo_app/lib/features/voice/voice_models_page.dart")
        cls.chat_page = source("apps/leo_app/lib/features/chat/chat_page.dart")
        cls.permission_service = source("apps/leo_app/lib/core/capabilities/capability_hub_service.dart")

    def test_version_and_voice_dependencies_are_pinned(self):
        version = source("config/VERSION").strip()
        build = source("config/BUILD_NUMBER").strip()
        self.assertEqual(source("config/RELEASE_CHANNEL").strip(), "ALPHA")
        self.assertEqual(build, "4")
        self.assertIn(f"version: {version.removeprefix('v')}+{build}", self.pubspec)
        self.assertRegex(self.pubspec, r"(?m)^\s+sherpa_onnx:\s*2\.0\.1\s*$")
        self.assertRegex(self.pubspec, r"(?m)^\s+record:\s*7\.2\.0\s*$")
        self.assertRegex(self.pubspec, r"(?m)^\s+audioplayers:\s*6\.8\.1\s*$")

    def test_catalog_has_asr_and_tts_models_with_explicit_files(self):
        self.assertEqual(self.catalog["schema_version"], 1)
        packs = {item["id"]: item for item in self.catalog["packs"]}
        self.assertIn("qwen3-asr-0.6b-int8", packs)
        self.assertIn("supertonic-3-int8", packs)
        self.assertIn("silero-vad", packs)
        self.assertEqual(packs["silero-vad"]["kind"], "voice_activity_detection")
        self.assertEqual(packs["silero-vad"]["required_files"], ["silero_vad.onnx"])
        self.assertEqual(packs["silero-vad"]["sample_rate_hz"], 16000)
        self.assertEqual(packs["silero-vad"]["window_samples"], 512)
        self.assertEqual(packs["qwen3-asr-0.6b-int8"]["kind"], "speech_recognition")
        self.assertEqual(packs["supertonic-3-int8"]["kind"], "speech_synthesis")
        self.assertIn("ar", packs["qwen3-asr-0.6b-int8"]["languages"])
        self.assertIn("en", packs["qwen3-asr-0.6b-int8"]["languages"])
        self.assertIn("mk", packs["qwen3-asr-0.6b-int8"]["languages"])
        self.assertIn("ro", packs["qwen3-asr-0.6b-int8"]["languages"])
        self.assertNotIn("ur", packs["qwen3-asr-0.6b-int8"]["languages"])
        self.assertNotIn("ca", packs["qwen3-asr-0.6b-int8"]["languages"])
        self.assertIn("ar", packs["supertonic-3-int8"]["languages"])
        self.assertIn("en", packs["supertonic-3-int8"]["languages"])
        self.assertEqual(len(packs["supertonic-3-int8"]["languages"]), 31)
        self.assertEqual(packs["supertonic-3-int8"]["languages_enabled_in_leo"], ["ar", "en"])
        self.assertEqual(
            set(packs["qwen3-asr-0.6b-int8"]["required_files"]),
            set(self._extract_list(self.pack_store, "speechRecognitionFiles")),
        )
        self.assertEqual(
            set(packs["supertonic-3-int8"]["required_files"]),
            set(self._extract_list(self.pack_store, "speechSynthesisFiles")),
        )
        self.assertEqual(
            set(packs["silero-vad"]["required_files"]),
            set(self._extract_list(self.pack_store, "voiceActivityDetectionFiles")),
        )

    @staticmethod
    def _extract_list(text: str, name: str) -> list[str]:
        match = re.search(rf"{name}\s*=\s*\[(.*?)\];", text, re.S)
        if not match:
            raise AssertionError(f"Missing {name} list")
        return re.findall(r"'([^']+)'", match.group(1))

    def test_voice_weights_are_optional_and_not_bundled_as_flutter_assets(self):
        self.assertIn("Optional model packs are user-imported", self.catalog["model_policy"])
        assets = ROOT / "apps/leo_app/assets"
        if assets.exists():
            model_files = [
                path for path in assets.rglob("*")
                if path.is_file() and path.suffix.lower() in {".onnx", ".gguf"}
            ]
            self.assertEqual(model_files, [])
        self.assertIn("getApplicationSupportDirectory", self.pack_store)
        self.assertNotIn("rootBundle.load", self.pack_store)

    def test_import_is_streamed_bounded_and_staged(self):
        self.assertIn("source.readAsByteStream()", self.pack_store)
        self.assertNotIn("await source.readAsByteStream()", self.pack_store)
        self.assertIn("maximumFileBytes", self.pack_store)
        self.assertIn("maximumPackBytes", self.pack_store)
        self.assertIn("staging.rename(target.path)", self.pack_store)
        self.assertIn("backup.rename(target.path)", self.pack_store)
        self.assertIn("streamedBytes != declaredSize", self.pack_store)

    def test_asr_is_local_and_uses_qwen3_feature_dimension_128(self):
        self.assertIn("OfflineRecognizerConfig", self.voice_service)
        self.assertIn("OfflineQwen3AsrModelConfig", self.voice_service)
        self.assertIn("featureDim: 128", self.voice_service)
        self.assertIn("provider: 'cpu'", self.voice_service)
        self.assertIn("Isolate.run", self.voice_service)
        self.assertIn("maximumRecordingSeconds = 30", self.voice_service)
        self.assertIn("generation != _speechGeneration", self.voice_service)
        self.assertIn("_speechGeneration++;", self.voice_service)
        self.assertNotIn("package:http", self.voice_service)
        self.assertNotIn("dart:html", self.voice_service)

    def test_tts_is_local_and_audio_playback_uses_local_file(self):
        self.assertIn("OfflineTtsConfig", self.voice_service)
        self.assertIn("OfflineTtsSupertonicModelConfig", self.voice_service)
        self.assertIn("extra: {'lang': language, 'num_steps': 8}", self.voice_service)
        self.assertIn("DeviceFileSource(wavPath)", self.voice_service)
        self.assertIn("_playerCompleteSubscription ??=", self.voice_service)
        self.assertIn("_player ??= AudioPlayer()", self.voice_service)
        self.assertIn("writeMonoPcm16Wav", self.voice_service)
        self.assertNotIn("sherpa.writeWave", self.voice_service)
        self.assertIn("sid: 0", self.voice_service)

    def test_transcript_is_inserted_into_composer_not_sent_automatically(self):
        stop_handler = self.chat_page.split("Future<void> _stopVoiceCapture({bool reachedLimit = false})", 1)[1].split("Future<void> _speakMessage", 1)[0]
        self.assertIn("_inputController.value = TextEditingValue", stop_handler)
        self.assertNotIn("_send(transcript)", stop_handler)
        self.assertNotIn("_send(", stop_handler)
        self.assertIn("راجع النص ثم أرسله بنفسك", stop_handler)
        self.assertIn("أول 30 ثانية", stop_handler)
        self.assertNotIn("90 ثانية", stop_handler)
        self.assertIn("_voiceLimitTimer = Timer(", self.chat_page)
        self.assertIn("reachedLimit: true", self.chat_page)
        self.assertIn("reachedMaximumDuration: reachedLimit", self.chat_page)

    def test_microphone_is_first_use_and_os_permission_is_independent(self):
        self.assertIn(flat("requestMicrophoneAccess(context)"), flat(self.chat_page))
        self.assertIn(flat("LeoPermissionStatus.previouslyDenied"), flat(self.permission_service))
        self.assertIn(flat("requestOsPermission('audio.microphone')"), flat(self.permission_service))
        self.assertIn(flat("openWindowsMicrophonePrivacySettings"), flat(self.permission_service))
        self.assertIn(flat("if (!Platform.isWindows)"), flat(self.voice_service))
        self.assertIn("audio.microphone", source("config/leo_capability_policy_v0.2.json"))
        self.assertIn("supported_in_alpha: true", source("core/capabilities/src/lib.rs").split('id: "audio.microphone"', 1)[1].split('CapabilityDefinition {', 1)[0])

    def test_asr_import_uses_two_native_picker_rounds_for_root_and_tokenizer(self):
        self.assertIn("الخطوة 1 من 2", self.voice_page)
        self.assertIn("الخطوة 2 من 2", self.voice_page)
        self.assertIn("files.addAll(tokenizerFiles)", self.voice_page)
        self.assertIn("اختر ملفات tokenizer الثلاثة", self.voice_page)

    def test_voice_library_offers_approved_official_links(self):
        self.assertIn("_capabilityHub.openUrl(context, url)", self.voice_page)
        self.assertIn("onOpenDownload", self.voice_page)
        self.assertIn("onOpenDocs", self.voice_page)
        self.assertIn("releases/download/asr-models/", self.voice_page)
        self.assertIn("releases/download/tts-models/", self.voice_page)

    def test_windows_build_preparation_applies_minimum_cmake_and_ci_uses_it(self):
        script = source("scripts/prepare_windows_runner.ps1")
        workflow = source(".github/workflows/ci.yml")
        self.assertIn("CMake 3.15+", script)
        self.assertIn("cmake_minimum_required(VERSION 3.15)", script)
        self.assertIn("cmake_policy(VERSION 3.15...$2)", script)
        self.assertIn("cmake_policy(SET CMP0091 NEW)", script)
        self.assertIn("./scripts/prepare_windows_runner.ps1", workflow)

    def test_voice_docs_and_runtime_license_notice_exist(self):
        self.assertTrue((ROOT / "docs/architecture/OFFLINE_VOICE_ENGINE.md").exists())
        self.assertTrue((ROOT / "docs/decisions/ADR-0018-offline-voice-engine.md").exists())
        self.assertTrue((ROOT / "docs/audit/ALPHA_0.13.0_WORK_LOG.md").exists())
        self.assertTrue((ROOT / "docs/audit/ALPHA_0.14.0_WORK_LOG.md").exists())
        self.assertTrue((ROOT / "docs/audit/ALPHA_0.15.0_WORK_LOG.md").exists())
        self.assertTrue((ROOT / "docs/audit/ALPHA_0.15.0_VALIDATION.md").exists())
        self.assertTrue((ROOT / "docs/decisions/ADR-0019-voice-pack-integrity-and-portable-wav.md").exists())
        self.assertTrue((ROOT / "docs/decisions/ADR-0020-optional-vad-and-voice-runtime-diagnostics.md").exists())
        self.assertTrue((ROOT / "licenses/sherpa-onnx-Apache-2.0.txt").exists())


    def test_voice_pack_integrity_manifest_is_streamed_and_distinguishes_baseline(self):
        self.assertIn("package:crypto/crypto.dart", self.pack_store)
        self.assertIn("sha256.startChunkedConversion", self.pack_store)
        self.assertIn("manifestFileName = '.leo-voice-pack.json'", self.pack_store)
        self.assertIn("'size_bytes'", self.pack_store)
        self.assertIn("'sha256'", self.pack_store)
        self.assertIn("verifyIntegrity(VoicePackKind kind)", self.pack_store)
        self.assertIn("VoicePackIntegrity.legacyUnverified", self.pack_store)
        self.assertIn("VoicePackIntegrity.failed", self.pack_store)
        self.assertIn("selectedByName.containsKey(name)", self.pack_store)
        self.assertIn("maximumPackBytes - copiedPackBytes", self.pack_store)
        self.assertIn("لا تثبت", self.voice_page)

    def test_voice_pack_manifest_is_not_claimed_as_publisher_authenticity(self):
        architecture = source("docs/architecture/OFFLINE_VOICE_ENGINE.md")
        self.assertIn("does not authenticate", architecture.lower())
        self.assertIn("local SHA-256", architecture)
        self.assertIn("legacy", architecture.lower())

    def test_tts_playback_generation_does_not_complete_newer_playback(self):
        self.assertIn("int? _activePlaybackGeneration", self.voice_service)
        self.assertIn("_completePlayback(generation)", self.voice_service)
        self.assertIn("if (_activePlaybackGeneration != generation) return", self.voice_service)
        self.assertIn("AudioPlayer? _player", self.voice_service)
        self.assertNotIn("final AudioPlayer _player = AudioPlayer()", self.voice_service)
        self.assertNotIn("sherpa.writeWave", self.voice_service)

    def test_portable_pcm16_wav_writer_and_dart_tests_exist(self):
        writer = source("apps/leo_app/lib/core/voice/wav_encoder.dart")
        self.assertIn("encodeMonoPcm16Wav", writer)
        self.assertIn("Endian.little", writer)
        self.assertIn("writeMonoPcm16Wav", self.voice_service)
        self.assertTrue((ROOT / "apps/leo_app/test/core/offline_voice_wav_encoder_test.dart").exists())
        self.assertTrue((ROOT / "apps/leo_app/test/core/voice_pack_store_test.dart").exists())



    def test_vad_endpointing_keeps_manual_and_maximum_duration_fallbacks(self):
        self.assertIn(flat("VoicePackKind.voiceActivityDetection"), flat(self.pack_store))
        self.assertIn(flat("voiceActivityDetectionReady"), flat(self.pack_store))
        self.assertIn(flat("VoiceActivityDetector"), flat(self.voice_service))
        self.assertIn(flat("acceptWaveform(frame)"), flat(self.voice_service))
        self.assertIn(flat("minSilenceDuration: 0.8"), flat(self.voice_service))
        self.assertIn(flat("maxSpeechDuration: maximumRecordingSeconds.toDouble()"), flat(self.voice_service))
        self.assertIn(flat("maximumRecordingSeconds = 30"), flat(self.voice_service))
        self.assertIn(flat("_vadFallbackReason"), flat(self.voice_service))
        self.assertIn("manual", self.voice_service.lower())
        self.assertIn(flat("onVadSpeechEnded"), flat(self.chat_page))
        self.assertIn(flat("onVadFallback: useVad ? _showNotice : null"), flat(self.chat_page))
        self.assertIn(flat("_setVadFallback"), flat(self.voice_service))
        self.assertIn(flat("_vadActive && _vadStopScheduled && !_finishingCapture"), flat(self.voice_service))
        self.assertIn(flat("_voiceVadEnabled"), flat(self.chat_page))

    def test_vad_is_optional_and_does_not_replace_the_asr_pcm_buffer(self):
        accept_handler = self.voice_service.split("void _acceptPcm16", 1)[1].split("Future<void> _prepareVad", 1)[0]
        self.assertIn("_pcmChunks.add(samples)", accept_handler)
        self.assertIn("_feedVad(samples)", accept_handler)
        self.assertIn("_pcmChunks", self.voice_service.split("Future<String> stopAndTranscribe", 1)[1])
        self.assertIn("if (useVad) await _prepareVad(generation)", self.voice_service)
        self.assertIn("if (!status.voiceActivityDetectionReady)", self.voice_service)

    def test_voice_diagnostics_are_default_off_and_metadata_only(self):
        diagnostics = source("apps/leo_app/lib/core/voice/voice_diagnostics.dart")
        self.assertIn("prefs.getBool(metricsEnabledKey) ?? false", diagnostics)
        self.assertIn("model_load_ms", diagnostics)
        self.assertIn("inference_ms", diagnostics)
        self.assertIn("process_peak_rss_bytes", diagnostics)
        self.assertIn("getOnnxruntimeVersion", diagnostics)
        # Privacy documentation may mention forbidden data types; the persisted
        # JSON schema must not serialize them as fields.
        self.assertNotIn("'transcript':", diagnostics)
        self.assertNotIn("'audio':", diagnostics)
        self.assertNotIn("'audio_bytes':", diagnostics)
        self.assertIn("recordIfEnabled", self.voice_service)

    def test_voice_runtime_errors_are_classified_and_preflight_is_user_triggered(self):
        self.assertIn("'native_runtime'", self.voice_service)
        self.assertIn("'model_load'", self.voice_service)
        self.assertIn("'inference'", self.voice_service)
        self.assertIn("VoiceRuntimeDiagnostics.checkNativeRuntime()", self.voice_page)
        self.assertIn("فحص مكتبة المحرك الأصلية", self.voice_page)

    def test_chat_lifecycle_cancels_capture_and_stops_playback(self):
        self.assertIn("with WidgetsBindingObserver", self.chat_page)
        self.assertIn("didChangeAppLifecycleState", self.chat_page)
        lifecycle = self.chat_page.split("void didChangeAppLifecycleState", 1)[1].split("void dispose()", 1)[0]
        self.assertIn("cancelCapture()", lifecycle)
        self.assertIn("_voiceRecording || _voiceBusy", lifecycle)
        self.assertIn("stopSpeaking()", lifecycle)
        self.assertIn("removeObserver(this)", self.chat_page)

    def test_voice_page_exposes_vad_installation_and_opt_in_controls(self):
        self.assertIn("silero_vad.onnx", self.voice_page)
        self.assertIn("_setVadEnabled", self.voice_page)
        self.assertIn("_setMetricsEnabled", self.voice_page)
        self.assertIn("قياسات الأداء المحلية (اختيارية)", self.voice_page)
        self.assertIn("الإيقاف التلقائي بعد انتهاء الكلام", self.voice_page)

    def test_voice_settings_refresh_after_returning_from_model_library(self):
        navigation = self.chat_page.split("Future<void> _openVoiceModels()", 1)[1].split("Future<void> _toggleVoiceCapture()", 1)[0]
        self.assertIn("vadAutoStopEnabled", navigation)
        self.assertIn("setState(() => _voiceVadEnabled = enabled)", navigation)
        self.assertIn("late final sherpa.OfflineRecognizer recognizer", self.voice_service)
        self.assertIn("late final sherpa.OfflineTts tts", self.voice_service)


    def test_voice_capture_transcription_is_single_flight_and_generation_cancelled(self):
        self.assertIn("bool _transcribing = false", self.voice_service)
        self.assertIn("int _captureGeneration = 0", self.voice_service)
        self.assertIn("if (_transcribing)", self.voice_service)
        self.assertIn("final generation = _captureGeneration", self.voice_service)
        self.assertIn("_ensureCaptureGeneration(generation)", self.voice_service)
        self.assertIn("_captureGeneration++", self.voice_service)
        self.assertIn("class VoiceCaptureCancelledException", self.voice_service)
        self.assertIn("bool get isTranscribing => _transcribing", self.voice_service)

    def test_voice_evaluation_harness_is_local_and_transcript_private(self):
        evaluator = source("scripts/voice_eval.py")
        template = source("config/voice_eval_template.json")
        self.assertIn("normalize_transcript", evaluator)
        self.assertIn("edit_distance", evaluator)
        self.assertIn("by_language", evaluator)
        self.assertIn("transcripts_included", evaluator)
        self.assertIn("FORBIDDEN_SAMPLE_KEYS", evaluator)
        self.assertIn('"schema_version": 1', template)
        self.assertTrue((ROOT / "docs/testing/VOICE_QUALITY_EVALUATION.md").exists())
        self.assertTrue((ROOT / "docs/audit/ALPHA_0.16.0_WORK_LOG.md").exists())
        self.assertTrue((ROOT / "docs/audit/ALPHA_0.16.0_VALIDATION.md").exists())
        self.assertTrue((ROOT / "docs/decisions/ADR-0021-voice-evaluation-and-session-cancellation.md").exists())
        self.assertTrue((ROOT / "docs/audit/ALPHA_0.17.0_WORK_LOG.md").exists())
        self.assertTrue((ROOT / "docs/audit/ALPHA_0.17.0_VALIDATION.md").exists())
        self.assertTrue((ROOT / "docs/decisions/ADR-0022-model-resource-policy-and-voice-budget.md").exists())
        self.assertTrue((ROOT / "scripts/tests/test_voice_evaluation.py").exists())

    def test_vad_and_diagnostics_architecture_documents_are_current(self):
        architecture = source("docs/architecture/OFFLINE_VOICE_ENGINE.md")
        self.assertIn("Alpha 0.15.0", architecture)
        self.assertIn("Silero VAD", architecture)
        self.assertIn("process RSS high-watermark", architecture)
        self.assertIn("No audio", architecture)
        worklog = source("docs/audit/ALPHA_0.15.0_WORK_LOG.md")
        self.assertIn("v0.15.0", worklog)
        self.assertIn("default-off", worklog)



if __name__ == "__main__":
    unittest.main(verbosity=2)
