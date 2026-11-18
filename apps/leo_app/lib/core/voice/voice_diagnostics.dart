import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class VoiceRunMetrics {
  const VoiceRunMetrics({
    required this.operation,
    required this.modelLoadMilliseconds,
    required this.inferenceMilliseconds,
    required this.processPeakRssBytes,
    required this.engineVersion,
    required this.onnxRuntimeVersion,
    required this.completedAtUtc,
    this.errorStage,
  });

  final String operation;
  final int modelLoadMilliseconds;
  final int inferenceMilliseconds;
  final int processPeakRssBytes;
  final String engineVersion;
  final String onnxRuntimeVersion;
  final DateTime completedAtUtc;
  final String? errorStage;

  Map<String, Object?> toJson() => {
        'operation': operation,
        'model_load_ms': modelLoadMilliseconds,
        'inference_ms': inferenceMilliseconds,
        'process_peak_rss_bytes': processPeakRssBytes,
        'engine_version': engineVersion,
        'onnxruntime_version': onnxRuntimeVersion,
        'completed_at_utc': completedAtUtc.toUtc().toIso8601String(),
        'error_stage': errorStage,
      };

  factory VoiceRunMetrics.fromJson(Map<String, dynamic> json) {
    return VoiceRunMetrics(
      operation: json['operation'] as String? ?? 'unknown',
      modelLoadMilliseconds: json['model_load_ms'] as int? ?? 0,
      inferenceMilliseconds: json['inference_ms'] as int? ?? 0,
      processPeakRssBytes: json['process_peak_rss_bytes'] as int? ?? 0,
      engineVersion: json['engine_version'] as String? ?? 'غير متاح',
      onnxRuntimeVersion: json['onnxruntime_version'] as String? ?? 'غير متاح',
      completedAtUtc: DateTime.tryParse(json['completed_at_utc'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      errorStage: json['error_stage'] as String?,
    );
  }
}

/// Opt-in, metadata-only measurements. No audio, transcript, prompt, file path,
/// or model payload is stored in this record.
class VoiceDiagnosticsStore {
  static const String metricsEnabledKey = 'leo.voice.metrics_enabled';
  static const String vadEnabledKey = 'leo.voice.vad_auto_stop_enabled';
  static const String _asrMetricsKey = 'leo.voice.metrics.asr.latest';
  static const String _ttsMetricsKey = 'leo.voice.metrics.tts.latest';

  Future<bool> get metricsEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(metricsEnabledKey) ?? false;
  }

  Future<void> setMetricsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(metricsEnabledKey, enabled);
  }

  Future<bool> get vadAutoStopEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(vadEnabledKey) ?? false;
  }

  Future<void> setVadAutoStopEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(vadEnabledKey, enabled);
  }

  Future<void> recordIfEnabled(VoiceRunMetrics metrics) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(metricsEnabledKey) ?? false)) return;
    final key = metrics.operation == 'asr' ? _asrMetricsKey : _ttsMetricsKey;
    await prefs.setString(key, jsonEncode(metrics.toJson()));
  }

  Future<VoiceRunMetrics?> readLatest(String operation) async {
    final prefs = await SharedPreferences.getInstance();
    final key = operation == 'asr' ? _asrMetricsKey : _ttsMetricsKey;
    final value = prefs.getString(key);
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) return null;
      return VoiceRunMetrics.fromJson(decoded);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> clearMetrics() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_asrMetricsKey);
    await prefs.remove(_ttsMetricsKey);
  }
}

class VoiceRuntimePreflightResult {
  const VoiceRuntimePreflightResult({
    required this.success,
    required this.engineVersion,
    required this.onnxRuntimeVersion,
    required this.elapsedMilliseconds,
    this.error,
  });

  final bool success;
  final String engineVersion;
  final String onnxRuntimeVersion;
  final int elapsedMilliseconds;
  final String? error;
}

class VoiceRuntimeDiagnostics {
  static Future<VoiceRuntimePreflightResult> checkNativeRuntime() async {
    final timer = Stopwatch()..start();
    try {
      await sherpa.initBindingsAsync();
      final engine = sherpa.getVersion();
      final onnx = sherpa.getOnnxruntimeVersion();
      timer.stop();
      return VoiceRuntimePreflightResult(
        success: true,
        engineVersion: engine,
        onnxRuntimeVersion: onnx,
        elapsedMilliseconds: timer.elapsedMilliseconds,
      );
    } catch (error) {
      timer.stop();
      return VoiceRuntimePreflightResult(
        success: false,
        engineVersion: 'غير متاح',
        onnxRuntimeVersion: 'غير متاح',
        elapsedMilliseconds: timer.elapsedMilliseconds,
        error: error.toString(),
      );
    }
  }
}

int readProcessPeakRssBytes() {
  try {
    return ProcessInfo.maxRss;
  } catch (_) {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return 0;
    }
  }
}

