import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../resources/model_resource_policy.dart';
import 'pcm_frame_buffer.dart';
import 'voice_diagnostics.dart';
import 'voice_pack_store.dart';
import 'wav_encoder.dart';

class LeoVoiceService {
  LeoVoiceService({VoicePackStore? packStore})
    : _packStore = packStore ?? VoicePackStore();

  static const int sampleRate = 16000;
  static const int maximumRecordingSeconds = 30;
  static const int minimumRecordingSamples = sampleRate ~/ 4;
  static const int _maximumSamples = sampleRate * maximumRecordingSeconds;

  final VoicePackStore _packStore;
  final VoiceDiagnosticsStore _diagnostics = VoiceDiagnosticsStore();
  AudioPlayer? _player;
  final List<Float32List> _pcmChunks = <Float32List>[];
  final PcmFrameBuffer _vadFrames = PcmFrameBuffer(frameSize: 512);
  sherpa.VoiceActivityDetector? _vad;
  void Function()? _onVadSpeechEnded;
  void Function(String reason)? _onVadFallback;
  bool _vadActive = false;
  bool _vadStopScheduled = false;
  bool _finishingCapture = false;
  String? _vadFallbackReason;

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _recordSubscription;
  Completer<void>? _playbackCompleter;
  StreamSubscription<void>? _playerCompleteSubscription;
  int? _activePlaybackGeneration;
  int _sampleCount = 0;
  Object? _recordingError;
  bool _recording = false;
  bool _transcribing = false;
  int _captureGeneration = 0;
  bool _disposed = false;
  bool _maximumDurationReached = false;
  int _speechGeneration = 0;

  bool get isRecording => _recording;
  bool get isTranscribing => _transcribing;
  bool get maximumDurationReached => _maximumDurationReached;
  bool get vadActive => _vadActive;
  String? get vadFallbackReason => _vadFallbackReason;

