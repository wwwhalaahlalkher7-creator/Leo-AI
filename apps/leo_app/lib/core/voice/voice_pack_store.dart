import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Voice model packages are optional and live outside the Flutter asset bundle.
/// This keeps multi-hundred-megabyte ONNX weights out of the base installer.
enum VoicePackKind {
  speechRecognition,
  speechSynthesis,
  voiceActivityDetection,
}

enum VoicePackIntegrity {
  unavailable,
  legacyUnverified,
  baseline,
  verified,
  failed,
}

class VoicePackStatus {
  const VoicePackStatus({
    required this.speechRecognitionReady,
    required this.speechSynthesisReady,
    required this.voiceActivityDetectionReady,
    required this.speechRecognitionMissing,
    required this.speechSynthesisMissing,
    required this.voiceActivityDetectionMissing,
    required this.speechRecognitionDirectory,
    required this.speechSynthesisDirectory,
    required this.voiceActivityDetectionDirectory,
    required this.speechRecognitionIntegrity,
    required this.speechSynthesisIntegrity,
    required this.voiceActivityDetectionIntegrity,
    required this.speechRecognitionIntegrityMessage,
    required this.speechSynthesisIntegrityMessage,
    required this.voiceActivityDetectionIntegrityMessage,
  });

  final bool speechRecognitionReady;
  final bool speechSynthesisReady;
  final bool voiceActivityDetectionReady;
  final List<String> speechRecognitionMissing;
  final List<String> speechSynthesisMissing;
  final List<String> voiceActivityDetectionMissing;
  final String speechRecognitionDirectory;
  final String speechSynthesisDirectory;
  final String voiceActivityDetectionDirectory;
  final VoicePackIntegrity speechRecognitionIntegrity;
  final VoicePackIntegrity speechSynthesisIntegrity;
  final VoicePackIntegrity voiceActivityDetectionIntegrity;
  final String speechRecognitionIntegrityMessage;
  final String speechSynthesisIntegrityMessage;
  final String voiceActivityDetectionIntegrityMessage;
}

class VoicePackIntegrityResult {
  const VoicePackIntegrityResult({
    required this.valid,
    required this.createdBaseline,
    required this.mismatches,
    required this.verifiedAtUtc,
  });

  final bool valid;
  final bool createdBaseline;
  final List<String> mismatches;
  final DateTime verifiedAtUtc;
}

class VoicePackStore {
  VoicePackStore({Directory? rootDirectory}) : _providedRoot = rootDirectory;

  static const String speechRecognitionPackId = 'qwen3-asr-0.6b-int8';
  static const String speechSynthesisPackId = 'supertonic-3-int8';
  static const String voiceActivityDetectionPackId = 'silero-vad';
  static const int maximumFileBytes = 1536 * 1024 * 1024;
  static const int maximumPackBytes = 3 * 1024 * 1024 * 1024;
  static const int manifestSchemaVersion = 1;
  static const String manifestFileName = '.leo-voice-pack.json';

  final Directory? _providedRoot;

  static const List<String> speechRecognitionFiles = [
    'conv_frontend.onnx',
    'encoder.int8.onnx',
    'decoder.int8.onnx',
    'tokenizer/merges.txt',
    'tokenizer/tokenizer_config.json',
    'tokenizer/vocab.json',
  ];

  static const List<String> speechSynthesisFiles = [
    'duration_predictor.int8.onnx',
    'text_encoder.int8.onnx',
    'vector_estimator.int8.onnx',
    'vocoder.int8.onnx',
    'tts.json',
    'unicode_indexer.bin',
    'voice.bin',
  ];

  static const List<String> voiceActivityDetectionFiles = ['silero_vad.onnx'];

  Future<Directory> _root() async {
    final root =
        _providedRoot ??
        Directory(
          p.join(
            (await getApplicationSupportDirectory()).path,
            'leo',
            'voice',
            'packs',
          ),
        );
    await root.create(recursive: true);
    return root;
  }

  String _packId(VoicePackKind kind) => switch (kind) {
    VoicePackKind.speechRecognition => speechRecognitionPackId,
    VoicePackKind.speechSynthesis => speechSynthesisPackId,
    VoicePackKind.voiceActivityDetection => voiceActivityDetectionPackId,
  };

