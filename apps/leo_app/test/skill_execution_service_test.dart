import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/core/skills/skill_execution_service.dart';
import 'package:leo_app/core/skills/skill_models.dart';

class _MemorySkillRunStore implements SkillRunSecureStore {
  String? value;

  @override
  Future<void> delete({required String key}) async => value = null;

  @override
  Future<String?> read({required String key}) async => value;

  @override
  Future<void> write({required String key, required String value}) async {
    this.value = value;
  }
}

LeoSkill _activeSkill() => const LeoSkill(
  id: 'skill-test',
  name: 'تنظيم ملفات الدراسة',
  description: 'ترتيب الملفات الدراسية بطريقة منظمة وآمنة.',
  triggers: ['رتب ملفات الدراسة'],
  instructions:
      'افحص محتويات الملفات أولاً، ولا تغير أي ملف قبل عرض خطة واضحة. '
      'اطلب موافقة المستخدم لكل عملية كتابة، وتوقف عند رفضه.',
  steps: [
    'افحص المستندات التي اختارها المستخدم وحدد أنواعها.',
    'اقترح طريقة تنظيم واضحة واعرضها للمستخدم.',
    'بعد الموافقة، اكتب التغييرات المراجعة فقط.',
  ],
  testCases: [
    LeoSkillTestCase(
      input: 'رتب ملفات محاضراتي',
      expectedOutcome: 'يقدم خطة ثم ينتظر الموافقة قبل الكتابة.',
    ),
  ],
  requiredCapabilities: ['files.read', 'files.write'],
  status: LeoSkillStatus.active,
  version: '0.2.0',
  createdAtUtc: '2026-11-17T00:00:00Z',
  updatedAtUtc: '2026-11-17T00:00:00Z',
  history: [],
  validationReport: LeoSkillValidationReport(
    checkedAtUtc: '2026-11-17T00:00:00Z',
    passed: true,
    checks: [],
    disclaimer: 'Structural preflight only.',
  ),
);

