import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// State of a durable agent checkpoint.
///
/// `running` contains only successful reasoning steps and can be resumed.
/// `awaitingAction` means an OS handoff was about to be shown, or may have
/// completed immediately before the process stopped. It must never be replayed.
/// `readyToResume` contains the result captured after a successful handoff.
enum AgentTaskCheckpointState { running, awaitingAction, readyToResume }

class AgentTaskCheckpointRecord {
  const AgentTaskCheckpointRecord({
    required this.taskId,
    required this.goal,
    required this.sessionId,
    required this.checkpointJson,
    required this.state,
    required this.savedAtUtc,
    this.toolCallId,
    this.toolName,
    this.toolResult,
  });

  final String taskId;
  final String goal;
  final String sessionId;
  final String checkpointJson;
  final AgentTaskCheckpointState state;
  final String savedAtUtc;
  final String? toolCallId;
  final String? toolName;
  final String? toolResult;

  Map<String, Object?> toJson() => {
    'task_id': taskId,
    'goal': goal,
    'session_id': sessionId,
    'checkpoint': checkpointJson,
    'state': state.name,
    'saved_at_utc': savedAtUtc,
    'tool_call_id': toolCallId,
    'tool_name': toolName,
    'tool_result': toolResult,
  };

  factory AgentTaskCheckpointRecord.fromJson(Map<String, Object?> json) {
    const keys = {
      'task_id',
      'goal',
      'session_id',
      'checkpoint',
      'state',
      'saved_at_utc',
      'tool_call_id',
      'tool_name',
      'tool_result',
    };
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        json.keys.toSet().length != keys.length) {
      throw const FormatException('Unexpected checkpoint record fields.');
    }
    final stateName = json['state'];
    AgentTaskCheckpointState? state;
    for (final candidate in AgentTaskCheckpointState.values) {
      if (candidate.name == stateName) {
        state = candidate;
        break;
      }
    }
    if (state == null) {
      throw const FormatException('Unknown checkpoint state.');
    }
    final record = AgentTaskCheckpointRecord(
      taskId: _requiredString(json, 'task_id'),
      goal: _requiredString(json, 'goal'),
      sessionId: _requiredString(json, 'session_id'),
      checkpointJson: _requiredString(json, 'checkpoint'),
      state: state,
      savedAtUtc: _requiredString(json, 'saved_at_utc'),
      toolCallId: json['tool_call_id'] as String?,
      toolName: json['tool_name'] as String?,
      toolResult: json['tool_result'] as String?,
    );
    _validateRecord(record);
    return record;
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid $key.');
  return value;
}

/// Tiny port to make persistence behavior unit-testable without platform
/// channels. Production uses the OS-backed encrypted secure-storage plugin.
abstract interface class SecureTextStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class _FlutterSecureTextStore implements SecureTextStore {
  _FlutterSecureTextStore() : _storage = FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// Stores at most eight checkpoints as one encrypted secure-storage value.
///
/// The checkpoint contains user conversation context and model output, so it is
/// not written to SharedPreferences or a plaintext JSON file. The store does
/// not persist tool arguments separately: the complete checkpoint is protected
/// by the OS-backed secure store and revalidated by Rust on resume.
class AgentTaskCheckpointStore {
  AgentTaskCheckpointStore({SecureTextStore? secureStore})
    : _secureStore = secureStore ?? _FlutterSecureTextStore();

  static const storageKey = 'leo.agent_task.checkpoints.v1';
  static const maxRecords = 8;
  static const maxCheckpointBytes = 256 * 1024;
  static const maxStoredBytes = 640 * 1024;
  static const maxResultCharacters = 12000;
  static const retention = Duration(days: 7);

  final SecureTextStore _secureStore;

