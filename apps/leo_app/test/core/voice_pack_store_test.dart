import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../lib/core/voice/voice_pack_store.dart';

void main() {
  late Directory tempDirectory;
  late VoicePackStore store;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('leo-voice-pack-test-');
    store = VoicePackStore(rootDirectory: tempDirectory);
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<List<PlatformFile>> makeSelectedFiles(List<String> requiredFiles) async {
    final sourceDirectory = Directory(p.join(tempDirectory.path, 'source'));
    await sourceDirectory.create(recursive: true);
    final selected = <PlatformFile>[];
    for (final relative in requiredFiles) {
      final file = File(p.join(sourceDirectory.path, p.basename(relative)));
      await file.writeAsBytes([1, 2, 3, 4, 5, 6]);
      selected.add(_TestPlatformFile(name: p.basename(relative), path: file.path));
    }
    return selected;
  }

  test('imports a pack with bounded streamed SHA-256 entries', () async {
    final files = await makeSelectedFiles(VoicePackStore.speechSynthesisFiles);
    await store.importFiles(kind: VoicePackKind.speechSynthesis, files: files);

    final status = await store.inspect();
    expect(status.speechSynthesisReady, isTrue);
    expect(status.speechSynthesisIntegrity, VoicePackIntegrity.baseline);

    final manifest = File(p.join(
      status.speechSynthesisDirectory,
      VoicePackStore.manifestFileName,
    ));
    expect(await manifest.exists(), isTrue);
    final contents = await manifest.readAsString();
    expect(contents, contains('"sha256"'));
    expect(contents, contains('"size_bytes"'));
  });

  test('verifies a baseline then flags a same-size content change', () async {
    final files = await makeSelectedFiles(VoicePackStore.speechSynthesisFiles);
    await store.importFiles(kind: VoicePackKind.speechSynthesis, files: files);

    final first = await store.verifyIntegrity(VoicePackKind.speechSynthesis);
    expect(first.valid, isTrue);
    expect(first.createdBaseline, isFalse);

    final status = await store.inspect();
    final modelFile = File(p.join(status.speechSynthesisDirectory, 'voice.bin'));
    await modelFile.writeAsBytes([9, 8, 7, 6, 5, 4]);

    final second = await store.verifyIntegrity(VoicePackKind.speechSynthesis);
    expect(second.valid, isFalse);
    expect(second.mismatches, contains('voice.bin'));
    expect((await store.inspect()).speechSynthesisReady, isFalse);
  });

  test('adopts a complete legacy pack by creating a local baseline', () async {
    final legacyDirectory = Directory(p.join(
      tempDirectory.path,
      VoicePackStore.speechRecognitionPackId,
    ));
    await legacyDirectory.create(recursive: true);
    for (final relative in VoicePackStore.speechRecognitionFiles) {
      final file = File(p.join(legacyDirectory.path, relative));
      await file.parent.create(recursive: true);
      await file.writeAsBytes([1, 2, 3, 4]);
    }

    final before = await store.inspect();
    expect(before.speechRecognitionReady, isTrue);
    expect(before.speechRecognitionIntegrity, VoicePackIntegrity.legacyUnverified);

    final result = await store.verifyIntegrity(VoicePackKind.speechRecognition);
    expect(result.valid, isTrue);
    expect(result.createdBaseline, isTrue);
    expect((await store.inspect()).speechRecognitionIntegrity, VoicePackIntegrity.baseline);
  });

  test('imports and verifies the optional Silero VAD pack', () async {
    final files = await makeSelectedFiles(VoicePackStore.voiceActivityDetectionFiles);
    await store.importFiles(
      kind: VoicePackKind.voiceActivityDetection,
      files: files,
    );

    final status = await store.inspect();
    expect(status.voiceActivityDetectionReady, isTrue);
    expect(status.voiceActivityDetectionMissing, isEmpty);
    expect(status.voiceActivityDetectionIntegrity, VoicePackIntegrity.baseline);

    final result = await store.verifyIntegrity(VoicePackKind.voiceActivityDetection);
    expect(result.valid, isTrue);
    expect((await store.inspect()).voiceActivityDetectionIntegrity,
        VoicePackIntegrity.verified);
  });

  test('rejects duplicate selected required filenames', () async {
    final files = await makeSelectedFiles(VoicePackStore.speechSynthesisFiles);
    files.add(files.first);
    await expectLater(
      store.importFiles(kind: VoicePackKind.speechSynthesis, files: files),
      throwsA(isA<VoicePackImportException>()),
    );
  });
}

base class _TestPlatformFile extends PlatformFile {
  _TestPlatformFile({required this.name, required this.path});

  @override
  final String name;

  @override
  final String? path;

  @override
  Uri get uri => Uri.file(path!);

  @override
  XFile get xFile => XFile(path!);

  @override
  Future<int> length() => File(path!).length();

  @override
  int? lengthSync() => File(path!).lengthSync();

  @override
  Future<Uint8List> readAsBytes() => File(path!).readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      File(path!).openRead().map(Uint8List.fromList);
}
