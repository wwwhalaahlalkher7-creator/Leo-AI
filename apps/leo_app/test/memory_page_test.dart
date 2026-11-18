import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/core/memory/memory_repository.dart';
import 'package:leo_app/features/memory/memory_page.dart';

void main() {
  testWidgets('memory page states local storage boundary and empty state', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MemoryPage(repository: _FakeMemoryRepository()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('ذاكرة Leo'), findsOneWidget);
    expect(find.textContaining('AES-256-GCM'), findsOneWidget);
    expect(find.text('لا توجد ذكريات محفوظة بعد.'), findsOneWidget);
  });

  testWidgets('chat-derived memory suggestion is saved only as a pending proposal', (tester) async {
    final repository = _RecordingMemoryRepository();
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MemoryPage(
          repository: repository,
          suggestionContent: 'أفضل أن يعمل Leo دون إنترنت',
          suggestionSourceReference: 'chat-message:test-session:test-message',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('مراجعة اقتراح ذاكرة'), findsOneWidget);
    expect(find.textContaining('لن يدخل سياق المحادثات'), findsOneWidget);
    await tester.tap(find.text('إضافة كاقتراح للمراجعة'));
    await tester.pumpAndSettle();

    expect(repository.proposals, hasLength(1));
    expect(repository.proposals.single.content, 'أفضل أن يعمل Leo دون إنترنت');
    expect(repository.proposals.single.userApproved, isFalse);
    expect(repository.proposals.single.active, isFalse);
    expect(repository.proposals.single.sourceReference, 'chat-message:test-session:test-message');
  });
}

class _RecordingMemoryRepository implements MemoryRepository {
  final List<LeoMemoryEntry> proposals = [];

  @override
  Future<List<LeoMemoryEntry>> list({bool includePending = true, int limit = 200}) async => proposals.take(limit).toList();

  @override
  Future<LeoMemoryEntry> propose({
    required LeoMemoryKind kind,
    required String content,
    required List<String> tags,
    String? sourceReference,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final entry = LeoMemoryEntry(
      id: 'proposal-${proposals.length}',
      kind: kind,
      content: content,
      tags: List.unmodifiable(tags),
      createdAtUtc: now,
      updatedAtUtc: now,
      userApproved: false,
      active: false,
      sourceReference: sourceReference,
    );
    proposals.add(entry);
    return entry;
  }

  @override
  Future<List<LeoMemorySearchHit>> search(String query, {int limit = 5}) async => const [];
  @override
  Future<LeoMemoryEntry> approve(String memoryId) async => throw UnimplementedError();
  @override
  Future<LeoMemoryEntry> setActive(String memoryId, bool active) async => throw UnimplementedError();
  @override
  Future<LeoMemoryEntry> updateApproved({required String memoryId, required String content, required List<String> tags, String? sourceReference}) async => throw UnimplementedError();
  @override
  Future<bool> delete(String memoryId) async => throw UnimplementedError();
  @override
  Future<LeoMemoryEntry> saveApproved({required LeoMemoryKind kind, required String content, required List<String> tags, String? sourceReference}) async => throw UnimplementedError();
  @override
  Future<void> rotateEncryptionKey() async => throw UnimplementedError();
  @override
  Future<bool> eraseAllAndVerify() async => throw UnimplementedError();
}

class _FakeMemoryRepository implements MemoryRepository {
  const _FakeMemoryRepository();

  @override
  Future<LeoMemoryEntry> approve(String memoryId) => throw UnimplementedError();

  @override
  Future<bool> delete(String memoryId) => throw UnimplementedError();

  @override
  Future<List<LeoMemoryEntry>> list({bool includePending = true, int limit = 200}) async => const [];

  @override
  Future<List<LeoMemorySearchHit>> search(String query, {int limit = 5}) async => const [];

  @override
  Future<LeoMemoryEntry> propose({
    required LeoMemoryKind kind,
    required String content,
    required List<String> tags,
    String? sourceReference,
  }) => Future.error(UnimplementedError());

  @override
  Future<void> rotateEncryptionKey() => Future.error(UnimplementedError());

  @override
  Future<bool> eraseAllAndVerify() => Future.error(UnimplementedError());

  @override
  Future<LeoMemoryEntry> saveApproved({
    required LeoMemoryKind kind,
    required String content,
    required List<String> tags,
    String? sourceReference,
  }) => throw UnimplementedError();

  @override
  Future<LeoMemoryEntry> setActive(String memoryId, bool active) => throw UnimplementedError();

  @override
  Future<LeoMemoryEntry> updateApproved({
    required String memoryId,
    required String content,
    required List<String> tags,
    String? sourceReference,
  }) => throw UnimplementedError();
}
