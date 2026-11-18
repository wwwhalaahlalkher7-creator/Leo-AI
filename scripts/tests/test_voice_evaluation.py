import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "voice_eval.py"
SPEC = importlib.util.spec_from_file_location("leo_voice_eval", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class VoiceEvaluationTests(unittest.TestCase):
    def test_arabic_normalization_removes_diacritics_tatweel_and_punctuation(self):
        actual = MODULE.normalize_transcript("إِنَّ الـسَّلَامَ، عَلَيْكُم!")
        self.assertEqual(actual, "ان السلام عليكم")

    def test_arabic_orthographic_variants_score_as_equal(self):
        dataset = {
            "schema_version": 1,
            "samples": [{
                "id": "ar-01", "language": "ar",
                "reference": "آمل أن ينجح الطالب",
                "hypothesis": "امل ان ينجح الطالب!!!",
            }],
        }
        report = MODULE.evaluate_dataset(dataset)
        self.assertEqual(report["overall"]["wer"], 0.0)
        self.assertEqual(report["overall"]["cer"], 0.0)

    def test_english_wer_and_cer_are_corpus_weighted(self):
        dataset = {
            "schema_version": 1,
            "samples": [
                {"id": "en-01", "language": "en", "reference": "hello world", "hypothesis": "hello word"},
                {"id": "en-02", "language": "en", "reference": "good morning", "hypothesis": "good morning"},
            ],
        }
        result = MODULE.evaluate_dataset(dataset)["overall"]
        self.assertEqual(result["word_errors"], 1)
        self.assertEqual(result["reference_words"], 4)
        self.assertEqual(result["wer"], 0.25)
        self.assertGreater(result["cer"], 0.0)

    def test_language_groups_and_performance_percentiles(self):
        dataset = {
            "schema_version": 1,
            "metadata": {"app_version": "v0.16.0", "platform": "android", "device_name": "private"},
            "samples": [
                {"id": "ar-1", "language": "ar", "reference": "مرحبا بك", "hypothesis": "مرحبا بك", "inference_ms": 100, "model_load_ms": 500, "process_peak_rss_bytes": 1024},
                {"id": "en-1", "language": "en", "reference": "hello there", "hypothesis": "hello", "inference_ms": 300, "model_load_ms": 700, "process_peak_rss_bytes": 2048},
            ],
        }
        report = MODULE.evaluate_dataset(dataset)
        self.assertEqual(set(report["by_language"]), {"ar", "en"})
        self.assertEqual(report["overall"]["inference_ms"]["median"], 200)
        self.assertEqual(report["overall"]["inference_ms"]["p95"], 300)
        self.assertEqual(report["overall"]["process_peak_rss_bytes_max"], 2048)
        self.assertNotIn("device_name", report["metadata"])
        self.assertFalse(report["privacy"]["transcripts_included"])

    def test_empty_hypothesis_counts_as_deletions(self):
        dataset = {
            "schema_version": 1,
            "samples": [{"id": "en-1", "language": "en", "reference": "hello there", "hypothesis": ""}],
        }
        result = MODULE.evaluate_dataset(dataset)["overall"]
        self.assertEqual(result["wer"], 1.0)
        self.assertEqual(result["cer"], 1.0)

    def test_rejects_audio_paths_and_transcript_side_channels(self):
        dataset = {
            "schema_version": 1,
            "samples": [{
                "id": "ar-1", "language": "ar", "reference": "كلام", "hypothesis": "كلام",
                "audio_path": "/private/recording.wav",
            }],
        }
        with self.assertRaisesRegex(ValueError, "disallowed fields"):
            MODULE.evaluate_dataset(dataset)

    def test_metadata_is_strictly_allowlisted_and_sample_ids_are_opaque(self):
        dataset = {
            "schema_version": 1,
            "metadata": {
                "app_version": "v0.16.0",
                "platform": "android",
                "device_class": "private-phone-name",
                "model": "Qwen3-ASR-0.6B-INT8",
                "sample_rate_hz": 16000,
                "notes": "private note",
            },
            "samples": [{"id": "phrase-01", "language": "ar", "reference": "مرحبا", "hypothesis": "مرحبا"}],
        }
        metadata = MODULE.evaluate_dataset(dataset)["metadata"]
        self.assertEqual(metadata, {
            "app_version": "v0.16.0",
            "platform": "android",
            "model": "Qwen3-ASR-0.6B-INT8",
            "sample_rate_hz": 16000,
        })
        dataset["samples"][0]["id"] = "user@example.com"
        with self.assertRaisesRegex(ValueError, "opaque alphanumeric id"):
            MODULE.evaluate_dataset(dataset)
        dataset["samples"][0]["id"] = "phrase-01"
        dataset["metadata"]["platform"] = ["android"]
        report = MODULE.evaluate_dataset(dataset)
        self.assertNotIn("platform", report["metadata"])
        dataset["metadata"]["audio_path"] = "/private/audio.wav"
        with self.assertRaisesRegex(ValueError, "metadata contains disallowed fields"):
            MODULE.evaluate_dataset(dataset)

    def test_rejects_duplicate_ids_empty_reference_and_invalid_latency(self):
        base = {"schema_version": 1, "samples": [
            {"id": "one", "language": "en", "reference": "hello", "hypothesis": "hello"},
            {"id": "one", "language": "en", "reference": "world", "hypothesis": "world"},
        ]}
        with self.assertRaisesRegex(ValueError, "Duplicate sample id"):
            MODULE.evaluate_dataset(base)
        base["samples"] = [{"id": "empty", "language": "en", "reference": "!!!", "hypothesis": ""}]
        with self.assertRaisesRegex(ValueError, "reference becomes empty"):
            MODULE.evaluate_dataset(base)
        base["samples"] = [{"id": "bad", "language": "en", "reference": "hello", "hypothesis": "hello", "inference_ms": -1}]
        with self.assertRaisesRegex(ValueError, "non-negative"):
            MODULE.evaluate_dataset(base)

    def test_cli_writes_report_without_transcript_content(self):
        dataset = {
            "schema_version": 1,
            "samples": [{"id": "en-1", "language": "en", "reference": "private phrase", "hypothesis": "private phrase"}],
        }
        with tempfile.TemporaryDirectory() as folder:
            input_path = Path(folder) / "input.json"
            output_path = Path(folder) / "report.json"
            input_path.write_text(json.dumps(dataset), encoding="utf-8")
            exit_code = MODULE.main(["--input", str(input_path), "--output", str(output_path)])
            self.assertEqual(exit_code, 0)
            report_text = output_path.read_text(encoding="utf-8")
            self.assertNotIn("private phrase", report_text)
            self.assertIn('"wer": 0.0', report_text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
