# Python tool-call cancellation

One-shot Python and conversation-scoped IPython now carry the exact
`tool_call_id` to the Android bridge.

- Dart polls only that invocation's cancellation predicate and sends
  `cancelPythonExecution(invocationId)` when it is cancelled.
- Android tracks active and cancelled Python invocation IDs independently.
- Queued work can be cancelled before dispatch; running sandbox work is marked
  interrupted and its result is discarded when the bounded Python execution
  returns. The sandbox's existing 2.5-second execution limit bounds this
  cooperative cancellation latency.
- Cancellation of Python does not cancel another Python session or the shared
  llama.cpp model context.

No tests, analyzer, CI workflow, or build were run.
