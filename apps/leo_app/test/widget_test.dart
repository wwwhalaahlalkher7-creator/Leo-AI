import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/main.dart';
import 'package:leo_app/core/chat/assistant_runtime_client.dart';
import 'package:leo_app/core/chat/chat_repository.dart';
import 'package:leo_app/features/chat/chat_page.dart';
import 'package:leo_app/core/memory/memory_repository.dart';
import 'package:leo_app/core/skills/skill_models.dart';
import 'package:leo_app/core/skills/skill_repository.dart';
import 'package:leo_app/core/skills/skill_execution_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Leo opens with its Arabic welcome screen', (tester) async {
    await tester.pumpWidget(const LeoApp());
    await _pumpUi(tester);

    expect(find.text('Leo'), findsOneWidget);
    expect(find.text('مرحباً، أنا Leo'), findsOneWidget);
    expect(find.textContaining('ربط محرك الذكاء المحلي قيد التطوير'), findsOneWidget);
  });

  testWidgets('the initial chat suggestions can fill the composer', (
    tester,
  ) async {
    await tester.pumpWidget(const LeoApp());
    await _pumpUi(tester);

    await tester.tap(find.text('الرياضيات'));
    await tester.pump();

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller!.text, 'اشرح لي النهايات خطوة بخطوة');
  });

  testWidgets('chat sends requests through an injected streaming runtime', (
    tester,
  ) async {
    final runtime = _StreamingTestRuntime();
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ChatPage(
            runtimeClient: runtime,
            memoryRepository: _EmptyMemoryRepository(),
            skillRepository: _EmptySkillRepository(),
            skillRunRepository: _emptySkillRunRepository(),
          ),
        ),
      ),
    );
    await _pumpUi(tester);

    await tester.enterText(find.byType(TextField), 'رسالة اختبار');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _pumpUi(tester);

    expect(runtime.requests, hasLength(1));
    expect(runtime.requests.single.messages.last.content, 'رسالة اختبار');
  });

  testWidgets('only active validated skills enter transient chat context', (
    tester,
  ) async {
    final runtime = _StreamingTestRuntime();
    final preferences = await SharedPreferences.getInstance();
    final chatRepository = ChatRepository(preferences);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ChatPage(
            repository: chatRepository,
            runtimeClient: runtime,
            memoryRepository: _EmptyMemoryRepository(),
            skillRepository: _ActiveSkillRepository(),
            skillRunRepository: _emptySkillRunRepository(),
          ),
        ),
      ),
    );
    await _pumpUi(tester);

    await tester.enterText(find.byType(TextField), 'رتب ملفاتي الدراسية');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await _pumpUi(tester);

    final request = runtime.requests.single;
    expect(
      request.messages.any(
        (message) =>
            message.role == 'system' &&
            message.content.contains('<leo_skill_guidance>'),
      ),
      isTrue,
    );
    final savedMessages = chatRepository.loadSessions().single.messages;
    expect(
      savedMessages.every(
        (message) => !message.content.contains('<leo_skill_guidance>'),
      ),
      isTrue,
    );
  });

  testWidgets('skill library is reachable from the chat header', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ChatPage(
            runtimeClient: _StreamingTestRuntime(),
            memoryRepository: _EmptyMemoryRepository(),
            skillRepository: _EmptySkillRepository(),
            skillRunRepository: _emptySkillRunRepository(),
          ),
        ),
      ),
    );
    await _pumpUi(tester);

    await tester.tap(find.byTooltip('مكتبات Leo'));
    await _pumpUi(tester);
    await tester.tap(find.text('المهارات'));
    await _pumpUi(tester);

    expect(find.text('مهارات Leo'), findsOneWidget);
    expect(find.text('مكتبة المهارات فارغة حالياً'), findsOneWidget);
  });
}

SkillRunRepository _emptySkillRunRepository() =>
    SkillRunRepository(secureStore: _EmptySkillRunSecureStore());

class _EmptySkillRunSecureStore implements SkillRunSecureStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }
}

