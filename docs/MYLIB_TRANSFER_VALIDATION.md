# Mylib transfer validation snapshot

Validation branch cut from `feat/kimi-subagent-orchestration` after the Kimi dynamic lifecycle and GPT-style local message-state changes.

## Included in the base branch

- MCP Streamable HTTP transport and typed content/resource results.
- OpenRouter incremental SSE parsing and tool-call-scoped cancellation.
- Durable parent/child request lifecycle with create/spawn separation.
- Model-facing `create_subagent`, `spawn_subagent`, `check_subagent_status`, `list_subagents`, and `delete_subagent`.
- Inline dynamic child execution under the active parent; reentrant shared-runtime lease prevents parent-queue, JNI-runtime and tool-FIFO deadlocks.
- Parent-scoped child ownership, dependency gating, soft dismissal, immutable child journal, tool_call_id propagation and targeted native cancellation.
- Worker metadata and lifecycle-boundary progress snapshots.
- Assistant message persistence with streaming/complete/interrupted/failed states, batched SSE delta writes, restart reconciliation and conversation-scoped deletion.

## Validation scope

The APK workflow intentionally runs `flutter analyze --no-pub` and builds APK ABIs; it does not run the Dart test suite. Test source files remain in the repository. This validation PR exists to make the current integration branch pass its configured analyzer/build gate without changing application behavior.

## Explicitly not claimed complete

- Real-device nested local inference and cancellation stress test.
- Real MCP server interoperability test.
- Kimi `send_message`, `wait_for_message`, `ask_user`, and `update_goal` handler parity; Mylib exposes operation names but not verified handler bodies or argument schemas.
- GPT remote message IDs, server-side synchronization, provider reasoning metadata and prepared markdown/entity payload parity.
