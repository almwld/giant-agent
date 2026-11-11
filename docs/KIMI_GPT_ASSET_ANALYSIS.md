# Kimi + GPT asset analysis and Giant Agent integration

## Scope and provenance

Analysis source: `almwld/Mylib`, main commit `8103497284f11a3df81eda1d517aebf0a8929916`.

The repository contains two source archives and the Kimi deep-scan report:
- `Libkimi.zip`: SHA-256 `ee4fa0462ce5811f3920de7b29aa9a6c3082fcf1ba444d47b4f33a29ad109f96`; 868 extracted files across 59 directories.
- `Libg.zip` (GPT/ChatGPT asset set): SHA-256 `da0cca97f2bd49d0811d0a02c59f4a53d3b02e96f0da92656e6d5111adf2cb8d`; 247 extracted files across 145 directories, including 70 Zstandard-compressed `.valdimodule` modules. The modules were decompressed for symbol/source-map string inspection; they are compiled application modules, not original editable source.
- `kimi_deep_scan_contents/REPORT.txt`, `JSON_KEYS.txt`, `NETWORK_URLS.txt`, and `TOP_PACKAGES.txt`.

The scan is a reverse-engineering aid, not a complete server-side implementation disclosure. Decompiled package names and protocol descriptors are stronger evidence than keyword counts. No proprietary Kimi or OpenAI implementation code is copied into Giant Agent; this document records public-facing architectural patterns and the independent implementation added here.

## Kimi evidence

### Delegated-agent lifecycle

The deep-scan report identifies protocol descriptors and operation names:
- `ToolMetaCreateSubagent`
- `ToolMetaSubagent`
- `ToolSubagentWorker`
- `SubagentStatusEvent`
- `CREATE_SUBAGENT`
- `SPAWN_SUBAGENT`
- `DELETE_SUBAGENT`
- `CHECK_SUBAGENT_STATUS`

The status event exposes a chat identifier, agent identifier, and status. The subagent metadata exposes `agentId`, `agentIndex`, `agentIcon`, worker name/icon URL/motto. This supports a distinct lifecycle: define child -> persist it -> spawn it -> observe status -> dismiss/delete it. It does not prove Kimi's server-side scheduling or retry internals.

### Tool-call identity, interruption, and MCP result shape

The scan also identifies:
- `ToolBlock(toolCallId, name, args)`
- `GetToolBlockRequest(chatId, toolCallId)`
- `InterruptRequest(toolCallId)`
- MCP SDK `CallToolResult(content, isError, structuredContent, meta)`
- `ToolResultResourceLink(url, title, mimeType)`

Architectural implications:
- Tool calls need stable per-call identity separate from the parent request.
- Interruption should target the specific call where the runtime supports safe cancellation.
- Tool results may contain multiple content blocks, structured data, metadata, and resource links; a single flattened string is lossy.
- Tool errors must remain explicit and must not be mistaken for successful output.

The archive also contains dedicated visual resources for create-subagent, MCP, memory, web, search, code, files, tasks, and other tool activities. These establish UI categories, not the implementation semantics of those tools.

## GPT / ChatGPT evidence

### Conversation state and persistence

Decompressed module `chatgpt_conversation.valdimodule` exposes module/source names including:
- `ChatGPTConversationState`
- `ChatGPTConversationPersistence`
- `ChatGPTConversationModels`
- `createAccountScopedChatGPTConversationPersistence`
- `createChatGPTConversationSnapshot`

The message state model distinguishes `Streaming`, `Complete`, `Interrupted`, and `Failed`; state transitions include append content, prepared Markdown, reasoning metadata, entity references, remote message identifiers, complete, fail, and finish-interrupted. Persistence validates account identity and a versioned conversation snapshot. This is a useful state-machine pattern: partial output remains partial after interruption and is not promoted to success.

### Streaming, workers, cancellation

The GPT modules expose a deliberately separated pipeline:
- `ChatGPTStreamingWorkerRuntime`
- `ChatGPTStreamingWorkerClient`
- `ChatGPTStreamingResponseProcessor`
- `ChatGPTStreamingProtocol`
- `ChatGPTStreamingContracts`
- `ChatGPTConversationEventDecoder`
- `ServerSentEventParser`, `ServerSentEventClient`, and `StreamingHTTPClient`

The SSE implementation exposes `lastEventId`, reconnection timing, event parsing, and cancellation. The worker bridge expects asynchronous Promise-based operations and has explicit cancellation handling. These are transport/runtime patterns, not evidence that every model operation is executed in a worker.

### Reasoning and activity presentation

The reasoning module distinguishes reasoning status, item kind, active kind, tool icons, and a timeline-like presentation. The visible activity surface can show tool/status transitions while the private reasoning payload remains separate. Giant Agent must continue to expose factual events and results, never private chain-of-thought.

### Tool and file service patterns

The services modules expose authenticated request clients, request cancellation, active-request tracking, bounded attachment validation, upload creation/content transfer/finalization, and explicit response validation. The Library and Global Search modules separate API, repository, models, and screen state. These support separation of transport, state, and UI, but do not justify copying provider endpoints or proprietary API contracts.

## Existing Giant Agent coverage before this integration