  /// Requests microphone permission only after the user presses the mic button.
  /// No permission or microphone access is requested at app startup. VAD is
  /// optional; a missing/failed VAD model always falls back to manual stop.
  Future<void> startCapture({
    bool useVad = false,
    void Function()? onVadSpeechEnded,
    void Function(String reason)? onVadFallback,
  }) async {
    _ensureNotDisposed();
    if (_recording) return;
    if (_transcribing) {
      throw const VoiceEngineException(
        'ينتظر Leo اكتمال تحويل التسجيل السابق.',
      );
    }
    final generation = ++_captureGeneration;

    _pcmChunks.clear();
    _sampleCount = 0;
    _recordingError = null;
    _maximumDurationReached = false;
    _finishingCapture = false;
    _vadStopScheduled = false;
    _vadFallbackReason = null;
    _onVadSpeechEnded = onVadSpeechEnded;
    _onVadFallback = onVadFallback;
    _vadFrames.clear();
    _disposeVad();
    if (useVad) await _prepareVad(generation);
    _ensureCaptureGeneration(generation);

    final recorder = AudioRecorder();
    _recorder = recorder;
    try {
      // The record plugin implements an OS permission prompt on Android. Its
      // permission-check matrix does not provide a Windows check; Windows
      // desktop apps are governed by the OS microphone privacy switch. On
      // Windows the UI directs users to Settings and native capture is the
      // final OS-enforced gate. Do not treat hasPermission() as a Windows API.
      if (!Platform.isWindows) {
        final permitted = await recorder.hasPermission();
        _ensureCaptureGeneration(generation);
        if (!permitted) {
          throw const VoicePermissionException(
            'لم يتم منح Leo صلاحية استخدام الميكروفون.',
          );
        }
      }
      const encoder = AudioEncoder.pcm16bits;
      if (!await recorder.isEncoderSupported(encoder)) {
        throw const VoiceEngineException(
          'تسجيل PCM16 غير مدعوم على هذا الجهاز.',
        );
      }
      _ensureCaptureGeneration(generation);
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
        ),
      );
      _ensureCaptureGeneration(generation);
      _recording = true;
      _recordSubscription = stream.listen(
        _acceptPcm16,
        onError: (Object error, StackTrace stackTrace) {
          _recordingError = error;
        },
        onDone: () {
          if (_recording) {
            _recordingError ??= const VoiceEngineException(
              'انتهى تدفق الميكروفون قبل إيقاف التسجيل.',
            );
          }
        },
      );
    } catch (_) {
      _recording = false;
      _disposeVad();
      _vadFrames.clear();
      _onVadSpeechEnded = null;
      _onVadFallback = null;
      try {
        await recorder.cancel();
      } catch (_) {
        // The platform may have rejected start before a stream existed.
      } finally {
        try {
          await recorder.dispose();
        } catch (_) {
          // Preserve the original capture error.
        }
        _recorder = null;
      }
      rethrow;
    }
  }

  void _acceptPcm16(Uint8List bytes) {
    if (!_recording || _sampleCount >= _maximumSamples || bytes.length < 2) {
      if (_sampleCount >= _maximumSamples) _maximumDurationReached = true;
      return;
    }
    if (bytes.length.isOdd) {
      _recordingError ??= const VoiceEngineException(
        'وصلت بيانات صوتية غير مكتملة من الميكروفون.',
      );
      return;
    }
    final availableSamples = bytes.length ~/ 2;
    final remainingSamples = _maximumSamples - _sampleCount;
    final count = availableSamples < remainingSamples
        ? availableSamples
        : remainingSamples;
    if (count <= 0) {
      _maximumDurationReached = true;
      return;
    }

    final data = ByteData.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    final samples = Float32List(count);
    for (var i = 0; i < count; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    _pcmChunks.add(samples);
    _sampleCount += count;
    if (_sampleCount >= _maximumSamples) _maximumDurationReached = true;
    _feedVad(samples);
  }

  Future<void> _prepareVad(int generation) async {
    late final VoicePackStatus status;
    try {
      status = await _packStore.inspect();
      _ensureCaptureGeneration(generation);
    } catch (error) {
      if (error is VoiceCaptureCancelledException) rethrow;
      _setVadFallback(
        'تعذر فحص نموذج اكتشاف نهاية الكلام؛ سيبقى الإيقاف يدوياً. $error',
      );
      return;
    }
    if (!status.voiceActivityDetectionReady) {
      _setVadFallback(
        'نموذج اكتشاف نهاية الكلام غير مثبت أو غير سليم؛ سيبقى الإيقاف يدوياً.',
      );
      return;
    }
    try {
      await sherpa.initBindingsAsync();
      _ensureCaptureGeneration(generation);
      final detector = sherpa.VoiceActivityDetector(
        config: sherpa.VadModelConfig(
          sileroVad: sherpa.SileroVadModelConfig(
            model: p.join(
              status.voiceActivityDetectionDirectory,
              'silero_vad.onnx',
            ),
            threshold: 0.5,
            minSilenceDuration: 0.8,
            minSpeechDuration: 0.25,
            windowSize: 512,
            maxSpeechDuration: maximumRecordingSeconds.toDouble(),
          ),
          sampleRate: sampleRate,
          numThreads: ModelResourcePolicy.recommendedVoiceThreads(
            Platform.numberOfProcessors,
          ),
          provider: 'cpu',
          debug: false,
        ),
        bufferSizeInSeconds: maximumRecordingSeconds.toDouble(),
      );
      if (generation != _captureGeneration || _disposed) {
        detector.free();
        throw const VoiceCaptureCancelledException();
      }
      _vad = detector;
      _vadActive = true;
    } catch (error) {
      if (error is VoiceCaptureCancelledException) rethrow;
      _setVadFallback(
        'تعذر تحميل نموذج اكتشاف الكلام؛ سيبقى الإيقاف يدوياً. $error',
      );
      _disposeVad();
    }
  }

  void _setVadFallback(String reason) {
    _vadFallbackReason = reason;
    try {
      _onVadFallback?.call(reason);
    } catch (_) {
      // A UI notification failure must never interrupt manual recording.
    }
  }

  void _feedVad(Float32List samples) {
    final vad = _vad;
    if (!_vadActive || vad == null || _finishingCapture) return;
    try {
      for (final frame in _vadFrames.add(samples)) {
        vad.acceptWaveform(frame);
        _drainVadSegments(vad);
      }
    } catch (error) {
      _setVadFallback(
        'تعطل اكتشاف نهاية الكلام؛ يمكنك إيقاف التسجيل يدوياً. $error',
      );
      _vadActive = false;
      _vadFrames.clear();
      _vadStopScheduled = false;
      _vadSpeechEndedSafely();
      _disposeVad();
    }
  }

  void _drainVadSegments(sherpa.VoiceActivityDetector vad) {
    var completedSpeech = false;
    while (!vad.isEmpty()) {
      completedSpeech = true;
      vad.pop();
    }
    if (!completedSpeech || _vadStopScheduled || _finishingCapture) return;
    if (_sampleCount < minimumRecordingSamples) return;
    _vadStopScheduled = true;
    final callback = _onVadSpeechEnded;
    if (callback != null) {
      scheduleMicrotask(() {
        if (_recording &&
            _vadActive &&
            _vadStopScheduled &&
            !_finishingCapture) {
          callback();
        }
      });
    }
  }

  void _vadSpeechEndedSafely() {
    // VAD errors do not stop recording; the 30-second cap/manual button remain.
    _onVadSpeechEnded = null;
  }

  void _disposeVad() {
    final vad = _vad;
    _vad = null;
    _vadActive = false;
    if (vad != null) {
      try {
        vad.free();
      } catch (_) {
        // Native handles may already be invalid after a runtime failure.
      }
    }
  }

  /// Stops recording, runs local Qwen3-ASR off the UI isolate and returns text.
  /// The result is inserted into the composer; it is never sent automatically.
  Future<String> stopAndTranscribe({
    bool reachedMaximumDuration = false,
  }) async {
    _ensureNotDisposed();
    if (reachedMaximumDuration) _maximumDurationReached = true;
    if (!_recording || _recorder == null) {
      throw const VoiceEngineException('لا يوجد تسجيل صوتي نشط.');
    }

    if (_transcribing) {
      throw const VoiceEngineException('عملية تحويل الصوت جارية بالفعل.');
    }
    final recorder = _recorder!;
    final generation = _captureGeneration;
    _transcribing = true;
    _finishingCapture = true;
    try {
      _recording = false;
      await recorder.stop();
      _ensureCaptureGeneration(generation);
      await _recordSubscription?.cancel();
      if (_recordingError != null) {
        throw VoiceEngineException(
          'حدث خطأ أثناء استقبال الصوت: $_recordingError',
        );
      }

      if (_sampleCount < minimumRecordingSamples) {
        throw const VoiceEngineException(
          'التسجيل قصير جداً. تحدث لمدة ربع ثانية على الأقل.',
        );
      }

      final status = await _packStore.inspect();
      _ensureCaptureGeneration(generation);
      if (!status.speechRecognitionReady) {
        final missing = status.speechRecognitionMissing.isEmpty
            ? status.speechRecognitionIntegrityMessage
            : status.speechRecognitionMissing.join('، ');
        throw VoiceModelMissingException(
          'حزمة التعرف على الكلام غير جاهزة. الملفات/الحالة: $missing. افتح مكتبة نماذج الصوت وأعد الاستيراد أو فحص السلامة.',
        );
      }

      final samples = Float32List(_sampleCount);
      var offset = 0;
      for (final chunk in _pcmChunks) {
        samples.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      final transcript = await _transcribeInWorker(
        samples: samples,
        modelDirectory: status.speechRecognitionDirectory,
      );
      _ensureCaptureGeneration(generation);
      return transcript;
    } finally {
      _recording = false;
      try {
        await _recordSubscription?.cancel();
      } catch (_) {
        // The plugin stream can already be closed by stop().
      }
      _recordSubscription = null;
      try {
        await recorder.dispose();
      } catch (_) {
        // Preserve the transcription/capture result while clearing state.
      }
      _recorder = null;
      _pcmChunks.clear();
      _sampleCount = 0;
      _recordingError = null;
      _vadFrames.clear();
      _vadStopScheduled = false;
      _onVadSpeechEnded = null;
      _onVadFallback = null;
      _disposeVad();
      _finishingCapture = false;
      _transcribing = false;
    }
  }

  Future<void> cancelCapture() async {
    _captureGeneration++;
    final recorder = _recorder;
    _recording = false;
    try {
      await _recordSubscription?.cancel();
    } catch (_) {
      // Continue cleanup even when a platform stream has already terminated.
    } finally {
      _recordSubscription = null;
    }
    if (recorder != null) {
      try {
        await recorder.cancel();
      } catch (_) {
        // The stream may already have stopped; dispose is still required.
      }
      try {
        await recorder.dispose();
      } catch (_) {
        // Do not leave the service in a permanently recording state.
      }
    }
    _recorder = null;
    _pcmChunks.clear();
    _sampleCount = 0;
    _recordingError = null;
    _maximumDurationReached = false;
    _vadFrames.clear();
    _vadStopScheduled = false;
    _onVadSpeechEnded = null;
    _onVadFallback = null;
    _finishingCapture = false;
    // A transcription isolate cannot be forcibly stopped. Keep the busy guard
    // until its generation check discards the stale result and its finally runs.
    if (!_transcribing) _disposeVad();
  }

  /// Generates a local Supertonic-3 WAV file and plays it through the device.
  /// Language is selected from the text, not sent to a remote service.
  Future<void> speak(String text) async {
    _ensureNotDisposed();
    final generation = ++_speechGeneration;

    // Only one output may play at a time. A newer request interrupts the
    // previous playback, while older syntheses are discarded by generation.
    final previousPlayback = _activePlaybackGeneration;
    if (previousPlayback != null) {
      final player = _player;
      try {
        if (player != null) await player.stop();
      } finally {
        _completePlayback(previousPlayback);
      }
    }

    final speechText = _prepareSpeechText(text);
    if (speechText.isEmpty) {
      throw const VoiceEngineException('لا يوجد نص مناسب لتحويله إلى صوت.');
    }
    if (speechText.length > 3000) {
      throw const VoiceEngineException(
        'النص طويل جداً للتشغيل الصوتي. حدد جزءاً أقصر.',
      );
    }

    final status = await _packStore.inspect();
    if (_disposed || generation != _speechGeneration) return;
    if (!status.speechSynthesisReady) {
      throw VoiceModelMissingException(
        'حزمة تحويل النص إلى كلام غير مثبتة أو فشل فحص سلامتها. افتح مكتبة نماذج الصوت.',
      );
    }

    final temp = await getTemporaryDirectory();
    final playbackDirectory = Directory(p.join(temp.path, 'leo-voice'));
    await playbackDirectory.create(recursive: true);
    final wavPath = p.join(
      playbackDirectory.path,
      'leo-tts-${DateTime.now().microsecondsSinceEpoch}-$generation.wav',
    );
    final language = RegExp(r'[\u0600-\u06FF]').hasMatch(speechText)
        ? 'ar'
        : 'en';

    try {
      await _synthesizeInWorker(
        text: speechText,
        language: language,
        modelDirectory: status.speechSynthesisDirectory,
        outputPath: wavPath,
      );
      if (_disposed || generation != _speechGeneration) return;

      final player = _player ??= AudioPlayer();
      final playback = Completer<void>();
      _playbackCompleter = playback;
      _activePlaybackGeneration = generation;
      _playerCompleteSubscription ??= player.onPlayerComplete.listen(
        (_) => _completeCurrentPlayback(),
      );
      await player.play(DeviceFileSource(wavPath));
      await playback.future;
    } finally {
      // A superseded request must never complete a newer request's playback.
      _completePlayback(generation);
      final file = File(wavPath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> stopSpeaking() async {
    _speechGeneration++;
    final generation = _activePlaybackGeneration;
    final player = _player;
    try {
      if (player != null) await player.stop();
    } finally {
      if (generation != null) _completePlayback(generation);
    }
  }

  void _completeCurrentPlayback() {
    final generation = _activePlaybackGeneration;
    if (generation != null) _completePlayback(generation);
  }

  void _completePlayback(int generation) {
    if (_activePlaybackGeneration != generation) return;
    final completer = _playbackCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
    _playbackCompleter = null;
    _activePlaybackGeneration = null;
  }

  String _prepareSpeechText(String source) {
    var text = source
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' مقطع برمجي. ')
        .replaceAllMapped(RegExp(r'`([^`]+)`'), (match) => ' ${match[1]} ')
        .replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), ' ')
        .replaceAllMapped(
          RegExp(r'\[([^\]]+)\]\([^)]*\)'),
          (match) => match[1] ?? '',
        )
        .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
        .replaceAll(RegExp(r'[*_~]{1,3}'), '')
        .replaceAll(RegExp(r'\$\$[\s\S]*?\$\$'), ' معادلة رياضية. ')
        .replaceAll(RegExp(r'\$[^$\n]+\$'), ' معادلة. ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text;
  }

  Future<String> _transcribeInWorker({
    required Float32List samples,
    required String modelDirectory,
  }) async {
    final outcome = await Isolate.run<Map<String, Object?>>(() async {
      var engineVersion = 'غير متاح';
      var onnxVersion = 'غير متاح';
      try {
        await sherpa.initBindingsAsync();
        engineVersion = sherpa.getVersion();
        onnxVersion = sherpa.getOnnxruntimeVersion();
      } catch (error) {
        return <String, Object?>{
          'ok': false,
          'stage': 'native_runtime',
          'error': error.toString(),
          'engine_version': engineVersion,
          'onnxruntime_version': onnxVersion,
          'model_load_ms': 0,
          'inference_ms': 0,
          'process_peak_rss_bytes': readProcessPeakRssBytes(),
        };
      }

      final tokenizer = p.join(modelDirectory, 'tokenizer');
      final loadTimer = Stopwatch()..start();
      late final sherpa.OfflineRecognizer recognizer;
      try {
        recognizer = sherpa.OfflineRecognizer(
          sherpa.OfflineRecognizerConfig(
            feat: const sherpa.FeatureConfig(
              sampleRate: sampleRate,
              featureDim: 128,
            ),
            model: sherpa.OfflineModelConfig(
              qwen3Asr: sherpa.OfflineQwen3AsrModelConfig(
                convFrontend: p.join(modelDirectory, 'conv_frontend.onnx'),
                encoder: p.join(modelDirectory, 'encoder.int8.onnx'),
                decoder: p.join(modelDirectory, 'decoder.int8.onnx'),
                tokenizer: tokenizer,
                maxTotalLen: 512,
                maxNewTokens: 128,
              ),
              tokens: '',
              numThreads: ModelResourcePolicy.recommendedVoiceThreads(
                Platform.numberOfProcessors,
              ),
              debug: false,
              provider: 'cpu',
            ),
          ),
        );
      } catch (error) {
        loadTimer.stop();
        return <String, Object?>{
          'ok': false,
          'stage': 'model_load',
          'error': error.toString(),
          'engine_version': engineVersion,
          'onnxruntime_version': onnxVersion,
          'model_load_ms': loadTimer.elapsedMilliseconds,
          'inference_ms': 0,
          'process_peak_rss_bytes': readProcessPeakRssBytes(),
        };
      }
      loadTimer.stop();

      final inferenceTimer = Stopwatch()..start();
      try {
        final stream = recognizer.createStream();
        try {
          stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
          recognizer.decode(stream);
          final text = recognizer.getResult(stream).text.trim();
          inferenceTimer.stop();
          return <String, Object?>{
            'ok': true,
            'text': text,
            'stage': 'complete',
            'engine_version': engineVersion,
            'onnxruntime_version': onnxVersion,
            'model_load_ms': loadTimer.elapsedMilliseconds,
            'inference_ms': inferenceTimer.elapsedMilliseconds,
            'process_peak_rss_bytes': readProcessPeakRssBytes(),
          };
        } finally {
          stream.free();
        }
      } catch (error) {
        inferenceTimer.stop();
        return <String, Object?>{
          'ok': false,
          'stage': 'inference',
          'error': error.toString(),
          'engine_version': engineVersion,
          'onnxruntime_version': onnxVersion,
          'model_load_ms': loadTimer.elapsedMilliseconds,
          'inference_ms': inferenceTimer.elapsedMilliseconds,
          'process_peak_rss_bytes': readProcessPeakRssBytes(),
        };
      } finally {
        recognizer.free();
      }
    });

    await _saveWorkerMetrics('asr', outcome);
    if (outcome['ok'] != true) {
      final stage = outcome['stage'] as String? ?? 'unknown';
      final detail = outcome['error']?.toString() ?? 'سبب غير معروف';
      final message = switch (stage) {
        'native_runtime' =>
          'تعذر تحميل مكتبة محرك الصوت الأصلية. تحقق من تثبيت نسخة التطبيق المطابقة للنظام. $detail',
        'model_load' =>
          'تعذر تحميل نموذج التعرف. افحص ملفات الحزمة وبصماتها ثم أعد استيرادها عند الحاجة. $detail',
        'inference' =>
          'فشل تحليل التسجيل بالنموذج. قد تكون الذاكرة غير كافية أو الملف الصوتي غير مناسب. $detail',
        _ => 'فشل تشغيل محرك التعرف على الكلام. $detail',
      };
      throw VoiceEngineException(message);
    }
    return outcome['text'] as String? ?? '';
  }

  Future<void> _synthesizeInWorker({
    required String text,
    required String language,
    required String modelDirectory,
    required String outputPath,
  }) async {
    final outcome = await Isolate.run<Map<String, Object?>>(() async {
      var engineVersion = 'غير متاح';
      var onnxVersion = 'غير متاح';
      try {
        await sherpa.initBindingsAsync();
        engineVersion = sherpa.getVersion();
        onnxVersion = sherpa.getOnnxruntimeVersion();
      } catch (error) {
        return <String, Object?>{
          'ok': false,
          'stage': 'native_runtime',
          'error': error.toString(),
          'engine_version': engineVersion,
          'onnxruntime_version': onnxVersion,
          'model_load_ms': 0,
          'inference_ms': 0,
          'process_peak_rss_bytes': readProcessPeakRssBytes(),
        };
      }

      final loadTimer = Stopwatch()..start();
      late final sherpa.OfflineTts tts;
      try {
        tts = sherpa.OfflineTts(
          sherpa.OfflineTtsConfig(
            model: sherpa.OfflineTtsModelConfig(
              supertonic: sherpa.OfflineTtsSupertonicModelConfig(
                durationPredictor: p.join(
                  modelDirectory,
                  'duration_predictor.int8.onnx',
                ),
                textEncoder: p.join(modelDirectory, 'text_encoder.int8.onnx'),
                vectorEstimator: p.join(
                  modelDirectory,
                  'vector_estimator.int8.onnx',
                ),
                vocoder: p.join(modelDirectory, 'vocoder.int8.onnx'),
                ttsJson: p.join(modelDirectory, 'tts.json'),
                unicodeIndexer: p.join(modelDirectory, 'unicode_indexer.bin'),
                voiceStyle: p.join(modelDirectory, 'voice.bin'),
              ),
              numThreads: ModelResourcePolicy.recommendedVoiceThreads(
                Platform.numberOfProcessors,
              ),
              debug: false,
              provider: 'cpu',
            ),
          ),
        );
      } catch (error) {
        loadTimer.stop();
        return <String, Object?>{
          'ok': false,
          'stage': 'model_load',
          'error': error.toString(),
          'engine_version': engineVersion,
          'onnxruntime_version': onnxVersion,
          'model_load_ms': loadTimer.elapsedMilliseconds,
          'inference_ms': 0,
          'process_peak_rss_bytes': readProcessPeakRssBytes(),
        };
      }
      loadTimer.stop();

      final inferenceTimer = Stopwatch()..start();
      try {
        final audio = tts.generateWithConfig(
          text: text,
          config: sherpa.OfflineTtsGenerationConfig(
            sid: 0,
            speed: 1.0,
            numSteps: 8,
            extra: {'lang': language, 'num_steps': 8},
          ),
        );
        if (audio.samples.isEmpty || audio.sampleRate <= 0) {
          throw const VoiceEngineException(
            'لم ينتج محرك الصوت ملفاً صوتياً صالحاً.',
          );
        }
        await writeMonoPcm16Wav(
          path: outputPath,
          samples: audio.samples,
          sampleRate: audio.sampleRate,
        );
        inferenceTimer.stop();
        return <String, Object?>{
          'ok': true,
          'stage': 'complete',
          'engine_version': engineVersion,
          'onnxruntime_version': onnxVersion,
          'model_load_ms': loadTimer.elapsedMilliseconds,
          'inference_ms': inferenceTimer.elapsedMilliseconds,
          'process_peak_rss_bytes': readProcessPeakRssBytes(),
        };
      } catch (error) {
        inferenceTimer.stop();
        return <String, Object?>{
          'ok': false,
          'stage': 'inference',
          'error': error.toString(),
          'engine_version': engineVersion,
          'onnxruntime_version': onnxVersion,
          'model_load_ms': loadTimer.elapsedMilliseconds,
          'inference_ms': inferenceTimer.elapsedMilliseconds,
          'process_peak_rss_bytes': readProcessPeakRssBytes(),
        };
      } finally {
        tts.free();
      }
    });

    await _saveWorkerMetrics('tts', outcome);
    if (outcome['ok'] != true) {
      final stage = outcome['stage'] as String? ?? 'unknown';
      final detail = outcome['error']?.toString() ?? 'سبب غير معروف';
      final message = switch (stage) {
        'native_runtime' =>
          'تعذر تحميل مكتبة الصوت الأصلية على هذا النظام. $detail',
        'model_load' =>
          'تعذر تحميل نموذج توليد الصوت. افحص ملفاته وسجل السلامة ثم أعد استيراده. $detail',
        'inference' =>
          'فشل توليد الصوت. قد تكون الذاكرة غير كافية أو إعدادات النموذج غير متوافقة. $detail',
        _ => 'فشل تشغيل محرك تحويل النص إلى كلام. $detail',
      };
      throw VoiceEngineException(message);
    }
  }

  Future<void> _saveWorkerMetrics(
    String operation,
    Map<String, Object?> outcome,
  ) async {
    try {
      await _diagnostics.recordIfEnabled(
        VoiceRunMetrics(
          operation: operation,
          modelLoadMilliseconds: outcome['model_load_ms'] as int? ?? 0,
          inferenceMilliseconds: outcome['inference_ms'] as int? ?? 0,
          processPeakRssBytes: outcome['process_peak_rss_bytes'] as int? ?? 0,
          engineVersion: outcome['engine_version'] as String? ?? 'غير متاح',
          onnxRuntimeVersion:
              outcome['onnxruntime_version'] as String? ?? 'غير متاح',
          completedAtUtc: DateTime.now().toUtc(),
          errorStage: outcome['ok'] == true
              ? null
              : outcome['stage'] as String?,
        ),
      );
    } catch (_) {
      // Diagnostics are optional and must never block transcription or speech.
    }
  }

  void _ensureCaptureGeneration(int generation) {
    if (_disposed || generation != _captureGeneration) {
      throw const VoiceCaptureCancelledException();
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) throw const VoiceEngineException('محرك الصوت مغلق.');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancelCapture();
    await stopSpeaking();
    await _playerCompleteSubscription?.cancel();
    await _player?.dispose();
    _player = null;
  }
}

class VoiceEngineException implements Exception {
  const VoiceEngineException(this.message);
  final String message;
  @override
  String toString() => message;
}

class VoiceCaptureCancelledException extends VoiceEngineException {
  const VoiceCaptureCancelledException()
    : super('أُلغي التسجيل قبل اكتمال تحويله.');
}

class VoicePermissionException extends VoiceEngineException {
  const VoicePermissionException(super.message);
}

class VoiceModelMissingException extends VoiceEngineException {
  const VoiceModelMissingException(super.message);
}
