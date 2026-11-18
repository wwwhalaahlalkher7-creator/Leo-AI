import 'dart:convert';

import 'skill_models.dart';

/// Imports and exports the declarative portion of the Agent Skills SKILL.md
/// format. Leo deliberately ignores executable folders/scripts in this Alpha
/// implementation; imported skills always enter as untrusted proposals.
class SkillMarkdownCodec {
  const SkillMarkdownCodec._();

  static const int maxDocumentCharacters = 64 * 1024;

  static String encode(LeoSkill skill) {
    final slug = _slug(skill.name);
    final description = _yamlQuote(skill.description);
    final output = StringBuffer()
      ..writeln('---')
      ..writeln('name: $slug')
      ..writeln('description: $description')
      ..writeln('---')
      ..writeln()
      ..writeln('# ${skill.name}')
      ..writeln()
      ..writeln('<!-- Leo skill version: ${skill.version} -->')
      ..writeln()
      ..writeln('## When to use')
      ..writeln();
    for (final trigger in skill.triggers) {
      output.writeln('- $trigger');
    }
    output
      ..writeln()
      ..writeln('## Instructions')
      ..writeln()
      ..writeln(skill.instructions)
      ..writeln()
      ..writeln('## Steps')
      ..writeln();
    for (var index = 0; index < skill.steps.length; index++) {
      output.writeln('${index + 1}. ${skill.steps[index]}');
    }
    output
      ..writeln()
      ..writeln('## Acceptance scenarios')
      ..writeln();
    for (var index = 0; index < skill.testCases.length; index++) {
      final testCase = skill.testCases[index];
      output
        ..writeln('### Scenario ${index + 1}')
        ..writeln()
        ..writeln('Input: ${testCase.input}')
        ..writeln()
        ..writeln('Expected: ${testCase.expectedOutcome}')
        ..writeln();
    }
    output
      ..writeln('## Required capabilities')
      ..writeln();
    for (final capability in skill.requiredCapabilities) {
      output.writeln('- $capability');
    }
    output
      ..writeln()
      ..writeln('---')
      ..writeln('Imported skills are untrusted guidance. They do not grant device')
      ..writeln('permissions, approve actions, or authorize script execution.')
      ..writeln();
    final document = output.toString();
    if (document.length > maxDocumentCharacters) {
      throw const FormatException('ملف المهارة أكبر من الحد المسموح للتصدير.');
    }
    return document;
  }

