import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/core/memory/memory_backup_service.dart';
import 'package:leo_app/core/memory/memory_repository.dart';

void main() {
  test(
    'exports AES-GCM encrypted backup and imports entries as pending proposals',
    () async {
      final source = _MemoryRepository()..seed(_entry('secret private memory'));
      final backup = await MemoryBackupService(source)
          .exportEncrypted('correct horse battery staple 2026');
      expect(utf8.decode(backup), isNot(contains('secret private memory')));
      expect(utf8.decode(backup), contains('AES-256-GCM'));

      final destination = _MemoryRepository();
      final report = await MemoryBackupService(destination)
          .importEncrypted(backup, 'correct horse battery staple 2026');
      expect(report.proposed, 1);
      expect(report.duplicatesSkipped, 0);
      expect(destination.records.single.content, 'secret private memory');
      expect(destination.records.single.userApproved, isFalse);
      expect(destination.records.single.active, isFalse);
    },
  );

  test('rejects an incorrect backup passphrase', () async {
    final source = _MemoryRepository()..seed(_entry('do not leak this'));
    final backup = await MemoryBackupService(source)
        .exportEncrypted('correct horse battery staple 2026');
    await expectLater(
      MemoryBackupService(_MemoryRepository())
          .importEncrypted(backup, 'incorrect password 2026'),
      throwsA(isA<Exception>()),
    );
  });

  test('rejects malformed and oversized backup envelopes', () async {
    final service = MemoryBackupService(_MemoryRepository());
    await expectLater(
      service.importEncrypted(
        utf8.encode('{"format":"not-leo"}'),
        'correct horse battery staple 2026',
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      service.importEncrypted(
        List<int>.filled(MemoryBackupService.maxBackupBytes + 1, 0),
        'correct horse battery staple 2026',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('requires a passphrase with at least twelve characters', () async {
    await expectLater(
      MemoryBackupService(_MemoryRepository()).exportEncrypted('short'),
      throwsA(isA<FormatException>()),
    );
  });
}

LeoMemoryEntry _entry(String content) => LeoMemoryEntry(
  id: 'memory-source',
  kind: LeoMemoryKind.project,
  content: content,
  tags: const ['Leo'],
  createdAtUtc: '2026-11-18T00:00:00Z',
  updatedAtUtc: '2026-11-18T00:00:00Z',
  userApproved: true,
  active: true,
  sourceReference: 'private path deliberately omitted',
);

class _MemoryRepository implements MemoryRepository {
  final List<LeoMemoryEntry> records = [];

  void seed(LeoMemoryEntry entry) => records.add(entry);

  @override
  Future<LeoMemoryEntry> propose({
    required LeoMemoryKind kind,
    required String content,
    required List<String> tags,
    String? sourceReference,
  }) async {
    if (records.any(
      (entry) => entry.kind == kind && entry.content == content,
    )) {
      throw StateError('duplicate memory');
    }
    final entry = LeoMemoryEntry(
      id: 'import-${records.length}',
      kind: kind,
      content: content,
      tags: List.unmodifiable(tags),
      createdAtUtc: DateTime.now().toUtc().toIso8601String(),
      updatedAtUtc: DateTime.now().toUtc().toIso8601String(),
      userApproved: false,
      active: false,
      sourceReference: sourceReference,
    );
    records.add(entry);
    return entry;
  }

  @override
  Future<List<LeoMemoryEntry>> list({
    bool includePending = true,
    int limit = 200,
  }) async => records
      .where((entry) => includePending || entry.userApproved)
      .take(limit)
      .toList();

  @override
  Future<List<LeoMemorySearchHit>> search(
    String query, {
    int limit = 5,
  }) async => const [];
  @override
  Future<LeoMemoryEntry> approve(String memoryId) async =>
      throw UnimplementedError();
  @override
  Future<bool> delete(String memoryId) async => throw UnimplementedError();
  @override
  Future<bool> eraseAllAndVerify() async => throw UnimplementedError();
  @override
  Future<void> rotateEncryptionKey() async => throw UnimplementedError();
  @override
  Future<LeoMemoryEntry> saveApproved({
    required LeoMemoryKind kind,
    required String content,
    required List<String> tags,
    String? sourceReference,
  }) async => throw UnimplementedError();
  @override
  Future<LeoMemoryEntry> setActive(String memoryId, bool active) async =>
      throw UnimplementedError();
  @override
  Future<LeoMemoryEntry> updateApproved({
    required String memoryId,
    required String content,
    required List<String> tags,
    String? sourceReference,
  }) async => throw UnimplementedError();
}
