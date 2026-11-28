import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/core/skills/skill_markdown_codec.dart';
import 'package:leo_app/core/skills/skill_models.dart';

LeoSkill sampleSkill() => const LeoSkill(
  id: 'skill-roundtrip',
  name: 'تنظيم ملفات الدراسة',
  description: 'يرتب الملفات الدراسية حسب المادة والفصل الدراسي.',
  triggers: ['رتب ملفاتي الدراسية', 'نظم مجلد الجامعة'],
  instructions:
      'افحص المجلد أولاً، ثم اعرض خطة التنظيم. احتفظ بالأصل، '
      'ولا تنقل أو تحذف أي ملف قبل موافقة المستخدم الصريحة.',
  steps: [
    'افحص الملفات وحدد أنواعها دون تعديل.',
    'اقترح بنية مجلدات مناسبة واعرضها للمستخدم.',
    'انتظر الموافقة قبل نقل الملفات أو إعادة تسميتها.',
  ],
  testCases: [
    LeoSkillTestCase(
      input: 'نظم ملفات محاضرات الفصل الحالي',
      expectedOutcome: 'يعرض خطة أولاً ثم ينتظر موافقة المستخدم قبل التغيير.',
    ),
  ],
  requiredCapabilities: ['files.read', 'files.write'],
  status: LeoSkillStatus.active,
  version: '0.3.0',
  createdAtUtc: '2026-11-15T00:00:00Z',
  updatedAtUtc: '2026-11-15T00:00:00Z',
  history: [],
  validationReport: LeoSkillValidationReport(
    checkedAtUtc: '2026-11-15T00:00:00Z',
    passed: true,
    checks: [],
    disclaimer: 'Structural preflight only.',
  ),
);

void main() {
  test(
    'exports a valid Agent Skills frontmatter and Leo workflow sections',
    () {
      final markdown = SkillMarkdownCodec.encode(sampleSkill());
      expect(markdown, startsWith('---\nname: leo-skill\ndescription:'));
      expect(markdown, contains('# تنظيم ملفات الدراسة'));
      expect(markdown, contains('## When to use'));
      expect(markdown, contains('## Steps'));
      expect(markdown, contains('## Acceptance scenarios'));
      expect(markdown, contains('files.write'));
    },
  );

  test(
    'round trips Leo workflow details but imports as an inactive proposal',
    () {
      final imported = SkillMarkdownCodec.decode(
        SkillMarkdownCodec.encode(sampleSkill()),
      );
      expect(imported.name, 'تنظيم ملفات الدراسة');
      expect(imported.description, sampleSkill().description);
      expect(imported.triggers, sampleSkill().triggers);
      expect(imported.instructions, sampleSkill().instructions);
      expect(imported.steps, sampleSkill().steps);
      expect(
        imported.testCases.single.input,
        sampleSkill().testCases.single.input,
      );
      expect(imported.requiredCapabilities, sampleSkill().requiredCapabilities);
      expect(imported.status, LeoSkillStatus.proposed);
      expect(imported.validationReport, isNull);
      expect(imported.history, isEmpty);
    },
  );

  test(
    'accepts a basic third-party SKILL.md and provides safe fallback steps',
    () {
      const external = '''
---
name: summarize-documents
description: Summarize long text documents into clear concise notes.
---
# Document Summarizer

Read the provided document, identify its main points, and produce a concise
summary that preserves the important facts and caveats.
''';
      final imported = SkillMarkdownCodec.decode(external);
      expect(imported.name, 'Document Summarizer');
      expect(imported.triggers.single, contains('Summarize long text'));
      expect(imported.steps, hasLength(2));
      expect(imported.status, LeoSkillStatus.proposed);
    },
  );

  test('supports folded YAML descriptions in third-party skills', () {
    const external = '''
---
name: meeting-notes
description: >-
  Turn meeting notes into decisions, action items and owners.
---
# Meeting Notes

## Steps
1. Read the notes and identify decisions.
2. Group action items by owner.
''';
    final imported = SkillMarkdownCodec.decode(external);
    expect(imported.description, contains('Turn meeting notes'));
    expect(imported.description, contains('action items and owners'));
    expect(imported.status, LeoSkillStatus.proposed);
  });

  test('rejects invalid frontmatter and oversized documents', () {
    expect(
      () => SkillMarkdownCodec.decode('# no frontmatter'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => SkillMarkdownCodec.decode('x' * 70000),
      throwsA(isA<FormatException>()),
    );
  });
}
