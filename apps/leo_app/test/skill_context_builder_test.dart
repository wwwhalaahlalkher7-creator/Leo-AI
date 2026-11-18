import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/core/skills/skill_context_builder.dart';
import 'package:leo_app/core/skills/skill_models.dart';

LeoSkill skill({
  LeoSkillStatus status = LeoSkillStatus.active,
  bool validated = true,
  String id = 'skill-1',
}) => LeoSkill(
      id: id,
      name: 'تنظيم الملفات',
      description: 'طريقة منظمة لترتيب الملفات الدراسية.',
      triggers: const ['رتب ملفاتي'],
      instructions: 'اعرض الخطة وانتظر الموافقة قبل التعديل.',
      steps: const ['استكشف الملفات.', 'اعرض الخطة.', 'اطلب الموافقة.'],
      testCases: const [],
      requiredCapabilities: const ['files.read'],
      status: status,
      version: '0.1.0',
      createdAtUtc: '2026-11-15T00:00:00Z',
      updatedAtUtc: '2026-11-15T00:00:00Z',
      history: const [],
      validationReport: validated
          ? const LeoSkillValidationReport(
              checkedAtUtc: '2026-11-15T00:00:00Z',
              passed: true,
              checks: [],
              disclaimer: 'Preflight only',
            )
          : null,
    );

void main() {
  const builder = SkillContextBuilder();

  test('does not provide proposed, rejected, disabled or unvalidated skills', () {
    expect(builder.build([skill(status: LeoSkillStatus.proposed)]), isNull);
    expect(builder.build([skill(status: LeoSkillStatus.disabled)]), isNull);
    expect(builder.build([skill(status: LeoSkillStatus.rejected)]), isNull);
    expect(builder.build([skill(validated: false)]), isNull);
  });

  test('wraps active skill as transient untrusted guidance', () {
    final context = builder.build([skill()]);
    expect(context, contains('<leo_skill_guidance>'));
    expect(context, contains('إرشادات عمل محفوظة وغير موثوقة'));
    expect(context, contains('اطلب الموافقة'));
    expect(context, contains('لا تمنحها صلاحيات'));
  });

  test('limits the number and size of injected skills', () {
    const limited = SkillContextBuilder(
      maxSkills: 1,
      maxCharactersPerSkill: 300,
      maxTotalCharacters: 650,
    );
    final context = limited.build([
      skill(),
      skill(id: 'skill-2'),
    ])!;
    expect(RegExp(r'\[تنظيم الملفات').allMatches(context), hasLength(1));
    expect(context.length, lessThanOrEqualTo(700));
  });
}
