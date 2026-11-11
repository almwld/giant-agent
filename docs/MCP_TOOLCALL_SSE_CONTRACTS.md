# MCP, tool-call identity and OpenRouter streaming

This branch integrates MCP as a real remote tool transport while preserving the
single existing agent/model execution path. It does not create a second local
inference runtime or Dart isolate.

## MCP transport and discovery

- `McpClient.instance` is the process-wide Streamable HTTP MCP client.
- Server definitions and optional bearer credentials are persisted in
  `FlutterSecureStorage`; credentials are never emitted to timeline events.
- HTTPS is required. Plain HTTP is accepted only for localhost/loopback.
- The client performs `initialize`, `notifications/initialized`,
  paginated `tools/list`, and `tools/call` JSON-RPC requests.
- It negotiates the MCP protocol version returned by the server, retains
  `Mcp-Session-Id`, sends `MCP-Protocol-Version`, and accepts JSON or SSE
  responses from Streamable HTTP endpoints.
- The agent prompt receives discovered tool names, descriptions, input schemas
  and annotations. The model invokes them through the single `mcp_call` gateway;
  runtime dispatch rejects tools not present in the latest discovery result.
- Only tools explicitly annotated `readOnlyHint: true` run without confirmation.
  All other remote tools require the app's `requestMcpApproval` callback; when
  no approval handler is configured, the call is denied by default.
- The API facade is `AgentService.addMcpServer`, `mcpServers`,
  `refreshMcpTools`, and `removeMcpServer`. This commit exposes the API;
  a dedicated settings screen and OAuth browser flow remain separate UI work.

## MCP result envelope

`McpToolResult` preserves ordered content blocks, text, image/audio/resource
payload fields, unknown extension fields, `isError`, `structuredContent`,
and `_meta`. Resource links remain structured rather than being flattened
into text. A text preview is a display projection, never the canonical result.
The evaluator verifies receipt of a typed remote result, not the remote
business side effect; that distinction is deliberate.

## Tool-call identity and interruption

`ToolCallRegistry` tracks each invocation by an independent `tool_call_id`,
separate from request, task and planner step identifiers. The ID is carried
through lifecycle events and timeline serialization. Cancellation targets
only that invocation and is classified as interrupted in the durable request
journal. Cancellation is cooperative: a remote/native side effect already
executing cannot be forcibly rolled back unless its transport exposes a
cancellation primitive.

## OpenRouter SSE

`ServerSentEventParser` incrementally parses SSE framing, multiline data,
comments, event names, IDs, retry hints and split UTF-8 chunks. The existing
OpenRouter provider sends `stream: true`, consumes the parser and publishes
token deltas through the existing `AgentEventBus`. The local provider remains
the existing singleton `ModelService` / `LlamaService` path.

## Verification boundary

The contract tests cover MCP result preservation, server/tool metadata
round-tripping, SSE framing and UTF-8 boundaries, and independent tool-call
cancellation. A passing CI run and runtime tests against a real MCP server are
still required before calling this production-ready. Standard input/output MCP transports and OAuth authorization are not
implemented in this mobile HTTP client. A dedicated server-management screen
and an app-wired approval dialog for non-read-only remote tools are also still
required for a complete end-user flow.
