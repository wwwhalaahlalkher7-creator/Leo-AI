import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/core/chat/assistant_runtime_client.dart';
import 'package:leo_app/core/chat/conversation_context_planner.dart';

void main() {
  const planner = ConversationContextPlanner();

  test('keeps a complete conversation when it fits', () {
    const messages = <RuntimeInputMessage>[
      RuntimeInputMessage(role: 'system', content: 'Do not reveal secrets.'),
      RuntimeInputMessage(role: 'user', content: 'First goal'),
      RuntimeInputMessage(role: 'assistant', content: 'Initial response'),
      RuntimeInputMessage(role: 'user', content: 'Current question'),
    ];

    final plan = planner.plan(messages, inputBudgetTokens: 256);

    expect(plan.messages, messages);
    expect(plan.compacted, isFalse);
    expect(plan.omittedTurnCount, 0);
  });

  test('keeps system instructions and the latest whole turn', () {
    final messages = <RuntimeInputMessage>[
      const RuntimeInputMessage(role: 'system', content: 'Core policy'),
      RuntimeInputMessage(role: 'user', content: 'Old question ${'a' * 120}'),
      const RuntimeInputMessage(role: 'assistant', content: 'Old answer'),
      RuntimeInputMessage(role: 'user', content: 'Middle question ${'b' * 120}'),
      const RuntimeInputMessage(role: 'assistant', content: 'Middle answer'),
      const RuntimeInputMessage(role: 'user', content: 'Newest request'),
      const RuntimeInputMessage(role: 'assistant', content: 'Tool proposal'),
      const RuntimeInputMessage(role: 'tool', content: 'Tool output'),
    ];

    final plan = planner.plan(messages, inputBudgetTokens: 200);

    expect(plan.compacted, isTrue);
    expect(plan.messages.first.content, ConversationContextPlanner.compactionNotice);
    expect(
      plan.messages.where((item) => item.role == 'system').last.content,
      'Core policy',
    );
    expect(plan.messages.any((item) => item.content == 'Newest request'), isTrue);
    expect(plan.messages.any((item) => item.content == 'Tool proposal'), isTrue);
    expect(plan.messages.any((item) => item.content == 'Tool output'), isTrue);
    expect(plan.messages.any((item) => item.content == 'Middle question ${'b' * 120}'), isFalse);
    expect(plan.messages.any((item) => item.content == 'Old question ${'a' * 120}'), isFalse);
    expect(plan.messages.any((item) => item.content == ConversationContextPlanner.compactionNotice), isTrue);
    expect(plan.estimatedInputTokens, lessThanOrEqualTo(plan.inputBudgetTokens));
  });

  test('prefers the newest complete historical turn over older turns', () {
    final messages = <RuntimeInputMessage>[
      const RuntimeInputMessage(role: 'system', content: 'Policy'),
      RuntimeInputMessage(role: 'user', content: 'Old ${'o' * 110}'),
      const RuntimeInputMessage(role: 'assistant', content: 'Old response'),
      RuntimeInputMessage(role: 'user', content: 'Recent ${'r' * 110}'),
      const RuntimeInputMessage(role: 'assistant', content: 'Recent response'),
      const RuntimeInputMessage(role: 'user', content: 'Current request'),
    ];

    final plan = planner.plan(messages, inputBudgetTokens: 205);

    expect(plan.compacted, isTrue);
    expect(plan.messages.any((item) => item.content.startsWith('Recent ')), isTrue);
    expect(plan.messages.any((item) => item.content.startsWith('Old ')), isFalse);
  });

  test('preserves first goal when it fits after recent turns', () {
    final messages = <RuntimeInputMessage>[
      const RuntimeInputMessage(role: 'system', content: 'Policy'),
      const RuntimeInputMessage(role: 'user', content: 'Initial project goal'),
      const RuntimeInputMessage(role: 'assistant', content: 'Acknowledged'),
      RuntimeInputMessage(role: 'user', content: 'Old context ${'m' * 300}'),
      RuntimeInputMessage(role: 'assistant', content: 'Old response ${'n' * 300}'),
      const RuntimeInputMessage(role: 'user', content: 'Recent request'),
    ];

    final plan = planner.plan(messages, inputBudgetTokens: 128);

    expect(plan.compacted, isTrue);
    expect(plan.keptFirstGoal, isTrue);
    expect(plan.messages.any((item) => item.content == 'Initial project goal'), isTrue);
    expect(plan.messages.any((item) => item.content.startsWith('Old context')), isFalse);
  });

  test('does not silently discard an oversized current request', () {
    final messages = <RuntimeInputMessage>[
      const RuntimeInputMessage(role: 'system', content: 'Policy'),
      RuntimeInputMessage(role: 'user', content: 'x' * 700),
    ];

    expect(
      () => planner.plan(messages, inputBudgetTokens: 128),
      throwsA(isA<ConversationContextException>()),
    );
  });

  test('refuses a system prompt that exceeds the complete input budget', () {
    final messages = <RuntimeInputMessage>[
      RuntimeInputMessage(role: 'system', content: 'P' * 500),
      const RuntimeInputMessage(role: 'user', content: 'question'),
    ];

    expect(
      () => planner.plan(messages, inputBudgetTokens: 128),
      throwsA(isA<ConversationContextException>()),
    );
  });

  test('rejects input with no current user request', () {
    const messages = <RuntimeInputMessage>[
      RuntimeInputMessage(role: 'system', content: 'Policy'),
      RuntimeInputMessage(role: 'assistant', content: 'Orphan output'),
    ];

    expect(
      () => planner.plan(messages, inputBudgetTokens: 128),
      throwsA(isA<ConversationContextException>()),
    );
  });
}
