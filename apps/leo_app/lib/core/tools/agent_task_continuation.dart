import 'dart:convert';

/// Framing for restoring a persisted multi-agent checkpoint.
///
/// A restore envelope can only continue local reasoning from completed steps.
/// Pending external actions require a separate success-only receipt and are
/// never replayed by this envelope.
class AgentTaskContinuationReceipt {
  const AgentTaskContinuationReceipt._();

  static const startMarker = '<leo_task_resume>';
  static const endMarker = '</leo_task_resume>';
  static const restoreStartMarker = '<leo_task_restore>';
  static const restoreEndMarker = '</leo_task_restore>';
  static const maxEnvelopeBytes = 320 * 1024;
  static const maxCheckpointBytes = 256 * 1024;
  static const maxResultCharacters = 12000;
  static const allowedTools = <String>{
    'files.read_selected',
    'workspace.write_file',
    'email.compose',
    'phone.dial',
    'messages.compose',
    'web.open',
    'app.launch',
  };

  static String encode({
    required String taskId,
    required String toolCallId,
    required String toolName,
    required String result,
    required String checkpointJson,
  }) {
    _validateTaskId(taskId);
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(toolCallId)) {
      throw const FormatException('Invalid continuation tool-call ID.');
    }
    if (!allowedTools.contains(toolName)) {
      throw const FormatException('Tool is not allowed in a continuation receipt.');
    }
    if (result.length > maxResultCharacters) {
      throw const FormatException('Continuation result is too large.');
    }
    final checkpoint = _decodeCheckpoint(checkpointJson);
    if (checkpoint['task_id'] != taskId ||
        checkpoint['state'] != 'awaiting_action' ||
        checkpoint['proposal'] is! Map<String, dynamic> ||
        (checkpoint['proposal'] as Map<String, dynamic>)['call_id'] != toolCallId ||
        (checkpoint['proposal'] as Map<String, dynamic>)['tool_name'] != toolName) {
      throw const FormatException('Checkpoint does not match the successful tool result.');
    }

    final payload = jsonEncode({
      'version': 1,
      'task_id': taskId,
      'tool_call_id': toolCallId,
      'tool_name': toolName,
      'success': true,
      'result': result,
      'checkpoint': checkpoint,
    });
    if (utf8.encode(payload).length > maxEnvelopeBytes) {
      throw const FormatException('Continuation envelope is too large.');
    }
    return '$startMarker$payload$endMarker';
  }

  /// Restores a checkpoint that was interrupted during local model reasoning.
  /// This format explicitly rejects an outstanding external action.
  static String encodeRestore({required String checkpointJson}) {
    final checkpoint = _decodeCheckpoint(checkpointJson);
    if (checkpoint['state'] != 'running' || checkpoint['proposal'] != null) {
      throw const FormatException('Only a running reasoning checkpoint can be restored this way.');
    }
    final payload = jsonEncode({'version': 1, 'checkpoint': checkpoint});
    if (utf8.encode(payload).length > maxEnvelopeBytes) {
      throw const FormatException('Restore envelope is too large.');
    }
    return '$restoreStartMarker$payload$restoreEndMarker';
  }

  static Map<String, dynamic> _decodeCheckpoint(String raw) {
    if (utf8.encode(raw).length > maxCheckpointBytes) {
      throw const FormatException('Checkpoint is too large.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['task_id'] is! String ||
        decoded['goal'] is! String ||
        decoded['plan'] is! Map<String, dynamic> ||
        decoded['step_results'] is! List ||
        decoded['completed_handoffs'] is! int) {
      throw const FormatException('Checkpoint envelope is invalid.');
    }
    _validateTaskId(decoded['task_id'] as String);
    return decoded;
  }

  static void _validateTaskId(String taskId) {
    if (!RegExp(r'^[A-Za-z0-9_.-]{1,96}$').hasMatch(taskId)) {
      throw const FormatException('Invalid continuation task ID.');
    }
  }
}