  Future<List<AgentTaskCheckpointRecord>> loadPending() async {
    final records = await _readRecords();
    final cutoff = DateTime.now().toUtc().subtract(retention);
    final fresh = records
        .where((record) {
          final savedAt = DateTime.tryParse(record.savedAtUtc)?.toUtc();
          return savedAt != null && savedAt.isAfter(cutoff);
        })
        .toList(growable: false);
    if (fresh.length != records.length) await _writeRecords(fresh);
    return fresh;
  }

  Future<AgentTaskCheckpointRecord?> get(String taskId) async {
    final records = await loadPending();
    for (final record in records) {
      if (record.taskId == taskId) return record;
    }
    return null;
  }

  /// Called for each Rust progress event. A later event replaces the older
  /// checkpoint for the same task. Persistence failure is surfaced to the
  /// caller so no tool proposal is shown without a durable recovery point.
  Future<void> saveCheckpoint({
    required String checkpointJson,
    required String sessionId,
  }) async {
    final decoded = jsonDecode(checkpointJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Task checkpoint must be a JSON object.');
    }
    _validateCheckpoint(decoded, checkpointJson);
    final stateName = decoded['state'];
    final state = switch (stateName) {
      'running' => AgentTaskCheckpointState.running,
      'awaiting_action' => AgentTaskCheckpointState.awaitingAction,
      _ => throw const FormatException('Invalid native checkpoint state.'),
    };
    final proposal = decoded['proposal'];
    final taskId = decoded['task_id'];
    final goal = decoded['goal'];
    if (taskId is! String || goal is! String) {
      throw const FormatException('Native checkpoint identity is invalid.');
    }
    final record = AgentTaskCheckpointRecord(
      taskId: taskId,
      goal: goal,
      sessionId: sessionId,
      checkpointJson: checkpointJson,
      state: state,
      savedAtUtc: DateTime.now().toUtc().toIso8601String(),
      toolCallId: proposal is Map<String, dynamic>
          ? proposal['call_id'] as String?
          : null,
      toolName: proposal is Map<String, dynamic>
          ? proposal['tool_name'] as String?
          : null,
    );
    _validateRecord(record);
    final records = await loadPending()
      ..removeWhere((item) => item.taskId == record.taskId);
    records.insert(0, record);
    await _writeRecords(records.take(maxRecords).toList(growable: false));
  }

  /// Persists the successful handoff result before invoking Rust to continue.
  /// A crash after this write can safely repeat local reasoning, never the tool.
  Future<AgentTaskCheckpointRecord> markActionSucceeded({
    required String taskId,
    required String toolCallId,
    required String toolName,
    required String toolResult,
  }) async {
    if (toolResult.trim().isEmpty || toolResult.length > maxResultCharacters) {
      throw const FormatException('Tool result exceeds the checkpoint limit.');
    }
    final records = await loadPending();
    final index = records.indexWhere((item) => item.taskId == taskId);
    if (index < 0)
      throw StateError('No durable checkpoint exists for this task.');
    final current = records[index];
    if (current.state != AgentTaskCheckpointState.awaitingAction ||
        current.toolCallId != toolCallId ||
        current.toolName != toolName) {
      throw StateError('Tool handoff does not match the durable checkpoint.');
    }
    final updated = AgentTaskCheckpointRecord(
      taskId: current.taskId,
      goal: current.goal,
      sessionId: current.sessionId,
      checkpointJson: current.checkpointJson,
      state: AgentTaskCheckpointState.readyToResume,
      savedAtUtc: DateTime.now().toUtc().toIso8601String(),
      toolCallId: toolCallId,
      toolName: toolName,
      toolResult: toolResult,
    );
    _validateRecord(updated);
    records[index] = updated;
    await _writeRecords(records);
    return updated;
  }

