import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/core/chat/assistant_runtime_client.dart';
import 'package:leo_app/core/chat/chat_models.dart';
import 'package:leo_app/core/skills/skill_execution_service.dart';
import 'package:leo_app/core/skills/skill_learning_service.dart';
import 'package:leo_app/core/skills/skill_models.dart';
import 'package:leo_app/core/skills/skill_repository.dart';

const validDraft = '''
```json
{
  "can_create": true,
  "reason": "",
  "name": "تنظيم ملفات الدراسة",
  "description": "يرتب الملفات الدراسية حسب المادة والفصل الدراسي بطريقة قابلة للتكرار.",
  "triggers": ["رتب ملفاتي الدراسية", "نظم مجلد الجامعة"],
  "instructions": "افحص المجلدات أولاً وحدد الملفات دون تعديلها. أنشئ خطة واضحة لهيكل المجلدات، واعرضها للمستخدم، واحتفظ بالأصل. لا تنقل أو تحذف أو تعيد تسمية أي ملف قبل موافقة المستخدم الصريحة.",
  "steps": [
    "افحص الملفات الموجودة وحدد أنواعها ومحتواها دون إجراء تغيير.",
    "اقترح بنية مجلدات حسب المادة والفصل الدراسي واعرض الخطة.",
    "انتظر موافقة المستخدم قبل نقل الملفات أو إعادة تسميتها.",
    "تحقق من النتيجة وأبلغ المستخدم بالملفات التي تم تنظيمها."
  ],
  "test_cases": [
    {"input": "رتب ملفات محاضرات الفصل الحالي", "expected_outcome": "يعرض خطة تنظيم ثم ينتظر الموافقة قبل نقل الملفات."}
  ],
  "required_capabilities": ["files.read", "files.write"]
}
```
''';

ChatSession buildSession({List<ChatMessage>? messages}) => ChatSession(
  id: 'chat-42',
  title: 'تنظيم ملفات الجامعة',
  createdAt: DateTime.utc(2026, 11, 15),
  updatedAt: DateTime.utc(2026, 11, 15),
  messages:
      messages ??
      [
        ChatMessage(
          id: 'u1',
          role: ChatMessageRole.user,
          content: 'أريد ترتيب ملفات الجامعة حسب المادة والفصل.',
          createdAt: DateTime.utc(2026, 11, 15),
        ),
        ChatMessage(
          id: 'a1',
          role: ChatMessageRole.assistant,
          content: 'افحص الملفات أولاً ثم اقترح بنية مجلدات وانتظر موافقتي.',
          createdAt: DateTime.utc(2026, 11, 15),
        ),
      ],
);

