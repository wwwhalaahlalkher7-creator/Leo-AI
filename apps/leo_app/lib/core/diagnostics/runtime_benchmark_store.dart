import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class RuntimeBenchmarkRecord {
  const RuntimeBenchmarkRecord({
    required this.timestampUtc,
    required this.elapsedMilliseconds,
    required this.outputCharacters,
    required this.residentBytes,
    required this.peakResidentBytes,
    required this.platform,
    required this.succeeded,
  });

  final DateTime timestampUtc;
  final int elapsedMilliseconds;
  final int outputCharacters;
  final int residentBytes;
  final int peakResidentBytes;
  final String platform;
  final bool succeeded;

  Map<String, Object?> toJson() => <String, Object?>{
        'timestamp_utc': timestampUtc.toUtc().toIso8601String(),
        'elapsed_ms': elapsedMilliseconds,
        'output_characters': outputCharacters,
        'resident_bytes': residentBytes,
        'peak_resident_bytes': peakResidentBytes,
        'platform': platform,
        'succeeded': succeeded,
      };

  factory RuntimeBenchmarkRecord.fromJson(Map<String, dynamic> json) {
    return RuntimeBenchmarkRecord(
      timestampUtc: DateTime.tryParse(json['timestamp_utc'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      elapsedMilliseconds: json['elapsed_ms'] as int? ?? 0,
      outputCharacters: json['output_characters'] as int? ?? 0,
      residentBytes: json['resident_bytes'] as int? ?? 0,
      peakResidentBytes: json['peak_resident_bytes'] as int? ?? 0,
      platform: json['platform'] as String? ?? 'unknown',
      succeeded: json['succeeded'] as bool? ?? false,
    );
  }
}

class RuntimeBenchmarkSummary {
  const RuntimeBenchmarkSummary({
    required this.sampleCount,
    required this.medianLatencyMilliseconds,
    required this.p95LatencyMilliseconds,
    required this.averageOutputCharactersPerSecond,
    required this.maximumPeakResidentBytes,
    required this.successRatePercent,
  });

  const RuntimeBenchmarkSummary.empty()
      : sampleCount = 0,
        medianLatencyMilliseconds = 0,
        p95LatencyMilliseconds = 0,
        averageOutputCharactersPerSecond = 0,
        maximumPeakResidentBytes = 0,
        successRatePercent = 0;

  final int sampleCount;
  final int medianLatencyMilliseconds;
  final int p95LatencyMilliseconds;
  final double averageOutputCharactersPerSecond;
  final int maximumPeakResidentBytes;
  final double successRatePercent;
}

/// Opt-in metadata-only runtime measurements. This store deliberately excludes
/// prompts, answers, model names, file paths, conversation IDs and request IDs.
class RuntimeBenchmarkStore {
  static const enabledKey = 'leo.runtime.benchmarks.enabled';
  static const _recordsKey = 'leo.runtime.benchmarks.records.v1';
  static const maximumRecords = 80;
  static const maximumSerializedBytes = 48 * 1024;

  Future<bool> get isEnabled async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(enabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(enabledKey, enabled);
  }

  Future<List<RuntimeBenchmarkRecord>> readRecords() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_recordsKey);
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      final records = <RuntimeBenchmarkRecord>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          records.add(RuntimeBenchmarkRecord.fromJson(item));
        }
      }
      return List<RuntimeBenchmarkRecord>.unmodifiable(records.take(maximumRecords));
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  Future<void> recordIfEnabled(RuntimeBenchmarkRecord record) async {
    if (record.elapsedMilliseconds < 1 ||
        record.elapsedMilliseconds > const Duration(hours: 1).inMilliseconds ||
        record.outputCharacters < 0 ||
        record.outputCharacters > 1000000 ||
        record.residentBytes < 0 ||
        record.peakResidentBytes < 0 ||
        record.platform.length > 16 ||
        !<String>{'android', 'windows', 'linux', 'macos', 'ios', 'unknown'}
            .contains(record.platform)) {
      throw ArgumentError('Runtime benchmark values are outside the safe range.');
    }
    final preferences = await SharedPreferences.getInstance();
    if (!(preferences.getBool(enabledKey) ?? false)) return;
    final records = (await readRecords()).toList(growable: true)..add(record);
    while (records.length > maximumRecords) {
      records.removeAt(0);
    }
    String encoded = jsonEncode(records.map((item) => item.toJson()).toList());
    while (utf8.encode(encoded).length > maximumSerializedBytes && records.length > 1) {
      records.removeAt(0);
      encoded = jsonEncode(records.map((item) => item.toJson()).toList());
    }
    if (utf8.encode(encoded).length > maximumSerializedBytes) return;
    await preferences.setString(_recordsKey, encoded);
  }

  Future<RuntimeBenchmarkSummary> summary() async {
    final records = await readRecords();
    if (records.isEmpty) return const RuntimeBenchmarkSummary.empty();
    final latencies = records.map((item) => item.elapsedMilliseconds).toList()..sort();
    final median = latencies.length.isOdd
        ? latencies[latencies.length ~/ 2]
        : ((latencies[(latencies.length ~/ 2) - 1] +
                latencies[latencies.length ~/ 2]) /
            2).round();
    final p95Index = ((latencies.length * 0.95).ceil().clamp(1, latencies.length)).toInt() - 1;
    // Failed/cancelled requests remain in latency and success-rate samples,
    // but must not inflate the output-throughput metric.
    final completedRecords = records.where((item) => item.succeeded).toList();
    final totalSeconds = completedRecords.fold<double>(
      0,
      (sum, item) => sum + item.elapsedMilliseconds / 1000,
    );
    final totalCharacters = completedRecords.fold<int>(
      0,
      (sum, item) => sum + item.outputCharacters,
    );
    final successful = completedRecords.length;
    final maxPeak = records.fold<int>(
      0,
      (maximum, item) => item.peakResidentBytes > maximum
          ? item.peakResidentBytes
          : maximum,
    );
    return RuntimeBenchmarkSummary(
      sampleCount: records.length,
      medianLatencyMilliseconds: median,
      p95LatencyMilliseconds: latencies[p95Index],
      averageOutputCharactersPerSecond:
          totalSeconds > 0 ? totalCharacters / totalSeconds : 0,
      maximumPeakResidentBytes: maxPeak,
      successRatePercent: successful * 100 / records.length,
    );
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_recordsKey);
  }
}