  /// User-mediated recovery for the ambiguous crash window where the OS
  /// handoff may have happened but its result was not durably recorded.
  Future<AgentTaskCheckpointRecord> confirmInterruptedAction({
    required String taskId,
    required String confirmationResult,
  }) async {
    final records = await loadPending();
    final index = records.indexWhere((item) => item.taskId == taskId);
    if (index < 0)
      throw StateError('No durable checkpoint exists for this task.');
    final current = records[index];
    if (current.state != AgentTaskCheckpointState.awaitingAction ||
        current.toolCallId == null ||
        current.toolName == null) {
      throw StateError('No interrupted action needs confirmation.');
    }
    final updated = AgentTaskCheckpointRecord(
      taskId: current.taskId,
      goal: current.goal,
      sessionId: current.sessionId,
      checkpointJson: current.checkpointJson,
      state: AgentTaskCheckpointState.readyToResume,
      savedAtUtc: DateTime.now().toUtc().toIso8601String(),
      toolCallId: current.toolCallId,
      toolName: current.toolName,
      toolResult: confirmationResult,
    );
    _validateRecord(updated);
    records[index] = updated;
    await _writeRecords(records);
    return updated;
  }

  Future<void> remove(String taskId) async {
    final records = await loadPending()
      ..removeWhere((record) => record.taskId == taskId);
    await _writeRecords(records);
  }