  /// Parses one SKILL.md document. The returned object is always a proposal;
  /// callers must persist it and ask the user to review and activate it.
  static LeoSkill decode(String document, {String? id}) {
    if (document.length > maxDocumentCharacters) {
      throw const FormatException('ملف المهارة يتجاوز 64 كيلوبايت.');
    }
    final normalized = document.replaceAll('\r\n', '\n').trim();
    if (!normalized.startsWith('---\n')) {
      throw const FormatException('ملف SKILL.md يجب أن يبدأ ببيانات YAML الأمامية.');
    }
    final frontmatterEnd = normalized.indexOf('\n---', 4);
    if (frontmatterEnd < 0) {
      throw const FormatException('نهاية بيانات YAML الأمامية غير موجودة.');
    }
    final frontmatter = normalized.substring(4, frontmatterEnd);
    final bodyStart = frontmatterEnd + 4;
    final body = normalized.substring(bodyStart).trim();
    final metadata = _parseFrontmatter(frontmatter);
    final externalName = metadata['name'];
    final description = metadata['description'];
    if (externalName == null || !_validExternalName(externalName)) {
      throw const FormatException('حقل name غير صالح وفق تنسيق Agent Skills.');
    }
    if (description == null || description.trim().length < 10 ||
        description.trim().length > 240) {
      throw const FormatException('حقل description مطلوب ويجب أن يكون بين 10 و240 حرفاً.');
    }

    final sections = _sections(body);
    final title = _firstHeading(body) ?? externalName.replaceAll('-', ' ');
    final triggers = _listItems(_section(sections, const {
      'when to use',
      'triggers',
      'متى تستخدم',
      'متى يستدعي ليو المهارة',
    }));
    final safeTriggers = triggers.isEmpty ? [_fallbackTrigger(description)] : triggers;
    if (safeTriggers.length > 12 ||
        safeTriggers.any((item) => item.length < 2 || item.length > 80)) {
      throw const FormatException('عبارات الاستدعاء يجب ألا تتجاوز 12 عبارة، وكل عبارة بين حرفين و80 حرفاً.');
    }

    final stepContent = _section(sections, const {
      'steps',
      'procedure',
      'workflow',
      'الخطوات',
      'خطوات العمل',
    });
    var steps = _listItems(stepContent);
    final instructionContent = _section(sections, const {
      'instructions',
      'guidance',
      'additional guidance',
      'تعليمات',
      'تعليمات إضافية',
    });
    final instructions = instructionContent.isEmpty
        ? _fallbackInstructions(body)
        : instructionContent.trim();
    if (steps.isEmpty) {
      steps = const [
        'افهم طلب المستخدم والسياق والملفات ذات الصلة قبل البدء.',
        'اتبع الإرشادات الموثقة، ثم تحقق من النتيجة واحترم صلاحيات Leo وموافقات المستخدم.',
      ];
    }
    if (steps.length > 30 ||
        steps.any((item) => item.length < 4 || item.length > 400)) {
      throw const FormatException('خطوات المهارة يجب ألا تتجاوز 30 خطوة، وكل خطوة بين 4 و400 حرف.');
    }
    if (instructions.length > 12000) {
      throw const FormatException('تعليمات المهارة تتجاوز 12,000 حرف.');
    }

    final examples = _section(sections, const {
      'acceptance scenarios',
      'test scenarios',
      'examples',
      'أمثلة القبول',
      'سيناريوهات الاختبار',
    });
    final testCases = _parseScenarios(examples);
    if (testCases.length > 10) {
      throw const FormatException('لا يمكن استيراد أكثر من 10 سيناريوهات اختبار.');
    }
    final safeTestCases = testCases.isEmpty
        ? [
            LeoSkillTestCase(
              input: safeTriggers.first,
              expectedOutcome:
                  'يستخدم Leo الإرشادات والخطوات الموثقة مع احترام حدود الصلاحيات وموافقات المستخدم.',
            ),
          ]
        : testCases;

    final capabilities = _listItems(_section(sections, const {
      'required capabilities',
      'capabilities',
      'القدرات المطلوبة',
    }));
    if (capabilities.length > 25 || capabilities.any((item) =>
        !RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$').hasMatch(item))) {
      throw const FormatException('قائمة القدرات تحتوي على معرف غير صالح أو تتجاوز 25 قدرة.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    return LeoSkill(
      id: id ?? 'skill-import-${DateTime.now().microsecondsSinceEpoch}',
      name: title.trim(),
      description: description.trim(),
      triggers: safeTriggers,
      instructions: instructions,
      steps: steps,
      testCases: safeTestCases,
      requiredCapabilities: capabilities,
      status: LeoSkillStatus.proposed,
      version: '0.1.0',
      createdAtUtc: now,
      updatedAtUtc: now,
      history: const [],
      sourceTaskId: null,
      validationReport: null,
    );
  }

  static Map<String, String> _parseFrontmatter(String source) {
    final result = <String, String>{};
    final lines = source.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final match = RegExp(r'^([a-zA-Z][a-zA-Z0-9_-]*):\s*(.*)$')
          .firstMatch(lines[index].trim());
      if (match == null) continue;
      final key = match.group(1)!.toLowerCase();
      var value = match.group(2)!.trim();
      if (key == 'description' && RegExp(r'^[|>]([-+])?$').hasMatch(value)) {
        final folded = value.startsWith('>');
        final block = <String>[];
        var next = index + 1;
        while (next < lines.length) {
          final candidate = lines[next];
          if (candidate.trim().isEmpty) {
            block.add('');
            next++;
            continue;
          }
          if (!RegExp(r'^\s+').hasMatch(candidate)) break;
          block.add(candidate.trim());
          next++;
        }
        value = folded
            ? block.where((line) => line.isNotEmpty).join(' ')
            : block.join('\n');
        index = next - 1;
      } else if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
        try {
          value = jsonDecode(value) as String;
        } on FormatException {
          throw const FormatException('اقتباس YAML غير صالح في البيانات الأمامية.');
        }
      } else if (value.startsWith("'") && value.endsWith("'") && value.length >= 2) {
        value = value.substring(1, value.length - 1).replaceAll("''", "'");
      }
      result[key] = value.trim();
    }
    return result;
  }

