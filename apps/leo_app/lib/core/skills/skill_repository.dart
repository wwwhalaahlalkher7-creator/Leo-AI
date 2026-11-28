import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'skill_models.dart';

abstract interface class SkillRepository {
  Future<List<LeoSkill>> list();

  Future<LeoSkill> createProposal({
    required String name,
    required String description,
    required List<String> triggers,
    required String instructions,
    required List<String> steps,
    required List<LeoSkillTestCase> testCases,
    required List<String> requiredCapabilities,
    String? sourceTaskId,
  });

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
  });

  Future<LeoSkill> validate(String skillId);
  Future<LeoSkill> activate(String skillId);
  Future<LeoSkill> disable(String skillId);
  Future<LeoSkill> reject(String skillId);
  Future<bool> delete(String skillId);
  Future<List<LeoSkill>> findApplicable(String request, {int limit = 2});
}

/// App-private, offline skill library.
///
/// Skills are declarative workflow guidance only in this milestone. The
/// repository never executes embedded scripts or grants capabilities.
class FileSkillRepository implements SkillRepository {
  FileSkillRepository({
    Future<Directory> Function()? supportDirectoryProvider,
    Directory? rootDirectory,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ??
           (rootDirectory == null
               ? getApplicationSupportDirectory
               : (() async => rootDirectory));

  final Future<Directory> Function() _supportDirectoryProvider;
  Future<void> _tail = Future<void>.value();
  static const _schemaVersion = 1;
  static const _maxSkills = 500;

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<File> _databaseFile() async {
    final support = await _supportDirectoryProvider();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}leo${Platform.pathSeparator}skills',
    );
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}skills-v1.json');
  }

  Future<List<LeoSkill>> _readAll() async {
    final file = await _databaseFile();
    final backup = File('${file.path}.bak');
    if (!await file.exists() && await backup.exists()) {
      await backup.rename(file.path);
    } else if (await file.exists() && await backup.exists()) {
      await backup.delete();
    }
    if (!await file.exists()) return const [];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('تنسيق مكتبة المهارات غير صالح.');
    }
    final schema = decoded['schemaVersion'];
    if (schema != _schemaVersion) {
      throw FormatException('إصدار مكتبة المهارات غير مدعوم: $schema');
    }
    final rawSkills = decoded['skills'];
    if (rawSkills is! List<Object?>) {
      throw const FormatException('قائمة المهارات غير موجودة.');
    }
    return rawSkills
        .whereType<Map<String, Object?>>()
        .map(LeoSkill.fromJson)
        .toList(growable: true);
  }

  Future<void> _writeAll(List<LeoSkill> skills) async {
    final file = await _databaseFile();
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temporary.writeAsString(encodeLeoSkills(skills), flush: true);

    var movedOriginal = false;
    try {
      if (await file.exists()) {
        if (await backup.exists()) await backup.delete();
        await file.rename(backup.path);
        movedOriginal = true;
      }
      await temporary.rename(file.path);
      if (movedOriginal && await backup.exists()) await backup.delete();
    } catch (_) {
      if (movedOriginal && !await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  @override
  Future<List<LeoSkill>> list() => _serialized(() async {
    final skills = await _readAll();
    skills.sort((a, b) => b.updatedAtUtc.compareTo(a.updatedAtUtc));
    return List.unmodifiable(skills);
  });

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
  }) => _serialized(() async {
    final skills = await _readAll();
    if (skills.length >= _maxSkills) {
      throw StateError('وصلت مكتبة Leo إلى الحد الأقصى للمهارات.');
    }
    final cleanSourceTaskId = _cleanOptional(sourceTaskId);
    if (cleanSourceTaskId != null &&
        cleanSourceTaskId.startsWith('verified-run:') &&
        skills.any((item) => item.sourceTaskId == cleanSourceTaskId)) {
      throw StateError('تم إنشاء اقتراح مسبقاً من تشغيل سير العمل هذا.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final skill = LeoSkill(
      id: 'skill-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      description: description.trim(),
      triggers: _cleanList(triggers),
      instructions: instructions.trim(),
      steps: _cleanList(steps),
      testCases: testCases,
      requiredCapabilities: _cleanList(requiredCapabilities),
      status: LeoSkillStatus.proposed,
      version: '0.1.0',
      createdAtUtc: now,
      updatedAtUtc: now,
      history: const [],
      sourceTaskId: cleanSourceTaskId,
    );
    if (skills.any((item) => item.id == skill.id)) {
      throw StateError('تعذر إنشاء معرف فريد للمهارة.');
    }
    skills.add(skill);
    await _writeAll(skills);
    return skill;
  });

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
  }) => _serialized(() async {
    final skills = await _readAll();
    final index = skills.indexWhere((item) => item.id == skillId);
    if (index < 0) throw StateError('لم يتم العثور على المهارة.');
    final existing = skills[index];
    if (existing.status == LeoSkillStatus.active) {
      throw StateError('أوقف المهارة قبل إنشاء إصدار جديد منها.');
    }
    if (existing.status == LeoSkillStatus.rejected) {
      throw StateError('لا يمكن تعديل اقتراح مرفوض؛ أنشئ مهارة جديدة.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final snapshot = LeoSkillVersionSnapshot(
      version: existing.version,
      instructions: existing.instructions,
      changeSummary: changeSummary.trim().isEmpty
          ? 'نسخة محفوظة قبل التعديل'
          : changeSummary.trim(),
      createdAtUtc: now,
    );
    final nextVersion = _nextMinorVersion(existing.version);
    final updated = existing.copyWith(
      name: name.trim(),
      description: description.trim(),
      triggers: _cleanList(triggers),
      instructions: instructions.trim(),
      steps: _cleanList(steps),
      testCases: testCases,
      requiredCapabilities: _cleanList(requiredCapabilities),
      status: LeoSkillStatus.proposed,
      version: nextVersion,
      updatedAtUtc: now,
      history: [...existing.history, snapshot],
      clearValidation: true,
    );
    skills[index] = updated;
    await _writeAll(skills);
    return updated;
  });

  @override
  Future<LeoSkill> validate(String skillId) => _serialized(() async {
    final skills = await _readAll();
    final index = skills.indexWhere((item) => item.id == skillId);
    if (index < 0) throw StateError('لم يتم العثور على المهارة.');
    final existing = skills[index];
    if (existing.status == LeoSkillStatus.rejected) {
      throw StateError('لا يمكن فحص مهارة مرفوضة. أنشئ اقتراحاً جديداً.');
    }
    final report = _validateSkill(existing);
    final updated = existing.copyWith(
      status: LeoSkillStatus.testing,
      validationReport: report,
      updatedAtUtc: DateTime.now().toUtc().toIso8601String(),
    );
    skills[index] = updated;
    await _writeAll(skills);
    return updated;
  });

  @override
  Future<LeoSkill> activate(String skillId) => _serialized(() async {
    final skills = await _readAll();
    final index = skills.indexWhere((item) => item.id == skillId);
    if (index < 0) throw StateError('لم يتم العثور على المهارة.');
    final skill = skills[index];
    final activatable =
        skill.status == LeoSkillStatus.testing ||
        skill.status == LeoSkillStatus.disabled;
    if (!activatable || !skill.isValidated) {
      throw StateError('يجب اجتياز الفحص المبدئي قبل اعتماد المهارة.');
    }
    final updated = skill.copyWith(
      status: LeoSkillStatus.active,
      updatedAtUtc: DateTime.now().toUtc().toIso8601String(),
    );
    skills[index] = updated;
    await _writeAll(skills);
    return updated;
  });

  @override
  Future<LeoSkill> disable(String skillId) => _setStatus(
    skillId,
    LeoSkillStatus.disabled,
    allowed: const {LeoSkillStatus.active},
  );

  @override
  Future<LeoSkill> reject(String skillId) => _setStatus(
    skillId,
    LeoSkillStatus.rejected,
    allowed: const {LeoSkillStatus.proposed, LeoSkillStatus.testing},
  );

  Future<LeoSkill> _setStatus(
    String skillId,
    LeoSkillStatus status, {
    required Set<LeoSkillStatus> allowed,
  }) => _serialized(() async {
    final skills = await _readAll();
    final index = skills.indexWhere((item) => item.id == skillId);
    if (index < 0) throw StateError('لم يتم العثور على المهارة.');
    final existing = skills[index];
    if (!allowed.contains(existing.status)) {
      throw StateError(
        'لا يمكن تغيير حالة المهارة من ${existing.status.name}.',
      );
    }
    final updated = existing.copyWith(
      status: status,
      updatedAtUtc: DateTime.now().toUtc().toIso8601String(),
    );
    skills[index] = updated;
    await _writeAll(skills);
    return updated;
  });

  @override
  Future<bool> delete(String skillId) => _serialized(() async {
    final skills = await _readAll();
    final originalLength = skills.length;
    skills.removeWhere((item) => item.id == skillId);
    if (skills.length == originalLength) return false;
    await _writeAll(skills);
    return true;
  });

  @override
  Future<List<LeoSkill>> findApplicable(
    String request, {
    int limit = 2,
  }) => _serialized(() async {
    if (limit < 1 || limit > 5) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 5');
    }
    final query = _normalize(request);
    if (query.isEmpty) return const [];
    final queryTokens = query
        .split(' ')
        .where((token) => token.length > 1)
        .toSet();
    final scored = <({LeoSkill skill, double score})>[];
    for (final skill in await _readAll()) {
      if (skill.status != LeoSkillStatus.active || !skill.isValidated) continue;
      var score = 0.0;
      for (final trigger in skill.triggers) {
        final normalizedTrigger = _normalize(trigger);
        if (normalizedTrigger.isNotEmpty &&
            (query.contains(normalizedTrigger) ||
                normalizedTrigger.contains(query))) {
          score += 4.0;
        }
        final triggerTokens = normalizedTrigger
            .split(' ')
            .where((token) => token.length > 1)
            .toSet();
        score += queryTokens.intersection(triggerTokens).length * 0.9;
      }
      final metadataTokens = _normalize('${skill.name} ${skill.description}')
          .split(' ')
          .where((token) => token.length > 1)
          .toSet();
      score += queryTokens.intersection(metadataTokens).length * 0.35;
      if (score >= 0.9) scored.add((skill: skill, score: score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0
          ? byScore
          : b.skill.updatedAtUtc.compareTo(a.skill.updatedAtUtc);
    });
    return scored.take(limit).map((item) => item.skill).toList(growable: false);
  });

  LeoSkillValidationReport _validateSkill(LeoSkill skill) {
    final checks = <LeoSkillValidationCheck>[];
    void add(
      String id,
      String title,
      bool passed,
      String details, {
      bool blocking = true,
    }) {
      checks.add(
        LeoSkillValidationCheck(
          id: id,
          title: title,
          passed: passed,
          blocking: blocking,
          details: details,
        ),
      );
    }

    add(
      'metadata',
      'البيانات الأساسية',
      skill.name.length >= 2 &&
          skill.name.length <= 80 &&
          skill.description.length >= 10 &&
          skill.description.length <= 240,
      'اسم المهارة ووصفها يجب أن يكونا واضحين وضمن الحدود المحددة.',
    );
    add(
      'triggers',
      'عبارات الاستدعاء',
      skill.triggers.isNotEmpty &&
          skill.triggers.length <= 12 &&
          skill.triggers.every((item) => item.length >= 2 && item.length <= 80),
      'أضف من عبارة إلى 12 عبارة تصف متى تكون المهارة مناسبة.',
    );
    add(
      'procedure',
      'خطوات الإجراء',
      skill.steps.length >= 2 &&
          skill.steps.length <= 30 &&
          skill.steps.every((item) => item.length >= 4 && item.length <= 400),
      'يجب أن تتضمن المهارة من خطوتين إلى 30 خطوة واضحة.',
    );
    add(
      'instructions',
      'تعليمات المهارة',
      skill.instructions.length >= 80 && skill.instructions.length <= 12000,
      'التعليمات مطلوبة، ويجب ألا تتجاوز 12,000 حرف.',
    );
    add(
      'examples',
      'أمثلة الاختبار',
      skill.testCases.isNotEmpty &&
          skill.testCases.length <= 10 &&
          skill.testCases.every(
            (item) =>
                item.input.trim().length >= 5 &&
                item.expectedOutcome.trim().length >= 5,
          ),
      'أضف من مثال إلى 10 أمثلة، لكل مثال طلب ونتيجة متوقعة.',
    );
    final allGuidance = '${skill.instructions}\n${skill.steps.join('\n')}'
        .toLowerCase();
    final riskyAction = RegExp(
      r'\b(delete|remove|send|transfer|purchase|pay|format|shutdown)\b|احذف|حذف|إرسال|ارسل|أرسل|تحويل|شراء|ادفع|تهيئة|إيقاف التشغيل',
    ).hasMatch(allGuidance);
    final approvalMentioned = RegExp(
      r'\b(confirm|confirmation|approval|permission|consent)\b|موافقة|تأكيد|إذن|اذن',
    ).hasMatch(allGuidance);
    add(
      'sensitive_actions',
      'سلامة الإجراءات الحساسة',
      !riskyAction || approvalMentioned,
      'الإجراءات الحساسة يجب أن تشترط موافقة المستخدم لكل عملية مؤثرة.',
    );
    final negativeSafetyStatements = allGuidance
        .replaceAll(
          RegExp(
            r'(?:do not|never)\s+bypass\s+(?:the )?(?:permission|approval|safety)',
          ),
          '',
        )
        .replaceAll(
          RegExp(r'(?:لا|عدم|ممنوع)\s+تجاوز\s+(?:الصلاحيات|الموافقة|الحماية)'),
          '',
        );
    final bypassAttempt = RegExp(
      r'ignore (all )?(safety|permissions|approvals)|bypass (the )?(permission|approval|safety)|تجاوز (الصلاحيات|الموافقة|الحماية)|تجاهل (الصلاحيات|الموافقة|الأمان)',
    ).hasMatch(negativeSafetyStatements);
    add(
      'no_bypass',
      'عدم تجاوز الحماية',
      !bypassAttempt,
      'لا يجوز أن تطلب المهارة تعطيل الحماية أو تجاوز الصلاحيات.',
    );
    add(
      'capabilities',
      'إعلان القدرات المطلوبة',
      skill.requiredCapabilities.length <= 25 &&
          skill.requiredCapabilities.every(
            (item) =>
                RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$').hasMatch(item),
          ),
      'يجب أن تكون القدرات المطلوبة محددة بمعرفات صالحة؛ إعلانها لا يمنحها.',
      blocking: true,
    );

    final passed = checks.every((item) => !item.blocking || item.passed);
    return LeoSkillValidationReport(
      checkedAtUtc: DateTime.now().toUtc().toIso8601String(),
      passed: passed,
      checks: checks,
      disclaimer: 'هذا فحص بنيوي وسلامة أولي فقط. لم تُنفّذ أمثلة الاختبار على نموذج ذكاء اصطناعي، ولم تُنفّذ أي أوامر أو سكربتات. اعتماد المهارة يظل بيد المستخدم.',
    );
  }

  static List<String> _cleanList(List<String> values) => values
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);

  static String? _cleanOptional(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  static String _nextMinorVersion(String version) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(version);
    if (match == null) return '0.2.0';
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    return '$major.${minor + 1}.0';
  }

  static String _normalize(String value) {
    final buffer = StringBuffer();
    for (final rune in value.toLowerCase().runes) {
      final character = String.fromCharCode(rune);
      if (character == '\u0640' ||
          RegExp(r'[\u064B-\u065F\u0670]').hasMatch(character)) {
        continue;
      }
      switch (character) {
        case 'أ':
        case 'إ':
        case 'آ':
        case 'ٱ':
          buffer.write('ا');
          break;
        case 'ؤ':
          buffer.write('و');
          break;
        case 'ئ':
        case 'ى':
          buffer.write('ي');
          break;
        case 'ة':
          buffer.write('ه');
          break;
        default:
          buffer.write(character);
      }
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
