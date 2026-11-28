import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/core/tools/tool_call_protocol.dart';

void main() {
  group('Leo tool-call protocol', () {
    test('parses one exact, allowlisted HTTP link request', () {
      final call = LeoToolCall.parseAssistantResponse(
        '<leo_tool_call>{"version":1,"id":"call_1","name":"web.open","arguments":{"url":"https://example.com"}}</leo_tool_call>',
      );

      expect(call.name, 'web.open');
      expect(call.arguments['url'], 'https://example.com');
      expect(call.displaySummary, 'فتح رابط في المتصفح');
    });

    test('rejects prose outside a tool call block', () {
      expect(
        () => LeoToolCall.parseAssistantResponse(
          'سأفتح الرابط. <leo_tool_call>{"version":1,"id":"x","name":"web.open","arguments":{"url":"https://example.com"}}</leo_tool_call>',
        ),
        throwsFormatException,
      );
    });

    test('rejects unknown tool names and unknown argument keys', () {
      expect(
        () => LeoToolCall.parseAssistantResponse(
          '<leo_tool_call>{"version":1,"id":"x","name":"process.run","arguments":{"command":"whoami"}}</leo_tool_call>',
        ),
        throwsFormatException,
      );
      expect(
        () => LeoToolCall.parseAssistantResponse(
          '<leo_tool_call>{"version":1,"id":"x","name":"phone.dial","arguments":{"number":"12345","direct":true}}</leo_tool_call>',
        ),
        throwsFormatException,
      );
    });

    test('rejects non-string values, invalid email and unsafe URL schemes', () {
      expect(
        () => LeoToolCall.parseAssistantResponse(
          '<leo_tool_call>{"version":1,"id":"x","name":"web.open","arguments":{"url":"javascript:alert(1)"}}</leo_tool_call>',
        ),
        throwsFormatException,
      );
      expect(
        () => LeoToolCall.parseAssistantResponse(
          '<leo_tool_call>{"version":1,"id":"x","name":"email.compose","arguments":{"to":"bad-address","subject":"Hi","body":"Hello"}}</leo_tool_call>',
        ),
        throwsFormatException,
      );
      expect(
        () => LeoToolCall.parseAssistantResponse(
          '<leo_tool_call>{"version":1,"id":"x","name":"phone.dial","arguments":{"number":12345}}</leo_tool_call>',
        ),
        throwsFormatException,
      );
    });

    test('rejects repeated or oversized payloads', () {
      const call =
          '<leo_tool_call>{"version":1,"id":"x","name":"contacts.list","arguments":{}}</leo_tool_call>';
      expect(
        () => LeoToolCall.parseAssistantResponse('$call$call'),
        throwsFormatException,
      );
      expect(
        () => LeoToolCall.parseAssistantResponse(
          '<leo_tool_call>${List.filled(LeoToolCall.maxPayloadBytes + 1, 'a').join()}</leo_tool_call>',
        ),
        throwsFormatException,
      );
    });

    test('enforces a separate role allowlist for agent proposals', () {
      final email = LeoToolCall.parseAssistantResponse(
        '<leo_tool_call>{"version":1,"id":"call_1","name":"email.compose","arguments":{"to":"a@example.com","subject":"Hi","body":"Hello"}}</leo_tool_call>',
      );
      final readFile = LeoToolCall.parseAssistantResponse(
        '<leo_tool_call>{"version":1,"id":"call_2","name":"files.read_selected","arguments":{}}</leo_tool_call>',
      );
      final launch = LeoToolCall.parseAssistantResponse(
        '<leo_tool_call>{"version":1,"id":"call_3","name":"app.launch","arguments":{"target":"calculator"}}</leo_tool_call>',
      );

      expect(email.isAllowedFromAgent('communications'), isTrue);
      expect(email.isAllowedFromAgent('device_operator'), isFalse);
      expect(readFile.isAllowedFromAgent('file_operator'), isTrue);
      expect(readFile.isAllowedFromAgent('communications'), isFalse);
      expect(launch.isAllowedFromAgent('device_operator'), isTrue);
      expect(launch.isAllowedFromAgent('file_operator'), isFalse);
      expect(email.isAllowedFromAgent('planner'), isFalse);
    });

    test(
      'parses a bounded workspace write and scopes it to the file operator',
      () {
        final call = LeoToolCall.parseAssistantResponse(
          '<leo_tool_call>{"version":1,"id":"write_1","name":"workspace.write_file","arguments":{"relative_path":"notes.md","content":"# Notes\\nHello"}}</leo_tool_call>',
        );
        expect(call.name, 'workspace.write_file');
        expect(call.isAllowedFromAgent('file_operator'), isTrue);
        expect(call.isAllowedFromAgent('device_operator'), isFalse);
        expect(call.arguments['relative_path'], 'notes.md');
        expect(call.arguments['content'], '# Notes\nHello');
      },
    );

    test('rejects unsafe workspace paths and oversized text', () {
      expect(
        () => LeoToolCall.parseAssistantResponse(
          '<leo_tool_call>{"version":1,"id":"write_2","name":"workspace.write_file","arguments":{"relative_path":"../escape.txt","content":"x"}}</leo_tool_call>',
        ),
        throwsFormatException,
      );
      final huge = 'x' * 33000;
      expect(
        () => LeoToolCall.parseAssistantResponse(
          '<leo_tool_call>{"version":1,"id":"write_3","name":"workspace.write_file","arguments":{"relative_path":"notes.txt","content":"$huge"}}</leo_tool_call>',
        ),
        throwsFormatException,
      );
    });

    test(
      'does not treat a partial start marker as visible assistant prose',
      () {
        expect(LeoToolCall.mayBeToolCallPrefix('<leo_tool_'), isTrue);
        expect(LeoToolCall.mayBeToolCallPrefix('<leo_tool_call>'), isTrue);
        expect(LeoToolCall.mayBeToolCallPrefix('مرحباً'), isFalse);
      },
    );
  });
}
