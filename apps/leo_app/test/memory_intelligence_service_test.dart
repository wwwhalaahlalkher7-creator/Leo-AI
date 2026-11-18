import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/core/memory/memory_intelligence_service.dart';
import 'package:leo_app/core/memory/memory_repository.dart';

LeoMemoryEntry memory(String content, {LeoMemoryKind kind = LeoMemoryKind.personal}) =>
    LeoMemoryEntry(
      id: 'memory-test',
      kind: kind,
      content: content,
      tags: const [],
      createdAtUtc: '2026-11-18T00:00:00Z',
      updatedAtUtc: '2026-11-18T00:00:00Z',
      userApproved: true,
      active: true,
    );

void main() {
  const service = MemoryIntelligenceService();

  test('finds high similarity duplicates after Arabic normalization', () {
    final findings = service.reviewCandidate(
      content: 'أُفضّلُ التشغيل المحلّي دون إنترنت',
      kind: LeoMemoryKind.personal,
      existing: [memory('أفضل التشغيل المحلي دون انترنت')],
    );
    expect(findings, isNotEmpty);
    expect(findings.first.kind, MemoryFindingKind.duplicate);
  });

  test('flags potential opposite-polarity memories for human review', () {
    final findings = service.reviewCandidate(
      content: 'لا أفضل استخدام الخدمات المدفوعة للمشروع',
      kind: LeoMemoryKind.personal,
      existing: [memory('أفضل استخدام الخدمات المدفوعة للمشروع')],
    );
    expect(findings, isNotEmpty);
    expect(findings.first.kind, MemoryFindingKind.possibleContradiction);
  });

  test('does not compare different memory categories', () {
    final findings = service.reviewCandidate(
      content: 'أفضل استخدام الخدمات المدفوعة للمشروع',
      kind: LeoMemoryKind.project,
      existing: [memory('أفضل استخدام الخدمات المدفوعة للمشروع')],
    );
    expect(findings, isEmpty);
  });

  test('never proposes changes or actions; returns at most five findings', () {
    final findings = service.reviewCandidate(
      content: 'أستخدم Flutter لتطوير التطبيق',
      kind: LeoMemoryKind.personal,
      existing: List.generate(8, (index) => memory('أستخدم Flutter لتطوير التطبيق $index')),
    );
    expect(findings.length, lessThanOrEqualTo(5));
    expect(findings.every((finding) => finding.existing.userApproved), isTrue);
  });
}