  List<String> _requiredFiles(VoicePackKind kind) => switch (kind) {
    VoicePackKind.speechRecognition => speechRecognitionFiles,
    VoicePackKind.speechSynthesis => speechSynthesisFiles,
    VoicePackKind.voiceActivityDetection => voiceActivityDetectionFiles,
  };

  Future<Directory> _packDirectory(VoicePackKind kind) async {
    final root = await _root();
    return Directory(p.join(root.path, _packId(kind)));
  }

  Future<VoicePackStatus> inspect() async {
    final asrDirectory = await _packDirectory(VoicePackKind.speechRecognition);
    final ttsDirectory = await _packDirectory(VoicePackKind.speechSynthesis);
    final vadDirectory = await _packDirectory(
      VoicePackKind.voiceActivityDetection,
    );
    final asr = await _inspectPack(
      asrDirectory,
      speechRecognitionPackId,
      speechRecognitionFiles,
    );
    final tts = await _inspectPack(
      ttsDirectory,
      speechSynthesisPackId,
      speechSynthesisFiles,
    );
    final vad = await _inspectPack(
      vadDirectory,
      voiceActivityDetectionPackId,
      voiceActivityDetectionFiles,
    );

    return VoicePackStatus(
      speechRecognitionReady: asr.ready,
      speechSynthesisReady: tts.ready,
      voiceActivityDetectionReady: vad.ready,
      speechRecognitionMissing: asr.missing,
      speechSynthesisMissing: tts.missing,
      voiceActivityDetectionMissing: vad.missing,
      speechRecognitionDirectory: asrDirectory.path,
      speechSynthesisDirectory: ttsDirectory.path,
      voiceActivityDetectionDirectory: vadDirectory.path,
      speechRecognitionIntegrity: asr.integrity,
      speechSynthesisIntegrity: tts.integrity,
      voiceActivityDetectionIntegrity: vad.integrity,
      speechRecognitionIntegrityMessage: asr.message,
      speechSynthesisIntegrityMessage: tts.message,
      voiceActivityDetectionIntegrityMessage: vad.message,
    );
  }

