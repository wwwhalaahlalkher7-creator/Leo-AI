import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leo_app/core/diagnostics/runtime_benchmark_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  RuntimeBenchmarkRecord sample({
    int elapsed = 1000,
    int chars = 500,
    bool succeeded = true,
  }) => RuntimeBenchmarkRecord(
        timestampUtc: DateTime.utc(2026, 11, 18),
        elapsedMilliseconds: elapsed,
        outputCharacters: chars,
        residentBytes: 1024,
        peakResidentBytes: 4096,
        platform: 'android',
        succeeded: succeeded,
      );

  test('benchmark collection is disabled by default', () async {
    final store = RuntimeBenchmarkStore();
    expect(await store.isEnabled, isFalse);
    await store.recordIfEnabled(sample());
    expect(await store.readRecords(), isEmpty);
  });

  test('opt-in stores only bounded metadata and can be cleared', () async {
    final store = RuntimeBenchmarkStore();
    await store.setEnabled(true);
    await store.recordIfEnabled(sample());
    final records = await store.readRecords();
    expect(records, hasLength(1));
    expect(records.single.outputCharacters, 500);

    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('leo.runtime.benchmarks.records.v1')!;
    final encoded = jsonDecode(raw) as List<dynamic>;
    final fields = (encoded.single as Map<String, dynamic>).keys.toSet();
    expect(fields, containsAll(<String>{
      'timestamp_utc',
      'elapsed_ms',
      'output_characters',
      'resident_bytes',
      'peak_resident_bytes',
      'platform',
      'succeeded',
    }));
    expect(fields, isNot(contains('prompt')));
    expect(fields, isNot(contains('answer')));
    expect(fields, isNot(contains('conversation_id')));
    expect(fields, isNot(contains('model_name')));

    await store.clear();
    expect(await store.readRecords(), isEmpty);
  });

  test('retains no more than maximumRecords and calculates useful aggregates', () async {
    final store = RuntimeBenchmarkStore();
    await store.setEnabled(true);
    for (var index = 0; index < RuntimeBenchmarkStore.maximumRecords + 5; index++) {
      await store.recordIfEnabled(sample(
        elapsed: 100 + index,
        chars: 200,
        succeeded: index.isEven,
      ));
    }
    final records = await store.readRecords();
    final summary = await store.summary();
    expect(records.length, RuntimeBenchmarkStore.maximumRecords);
    expect(summary.sampleCount, RuntimeBenchmarkStore.maximumRecords);
    expect(summary.p95LatencyMilliseconds, greaterThanOrEqualTo(summary.medianLatencyMilliseconds));
    expect(summary.averageOutputCharactersPerSecond, greaterThan(0));
    expect(summary.maximumPeakResidentBytes, 4096);
    expect(summary.successRatePercent, greaterThan(0));
    expect(summary.successRatePercent, lessThan(100));
  });

  test('failed and cancelled attempts do not inflate output throughput', () async {
    final store = RuntimeBenchmarkStore();
    await store.setEnabled(true);
    await store.recordIfEnabled(sample(elapsed: 1000, chars: 500, succeeded: true));
    await store.recordIfEnabled(sample(elapsed: 1000, chars: 9000, succeeded: false));
    await store.recordIfEnabled(sample(elapsed: 1000, chars: 1000, succeeded: true));

    final summary = await store.summary();
    expect(summary.sampleCount, 3);
    expect(summary.averageOutputCharactersPerSecond, 750);
    expect(summary.successRatePercent, closeTo(66.6667, 0.01));
  });

  test('rejects invalid samples and ignores opt-in when disabled again', () async {
    final store = RuntimeBenchmarkStore();
    await store.setEnabled(true);
    expect(
      () => store.recordIfEnabled(sample(elapsed: 0)),
      throwsArgumentError,
    );
    await store.setEnabled(false);
    await store.recordIfEnabled(sample());
    expect(await store.readRecords(), isEmpty);
  });
}
