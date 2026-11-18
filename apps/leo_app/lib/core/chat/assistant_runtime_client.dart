import 'dart:async';

import '../../src/rust/api/simple.dart' as rust_api;
import '../../src/rust/rust_bridge_initializer.dart';

class RuntimeInputMessage {
  const RuntimeInputMessage({required this.role, required this.content});

  final String role;
  final String content;
}

class RuntimeRequest {
  const RuntimeRequest({
    required this.requestId,
    required this.conversationId,
    required this.messages,
    this.maxNewTokens = 1024,
    this.temperature = 0.7,
  });

  final String requestId;
  final String conversationId;
  final List<RuntimeInputMessage> messages;
  final int maxNewTokens;
  final double temperature;
}

enum RuntimeEventType { started, delta, completed, cancelled, failed }

class RuntimeEvent {
  const RuntimeEvent(this.type, {this.text = ''});

  final RuntimeEventType type;
  final String text;
}

abstract interface class AssistantRuntimeClient {
  Stream<RuntimeEvent> generate(RuntimeRequest request);
  Future<void> cancel(String requestId);
}

/// Real, typed Flutter <-> Rust bridge. There is deliberately no mock answer
/// or remote fallback: errors from an unavailable native backend stay visible.
class FlutterRustBridgeAssistantRuntimeClient
    implements AssistantRuntimeClient {
  @override
  Stream<RuntimeEvent> generate(RuntimeRequest request) async* {
    try {
      await RustBridgeInitializer.ensureInitialized();
      final nativeRequest = rust_api.AssistantRequestDto(
        requestId: request.requestId,
        conversationId: request.conversationId,
        messages: request.messages
            .map((message) => rust_api.ChatMessageInputDto(
                  role: message.role,
                  content: message.content,
                ))
            .toList(growable: false),
        maxNewTokens: request.maxNewTokens,
        temperature: request.temperature,
      );

      await for (final event in rust_api.generateText(request: nativeRequest)) {
        final type = switch (event.kind) {
          'started' => RuntimeEventType.started,
          'delta' => RuntimeEventType.delta,
          'completed' => RuntimeEventType.completed,
          'cancelled' => RuntimeEventType.cancelled,
          _ => RuntimeEventType.failed,
        };
        yield RuntimeEvent(type, text: event.text);
      }
    } catch (error) {
      yield RuntimeEvent(
        RuntimeEventType.failed,
        text: _friendlyError(error),
      );
    }
  }

  @override
  Future<void> cancel(String requestId) async {
    try {
      await RustBridgeInitializer.ensureInitialized();
      await rust_api.cancelGeneration(requestId: requestId);
    } catch (_) {
      // Cancellation is best effort; the native runtime also bounds work.
    }
  }

  String _friendlyError(Object error) {
    final details = error.toString();
    if (details.contains('libleo_llama_backend') ||
        details.contains('leo_llama_backend')) {
      return 'تعذر العثور على محرك llama.cpp المحلي. تحقق من حزمة المحرك الخاصة بجهازك.';
    }
    return 'تعذر تشغيل محرك Leo المحلي: $details';
  }
}
