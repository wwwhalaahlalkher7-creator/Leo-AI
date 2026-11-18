import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/core/tools/agent_task_continuation.dart';

Map<String, dynamic> _checkpoint({
  String state = 'awaiting_action',
  Object? proposal = const {
    'step_id': 'specialist_0',
    'agent_id': 'device_operator',
    'call_id': 'call_1',
    'tool_name': 'web.open',
    'raw_call': '<leo_tool_call>{"version":1}</leo_tool_call>',
  },
}) => {
      'version': 1,
      'task_id': 'task-123',
      'goal': 'افتح الموقع ثم راجع النتيجة',
      'conversation_context': '[المستخدم] افتح الموقع',
      'state': state,
      'plan': {
        'id': 'task-123',
        'goal': 'افتح الموقع ثم راجع النتيجة',
        'state': 'planned',
        'steps': <Object>[],
      },
      'step_results': <Object>[],
      'proposal': proposal,
      'completed_handoffs': 0,
    };

void main() {
  group('AgentTaskContinuationReceipt', () {
    test('encodes success result and exact durable checkpoint fields', () {
      final checkpoint = jsonEncode(_checkpoint());
      final encoded = AgentTaskContinuationReceipt.encode(
        taskId: 'task-123',
        toolCallId: 'call_1',
        toolName: 'web.open',
        result: 'تم تسليم الرابط إلى المتصفح.',
        checkpointJson: checkpoint,
      );
      expect(encoded, startsWith(AgentTaskContinuationReceipt.startMarker));
      expect(encoded, endsWith(AgentTaskContinuationReceipt.endMarker));
      final payload = encoded.substring(
        AgentTaskContinuationReceipt.startMarker.length,
        encoded.length - AgentTaskContinuationReceipt.endMarker.length,
      );
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      expect(decoded.keys.toSet(), {
        'version', 'task_id', 'tool_call_id', 'tool_name', 'success', 'result', 'checkpoint',
      });
      expect(decoded['success'], isTrue);
      expect(decoded['tool_call_id'], 'call_1');
      expect(decoded['checkpoint']['task_id'], 'task-123');
    });

    test('rejects invalid IDs, tools and mismatched checkpoints', () {
      final valid = jsonEncode(_checkpoint());
      expect(
        () => AgentTaskContinuationReceipt.encode(
          taskId: '../escape', toolCallId: 'call_1',
          toolName: 'web.open', result: 'ok', checkpointJson: valid,
        ),
        throwsFormatException,
      );
      expect(
        () => AgentTaskContinuationReceipt.encode(
          taskId: 'task-123', toolCallId: 'call_1',
          toolName: 'shell.exec', result: 'ok', checkpointJson: valid,
        ),
        throwsFormatException,
      );
      expect(
        () => AgentTaskContinuationReceipt.encode(
          taskId: 'task-123', toolCallId: 'call_wrong',
          toolName: 'web.open', result: 'ok', checkpointJson: valid,
        ),
        throwsFormatException,
      );
    });

    test('restore envelope accepts only a running checkpoint with no proposal', () {
      final encoded = AgentTaskContinuationReceipt.encodeRestore(
        checkpointJson: jsonEncode(_checkpoint(state: 'running', proposal: null)),
      );
      expect(encoded, startsWith(AgentTaskContinuationReceipt.restoreStartMarker));
      expect(encoded, endsWith(AgentTaskContinuationReceipt.restoreEndMarker));
      expect(
        () => AgentTaskContinuationReceipt.encodeRestore(
          checkpointJson: jsonEncode(_checkpoint()),
        ),
        throwsFormatException,
      );
    });

    test('enforces result and checkpoint byte budgets', () {
      final valid = jsonEncode(_checkpoint());
      expect(
        () => AgentTaskContinuationReceipt.encode(
          taskId: 'task-123', toolCallId: 'call_1',
          toolName: 'web.open',
          result: List.filled(AgentTaskContinuationReceipt.maxResultCharacters + 1, 'x').join(),
          checkpointJson: valid,
        ),
        throwsFormatException,
      );
      expect(
        () => AgentTaskContinuationReceipt.encodeRestore(
          checkpointJson: jsonEncode({
            ..._checkpoint(state: 'running', proposal: null),
            'conversation_context': List.filled(AgentTaskContinuationReceipt.maxCheckpointBytes, 'x').join(),
          }),
        ),
        throwsFormatException,
      );
    });
  });
}
