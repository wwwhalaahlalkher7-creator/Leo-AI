import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/core/skills/skill_models.dart';
import 'package:leo_app/core/skills/skill_repository.dart';
import 'package:leo_app/features/skills/skill_library_page.dart';

void main() {
  testWidgets('skill library explains its safety boundary and empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: SkillLibraryPage(repository: _EmptySkillRepository()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مهارات Leo'), findsOneWidget);
    expect(find.text('مكتبة المهارات فارغة حالياً'), findsOneWidget);
    expect(find.textContaining('الفحص الحالي بنيوي فقط'), findsOneWidget);
    expect(find.text('تعلم مهارة'), findsOneWidget);
  });
}

class _EmptySkillRepository implements SkillRepository {
  const _EmptySkillRepository();

  @override
  Future<LeoSkill> activate(String skillId) => throw UnimplementedError();

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
  }) => throw UnimplementedError();

  @override
  Future<bool> delete(String skillId) => throw UnimplementedError();

  @override
  Future<LeoSkill> disable(String skillId) => throw UnimplementedError();

  @override
  Future<List<LeoSkill>> findApplicable(
    String request, {
    int limit = 2,
  }) async => const [];

  @override
  Future<List<LeoSkill>> list() async => const [];

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
}