void main() {
  test(
    'extracts an inactive proposal from the selected conversation',
    () async {
      final runtime = _FakeRuntime(validDraft);
      final repository = _FakeSkillRepository();
      final skill = await SkillLearningService(
        runtime: runtime,
        repository: repository,
      ).proposeFromConversation(buildSession());

      expect(repository.created, isNotNull);
      expect(skill.status, LeoSkillStatus.proposed);
      expect(skill.validationReport, isNull);
      expect(skill.sourceTaskId, 'conversation:chat-42');
      expect(skill.name, 'تنظيم ملفات الدراسة');
      expect(repository.created!['requiredCapabilities'], [
        'files.read',
        'files.write',
      ]);
      expect(
        runtime.requests.single.messages.last.content,
        contains('<conversation_transcript>'),
      );
      expect(
        runtime.requests.single.messages.last.content,
        contains('افحص الملفات أولاً'),
      );
    },
  );

  test('does not create a skill when the model says the conversation is insufficient', () async {
    final runtime = _FakeRuntime(
      '{"can_create":false,"reason":"لا توجد خطوات كافية."}',
    );
    final repository = _FakeSkillRepository();

    await expectLater(
      SkillLearningService(
        runtime: runtime,
        repository: repository,
      ).proposeFromConversation(buildSession()),
      throwsA(isA<StateError>()),
    );
    expect(repository.created, isNull);
  });

  test(
    'rejects malformed or unsafe capability output before persistence',
    () async {
      final invalid = validDraft.replaceAll('"files.write"', '"../../shell"');
      final runtime = _FakeRuntime(invalid);
      final repository = _FakeSkillRepository();
      await expectLater(
        SkillLearningService(
          runtime: runtime,
          repository: repository,
        ).proposeFromConversation(buildSession()),
        throwsA(isA<FormatException>()),
      );
      expect(repository.created, isNull);
    },
  );

  test(
    'uses the caller request id and keeps transcript input bounded',
    () async {
      final runtime = _FakeRuntime(validDraft);
      final repository = _FakeSkillRepository();
      await SkillLearningService(
        runtime: runtime,
        repository: repository,
      ).proposeFromConversation(
        buildSession(
          messages: [
            ChatMessage(
              id: 'u-long',
              role: ChatMessageRole.user,
              content: List<String>.filled(3000, 'طلب طويل. ').join(),
              createdAt: DateTime.utc(2026, 11, 15),
            ),
            ChatMessage(
              id: 'a-long',
              role: ChatMessageRole.assistant,
              content: List<String>.filled(3000, 'رد طويل. ').join(),
              createdAt: DateTime.utc(2026, 11, 15),
            ),
          ],
        ),
        requestId: 'skill-request-explicit',
      );

      expect(runtime.requests.single.requestId, 'skill-request-explicit');
      expect(runtime.requests.single.maxNewTokens, 1000);
      expect(
        runtime.requests.single.messages.last.content.length,
        lessThan(10000),
      );
      expect(
        runtime.requests.single.messages.last.content,
        contains('[المستخدم]'),
      );
      expect(runtime.requests.single.messages.last.content, contains('[Leo]'));
    },
  );

  test('rejects oversized model output before parsing or saving', () async {
    final runtime = _FakeRuntime(List<String>.filled(24001, '{').join());
    final repository = _FakeSkillRepository();
    await expectLater(
      SkillLearningService(
        runtime: runtime,
        repository: repository,
      ).proposeFromConversation(buildSession()),
      throwsA(isA<FormatException>()),
    );
    expect(repository.created, isNull);
  });

  test(
    'derives an inactive proposal only from a fully user-verified workflow',
    () async {
      final source = _learningSourceSkill();
      final repo = _FakeSkillRepository(existingSkills: [source]);
      final runtime = _FakeRuntime(validDraft);
      final run = _verifiedRun(source);
      final skill = await SkillLearningService(
        runtime: runtime,
        repository: repo,
        runRepository: _FakeRunReader(run),
      ).proposeFromVerifiedRun(run.taskId, requestId: 'workflow-learn-1');

      expect(skill.status, LeoSkillStatus.proposed);
      expect(skill.sourceTaskId, 'verified-run:${run.taskId}');
      expect(repo.created!['requiredCapabilities'], [
        'files.read',
        'files.write',
      ]);
      expect(runtime.requests.single.requestId, 'workflow-learn-1');
      expect(
        runtime.requests.single.messages.last.content,
        contains('<verified_workflow_evidence>'),
      );
    },
  );

  test(
    'redacts contact data, paths and secret-like tokens before local analysis',
    () async {
      final source = _learningSourceSkill(withPrivateData: true);
      final repo = _FakeSkillRepository(existingSkills: [source]);
      final runtime = _FakeRuntime(validDraft);
      final run = _verifiedRun(source);
      await SkillLearningService(
        runtime: runtime,
        repository: repo,
        runRepository: _FakeRunReader(run),
      ).proposeFromVerifiedRun(run.taskId);

      final prompt = runtime.requests.single.messages.last.content;
      expect(prompt, contains('[بريد محذوف]'));
      expect(prompt, contains('[مسار محذوف]'));
      expect(prompt, contains('[رقم محذوف]'));
      expect(prompt, contains('[سر محذوف]'));
      expect(prompt, contains('[اسم ملف محذوف]'));
      expect(prompt, contains('[عنوان شبكة محذوف]'));
      expect(prompt, contains('[معرف جهاز محذوف]'));
      expect(prompt, isNot(contains('alice@example.com')));
      expect(prompt, isNot(contains(r'C:\Users\Ali\private\report.txt')));
      expect(prompt, isNot(contains('+249 912345678')));
      expect(prompt, isNot(contains('ghp_abcdefghijklmnopqrstuvwxyz')));
      expect(prompt, isNot(contains('report.txt')));
      expect(prompt, isNot(contains('192.0.2.10')));
      expect(prompt, isNot(contains('00:11:22:33:44:55')));
      expect(prompt, isNot(contains('tool_arguments')));
      expect(prompt, isNot(contains('file_contents')));
    },
  );

  test(
    'rejects workflow runs that are not user-verified before invoking model',
    () async {
      final source = _learningSourceSkill();
      final repo = _FakeSkillRepository(existingSkills: [source]);
      final runtime = _FakeRuntime(validDraft);
      final incomplete = _verifiedRun(source)
          .copyWith(status: LeoSkillRunStatus.awaitingReview);
      await expectLater(
        SkillLearningService(
          runtime: runtime,
          repository: repo,
          runRepository: _FakeRunReader(incomplete),
        ).proposeFromVerifiedRun(incomplete.taskId),
        throwsA(isA<StateError>()),
      );
      expect(runtime.requests, isEmpty);
      expect(repo.created, isNull);
    },
  );

  test(
    'rejects a generated capability outside the source skill allowlist',
    () async {
      final source = _learningSourceSkill();
      final repo = _FakeSkillRepository(existingSkills: [source]);
      final runtime = _FakeRuntime(
        validDraft.replaceAll('"files.write"', '"shell.exec"'),
      );
      final run = _verifiedRun(source);
      await expectLater(
        SkillLearningService(
          runtime: runtime,
          repository: repo,
          runRepository: _FakeRunReader(run),
        ).proposeFromVerifiedRun(run.taskId),
        throwsA(isA<FormatException>()),
      );
      expect(repo.created, isNull);
    },
  );

  test(
    'prevents deriving more than one proposal from the same verified run',
    () async {
      final source = _learningSourceSkill();
      final repo = _FakeSkillRepository(
        existingSkills: [
          source,
          _proposalFromRun('verified-run:task-verified'),
        ],
      );
      final runtime = _FakeRuntime(validDraft);
      final run = _verifiedRun(source);
      await expectLater(
        SkillLearningService(
          runtime: runtime,
          repository: repo,
          runRepository: _FakeRunReader(run),
        ).proposeFromVerifiedRun(run.taskId),
        throwsA(isA<StateError>()),
      );
      expect(runtime.requests, isEmpty);
    },
  );

  test(
    'redacts sensitive strings from the generated proposal before saving',
    () async {
      final source = _learningSourceSkill();
      final pollutedDraft = validDraft.replaceFirst(
        'يرتب الملفات الدراسية حسب المادة والفصل الدراسي بطريقة قابلة للتكرار.',
        'يرتب الملفات الدراسية alice@example.com اعتماد api_key=sk-secret-placeholder بطريقة قابلة للتكرار.',
      );
      final repo = _FakeSkillRepository(existingSkills: [source]);
      final runtime = _FakeRuntime(pollutedDraft);
      final run = _verifiedRun(source);
      final proposal = await SkillLearningService(
        runtime: runtime,
        repository: repo,
        runRepository: _FakeRunReader(run),
      ).proposeFromVerifiedRun(run.taskId);

      expect(proposal.description, contains('[بريد محذوف]'));
      expect(proposal.description, contains('[بيان اعتماد محذوف]'));
      expect(proposal.description, isNot(contains('alice@example.com')));
      expect(proposal.description, isNot(contains('sk-secret-placeholder')));
    },
  );

  test(
    'requires both sides of a real conversation before calling the model',
    () async {
      final runtime = _FakeRuntime(validDraft);
      final repository = _FakeSkillRepository();
      final oneMessage = buildSession(
        messages: [
          ChatMessage(
            id: 'u1',
            role: ChatMessageRole.user,
            content: 'رتب الملفات',
            createdAt: DateTime.utc(2026, 11, 15),
          ),
        ],
      );
      await expectLater(
        SkillLearningService(
          runtime: runtime,
          repository: repository,
        ).proposeFromConversation(oneMessage),
        throwsA(isA<StateError>()),
      );
      expect(runtime.requests, isEmpty);
    },
  );
}