  Future<_PackInspection> _inspectPack(
    Directory directory,
    String packId,
    List<String> requiredPaths,
  ) async {
    final missing = await _missingFiles(directory, requiredPaths);
    if (missing.isNotEmpty) {
      return _PackInspection(
        ready: false,
        missing: missing,
        integrity: VoicePackIntegrity.unavailable,
        message: 'بعض الملفات المطلوبة غير موجودة أو فارغة.',
      );
    }

    final manifestFile = File(p.join(directory.path, manifestFileName));
    if (!await manifestFile.exists()) {
      return const _PackInspection(
        ready: true,
        missing: [],
        integrity: VoicePackIntegrity.legacyUnverified,
        message: 'حزمة قديمة بلا سجل بصمات. أجرِ فحص السلامة لإنشاء سجل محلي.',
      );
    }

    try {
      final manifest = jsonDecode(await manifestFile.readAsString());
      final entries = _validatedManifestEntries(
        manifest,
        packId: packId,
        requiredPaths: requiredPaths,
      );
      final integrityStatus = manifest['integrity_status'];
      if (!const {'baseline', 'verified', 'failed'}.contains(integrityStatus)) {
        throw const FormatException(
          'Invalid integrity status in voice-pack manifest.',
        );
      }
      if (integrityStatus == 'failed') {
        final mismatchNames =
            (manifest['verification_mismatches'] as List?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const <String>[];
        return _PackInspection(
          ready: false,
          missing: [],
          integrity: VoicePackIntegrity.failed,
          message: mismatchNames.isEmpty
              ? 'فشل آخر فحص سلامة. أعد استيراد الحزمة من المصدر الرسمي.'
              : 'اكتُشفت ملفات مختلفة: ${mismatchNames.join('، ')}. أعد استيراد الحزمة.',
        );
      }

      for (final relativePath in requiredPaths) {
        final file = File(p.join(directory.path, relativePath));
        final expectedSize = entries[relativePath]!['size_bytes'] as int;
        if (await file.length() != expectedSize) {
          return _PackInspection(
            ready: false,
            missing: [],
            integrity: VoicePackIntegrity.failed,
            message: 'تغيّر حجم الملف $relativePath منذ إنشاء سجل البصمات.',
          );
        }
      }

      final lastVerified = manifest['last_verified_utc'];
      final parsedVerificationTime = lastVerified is String
          ? DateTime.tryParse(lastVerified)
          : null;
      final isVerified =
          integrityStatus == 'verified' &&
          parsedVerificationTime != null &&
          parsedVerificationTime.isUtc;
      return _PackInspection(
        ready: true,
        missing: [],
        integrity: isVerified
            ? VoicePackIntegrity.verified
            : VoicePackIntegrity.baseline,
        message: isVerified ? 'اجتازت الملفات آخر فحص SHA-256 مسجل.' : 'توجد بصمات SHA-256 محلية. أعد الفحص قبل الاعتماد على سلامة الملفات.',
      );
    } catch (error) {
      return _PackInspection(
        ready: false,
        missing: [],
        integrity: VoicePackIntegrity.failed,
        message: 'سجل سلامة الحزمة غير صالح: $error',
      );
    }
  }

  Future<void> importFiles({
    required VoicePackKind kind,
    required List<PlatformFile> files,
  }) async {
    if (files.isEmpty) {
      throw const VoicePackImportException('لم يتم اختيار ملفات.');
    }

    final requiredPaths = _requiredFiles(kind);
    final expectedByName = <String, String>{
      for (final relative in requiredPaths) p.basename(relative): relative,
    };
    final selectedByName = <String, PlatformFile>{};
    for (final file in files) {
      final normalizedName = file.name.trim().replaceAll('\\', '/');
      final name = normalizedName.split('/').last;
      if (!expectedByName.containsKey(name)) continue;
      if (selectedByName.containsKey(name)) {
        throw VoicePackImportException('تم اختيار الملف $name أكثر من مرة.');
      }
      selectedByName[name] = file;
    }

    final missing = expectedByName.keys
        .where((name) => !selectedByName.containsKey(name))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      throw VoicePackImportException(
        'الملفات التالية غير موجودة في الاختيار: ${missing.join(', ')}',
      );
    }

    final target = await _packDirectory(kind);
    final parent = target.parent;
    await parent.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final staging = Directory(
      p.join(parent.path, '.${p.basename(target.path)}-$stamp.tmp'),
    );
    final backup = Directory(
      p.join(parent.path, '.${p.basename(target.path)}-$stamp.bak'),
    );
    await staging.create(recursive: true);

    var copiedPackBytes = 0;
    final manifestEntries = <Map<String, Object>>[];
    try {
      for (final entry in expectedByName.entries) {
        final relativePath = entry.value;
        final source = selectedByName[entry.key]!;
        final destination = File(p.join(staging.path, relativePath));
        final declaredSize = await source.length();
        if (declaredSize <= 0 || declaredSize > maximumFileBytes) {
          throw VoicePackImportException(
            'حجم الملف ${source.name} غير متاح أو غير صالح أو يتجاوز الحد المسموح.',
          );
        }
        if (declaredSize > maximumPackBytes - copiedPackBytes) {
          throw const VoicePackImportException(
            'حجم حزمة الصوت الإجمالي يتجاوز 3 GiB.',
          );
        }
        copiedPackBytes += declaredSize;
        await destination.parent.create(recursive: true);

        final hashResult = _SingleDigestSink();
        final hashInput = sha256.startChunkedConversion(hashResult);
        final stream = source.readAsByteStream();
        final sink = destination.openWrite();
        var streamedBytes = 0;
        try {
          await sink.addStream(
            stream.map((chunk) {
              streamedBytes += chunk.length;
              if (streamedBytes > maximumFileBytes ||
                  streamedBytes > declaredSize) {
                throw VoicePackImportException(
                  'تجاوز الملف ${source.name} حجمه المعلن.',
                );
              }
              hashInput.add(chunk);
              return chunk;
            }),
          );
          await sink.flush();
        } finally {
          try {
            await sink.close();
          } finally {
            hashInput.close();
          }
        }

        if (streamedBytes != declaredSize) {
          throw VoicePackImportException(
            'حجم الملف ${source.name} لا يطابق الحجم المعلن.',
          );
        }
        if (!await destination.exists() ||
            await destination.length() != declaredSize) {
          throw VoicePackImportException(
            'تعذر نسخ الملف ${source.name} بالحجم الصحيح.',
          );
        }
        final digest = hashResult.digest;
        if (digest == null) {
          throw VoicePackImportException(
            'تعذر حساب بصمة SHA-256 للملف ${source.name}.',
          );
        }
        manifestEntries.add({
          'path': relativePath,
          'size_bytes': streamedBytes,
          'sha256': digest.toString(),
        });
      }

      final stagedMissing = await _missingFiles(staging, requiredPaths);
      if (stagedMissing.isNotEmpty) {
        throw VoicePackImportException(
          'فشل التحقق من الحزمة بعد النسخ: ${stagedMissing.join(', ')}',
        );
      }

      await _writeManifest(
        staging,
        _createManifest(
          packId: _packId(kind),
          entries: manifestEntries,
          integrityStatus: 'baseline',
        ),
      );

      if (await target.exists()) await target.rename(backup.path);
      try {
        await staging.rename(target.path);
      } catch (_) {
        if (await backup.exists() && !await target.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }
      if (await backup.exists()) await backup.delete(recursive: true);
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      if (await backup.exists() && !await target.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
  }

  /// Re-hashes every required model file. For legacy packs without a manifest,
  /// this creates a local SHA-256 baseline; it does not prove upstream origin.
  Future<VoicePackIntegrityResult> verifyIntegrity(VoicePackKind kind) async {
    final directory = await _packDirectory(kind);
    final requiredPaths = _requiredFiles(kind);
    final missing = await _missingFiles(directory, requiredPaths);
    if (missing.isNotEmpty) {
      throw VoicePackImportException(
        'لا يمكن فحص الحزمة قبل استكمال الملفات: ${missing.join(', ')}',
      );
    }

    final manifestFile = File(p.join(directory.path, manifestFileName));
    final createdBaseline = !await manifestFile.exists();
    Map<String, dynamic> manifest;
    if (createdBaseline) {
      final entries = <Map<String, Object>>[];
      var totalBytes = 0;
      for (final relativePath in requiredPaths) {
        final file = File(p.join(directory.path, relativePath));
        final size = await file.length();
        if (size <= 0 ||
            size > maximumFileBytes ||
            size > maximumPackBytes - totalBytes) {
          throw VoicePackImportException(
            'حجم الملف $relativePath أو حجم الحزمة الإجمالي خارج الحدود المسموحة.',
          );
        }
        totalBytes += size;
        final digest = await _hashFile(file);
        entries.add({
          'path': relativePath,
          'size_bytes': size,
          'sha256': digest,
        });
      }
      manifest = _createManifest(
        packId: _packId(kind),
        entries: entries,
        integrityStatus: 'baseline',
      );
      await _writeManifest(directory, manifest);
      return VoicePackIntegrityResult(
        valid: true,
        createdBaseline: true,
        mismatches: const [],
        verifiedAtUtc: DateTime.now().toUtc(),
      );
    } else {
      final decoded = jsonDecode(await manifestFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const VoicePackImportException(
          'سجل بصمات الحزمة ليس كائن JSON صالحاً.',
        );
      }
      _validatedManifestEntries(
        decoded,
        packId: _packId(kind),
        requiredPaths: requiredPaths,
      );
      manifest = decoded;
    }

    final entries = _validatedManifestEntries(
      manifest,
      packId: _packId(kind),
      requiredPaths: requiredPaths,
    );
    final mismatches = <String>[];
    for (final relativePath in requiredPaths) {
      final file = File(p.join(directory.path, relativePath));
      final metadata = entries[relativePath]!;
      final expectedSize = metadata['size_bytes'] as int;
      final expectedDigest = metadata['sha256'] as String;
      if (await file.length() != expectedSize) {
        mismatches.add(relativePath);
        continue;
      }
      final actualDigest = await _hashFile(file);
      if (actualDigest != expectedDigest) mismatches.add(relativePath);
    }

    final verifiedAt = DateTime.now().toUtc();
    manifest['integrity_status'] = mismatches.isEmpty ? 'verified' : 'failed';
    manifest['last_verified_utc'] = verifiedAt.toIso8601String();
    manifest['verification_mismatches'] = mismatches;
    await _writeManifest(directory, manifest);

    return VoicePackIntegrityResult(
      valid: mismatches.isEmpty,
      createdBaseline: createdBaseline,
      mismatches: mismatches,
      verifiedAtUtc: verifiedAt,
    );
  }

  Future<String> _hashFile(File file) async {
    final result = _SingleDigestSink();
    final input = sha256.startChunkedConversion(result);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    final digest = result.digest;
    if (digest == null) throw StateError('SHA-256 returned no digest');
    return digest.toString();
  }

  Map<String, dynamic> _createManifest({
    required String packId,
    required List<Map<String, Object>> entries,
    required String integrityStatus,
  }) => {
    'schema_version': manifestSchemaVersion,
    'pack_id': packId,
    'runtime': 'sherpa-onnx 2.0.1',
    'created_at_utc': DateTime.now().toUtc().toIso8601String(),
    'integrity_status': integrityStatus,
    'last_verified_utc': null,
    'verification_mismatches': <String>[],
    'files': entries,
  };

  Map<String, Map<String, dynamic>> _validatedManifestEntries(
    Object? value, {
    required String packId,
    required List<String> requiredPaths,
  }) {
    if (value is! Map<String, dynamic> ||
        value['schema_version'] != manifestSchemaVersion ||
        value['pack_id'] != packId ||
        value['files'] is! List) {
      throw const FormatException(
        'Unsupported or mismatched voice-pack manifest.',
      );
    }

    final entries = <String, Map<String, dynamic>>{};
    for (final raw in value['files'] as List) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException(
          'Invalid file entry in voice-pack manifest.',
        );
      }
      final path = raw['path'];
      final size = raw['size_bytes'];
      final digest = raw['sha256'];
      if (path is! String ||
          size is! int ||
          size <= 0 ||
          size > maximumFileBytes ||
          digest is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
          !requiredPaths.contains(path) ||
          entries.containsKey(path)) {
        throw const FormatException(
          'Invalid or duplicate voice-pack file metadata.',
        );
      }
      entries[path] = raw;
    }
    final totalBytes = entries.values.fold<int>(
      0,
      (total, entry) => total + (entry['size_bytes'] as int),
    );
    if (entries.length != requiredPaths.length ||
        !requiredPaths.every(entries.containsKey) ||
        totalBytes > maximumPackBytes) {
      throw const FormatException(
        'Voice-pack manifest does not list every required file or exceeds the pack size limit.',
      );
    }
    return entries;
  }

  Future<void> _writeManifest(
    Directory directory,
    Map<String, dynamic> manifest,
  ) async {
    const encoder = JsonEncoder.withIndent('  ');
    final target = File(p.join(directory.path, manifestFileName));
    final temporary = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    await temporary.writeAsString(
      '${encoder.convert(manifest)}\n',
      flush: true,
    );
    if (await backup.exists()) await backup.delete();
    if (await target.exists()) await target.rename(backup.path);
    try {
      await temporary.rename(target.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await backup.exists() && !await target.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<List<String>> _missingFiles(
    Directory root,
    List<String> required,
  ) async {
    final missing = <String>[];
    for (final relative in required) {
      final file = File(p.join(root.path, relative));
      if (!await file.exists()) {
        missing.add(relative);
        continue;
      }
      try {
        if (await file.length() <= 0) missing.add(relative);
      } on FileSystemException {
        missing.add(relative);
      }
    }
    return missing;
  }
}

class _PackInspection {
  const _PackInspection({
    required this.ready,
    required this.missing,
    required this.integrity,
    required this.message,
  });

  final bool ready;
  final List<String> missing;
  final VoicePackIntegrity integrity;
  final String message;
}

class _SingleDigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest value) {
    if (digest != null)
      throw StateError('A digest was emitted more than once.');
    digest = value;
  }

  @override
  void close() {}
}

class VoicePackImportException implements Exception {
  const VoicePackImportException(this.message);

  final String message;

  @override
  String toString() => message;
}
