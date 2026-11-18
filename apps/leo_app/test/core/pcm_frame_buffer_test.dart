import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../lib/core/voice/pcm_frame_buffer.dart';

void main() {
  group('PcmFrameBuffer', () {
    test('joins irregular chunks into ordered fixed-size frames', () {
      final buffer = PcmFrameBuffer(frameSize: 512);
      final first = Float32List.fromList(List<double>.generate(300, (i) => i.toDouble()));
      final second = Float32List.fromList(List<double>.generate(700, (i) => (i + 300).toDouble()));

      final firstFrames = buffer.add(first);
      expect(firstFrames, isEmpty);
      expect(buffer.pendingSamples, 300);

      final secondFrames = buffer.add(second);
      expect(secondFrames, hasLength(1));
      expect(secondFrames.single, hasLength(512));
      expect(secondFrames.single.first, 0);
      expect(secondFrames.single.last, 511);
      expect(buffer.pendingSamples, 488);

      final finalFrames = buffer.add(Float32List.fromList(List<double>.generate(24, (i) => (i + 1000).toDouble())));
      expect(finalFrames, hasLength(1));
      expect(finalFrames.single.first, 512);
      expect(finalFrames.single.last, 1023);
      expect(buffer.pendingSamples, 0);
    });

    test('retains an incomplete tail and clear discards it', () {
      final buffer = PcmFrameBuffer(frameSize: 4);
      expect(buffer.add(Float32List.fromList([1, 2, 3])), isEmpty);
      expect(buffer.pendingSamples, 3);
      buffer.clear();
      expect(buffer.pendingSamples, 0);
    });
  });
}
