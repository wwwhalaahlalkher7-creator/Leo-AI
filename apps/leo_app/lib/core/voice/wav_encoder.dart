import 'dart:io';
import 'dart:typed_data';

/// Encodes normalized mono floating-point samples as a standard PCM16 WAV.
/// This pure-Dart implementation avoids native path-encoding differences on
/// Windows and keeps WAV output independent of the inference runtime.
Uint8List encodeMonoPcm16Wav({
  required Float32List samples,
  required int sampleRate,
}) {
  if (samples.isEmpty) {
    throw ArgumentError.value(samples.length, 'samples', 'Must not be empty.');
  }
  if (sampleRate < 8000 || sampleRate > 192000) {
    throw ArgumentError.value(
      sampleRate,
      'sampleRate',
      'Must be between 8 kHz and 192 kHz.',
    );
  }

  final dataLength = samples.length * 2;
  if (dataLength > 0xFFFFFFFF - 36) {
    throw ArgumentError('Audio is too large for a RIFF/WAV file.');
  }

  final bytes = Uint8List(44 + dataLength);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, const [0x52, 0x49, 0x46, 0x46]); // RIFF
  data.setUint32(4, 36 + dataLength, Endian.little);
  bytes.setRange(8, 12, const [0x57, 0x41, 0x56, 0x45]); // WAVE
  bytes.setRange(12, 16, const [0x66, 0x6D, 0x74, 0x20]); // fmt
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little); // block align
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, const [0x64, 0x61, 0x74, 0x61]); // data
  data.setUint32(40, dataLength, Endian.little);

  for (var index = 0; index < samples.length; index++) {
    final sample = samples[index];
    final normalized = sample.isFinite ? sample.clamp(-1.0, 1.0) : 0.0;
    final pcm = normalized < 0
        ? (normalized * 32768).round()
        : (normalized * 32767).round();
    data.setInt16(44 + index * 2, pcm, Endian.little);
  }

  return bytes;
}

Future<void> writeMonoPcm16Wav({
  required String path,
  required Float32List samples,
  required int sampleRate,
}) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(
    encodeMonoPcm16Wav(samples: samples, sampleRate: sampleRate),
    flush: true,
  );
}
