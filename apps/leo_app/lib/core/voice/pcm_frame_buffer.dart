import 'dart:typed_data';

/// Collects arbitrary PCM sample chunks into fixed-size VAD windows.
/// The incomplete tail is retained until the next chunk and can be discarded
/// safely when capture ends; raw PCM remains available for push-to-talk ASR.
class PcmFrameBuffer {
  PcmFrameBuffer({this.frameSize = 512}) : assert(frameSize > 0);

  final int frameSize;
  final List<double> _pending = <double>[];

  int get pendingSamples => _pending.length;

  List<Float32List> add(Float32List samples) {
    if (samples.isEmpty) return const <Float32List>[];
    _pending.addAll(samples);
    final frames = <Float32List>[];
    while (_pending.length >= frameSize) {
      frames.add(Float32List.fromList(_pending.sublist(0, frameSize)));
      _pending.removeRange(0, frameSize);
    }
    return frames;
  }

  void clear() => _pending.clear();
}
