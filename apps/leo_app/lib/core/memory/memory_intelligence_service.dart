import 'memory_repository.dart';

enum MemoryFindingKind { duplicate, possibleContradiction }

class MemoryReviewFinding {
  const MemoryReviewFinding({
    required this.kind,
    required this.existing,
    required this.similarity,
    required this.explanation,
  });

  final MemoryFindingKind kind;
  final LeoMemoryEntry existing;
  final double similarity;
  final String explanation;
}

/// Conservative, local review helper. It never merges, edits, approves or
/// deletes records; it only surfaces candidate duplicates/contradictions for
/// a person to inspect before saving a new proposal.
class MemoryIntelligenceService {
  const MemoryIntelligenceService({
    this.duplicateThreshold = 0.78,
    this.conflictThreshold = 0.48,
  });

  final double duplicateThreshold;
  final double conflictThreshold;

  List<MemoryReviewFinding> reviewCandidate({
    required String content,
    required LeoMemoryKind kind,
    required List<LeoMemoryEntry> existing,
  }) {
    final candidate = _tokens(content);
    if (candidate.isEmpty) return const [];
    final candidatePolarity = _polarity(content);
    final findings = <MemoryReviewFinding>[];
    for (final entry in existing) {
      if (entry.kind != kind || !entry.userApproved) continue;
      final prior = _tokens(entry.content);
      if (prior.isEmpty) continue;
      final similarity = _jaccard(candidate, prior);
      if (similarity >= duplicateThreshold) {
        findings.add(
          MemoryReviewFinding(
            kind: MemoryFindingKind.duplicate,
            existing: entry,
            similarity: similarity,
            explanation: 'توجد ذاكرة معتمدة متشابهة بدرجة عالية.',
          ),
        );
      } else if (similarity >= conflictThreshold &&
          candidatePolarity != _polarity(entry.content)) {
        findings.add(
          MemoryReviewFinding(
            kind: MemoryFindingKind.possibleContradiction,
            existing: entry,
            similarity: similarity,
            explanation: 'قد تتعارض المعلومة الجديدة مع ذاكرة موجودة؛ راجع السياق قبل اعتمادها.',
          ),
        );
      }
    }
    findings.sort((a, b) => b.similarity.compareTo(a.similarity));
    return findings.take(5).toList(growable: false);
  }

  Set<String> _tokens(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]'), '')
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');
    return normalized
        .split(RegExp(r'\s+'))
        .where((token) => token.runes.length > 1 && !_stopWords.contains(token))
        .toSet();
  }

  double _jaccard(Set<String> left, Set<String> right) {
    if (left.isEmpty || right.isEmpty) return 0;
    final intersection = left.intersection(right).length;
    final union = left.union(right).length;
    return union == 0 ? 0 : intersection / union;
  }

  bool _polarity(String value) {
    final normalized = value.toLowerCase();
    return RegExp(
      r'(^|\s)(لا|ليس|ليست|لم|لن|ما|بدون|غير|ما بحب|ما افضل|لا افضل|لا أفضّل|not|never|no|dont|don.t|cannot|can.t|without)(\s|$)',
      caseSensitive: false,
    ).hasMatch(normalized);
  }

  static const _stopWords = <String>{
    'من',
    'في',
    'على',
    'عن',
    'الى',
    'إلى',
    'هذا',
    'هذه',
    'ذلك',
    'تلك',
    'مع',
    'هو',
    'هي',
    'انا',
    'أنا',
    'انت',
    'أنت',
    'the',
    'and',
    'for',
    'with',
    'from',
    'that',
    'this',
    'are',
    'was',
    'were',
    'have',
    'has',
  };
}
