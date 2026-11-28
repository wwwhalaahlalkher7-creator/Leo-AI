import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:leo_app/core/chat/chat_models.dart';
import 'package:leo_app/core/chat/chat_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('chat sessions survive repository reconstruction', () async {
    final firstRepository = await ChatRepository.open();
    final now = DateTime.utc(2026, 11, 15);
    final session = ChatSession(
      id: 'chat-1',
      title: 'محادثة تجريبية',
      createdAt: now,
      updatedAt: now,
      messages: [
        ChatMessage(
          id: 'message-1',
          role: ChatMessageRole.user,
          content: 'مرحبا Leo',
          createdAt: now,
        ),
      ],
    );

    await firstRepository.saveSession(session);
    final secondRepository = await ChatRepository.open();
    final restored = secondRepository.loadSessions();

    expect(restored, hasLength(1));
    expect(restored.single.title, 'محادثة تجريبية');
    expect(restored.single.messages.single.content, 'مرحبا Leo');
  });

  test('deleting a session removes it from local history', () async {
    final repository = await ChatRepository.open();
    final now = DateTime.now();
    await repository.saveSession(
      ChatSession(
        id: 'chat-to-delete',
        title: 'حذف',
        createdAt: now,
        updatedAt: now,
        messages: const [],
      ),
    );

    await repository.deleteSession('chat-to-delete');

    expect(repository.loadSessions(), isEmpty);
  });
}
