import 'dart:convert';

enum LeoSkillStatus { proposed, testing, active, disabled, rejected }

class LeoSkillTestCase {
  const LeoSkillTestCase({required this.input, required this.expectedOutcome});

  final String input;
  final String expectedOutcome;

  Map<String, Object?> toJson() => {
    'input': input,
    'expectedOutcome': expectedOutcome,
  };

  factory LeoSkillTestCase.fromJson(Map<String, Object?> json) =>
      LeoSkillTestCase(
        input: json['input'] as String? ?? '',
        expectedOutcome: json['expectedOutcome'] as String? ?? '',
      );
}

class LeoSkillValidationCheck {
  const LeoSkillValidationCheck({
    required this.id,
    required this.title,
    required this.passed,
    required this.blocking,
    required this.details,
  });

  final String id;
  final String title;
  final bool passed;
  final bool blocking;
  final String details;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'passed': passed,
    'blocking': blocking,
    'details': details,
  };

  factory LeoSkillValidationCheck.fromJson(Map<String, Object?> json) =>
      LeoSkillValidationCheck(
        id: json['id'] as String? ?? 'unknown',
        title: json['title'] as String? ?? '',
        passed: json['passed'] as bool? ?? false,
        blocking: json['blocking'] as bool? ?? true,
        details: json['details'] as String? ?? '',
      );
}

class LeoSkillValidationReport {
  const LeoSkillValidationReport({
    required this.checkedAtUtc,
    required this.passed,
    required this.checks,
    required this.disclaimer,
  });

  final String checkedAtUtc;
  final bool passed;
  final List<LeoSkillValidationCheck> checks;
  final String disclaimer;

  Map<String, Object?> toJson() => {
    'checkedAtUtc': checkedAtUtc,
    'passed': passed,
    'checks': checks.map((item) => item.toJson()).toList(),
    'disclaimer': disclaimer,
  };

  factory LeoSkillValidationReport.fromJson(Map<String, Object?> json) =>
      LeoSkillValidationReport(
        checkedAtUtc: json['checkedAtUtc'] as String? ?? '',
        passed: json['passed'] as bool? ?? false,
        checks: (json['checks'] as List<Object?>? ?? const [])
            .whereType<Map<String, Object?>>()
            .map(LeoSkillValidationCheck.fromJson)
            .toList(growable: false),
        disclaimer: json['disclaimer'] as String? ?? '',
      );
}

class LeoSkillVersionSnapshot {
  const LeoSkillVersionSnapshot({
    required this.version,
    required this.instructions,
    required this.changeSummary,
    required this.createdAtUtc,
  });

  final String version;
  final String instructions;
  final String changeSummary;
  final String createdAtUtc;

  Map<String, Object?> toJson() => {
    'version': version,
    'instructions': instructions,
    'changeSummary': changeSummary,
    'createdAtUtc': createdAtUtc,
  };

  factory LeoSkillVersionSnapshot.fromJson(Map<String, Object?> json) =>
      LeoSkillVersionSnapshot(
        version: json['version'] as String? ?? '0.1.0',
        instructions: json['instructions'] as String? ?? '',
        changeSummary: json['changeSummary'] as String? ?? '',
        createdAtUtc: json['createdAtUtc'] as String? ?? '',
      );
}

class LeoSkill {
  const LeoSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.triggers,
    required this.instructions,
    required this.steps,
    required this.testCases,
    required this.requiredCapabilities,
    required this.status,
    required this.version,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.history,
    this.sourceTaskId,
    this.validationReport,
  });

  final String id;
  final String name;
  final String description;
  final List<String> triggers;
  final String instructions;
  final List<String> steps;
  final List<LeoSkillTestCase> testCases;
  final List<String> requiredCapabilities;
  final LeoSkillStatus status;
  final String version;
  final String createdAtUtc;
  final String updatedAtUtc;
  final List<LeoSkillVersionSnapshot> history;
  final String? sourceTaskId;
  final LeoSkillValidationReport? validationReport;

  bool get isValidated => validationReport?.passed == true;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'triggers': triggers,
    'instructions': instructions,
    'steps': steps,
    'testCases': testCases.map((item) => item.toJson()).toList(),
    'requiredCapabilities': requiredCapabilities,
    'status': status.name,
    'version': version,
    'createdAtUtc': createdAtUtc,
    'updatedAtUtc': updatedAtUtc,
    'history': history.map((item) => item.toJson()).toList(),
    'sourceTaskId': sourceTaskId,
    'validationReport': validationReport?.toJson(),
  };

  factory LeoSkill.fromJson(Map<String, Object?> json) {
    final statusName = json['status'] as String? ?? 'proposed';
    return LeoSkill(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      triggers: _stringList(json['triggers']),
      instructions: json['instructions'] as String? ?? '',
      steps: _stringList(json['steps']),
      testCases: (json['testCases'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(LeoSkillTestCase.fromJson)
          .toList(growable: false),
      requiredCapabilities: _stringList(json['requiredCapabilities']),
      status: LeoSkillStatus.values.firstWhere(
        (value) => value.name == statusName,
        orElse: () => LeoSkillStatus.proposed,
      ),
      version: json['version'] as String? ?? '0.1.0',
      createdAtUtc: json['createdAtUtc'] as String? ?? '',
      updatedAtUtc: json['updatedAtUtc'] as String? ?? '',
      history: (json['history'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .map(LeoSkillVersionSnapshot.fromJson)
          .toList(growable: false),
      sourceTaskId: json['sourceTaskId'] as String?,
      validationReport: json['validationReport'] is Map<String, Object?>
          ? LeoSkillValidationReport.fromJson(
              json['validationReport'] as Map<String, Object?>,
            )
          : null,
    );
  }

  LeoSkill copyWith({
    String? name,
    String? description,
    List<String>? triggers,
    String? instructions,
    List<String>? steps,
    List<LeoSkillTestCase>? testCases,
    List<String>? requiredCapabilities,
    LeoSkillStatus? status,
    String? version,
    String? updatedAtUtc,
    List<LeoSkillVersionSnapshot>? history,
    String? sourceTaskId,
    LeoSkillValidationReport? validationReport,
    bool clearValidation = false,
  }) => LeoSkill(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    triggers: triggers ?? this.triggers,
    instructions: instructions ?? this.instructions,
    steps: steps ?? this.steps,
    testCases: testCases ?? this.testCases,
    requiredCapabilities: requiredCapabilities ?? this.requiredCapabilities,
    status: status ?? this.status,
    version: version ?? this.version,
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    history: history ?? this.history,
    sourceTaskId: sourceTaskId ?? this.sourceTaskId,
    validationReport: clearValidation
        ? null
        : validationReport ?? this.validationReport,
  );

  static List<String> _stringList(Object? value) =>
      (value as List<Object?>? ?? const []).whereType<String>().toList(
        growable: false,
      );
}

String encodeLeoSkills(List<LeoSkill> skills) => jsonEncode({
  'schemaVersion': 1,
  'skills': skills.map((skill) => skill.toJson()).toList(),
});
