import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/core/skills/skill_models.dart';
import 'package:leo_app/core/skills/skill_repository.dart';

void main() {
  late Directory temporaryDirectory;
  late FileSkillRepository repository;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'leo-skills-test-',
    );
    repository = FileSkillRepository(rootDirectory: temporaryDirectory);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  Future<LeoSkill> createValidProposal() => repository.createProposal(
    name: 'تنظيم ملفات الدراسة',
    description: 'ترتيب الملفات الدراسية في مجلدات منظمة حسب المادة والفصل.',
    triggers: const ['رتب ملفاتي الدراسية', 'نظم ملفات الجامعة'],
    instructions:
        'راجع محتويات المجلد أولاً. اقترح البنية قبل إجراء أي تغيير. '
        'احتفظ بنسخة من الملفات قبل النقل أو إعادة التسمية. '
        'اطلب موافقة المستخدم قبل أي تغيير جماعي.',
    steps: const [
      'استكشف الملفات وحدد أنواعها دون تعديلها.',
      'اقترح مجلدات بحسب الفصل والمادة واعرض الخطة.',
      'اطلب الموافقة قبل النقل أو إعادة التسمية.',
    ],
    testCases: const [
      LeoSkillTestCase(
        input: 'رتب مجلد محاضرات الفصل الحالي',
        expectedOutcome: 'يعرض خطة ترتيب ثم ينتظر الموافقة قبل النقل.',
      ),
    ],
    requiredCapabilities: const ['files.read', 'files.write'],
    sourceTaskId: 'task-demo-01',
  );

  test(
    'new skills remain proposals until preflight and user activation',
    () async {
      final proposal = await createValidProposal();
      expect(proposal.status, LeoSkillStatus.proposed);

      final checked = await repository.validate(proposal.id);
      expect(checked.status, LeoSkillStatus.testing);
      expect(checked.isValidated, isTrue);

      final active = await repository.activate(proposal.id);
      expect(active.status, LeoSkillStatus.active);

      final restored = await FileSkillRepository(
        rootDirectory: temporaryDirectory,
      ).list();
      expect(restored, hasLength(1));
      expect(restored.single.status, LeoSkillStatus.active);
      expect(restored.single.sourceTaskId, 'task-demo-01');
    },
  );

  test(
    'a verified workflow can only produce one derived proposal per run',
    () async {
      final first = await repository.createProposal(
        name: 'مهارة مشتقة',
        description: 'اقتراح عام مشتق من سير عمل راجعه المستخدم.',
        triggers: const ['نفذ سير العمل'],
        instructions: 'افحص الطلب أولاً، ثم اعرض الإجراء المتوقع. لا تنفذ إجراءً خارجياً قبل موافقة المستخدم الصريحة.',
        steps: const [
          'حلل الطلب وحدد المعلومات المطلوبة.',
          'اعرض خطة العمل وانتظر موافقة المستخدم.',
        ],
        testCases: const [
          LeoSkillTestCase(
            input: 'ابدأ الإجراء التجريبي',
            expectedOutcome: 'يعرض الخطة وينتظر الموافقة.',
          ),
        ],
        requiredCapabilities: const [],
        sourceTaskId: 'verified-run:task-01',
      );
      expect(first.sourceTaskId, 'verified-run:task-01');
      await expectLater(
        repository.createProposal(
          name: 'اقتراح مكرر',
          description: 'محاولة تكرار اقتراح من نفس سير العمل.',
          triggers: const ['كرر الإجراء'],
          instructions: 'افحص الطلب أولاً، ثم اعرض الإجراء المتوقع. لا تنفذ إجراءً خارجياً قبل موافقة المستخدم الصريحة.',
          steps: const [
            'حلل الطلب وحدد المعلومات المطلوبة.',
            'اعرض خطة العمل وانتظر موافقة المستخدم.',
          ],
          testCases: const [
            LeoSkillTestCase(
              input: 'ابدأ الإجراء التجريبي',
              expectedOutcome: 'يعرض الخطة وينتظر الموافقة.',
            ),
          ],
          requiredCapabilities: const [],
          sourceTaskId: 'verified-run:task-01',
        ),
        throwsA(isA<StateError>()),
      );
      expect(await repository.list(), hasLength(1));
    },
  );

  test('skill retrieval uses active validated skills only', () async {
    final proposal = await createValidProposal();
    expect(await repository.findApplicable('رتب ملفاتي الدراسية'), isEmpty);

    await repository.validate(proposal.id);
    await repository.activate(proposal.id);
    final matches = await repository.findApplicable('أريد تنظيم ملفات الجامعة');
    expect(matches, hasLength(1));
    expect(matches.single.id, proposal.id);

    await repository.disable(proposal.id);
    expect(await repository.findApplicable('رتب ملفاتي الدراسية'), isEmpty);
  });

  test(
    'sensitive workflows fail preflight when approval language is absent',
    () async {
      final proposal = await repository.createProposal(
        name: 'إرسال بريد',
        description: 'إعداد رسالة بريد وإرسالها إلى جهة محددة.',
        triggers: const ['أرسل بريداً'],
        instructions: 'أرسل البريد بمجرد تجهيز نص الرسالة إلى المستلم.',
        steps: const [
          'اكتب عنوان الرسالة ومحتواها.',
          'أرسل الرسالة مباشرة بعد تجهيزها.',
        ],
        testCases: const [
          LeoSkillTestCase(
            input: 'جهز بريداً للمدير',
            expectedOutcome: 'يتم إعداد البريد.',
          ),
        ],
        requiredCapabilities: const ['email.compose'],
      );

      final checked = await repository.validate(proposal.id);
      expect(checked.isValidated, isFalse);
      expect(
        checked.validationReport!.checks
            .singleWhere((check) => check.id == 'sensitive_actions')
            .passed,
        isFalse,
      );
      await expectLater(
        repository.activate(proposal.id),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'skill updates create a new proposal version and retain prior history',
    () async {
      final proposal = await createValidProposal();
      await repository.validate(proposal.id);
      final updated = await repository.updateProposal(
        skillId: proposal.id,
        name: proposal.name,
        description: proposal.description,
        triggers: proposal.triggers,
        instructions:
            '${proposal.instructions} أبلغ المستخدم بالنتيجة النهائية.',
        steps: proposal.steps,
        testCases: proposal.testCases,
        requiredCapabilities: proposal.requiredCapabilities,
        changeSummary: 'إضافة خطوة عرض التقرير النهائي',
      );

      expect(updated.version, '0.2.0');
      expect(updated.status, LeoSkillStatus.proposed);
      expect(updated.validationReport, isNull);
      expect(updated.history, hasLength(1));
      expect(updated.history.single.version, '0.1.0');
    },
  );

  test('skills can be deleted from the local library', () async {
    final proposal = await createValidProposal();
    expect(await repository.delete(proposal.id), isTrue);
    expect(await repository.delete(proposal.id), isFalse);
    expect(await repository.list(), isEmpty);
  });
}