The current branch already contains:
- Durable SQLite parent requests, task snapshots, append-only event journals, and output artifact records.
- Subagent graph validation, dependency result passing, bounded cloud concurrency, and an exclusive workspace lease for coder workers.
- Local GGUF inference serialized through the single shared `ModelService` / `LlamaService` runtime.
- Child cancellation, parent cancellation, process-restart reconciliation, explicit resume authorization, and no automatic replay of side effects.
- Output synthesis and artifact verification before the parent request can be marked completed.
- Timeline correlation through request, task, agent role, step, and event IDs.

Do not create a second model/JNI runtime or a second background Dart isolate to imitate a competitor's implementation.

## Gaps selected and implemented from the evidence

1. **Create before spawn:** the orchestrator now emits and durably journals `subagent_created/pending` for every validated child before it schedules any worker. The later `subagent_queued` and `subagent_started` events remain separate.
2. **Status query:** `AgentService.subagentStatus(taskId)` exposes the latest durable child snapshot.
3. **Safe delete/dismiss:** `AgentService.dismissSubagent(taskId)` soft-dismisses only terminal children. It preserves the original terminal status and immutable event history, refuses pending/running children, and prevents a dismissed child from being resumed.
4. **Concurrency contract correction:** the previous concurrency test accidentally declared both workers as `coder`, while the scheduler correctly grants coders an exclusive workspace lease. The test now uses read-only `explore` and `reviewer` roles for parallel execution and separately verifies coder exclusivity.

## Remaining integration work

- A typed MCP adapter is not yet present in Giant Agent. Before exposing external MCP servers, add a validated result envelope that preserves content blocks, `isError`, structured content, metadata, and resource links; do not silently flatten them.
- `step_id` already uniquely correlates tool lifecycle events, but a dedicated `tool_call_id` field and per-call cancellation contract are not yet wired end-to-end.
- GPT's worker/SSE transport pipeline is not implemented as a separate service in Giant Agent. Current model execution must be inspected before introducing streaming transport; preserve the existing provider contract and shared local runtime.
- Device/OEM background execution and force-stop behavior still require physical-device validation.

## Validation boundary

The Mylib archives were extracted and integrity-checked. All 70 GPT `.valdimodule` files were decompressed for module/source-name and symbol inspection; the Kimi asset archive and deep-scan report were inventoried and searched for the protocol descriptors above. This does not amount to a full decompilation of every native library or a claim of server-side parity.

The latest pre-change Giant Agent CI run `42909088830` had 79 passing tests and one failing concurrency assertion. The failure was caused by the test's default `coder` role conflicting with the intentional exclusive workspace lease; the test and a dedicated coder-lease regression case have been updated. A fresh CI run is required to confirm the integrated branch.


## Transfer status correction — 2026-11-12

The earlier "Remaining integration work" section above is historical and predates the merged MCP/SSE work. The current Giant Agent integration branch now includes:

- MCP Streamable HTTP client with secure server configuration, endpoint validation, session handling, paginated discovery, `tools/call`, and `resources/read`.
- Typed MCP result envelopes preserving ordered content blocks, media, resource links, `structuredContent`, metadata and errors.
- Independent `tool_call_id` identity, targeted cooperative cancellation and durable interrupted classification.
- OpenRouter SSE streaming with incremental UTF-8-safe parsing and cancellation, through the existing provider service.
- Durable parent requests, child snapshots, append-only journals, restart reconciliation, explicit resume authorization, output artifact persistence and verification.
- Model-facing dynamic child lifecycle tools (`create_subagent`, `spawn_subagent`, `check_subagent_status`, `list_subagents`, `delete_subagent`) on the Kimi transfer branch, using a separate bridge and the shared local runtime.
- Worker metadata and bounded lifecycle progress in durable snapshots.

### Still not transferred / not proven

- GPT's exact account-scoped conversation snapshot implementation and remote API contracts are not present as source in Mylib; Giant uses its own local conversation memory and durable request/event model.
- Streaming deltas are currently live UI events and are excluded from the durable lifecycle journal; full resumable partial assistant-message snapshots are not yet equivalent to the GPT module symbols found in the compiled asset archive.
- Mylib does not expose verified handler bodies or argument schemas for `send_message`, `wait_for_message`, `ask_user`, or `update_goal`. Only their operation names are visible in the Kimi registry. These remain a separate implementation tranche with explicit Giant-owned contracts.
- Real-device validation is still required for Android foreground execution, process death, cancellation during native inference, and nested local child execution.
- A real MCP server integration test and OAuth/stdio transports remain outside the current mobile Streamable HTTP implementation.

No proprietary source code or private provider endpoint contract has been copied. The transfer is an independent implementation of observed architectural patterns.


## Follow-up: durable assistant message state — 2026-11-12

The previous note that streaming deltas were not durable has been narrowed by a new local message-state store:

- `assistant_messages` stores one assistant response per request/child conversation with `streaming`, `complete`, `interrupted`, or `failed` state.
- OpenRouter SSE deltas are batched and appended while the response is streaming.
- Completion stores the final user-visible response, replacing intermediate tool-call/control text.
- Cancellation/failure preserves the available partial response and its terminal state.
- App startup reconciles any message left in `streaming` to `interrupted`; it never upgrades an abandoned stream to success.
- Message records are scoped by conversation and can be queried independently from the compact turn-recall table.
- The database upgrade is forward-only (memory schema v4), and conversation-memory deletion clears message snapshots for that conversation without deleting saved facts.

Remaining GPT asset differences: remote message IDs, provider-specific reasoning metadata, prepared markdown/entity payloads, and server-side conversation synchronization are not implemented. No hidden reasoning is stored.