LeoSkill _learningSourceSkill({bool withPrivateData = false}) {
  final now = '2026-11-17T00:00:00Z';
  final steps = withPrivateData
      ? [
          r'افتح C:\Users\Ali\private\report.txt وتحقق من alice@example.com',
          'راجع رقم الهاتف +249 912345678 وتجاهل الرمز ghp_abcdefghijklmnopqrstuvwxyz.',
          'اعرض النتيجة للمستخدم دون حفظ معلوماته الخاصة، ولا تذكر report.txt أو 192.0.2.10 أو 00:11:22:33:44:55.',
        ]
      : const [
          'افحص المستندات التي اختارها المستخدم وحدد أنواعها دون إجراء تغيير.',
          'اقترح طريقة تنظيم واضحة واعرض الخطة للمستخدم.',
          'تحقق من النتيجة بعد موافقة المستخدم على التغيير.',
        ];
  return LeoSkill(
    id: 'skill-learning-source',
    name: 'تنظيم الملفات الدراسية',
    description: withPrivateData
        ? 'تنظيم الملفات مع مرجع https://private.example.org'
        : 'يرتب الملفات الدراسية بطريقة قابلة للتكرار.',
    triggers: const ['نظم الملفات الدراسية'],
    instructions: 'افحص المحتوى أولاً، ثم اعرض خطة قابلة للمراجعة. لا تغير ملفاً ولا تنفذ إجراءً خارجياً قبل موافقة المستخدم الصريحة.',
    steps: steps,
    testCases: const [
      LeoSkillTestCase(
        input: 'نظم مجموعة ملفات تجريبية',
        expectedOutcome: 'يعرض خطة ولا يكتب قبل الموافقة.',
      ),
    ],
    requiredCapabilities: const ['files.read', 'files.write'],
    status: LeoSkillStatus.active,
    version: '0.2.0',
    createdAtUtc: now,
    updatedAtUtc: now,
    history: const [],
    validationReport: LeoSkillValidationReport(
      checkedAtUtc: now,
      passed: true,
      checks: const [],
      disclaimer: 'Structural review only.',
    ),
  );
}

