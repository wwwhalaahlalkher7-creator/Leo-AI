# Flutter ↔ native runtime channel contract

**Status:** Alpha v0.2.0 integration boundary; native handlers are pending.

The Flutter chat UI does not call llama.cpp or Hermes directly. It communicates
through a narrow runtime boundary so the Android and Windows implementations
can be replaced without rewriting the conversation UI.

## Method channel

Channel name: `leo.ai/runtime`

### `startGeneration`

Input map:

```json
{
  "requestId": "request-...",
  "conversationId": "chat-...",
  "messages": [
    {"role": "user", "content": "..."}
  ],
  "maxNewTokens": 1024,
  "temperature": 0.7
}
```

The native adapter validates the request, checks model/runtime availability,
then starts generation. It must not silently fall back to a cloud service.

### `cancelGeneration`

Input map: `{"requestId": "request-..."}`.

Cancellation is scoped to the request ID; it must not unload a model or cancel
another conversation.

## Event channel

Channel name: `leo.ai/runtime/events`.

The stream is subscribed with `{"requestId": "request-..."}` before
`startGeneration` is invoked. Every event includes a `type` and may include
`text`:

- `started`
- `delta`
- `completed`
- `cancelled`
- `failed`

`delta` contains incremental text. `completed.text`, when non-empty, is the complete final answer and replaces the accumulated deltas. When it is empty, the Flutter client keeps the deltas already received.
`failed` should contain a user-safe message; sensitive native diagnostics belong
in local logs, not the transcript.

## Error behavior

- Missing platform handler: report that the local runtime is not linked yet.
- No model loaded: offer model import/load UI in the future; never fabricate an
  assistant answer.
- Unsupported platform/runtime: state that the capability is unavailable.
- Offline operation: never route to a remote provider unless the user has
  explicitly enabled an optional remote runtime.
