import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/core/voice/wav_encoder.dart';

void main() {
  group('encodeMonoPcm16Wav', () {
    test('writes a valid PCM16 mono RIFF/WAV header and samples', () {
      final wav = encodeMonoPcm16Wav(
        samples: Float32List.fromList([-1.0, 0.0, 1.0]),
        sampleRate: 16000,
      );
      final bytes = ByteData.sublistView(wav);

      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(bytes.getUint32(4, Endian.little), 42);
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(bytes.getUint16(20, Endian.little), 1);
      expect(bytes.getUint16(22, Endian.little), 1);
      expect(bytes.getUint32(24, Endian.little), 16000);
      expect(bytes.getUint32(28, Endian.little), 32000);
      expect(bytes.getUint16(32, Endian.little), 2);
      expect(bytes.getUint16(34, Endian.little), 16);
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
      expect(bytes.getUint32(40, Endian.little), 6);
      expect(bytes.getInt16(44, Endian.little), -32768);
      expect(bytes.getInt16(46, Endian.little), 0);
      expect(bytes.getInt16(48, Endian.little), 32767);
    });

    test('clamps out-of-range samples and neutralizes non-finite values', () {
      final wav = encodeMonoPcm16Wav(
        samples: Float32List.fromList([-2.0, 2.0, double.nan, double.infinity]),
        sampleRate: 24000,
      );
      final bytes = ByteData.sublistView(wav);

      expect(bytes.getInt16(44, Endian.little), -32768);
      expect(bytes.getInt16(46, Endian.little), 32767);
      expect(bytes.getInt16(48, Endian.little), 0);
      expect(bytes.getInt16(50, Endian.little), 0);
    });

    test('rejects empty samples and unsupported sample rates', () {
      expect(
        () => encodeMonoPcm16Wav(samples: Float32List(0), sampleRate: 16000),
        throwsArgumentError,
      );
      expect(
        () => encodeMonoPcm16Wav(
          samples: Float32List.fromList([0.1]),
          sampleRate: 4000,
        ),
        throwsArgumentError,
      );
    });
  });
}
