import 'assistant_runtime_client.dart';

/// Result of a best-effort, application-side conversation compaction pass.
/// The estimate is not a tokenizer; native llama.cpp remains authoritative.
class ConversationContextPlan {
  const ConversationContextPlan({
    required this.messages,
    required this.estimatedInputTokens,
    required this.inputBudgetTokens,
    required this.omittedMessageCount,
    required this.omittedTurnCount,
    required this.keptFirstGoal,
  });

  final List<RuntimeInputMessage> messages;
  final int estimatedInputTokens;
  final int inputBudgetTokens;
  final int omittedMessageCount;
  final int omittedTurnCount;
  final bool keptFirstGoal;

  bool get compacted => omittedMessageCount > 0;
}

class ConversationContextException implements Exception {
  const ConversationContextException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Keeps every system instruction and the latest user/tool cycle, then fills
/// the remaining budget with the newest complete conversation turns. Older
/// turns are never partially retained. An initial user goal is kept only when
/// it fits after the recent turns and pinned instructions.
class ConversationContextPlanner {
  const ConversationContextPlanner({this.messageOverheadTokens = 8});

  static const String compactionNotice =
      'Context note: older complete turns were omitted to fit the active context. Do not infer missing details.';

  final int messageOverheadTokens;

  ConversationContextPlan plan(
    List<RuntimeInputMessage> input, {
    required int inputBudgetTokens,
  }) {
    if (inputBudgetTokens < 1) {
      throw const ConversationContextException(
        'ميزانية سياق النموذج غير كافية. اختر سياقاً أكبر أو خفّض حد الإخراج.',
      );
    }

    final messages = List<RuntimeInputMessage>.unmodifiable(input);
    final systemIndexes = <int>[];
    final turns = <_ConversationTurn>[];
    var currentIndexes = <int>[];
    var hasUserRequest = false;

    for (var index = 0; index < messages.length; index++) {
      final message = messages[index];
      if (message.role == 'system') {
        systemIndexes.add(index);
        continue;
      }
      if (message.role == 'user') {
        hasUserRequest = true;
        if (currentIndexes.isNotEmpty) {
          turns.add(_ConversationTurn(List<int>.unmodifiable(currentIndexes)));
          currentIndexes = <int>[];
        }
      }
      currentIndexes.add(index);
    }
    if (currentIndexes.isNotEmpty) {
      turns.add(_ConversationTurn(List<int>.unmodifiable(currentIndexes)));
    }
    if (!hasUserRequest ||
        turns.isEmpty ||
        !turns.last.indexes.any((index) => messages[index].role == 'user')) {
      throw const ConversationContextException(
        'لا توجد رسالة مستخدم حالية يمكن الحفاظ عليها في سياق النموذج.',
      );
    }

    final pinnedCost = _costFor(messages, systemIndexes);
    if (pinnedCost > inputBudgetTokens) {
      throw ConversationContextException(
        'تعليمات النظام والذاكرة المرجعية تحتاج نحو $pinnedCost رمزاً، بينما المتاح $inputBudgetTokens. اختصر التعليمات أو قلّل الذكريات المسترجعة.',
      );
    }

    final fullConversationIndexes = <int>{...systemIndexes};
    for (final turn in turns) {
      fullConversationIndexes.addAll(turn.indexes);
    }
    final fullConversationCost = _costFor(messages, fullConversationIndexes);
    if (fullConversationCost <= inputBudgetTokens) {
      return ConversationContextPlan(
        messages: messages,
        estimatedInputTokens: fullConversationCost,
        inputBudgetTokens: inputBudgetTokens,
        omittedMessageCount: 0,
        omittedTurnCount: 0,
        keptFirstGoal: true,
      );
    }

    final lastTurn = turns.last;
    final latestCost = _costFor(messages, lastTurn.indexes);
    final noteCost = _messageCost(compactionNotice);
    var used = pinnedCost + latestCost + noteCost;
    if (used > inputBudgetTokens) {
      throw ConversationContextException(
        'الطلب الحالي وحده يحتاج نحو ${latestCost + pinnedCost} رمزاً، بينما ميزانية الإدخال $inputBudgetTokens. اختصر الرسالة أو نتائج الأدوات أو خفّض حد الإخراج.',
      );
    }

    final keptTurnIndexes = <int>{turns.length - 1};
    // Fill newest-to-oldest, never splitting a user turn.
    for (var turnIndex = turns.length - 2; turnIndex >= 1; turnIndex--) {
      final cost = _costFor(messages, turns[turnIndex].indexes);
      if (used + cost <= inputBudgetTokens) {
        used += cost;
        keptTurnIndexes.add(turnIndex);
      }
    }

    var keptFirstGoal = false;
    if (turns.length > 1) {
      final firstCost = _costFor(messages, turns.first.indexes);
      if (used + firstCost <= inputBudgetTokens) {
        used += firstCost;
        keptTurnIndexes.add(0);
        keptFirstGoal = true;
      }
    } else {
      keptFirstGoal = true;
    }

    final retainedIndexes = <int>{...systemIndexes};
    for (final turnIndex in keptTurnIndexes) {
      retainedIndexes.addAll(turns[turnIndex].indexes);
    }
    final omittedTurnCount = turns.length - keptTurnIndexes.length;
    final omittedMessageCount = messages.length - retainedIndexes.length;
    final result = <RuntimeInputMessage>[];
    for (var index = 0; index < messages.length; index++) {
      if (retainedIndexes.contains(index)) result.add(messages[index]);
    }
    if (omittedTurnCount > 0) {
      // Put the compaction note before every existing system instruction so
      // the tool/security policy remains the last system instruction.
      result.insert(
        0,
        const RuntimeInputMessage(role: 'system', content: compactionNotice),
      );
    }

    return ConversationContextPlan(
      messages: List<RuntimeInputMessage>.unmodifiable(result),
      estimatedInputTokens: used,
      inputBudgetTokens: inputBudgetTokens,
      omittedMessageCount: omittedMessageCount,
      omittedTurnCount: omittedTurnCount,
      keptFirstGoal: keptFirstGoal,
    );
  }

  int _costFor(List<RuntimeInputMessage> messages, Iterable<int> indexes) {
    var total = 0;
    for (final index in indexes) {
      total += _messageCost(messages[index].content);
    }
    return total;
  }

  int _messageCost(String content) {
    // This lightweight heuristic is only for deciding which older turns to
    // compact. Token density varies by model and language; native llama.cpp
    // performs exact tokenization and may still trim more complete old turns.
    final estimatedTokens = (content.runes.length + 1) ~/ 2;
    return estimatedTokens + messageOverheadTokens;
  }
}

class _ConversationTurn {
  const _ConversationTurn(this.indexes);

  final List<int> indexes;
}
