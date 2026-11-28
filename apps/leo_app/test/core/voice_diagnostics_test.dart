import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leo_app/core/voice/voice_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'metrics are disabled by default and are not recorded without opt-in',
    () async {
      final store = VoiceDiagnosticsStore();
      expect(await store.metricsEnabled, isFalse);
      await store.recordIfEnabled(
        VoiceRunMetrics(
          operation: 'asr',
          modelLoadMilliseconds: 100,
          inferenceMilliseconds: 200,
          processPeakRssBytes: 300,
          engineVersion: 'test',
          onnxRuntimeVersion: 'test',
          completedAtUtc: DateTime.utc(2026),
        ),
      );
      expect(await store.readLatest('asr'), isNull);
    },
  );

  test('opt-in stores performance metadata only and can be cleared', () async {
    final store = VoiceDiagnosticsStore();
    await store.setMetricsEnabled(true);
    await store.recordIfEnabled(
      VoiceRunMetrics(
        operation: 'tts',
        modelLoadMilliseconds: 12,
        inferenceMilliseconds: 34,
        processPeakRssBytes: 56,
        engineVersion: '2.0.1',
        onnxRuntimeVersion: '1.22',
        completedAtUtc: DateTime.utc(2026),
      ),
    );

    final metrics = await store.readLatest('tts');
    expect(metrics?.inferenceMilliseconds, 34);
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('leo.voice.metrics.tts.latest')!;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    expect(
      json.keys,
      containsAll([
        'operation',
        'model_load_ms',
        'inference_ms',
        'process_peak_rss_bytes',
        'engine_version',
        'onnxruntime_version',
        'completed_at_utc',
        'error_stage',
      ]),
    );
    expect(json.keys, isNot(contains('audio')));
    expect(json.keys, isNot(contains('transcript')));
    expect(json.keys, isNot(contains('prompt')));

    await store.clearMetrics();
    expect(await store.readLatest('tts'), isNull);
  });
}