  Future<List<AgentTaskCheckpointRecord>> _readRecords() async {
    final raw = await _secureStore.read(key: storageKey);
    if (raw == null || raw.isEmpty) return <AgentTaskCheckpointRecord>[];
    if (utf8.encode(raw).length > maxStoredBytes) {
      throw const FormatException('Secure task checkpoint store is too large.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.length > maxRecords) {
      throw const FormatException('Secure task checkpoint index is invalid.');
    }
    final records = decoded
        .map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Task checkpoint record is invalid.');
          }
          return AgentTaskCheckpointRecord.fromJson(item);
        })
        .toList(growable: true);
    final ids = <String>{};
    for (final record in records) {
      if (!ids.add(record.taskId)) {
        throw const FormatException(
          'Duplicate task checkpoint IDs were found.',
        );
      }
    }
    return records;
  }

  Future<void> _writeRecords(List<AgentTaskCheckpointRecord> records) async {
    if (records.length > maxRecords) {
      throw const FormatException('Too many pending task checkpoints.');
    }
    final ids = <String>{};
    for (final record in records) {
      _validateRecord(record);
      if (!ids.add(record.taskId)) {
        throw const FormatException(
          'Duplicate task checkpoint IDs were found.',
        );
      }
    }
    final encoded = jsonEncode(
      records.map((record) => record.toJson()).toList(),
    );
    final bytes = utf8.encode(encoded).length;
    if (bytes > maxStoredBytes) {
      throw const FormatException(
        'Pending tasks exceed the secure storage budget.',
      );
    }
    if (records.isEmpty) {
      await _secureStore.delete(key: storageKey);
    } else {
      await _secureStore.write(key: storageKey, value: encoded);
    }
  }

  static void _validateCheckpoint(Map<String, dynamic> decoded, String raw) {
    const expected = {
      'version',
      'task_id',
      'goal',
      'conversation_context',
      'state',
      'plan',
      'step_results',
      'proposal',
      'completed_handoffs',
    };
    if (decoded.keys.toSet().difference(expected).isNotEmpty ||
        decoded.keys.toSet().length != expected.length ||
        decoded['version'] != 1 ||
        utf8.encode(raw).length > maxCheckpointBytes) {
      throw const FormatException('Native checkpoint envelope is unsupported.');
    }
    final taskId = decoded['task_id'];
    final goal = decoded['goal'];
    final context = decoded['conversation_context'];
    if (taskId is! String ||
        !RegExp(r'^[A-Za-z0-9_.-]{1,96}$').hasMatch(taskId) ||
        goal is! String ||
        goal.trim().isEmpty ||
        goal.length > 6000 ||
        context is! String ||
        context.length > 12000 ||
        decoded['completed_handoffs'] is! int ||
        (decoded['completed_handoffs'] as int) < 0 ||
        (decoded['completed_handoffs'] as int) > 3 ||
        decoded['plan'] is! Map<String, dynamic> ||
        decoded['step_results'] is! List) {
      throw const FormatException('Native checkpoint values are invalid.');
    }
    final state = decoded['state'];
    final proposal = decoded['proposal'];
    if (state == 'running' && proposal != null) {
      throw const FormatException(
        'A running checkpoint cannot contain a pending action.',
      );
    }
    if (state == 'awaiting_action' && proposal is! Map<String, dynamic>) {
      throw const FormatException(
        'An action checkpoint is missing its proposal.',
      );
    }
    if (state != 'running' && state != 'awaiting_action') {
      throw const FormatException('Unknown native checkpoint state.');
    }
  }

  static void _validateRecord(AgentTaskCheckpointRecord record) {
    if (!RegExp(r'^[A-Za-z0-9_.-]{1,96}$').hasMatch(record.taskId) ||
        record.goal.trim().isEmpty ||
        record.goal.length > 6000 ||
        !RegExp(r'^[A-Za-z0-9_.-]{1,128}$').hasMatch(record.sessionId) ||
        utf8.encode(record.checkpointJson).length > maxCheckpointBytes ||
        (record.toolResult?.length ?? 0) > maxResultCharacters) {
      throw const FormatException(
        'Task checkpoint record exceeds a safety limit.',
      );
    }
    final savedAt = DateTime.tryParse(record.savedAtUtc);
    if (savedAt == null || !savedAt.isUtc) {
      throw const FormatException('Task checkpoint timestamp must be UTC.');
    }
    if (record.toolCallId != null &&
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(record.toolCallId!)) {
      throw const FormatException('Task checkpoint tool-call ID is invalid.');
    }
    if (record.toolName != null &&
        !const {
          'files.read_selected',
          'workspace.write_file',
          'email.compose',
          'phone.dial',
          'messages.compose',
          'web.open',
          'app.launch',
        }.contains(record.toolName)) {
      throw const FormatException('Task checkpoint tool name is invalid.');
    }
    final decoded = jsonDecode(record.checkpointJson);
    if (decoded is! Map<String, dynamic> ||
        decoded['task_id'] != record.taskId ||
        decoded['goal'] != record.goal ||
        (decoded['state'] != 'running' &&
            decoded['state'] != 'awaiting_action')) {
      throw const FormatException(
        'Task checkpoint record does not match its payload.',
      );
    }
    final proposal = decoded['proposal'];
    if (record.state == AgentTaskCheckpointState.running &&
        (decoded['state'] != 'running' ||
            proposal != null ||
            record.toolCallId != null ||
            record.toolName != null ||
            record.toolResult != null)) {
      throw const FormatException(
        'Running checkpoint contains an external action.',
      );
    }
    if (record.state != AgentTaskCheckpointState.running) {
      if (decoded['state'] != 'awaiting_action' ||
          proposal is! Map<String, dynamic> ||
          proposal['call_id'] != record.toolCallId ||
          proposal['tool_name'] != record.toolName) {
        throw const FormatException(
          'Action checkpoint metadata does not match its proposal.',
        );
      }
    }
    if (record.state == AgentTaskCheckpointState.awaitingAction &&
        record.toolResult != null) {
      throw const FormatException(
        'An unconfirmed action cannot contain a result.',
      );
    }
    if (record.toolResult != null && record.toolResult!.trim().isEmpty) {
      throw const FormatException('A saved action result cannot be empty.');
    }
    if (record.state == AgentTaskCheckpointState.readyToResume &&
        (record.toolCallId == null ||
            record.toolName == null ||
            record.toolResult == null ||
            record.toolResult!.trim().isEmpty)) {
      throw const FormatException('Ready-to-resume checkpoint is incomplete.');
    }
    if (record.state == AgentTaskCheckpointState.awaitingAction &&
        (record.toolCallId == null || record.toolName == null)) {
      throw const FormatException('Awaiting-action checkpoint is incomplete.');
    }
  }
}
