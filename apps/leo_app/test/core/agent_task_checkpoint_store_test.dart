import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/core/tools/agent_task_checkpoint_store.dart';

class _MemorySecureTextStore implements SecureTextStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

Map<String, dynamic> _checkpoint({
  String state = 'running',
  Object? proposal,
}) => {
  'version': 1,
  'task_id': 'task-1',
  'goal': 'نفذ مهمة متعددة الخطوات',
  'conversation_context': '[المستخدم] نفذ المهمة',
  'state': state,
  'plan': {
    'id': 'task-1',
    'goal': 'نفذ مهمة متعددة الخطوات',
    'state': 'planned',
    'steps': <Object>[],
  },
  'step_results': <Object>[],
  'proposal': proposal,
  'completed_handoffs': 0,
};

Map<String, dynamic> _actionProposal() => {
  'step_id': 'specialist_0',
  'agent_id': 'device_operator',
  'call_id': 'call_1',
  'tool_name': 'app.launch',
  'raw_call': '<leo_tool_call>{"version":1}</leo_tool_call>',
};

void main() {
  group('AgentTaskCheckpointStore', () {
    late _MemorySecureTextStore secure;
    late AgentTaskCheckpointStore store;

    setUp(() {
      secure = _MemorySecureTextStore();
      store = AgentTaskCheckpointStore(secureStore: secure);
    });

    test('persists and restores a running checkpoint', () async {
      await store.saveCheckpoint(
        checkpointJson: jsonEncode(_checkpoint()),
        sessionId: 'chat-1',
      );

      final records = await store.loadPending();
      expect(records, hasLength(1));
      expect(records.single.taskId, 'task-1');
      expect(records.single.sessionId, 'chat-1');
      expect(records.single.state, AgentTaskCheckpointState.running);
      expect(records.single.toolCallId, isNull);
    });

    test(
      'stores action intent before result and requires an exact match',
      () async {
        await store.saveCheckpoint(
          checkpointJson: jsonEncode(
            _checkpoint(state: 'awaiting_action', proposal: _actionProposal()),
          ),
          sessionId: 'chat-1',
        );
        expect(
          () => store.markActionSucceeded(
            taskId: 'task-1',
            toolCallId: 'wrong',
            toolName: 'app.launch',
            toolResult: 'ok',
          ),
          throwsStateError,
        );

        final updated = await store.markActionSucceeded(
          taskId: 'task-1',
          toolCallId: 'call_1',
          toolName: 'app.launch',
          toolResult: 'تم فتح التطبيق.',
        );
        expect(updated.state, AgentTaskCheckpointState.readyToResume);
        expect(updated.toolResult, 'تم فتح التطبيق.');
        expect(
          (await store.get('task-1'))?.state,
          AgentTaskCheckpointState.readyToResume,
        );
      },
    );

    test(
      'ambiguous interrupted action needs explicit user confirmation',
      () async {
        await store.saveCheckpoint(
          checkpointJson: jsonEncode(
            _checkpoint(state: 'awaiting_action', proposal: _actionProposal()),
          ),
          sessionId: 'chat-1',
        );
        final confirmed = await store.confirmInterruptedAction(
          taskId: 'task-1',
          confirmationResult:
              'أكد المستخدم بعد المراجعة اليدوية اكتمال التسليم.',
        );
        expect(confirmed.state, AgentTaskCheckpointState.readyToResume);
        expect(confirmed.toolResult, contains('المراجعة اليدوية'));
      },
    );

    test(
      'expires old checkpoints and deletes empty secure-store value',
      () async {
        final oldRecord = AgentTaskCheckpointRecord(
          taskId: 'task-1',
          goal: 'نفذ مهمة متعددة الخطوات',
          sessionId: 'chat-1',
          checkpointJson: jsonEncode(_checkpoint()),
          state: AgentTaskCheckpointState.running,
          savedAtUtc: DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 8))
              .toIso8601String(),
        );
        secure.values[AgentTaskCheckpointStore.storageKey] = jsonEncode([
          oldRecord.toJson(),
        ]);
        expect(await store.loadPending(), isEmpty);
        expect(secure.values, isEmpty);
      },
    );

    test('rejects duplicate and malformed checkpoint records', () async {
      final record = AgentTaskCheckpointRecord(
        taskId: 'task-1',
        goal: 'نفذ مهمة متعددة الخطوات',
        sessionId: 'chat-1',
        checkpointJson: jsonEncode(_checkpoint()),
        state: AgentTaskCheckpointState.running,
        savedAtUtc: DateTime.now().toUtc().toIso8601String(),
      ).toJson();
      secure.values[AgentTaskCheckpointStore.storageKey] = jsonEncode([
        record,
        record,
      ]);
      await expectLater(store.loadPending(), throwsFormatException);
      secure.values[AgentTaskCheckpointStore.storageKey] = '{invalid';
      await expectLater(store.loadPending(), throwsFormatException);
    });

    test(
      'removes a task and clears secure storage when no tasks remain',
      () async {
        await store.saveCheckpoint(
          checkpointJson: jsonEncode(_checkpoint()),
          sessionId: 'chat-1',
        );
        await store.remove('task-1');
        expect(await store.loadPending(), isEmpty);
        expect(
          secure.values.containsKey(AgentTaskCheckpointStore.storageKey),
          isFalse,
        );
      },
    );
  });
}
