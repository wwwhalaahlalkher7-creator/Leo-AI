import 'dart:convert';

enum ChatMessageRole { user, assistant, notice }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final ChatMessageRole role;
  final String content;
  final DateTime createdAt;

  ChatMessage copyWith({String? content}) => ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, Object?> json) => ChatMessage(
        id: json['id']! as String,
        role: ChatMessageRole.values.byName(json['role']! as String),
        content: json['content']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String).toLocal(),
      );
}

class ChatSession {
  const ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  ChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) =>
      ChatSession(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        messages: messages ?? this.messages,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'messages': messages.map((message) => message.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, Object?> json) => ChatSession(
        id: json['id']! as String,
        title: json['title']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String).toLocal(),
        updatedAt: DateTime.parse(json['updatedAt']! as String).toLocal(),
        messages: (json['messages']! as List<Object?>)
            .map((item) => ChatMessage.fromJson(item! as Map<String, Object?>))
            .toList(growable: false),
      );

  static String encodeList(List<ChatSession> sessions) => jsonEncode(
        sessions.map((session) => session.toJson()).toList(),
      );
}

String createLocalId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';