class _StreamingTestRuntime implements AssistantRuntimeClient {
  final List<RuntimeRequest> requests = [];

  @override
  Stream<RuntimeEvent> generate(RuntimeRequest request) async* {
    requests.add(request);
    yield const RuntimeEvent(RuntimeEventType.started);
    yield const RuntimeEvent(RuntimeEventType.delta, text: 'إجابة ');
    yield const RuntimeEvent(RuntimeEventType.delta, text: 'اختبار');
    yield const RuntimeEvent(RuntimeEventType.completed);
  }

  @override
  Future<void> cancel(String requestId) async {}
}

class _EmptyMemoryRepository implements MemoryRepository {
  @override
  Future<LeoMemoryEntry> approve(String memoryId) =>
      Future.error(UnimplementedError());

  @override
  Future<bool> delete(String memoryId) => Future.error(UnimplementedError());

  @override
  Future<List<LeoMemoryEntry>> list({
    bool includePending = true,
    int limit = 200,
  }) async => const [];

  @override
  Future<List<LeoMemorySearchHit>> search(
    String query, {
    int limit = 5,
  }) async => const [];

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
  }) => Future.error(UnimplementedError());

  @override
  Future<LeoMemoryEntry> setActive(String memoryId, bool active) =>
      Future.error(UnimplementedError());

  @override
  Future<LeoMemoryEntry> updateApproved({
    required String memoryId,
    required String content,
    required List<String> tags,
    String? sourceReference,
  }) => Future.error(UnimplementedError());
}

class _EmptySkillRepository implements SkillRepository {
  @override
  Future<LeoSkill> activate(String skillId) =>
      Future.error(UnimplementedError());

  @override
  Future<LeoSkill> createProposal({
    required String name,
    required String description,
    required List<String> triggers,
    required String instructions,
    required List<String> steps,
    required List<LeoSkillTestCase> testCases,
    required List<String> requiredCapabilities,
    String? sourceTaskId,
  }) => Future.error(UnimplementedError());

  @override
  Future<bool> delete(String skillId) => Future.error(UnimplementedError());

  @override
  Future<LeoSkill> disable(String skillId) =>
      Future.error(UnimplementedError());

  @override
  Future<List<LeoSkill>> findApplicable(
    String request, {
    int limit = 2,
  }) async => const [];

  @override
  Future<List<LeoSkill>> list() async => const [];

  @override
  Future<LeoSkill> reject(String skillId) => Future.error(UnimplementedError());

  @override
  Future<LeoSkill> updateProposal({
    required String skillId,
    required String name,
    required String description,
    required List<String> triggers,
    required String instructions,
    required List<String> steps,
    required List<LeoSkillTestCase> testCases,
    required List<String> requiredCapabilities,
    required String changeSummary,
  }) => Future.error(UnimplementedError());

  @override
  Future<LeoSkill> validate(String skillId) =>
      Future.error(UnimplementedError());
}

class _ActiveSkillRepository extends _EmptySkillRepository {
  @override
  Future<List<LeoSkill>> findApplicable(
    String request, {
    int limit = 2,
  }) async => [
    const LeoSkill(
      id: 'skill-files',
      name: 'تنظيم الملفات الدراسية',
      description: 'خطوات لترتيب الملفات حسب المادة والفصل.',
      triggers: ['رتب ملفاتي الدراسية'],
      instructions: 'اعرض خطة قبل تغيير أي ملف.',
      steps: ['استكشف الملفات.', 'اقترح هيكل المجلدات.', 'انتظر الموافقة.'],
      testCases: [],
      requiredCapabilities: ['files.read', 'files.write'],
      status: LeoSkillStatus.active,
      version: '0.1.0',
      createdAtUtc: '2026-11-15T00:00:00Z',
      updatedAtUtc: '2026-11-15T00:00:00Z',
      history: [],
      validationReport: LeoSkillValidationReport(
        checkedAtUtc: '2026-11-15T00:00:00Z',
        passed: true,
        checks: [],
        disclaimer: 'Preflight only',
      ),
    ),
  ];
}


Future<void> _pumpUi(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
