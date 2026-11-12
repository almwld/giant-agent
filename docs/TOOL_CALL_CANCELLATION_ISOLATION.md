# Tool-call cancellation isolation

Cancellation is scoped to the independent `tool_call_id` registry entry.
Cancelling a tool no longer calls the shared llama.cpp cancellation API, which
could interrupt unrelated inference using the process-wide local model.

- MCP requests already receive the exact invocation's cancellation predicate
  and close their own HTTP client/stream.
- Gain PTY commands receive the same predicate and interrupt/stop only their
  active PTY command.
- Terminal approval now races the pending approval result against the exact
  invocation's cancellation signal. A cancelled approval never dispatches the
  command.
- Model generation cancellation remains a separate request-level operation.

No tests, analyzer, CI workflow, or build were run.
