import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/core/resources/model_resource_policy.dart';

void main() {
  group('ModelResourcePolicy', () {
    test(
      'reserves at least one logical processor and caps chat threads at four',
      () {
        expect(ModelResourcePolicy.recommendedModelThreads(0), 1);
        expect(ModelResourcePolicy.recommendedModelThreads(1), 1);
        expect(ModelResourcePolicy.recommendedModelThreads(2), 1);
        expect(ModelResourcePolicy.recommendedModelThreads(4), 3);
        expect(ModelResourcePolicy.recommendedModelThreads(16), 4);
      },
    );

    test('uses a smaller CPU budget for speech workloads', () {
      expect(ModelResourcePolicy.recommendedVoiceThreads(1), 1);
      expect(ModelResourcePolicy.recommendedVoiceThreads(2), 1);
      expect(ModelResourcePolicy.recommendedVoiceThreads(4), 2);
      expect(ModelResourcePolicy.recommendedVoiceThreads(16), 2);
    });

    test('context presets never exceed the context declared by GGUF', () {
      expect(ModelResourcePolicy.supportedContextChoices(3072), <int>[
        512,
        1024,
        2048,
      ]);
      expect(ModelResourcePolicy.supportedContextChoices(4096), <int>[
        512,
        1024,
        2048,
        4096,
      ]);
      expect(ModelResourcePolicy.supportedContextChoices(256), isEmpty);
    });

    test('defaults to no more than 2048 context tokens', () {
      expect(ModelResourcePolicy.defaultContextTokens(4096), 2048);
      expect(ModelResourcePolicy.defaultContextTokens(1024), 1024);
      expect(ModelResourcePolicy.defaultContextTokens(256), 0);
    });

    test('memory estimate mirrors the native adapter admission formula', () {
      const gib = 1024 * 1024 * 1024;
      final for2k = ModelResourcePolicy.estimateRequiredAvailableMemory(
        modelFileSizeBytes: BigInt.from(gib),
        contextTokens: 2048,
      );
      final for4k = ModelResourcePolicy.estimateRequiredAvailableMemory(
        modelFileSizeBytes: BigInt.from(gib),
        contextTokens: 4096,
      );
      final expected2k =
          BigInt.from(gib) +
          BigInt.from(gib ~/ 8) +
          BigInt.from(384 + 128) * BigInt.from(1024 * 1024);
      expect(for2k, expected2k);
      expect(for4k - for2k, BigInt.from(128 * 1024 * 1024));
    });

    test('rejects invalid model size and context inputs', () {
      expect(
        () => ModelResourcePolicy.estimateRequiredAvailableMemory(
          modelFileSizeBytes: BigInt.zero,
          contextTokens: 2048,
        ),
        throwsArgumentError,
      );
      expect(
        () => ModelResourcePolicy.estimateRequiredAvailableMemory(
          modelFileSizeBytes: BigInt.from(1024),
          contextTokens: 256,
        ),
        throwsArgumentError,
      );
    });
  });
}