LeoSkillRunRecord _verifiedRun(LeoSkill skill) => LeoSkillRunRecord(
  id: 'skill-run-task-verified',
  taskId: 'task-verified',
  skillId: skill.id,
  skillName: skill.name,
  skillVersion: skill.version,
  status: LeoSkillRunStatus.verified,
  steps: skill.steps
      .asMap()
      .entries
      .map(
        (entry) => LeoSkillStepReview(
          index: entry.key,
          instruction: entry.value,
          status: LeoSkillStepReviewStatus.confirmed,
        ),
      )
      .toList(growable: false),
  startedAtUtc: '2026-11-17T00:00:00Z',
  updatedAtUtc: '2026-11-17T00:10:00Z',
  finishedAtUtc: '2026-11-17T00:10:00Z',
  lastEvent: 'user confirmed all steps',
  toolApprovals: 1,
);

LeoSkill _proposalFromRun(String sourceTaskId) {
  final source = _learningSourceSkill();
  return source.copyWith(
    status: LeoSkillStatus.proposed,
    sourceTaskId: sourceTaskId,
    version: '0.1.0',
  );
}

class _FakeRunReader implements SkillRunEvidenceReader {
  const _FakeRunReader(this.record);
  final LeoSkillRunRecord record;

  @override
  Future<LeoSkillRunRecord?> getByTaskId(String taskId) async =>
      taskId == record.taskId ? record : null;
}

class _FakeRuntime implements AssistantRuntimeClient {
  _FakeRuntime(this.response);

  final String response;
  final List<RuntimeRequest> requests = [];

  @override
  Stream<RuntimeEvent> generate(RuntimeRequest request) async* {
    requests.add(request);
    yield const RuntimeEvent(RuntimeEventType.started);
    yield RuntimeEvent(RuntimeEventType.delta, text: response);
    yield RuntimeEvent(RuntimeEventType.completed, text: response);
  }

  @override
  Future<void> cancel(String requestId) async {}
}

class _FakeSkillRepository implements SkillRepository {
  _FakeSkillRepository({List<LeoSkill> existingSkills = const []})
    : existingSkills = [...existingSkills];

  final List<LeoSkill> existingSkills;
  Map<String, Object?>? created;

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
  }) async {
    created = {
      'name': name,
      'description': description,
      'triggers': triggers,
      'instructions': instructions,
      'steps': steps,
      'testCases': testCases,
      'requiredCapabilities': requiredCapabilities,
      'sourceTaskId': sourceTaskId,
    };
    final now = DateTime.now().toUtc().toIso8601String();
    final result = LeoSkill(
      id: 'skill-new',
      name: name,
      description: description,
      triggers: triggers,
      instructions: instructions,
      steps: steps,
      testCases: testCases,
      requiredCapabilities: requiredCapabilities,
      status: LeoSkillStatus.proposed,
      version: '0.1.0',
      createdAtUtc: now,
      updatedAtUtc: now,
      history: const [],
      sourceTaskId: sourceTaskId,
    );
    existingSkills.add(result);
    return result;
  }

  @override
  Future<LeoSkill> activate(String skillId) => throw UnimplementedError();
  @override
  Future<LeoSkill> disable(String skillId) => throw UnimplementedError();
  @override
  Future<List<LeoSkill>> findApplicable(
    String request, {
    int limit = 2,
  }) async => const [];
  @override
  Future<List<LeoSkill>> list() async => List.unmodifiable(existingSkills);
  @override
  Future<LeoSkill> reject(String skillId) => throw UnimplementedError();
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
  }) => throw UnimplementedError();
  @override
  Future<LeoSkill> validate(String skillId) => throw UnimplementedError();
  @override
  Future<bool> delete(String skillId) => throw UnimplementedError();
}