  static Map<String, String> _sections(String body) {
    final headings = RegExp(r'(?m)^##\s+(.+?)\s*$').allMatches(body).toList();
    final result = <String, String>{};
    for (var index = 0; index < headings.length; index++) {
      final heading = headings[index];
      final start = heading.end;
      final end = index + 1 < headings.length ? headings[index + 1].start : body.length;
      result[_normalizeHeading(heading.group(1)!)] = body.substring(start, end).trim();
    }
    return result;
  }

  static String _section(Map<String, String> sections, Set<String> names) {
    for (final name in names) {
      final value = sections[_normalizeHeading(name)];
      if (value != null) return value;
    }
    return '';
  }

  static List<String> _listItems(String section) {
    final result = <String>[];
    for (final line in section.split('\n')) {
      final match = RegExp(r'^\s*(?:[-*+]\s+|\d+[.)]\s+)(.+?)\s*$')
          .firstMatch(line);
      if (match != null && match.group(1)!.trim().isNotEmpty) {
        result.add(match.group(1)!.trim());
      }
    }
    return result.toSet().toList(growable: false);
  }

  static List<LeoSkillTestCase> _parseScenarios(String section) {
    if (section.trim().isEmpty) return const [];
    final scenarios = <LeoSkillTestCase>[];
    String? input;
    String? expected;
    void flush() {
      if (input != null && expected != null) {
        scenarios.add(LeoSkillTestCase(
          input: input!.trim(),
          expectedOutcome: expected!.trim(),
        ));
      }
      input = null;
      expected = null;
    }

    for (final line in section.split('\n')) {
      final clean = line.trim();
      if (clean.startsWith('### ')) {
        flush();
        continue;
      }
      final inputMatch = RegExp(r'^(?:[-*]\s*)?Input:\s*(.+)$', caseSensitive: false)
          .firstMatch(clean);
      if (inputMatch != null) {
        if (input != null || expected != null) flush();
        input = inputMatch.group(1)!.trim();
        continue;
      }
      final expectedMatch = RegExp(
        r'^(?:[-*]\s*)?Expected(?: outcome)?:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(clean);
      if (expectedMatch != null) {
        expected = expectedMatch.group(1)!.trim();
      }
    }
    flush();
    return scenarios.take(10).toList(growable: false);
  }

  static String? _firstHeading(String body) {
    final match = RegExp(r'(?m)^#\s+(.+?)\s*$').firstMatch(body);
    return match?.group(1)?.trim();
  }

  static String _fallbackInstructions(String body) {
    final cleaned = body
        .replaceAll(RegExp(r'(?m)^#{1,6}\s+.*$'), '')
        .replaceAll(RegExp(r'(?m)^<!--.*?-->\s*$', dotAll: true), '')
        .trim();
    final value = cleaned.isEmpty
        ? 'اتبع خطوات المهارة عند ملاءمتها لطلب المستخدم.'
        : cleaned;
    return value.length > 12000 ? value.substring(0, 12000) : value;
  }

  static String _fallbackTrigger(String description) {
    final words = description.trim().split(RegExp(r'\s+'));
    var trigger = words.take(8).join(' ');
    if (trigger.length > 80) {
      trigger = trigger.substring(0, 80).trimRight();
    }
    return trigger;
  }

  static String _normalizeHeading(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  static bool _validExternalName(String name) =>
      name.length >= 1 &&
      name.length <= 64 &&
      RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(name);

  static String _slug(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (slug.isEmpty) return 'leo-skill';
    return slug.length > 64 ? slug.substring(0, 64).replaceAll(RegExp(r'-$'), '') : slug;
  }

  static String _yamlQuote(String value) => jsonEncode(value);
}