void main() {
  late _MemorySkillRunStore store;
  late SkillRunRepository repository;

  setUp(() {
    store = _MemorySkillRunStore();
    repository = SkillRunRepository(secureStore: store);
  });

  test('only active validated skills can start a persistent run', () async {
    final skill = _activeSkill();
    final record = await repository.create(skill: skill, taskId: 'task-123');
    expect(record.status, LeoSkillRunStatus.running);
    expect(record.steps, hasLength(3));
    expect((await repository.getByTaskId('task-123'))?.skillVersion, '0.2.0');

    final disabled = skill.copyWith(status: LeoSkillStatus.disabled);
    await expectLater(
      repository.create(skill: disabled, taskId: 'task-456'),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'execution envelope is bounded, ordered and cannot grant capabilities',
    () async {
      final skill = _activeSkill();
      final run = await repository.create(skill: skill, taskId: 'task-789');
      final context = const SkillExecutionService().buildExecutionContext(
        run,
        skill,
      );
      expect(context, contains('<leo_skill_execution_contract version="1">'));
      expect(context, contains('لا تنفذ سكربتات أو أوامر shell'));
      expect(context, contains('كل إجراء خارجي منفصل ويحتاج موافقة المستخدم'));
      expect(
        context.indexOf('افحص المستندات'),
        lessThan(context.indexOf('اقترح طريقة')),
      );
      expect(context, contains('سيناريوهات القبول'));
      expect(context, contains('لا تمنح الصلاحيات'));
    },
  );

  test('run transitions pause on app interruption and safely resume', () async {
    await repository.create(skill: _activeSkill(), taskId: 'task-pause');
    await repository.setStatus(
      'task-pause',
      LeoSkillRunStatus.paused,
      event: 'انتقل التطبيق إلى الخلفية.',
    );
    final resumed = await repository.setStatus(
      'task-pause',
      LeoSkillRunStatus.running,
      event: 'استعادة من نقطة حفظ.',
    );
    expect(resumed.status, LeoSkillRunStatus.running);
    await expectLater(
      repository.setStatus(
        'task-pause',
        LeoSkillRunStatus.verified,
        event: 'تجاوز المراجعة',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'each external approval is counted and cannot exceed tool budget',
    () async {
      await repository.create(skill: _activeSkill(), taskId: 'task-tools');
      for (var index = 0; index < 3; index++) {
        await repository.setStatus(
          'task-tools',
          LeoSkillRunStatus.awaitingApproval,
          event: 'ينتظر موافقة.',
        );
        await repository.setStatus(
          'task-tools',
          LeoSkillRunStatus.running,
          event: 'تمت الموافقة.',
          incrementToolApproval: true,
        );
      }
      final record = await repository.getByTaskId('task-tools');
      expect(record!.toolApprovals, 3);
      await expectLater(
        repository.setStatus(
          'task-tools',
          LeoSkillRunStatus.awaitingApproval,
          event: 'موافقة رابعة',
          incrementToolApproval: true,
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'user must review every step; missed steps never become verified',
    () async {
      await repository.create(skill: _activeSkill(), taskId: 'task-review');
      await repository.setStatus(
        'task-review',
        LeoSkillRunStatus.awaitingReview,
        event: 'انتهى استدلال الوكلاء.',
      );
      await repository.reviewStep(
        taskId: 'task-review',
        stepIndex: 0,
        status: LeoSkillStepReviewStatus.confirmed,
      );
      await repository.reviewStep(
        taskId: 'task-review',
        stepIndex: 1,
        status: LeoSkillStepReviewStatus.notCompleted,
      );
      final partial = await repository.reviewStep(
        taskId: 'task-review',
        stepIndex: 2,
        status: LeoSkillStepReviewStatus.confirmed,
      );
      expect(partial.status, LeoSkillRunStatus.needsChanges);

      final corrected = await repository.reviewStep(
        taskId: 'task-review',
        stepIndex: 1,
        status: LeoSkillStepReviewStatus.confirmed,
      );
      expect(corrected.status, LeoSkillRunStatus.verified);
      expect(
        corrected.steps.every(
          (step) => step.status == LeoSkillStepReviewStatus.confirmed,
        ),
        isTrue,
      );
    },
  );

  test(
    'encrypted run history round-trips and rejects duplicate task ids',
    () async {
      await repository.create(skill: _activeSkill(), taskId: 'task-roundtrip');
      final raw = store.value!;
      expect(jsonDecode(raw), isA<Map<String, dynamic>>());
      final restored = SkillRunRepository(secureStore: store);
      expect((await restored.list()).single.taskId, 'task-roundtrip');
      await expectLater(
        restored.create(skill: _activeSkill(), taskId: 'task-roundtrip'),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('run audit metadata does not store the raw user goal', () async {
    await repository.create(skill: _activeSkill(), taskId: 'task-private');
    final raw = store.value!;
    final runJson =
        (jsonDecode(raw) as Map<String, dynamic>)['runs'].single
            as Map<String, dynamic>;
    expect(runJson.containsKey('goal'), isFalse);
  });

  test(
    'only terminal records are evicted when the history reaches its cap',
    () async {
      final skill = _activeSkill();
      for (var index = 0; index < SkillRunRepository.maxRuns; index++) {
        await repository.create(skill: skill, taskId: 'task-record-$index');
      }
      await repository.setStatus(
        'task-record-0',
        LeoSkillRunStatus.failed,
        event: 'فشل التشغيل.',
      );
      await repository.create(skill: skill, taskId: 'task-record-new');
      expect(await repository.getByTaskId('task-record-0'), isNull);
      expect(await repository.getByTaskId('task-record-new'), isNotNull);
      expect(await repository.list(), hasLength(SkillRunRepository.maxRuns));
    },
  );

  test(
    'active and awaiting-review runs are never evicted to make room',
    () async {
      final skill = _activeSkill();
      for (var index = 0; index < SkillRunRepository.maxRuns; index++) {
        await repository.create(skill: skill, taskId: 'task-live-$index');
      }
      await expectLater(
        repository.create(skill: skill, taskId: 'task-overflow'),
        throwsA(isA<StateError>()),
      );
      expect(await repository.list(), hasLength(SkillRunRepository.maxRuns));
    },
  );
}
