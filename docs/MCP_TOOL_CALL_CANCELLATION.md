# MCP tool-call cancellation

MCP tool discovery and approval now remain within the exact tool invocation's
cancellation boundary.

- `findTool` accepts the invocation cancellation predicate and propagates it
  through `tools/list` when discovery is required.
- The approval wait races the pending user decision against cancellation.
- If cancelled, the remote `tools/call` request is never dispatched.
- The actual JSON-RPC HTTP/SSE operation continues to receive the same
  invocation-scoped predicate and closes its own request stream when cancelled.

No tests, analyzer, CI workflow, or build were run.
