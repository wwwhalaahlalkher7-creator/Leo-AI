/// Conservative resource guidance shared by the model library and offline voice.
///
/// The GGUF admission estimate intentionally mirrors the native adapter's
/// `has_sufficient_memory` calculation. It is a pre-load estimate, not a claim
/// that the model will fit: the native loader independently checks live
/// available physical memory immediately before allocating model weights.
class ModelResourcePolicy {
  ModelResourcePolicy._();

  static const int minimumContextTokens = 512;
  static const int maximumContextTokens = 4096;
  static const int defaultContextTargetTokens = 2048;
  static const int maximumModelThreads = 4;
  static const int maximumVoiceThreads = 2;

  static final BigInt _bytesPerMiB = BigInt.from(1024 * 1024);
  static final BigInt _baseReserveBytes = BigInt.from(384) * _bytesPerMiB;
  static final BigInt _contextReservePer2048Bytes =
      BigInt.from(128) * _bytesPerMiB;

  static const List<int> contextChoices = <int>[512, 1024, 2048, 4096];

  /// Leaves at least one logical processor available to the OS/UI when the
  /// device has more than one. Model inference is capped at four CPU threads.
  static int recommendedModelThreads(int logicalProcessors) {
    final cores = logicalProcessors < 1 ? 1 : logicalProcessors;
    return (cores - 1).clamp(1, maximumModelThreads).toInt();
  }

  /// Speech workloads are kept smaller than chat inference so recording,
  /// playback and the foreground UI remain responsive on modest devices.
  static int recommendedVoiceThreads(int logicalProcessors) {
    final cores = logicalProcessors < 1 ? 1 : logicalProcessors;
    return (cores - 1).clamp(1, maximumVoiceThreads).toInt();
  }

  /// Returns supported context presets that do not exceed the GGUF header.
  static List<int> supportedContextChoices(int modelContextLength) {
    final maximum = modelContextLength.clamp(0, maximumContextTokens).toInt();
    return contextChoices
        .where((value) => value <= maximum)
        .toList(growable: false);
  }

  /// Prefers a 2K context to reduce KV-cache pressure; smaller declared
  /// contexts fall back to the largest supported preset below that ceiling.
  static int defaultContextTokens(int modelContextLength) {
    final choices = supportedContextChoices(modelContextLength);
    if (choices.isEmpty) return 0;
    for (final value in choices.reversed) {
      if (value <= defaultContextTargetTokens) return value;
    }
    return choices.first;
  }

  /// Mirrors native/llama/src/llama_probe.cpp exactly:
  /// model file + 12.5% margin + 384 MiB process reserve + 128 MiB per
  /// (rounded-up) 2048 context tokens.
  static BigInt estimateRequiredAvailableMemory({
    required BigInt modelFileSizeBytes,
    required int contextTokens,
  }) {
    if (modelFileSizeBytes <= BigInt.zero) {
      throw ArgumentError.value(modelFileSizeBytes, 'modelFileSizeBytes');
    }
    if (contextTokens < minimumContextTokens ||
        contextTokens > maximumContextTokens) {
      throw ArgumentError.value(contextTokens, 'contextTokens');
    }
    final contextUnits = (contextTokens + 2047) ~/ 2048;
    return modelFileSizeBytes +
        (modelFileSizeBytes ~/ BigInt.from(8)) +
        _baseReserveBytes +
        (BigInt.from(contextUnits) * _contextReservePer2048Bytes);
  }
}

class ModelLoadConfiguration {
  const ModelLoadConfiguration({
    required this.contextTokens,
    required this.threads,
  });

  final int contextTokens;
  final int threads;
}
