import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'chat_models.dart';

/// Local-only conversation storage. No account, server or network is required.
class ChatRepository {
  ChatRepository(this._preferences);

  static const _storageKey = 'leo.chat.sessions.v1';
  static const _maxSessions = 40;
  final SharedPreferences _preferences;

  static Future<ChatRepository> open() async =>
      ChatRepository(await SharedPreferences.getInstance());

  List<ChatSession> loadSessions() {
    final raw = _preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw) as List<Object?>;
      final sessions = decoded
          .map((item) => ChatSession.fromJson(item! as Map<String, Object?>))
          .toList();
      sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return sessions;
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveSession(ChatSession session) async {
    final sessions = List<ChatSession>.of(loadSessions());
    final existingIndex = sessions.indexWhere((item) => item.id == session.id);
    if (existingIndex >= 0) {
      sessions[existingIndex] = session;
    } else {
      sessions.add(session);
    }
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (sessions.length > _maxSessions) {
      sessions.removeRange(_maxSessions, sessions.length);
    }
    await _preferences.setString(_storageKey, ChatSession.encodeList(sessions));
  }

  Future<void> deleteSession(String sessionId) async {
    final sessions = List<ChatSession>.of(loadSessions())
      ..removeWhere((session) => session.id == sessionId);
    await _preferences.setString(_storageKey, ChatSession.encodeList(sessions));
  }
}
