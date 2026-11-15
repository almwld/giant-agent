# Unified Runtime Ownership

This document records the operational ownership boundaries used by `main`.
SQLite is the only durable authority for request/task lifecycle state. This is
an implementation map, not a claim that device validation or every optional
capability is complete.

## Canonical ownership

| Capability | Canonical owner | Integration contract |
| --- | --- | --- |
| Application task admission | `AgentService` | The only application-facing request boundary. |
| Durable request queue and recovery | `domain/kernel/AgentKernel` + `AgentKernelStore` | SQLite alone owns FIFO sequence, request status, attempt count, append-only event journal, output artifacts and restart reconciliation. |
| Volatile execution adapter | `agent/architecture/AgentKernel` | Runs the active planner/model/tool invocation and scoped cancellation handles only. Its in-memory active flag is diagnostic/transient; it is not a request-status authority and is never used for recovery or AgentsOS status. |
| Model/runtime selection | `ModelService` + `ModelProviderSettings` + `OpenAICompatibleProvider` | Local GGUF and OpenRouter are provider modes behind the existing model facade; do not instantiate another inference runtime in services. |
| Agent lifecycle and UI event fan-out | `AgentEventBus` + `AgentService` journal subscriber | Events are append-projected into the same SQLite store; token deltas are excluded. EventBus is transport, not state authority. |
| Timeline and Gain diagnostics | `AgentService` + `AgentKernelObservability` | Read the canonical kernel database; cursor pagination is based on immutable event row IDs. |
| MCP sessions and remote tools | `McpClient` | Owns MCP server configuration/session lifecycle only; it never owns inference. Tool results retain content blocks, structured content and metadata. |
| Tool cancellation | `AgentService.cancelToolCall` -> `ModelService` | Cancellation is scoped by independent `tool_call_id`; do not substitute request IDs. |
| Child-agent lifecycle and persistence | `ModelService` + `SubagentLifecycleManager` bound to the exact `AgentService` `AgentKernelStore` instance | Dynamic child state is request-scoped; lifecycle events and durable task projections share the canonical SQLite store. No second child database connection is created. |
| Detached child scheduling | Execution `AgentKernel` + its existing `FifoTaskQueue` | `spawn_subagent(run_in_background: true)` persists a pending async snapshot and queues execution behind the current request. Children reuse the one `ModelService`/`LlamaService`; they are serialized, not parallel local inference jobs. Pending not-yet-started jobs are requeued after restart; running jobs are interrupted and require explicit side-effect review. |
| Child-agent recovery | `SubagentRecoveryCoordinator` + `AgentKernelStore` | Resume requires an explicit side-effect disposition and an atomic claim; dependency results are passed as a snapshot. |
| Memory | `AgentMemoryService` | Owns episodic turns, facts, edits and workspace versions. Memory remains contextual data, not executable instructions. |
| Background execution | `AgentBackgroundExecutionService` | Android foreground notification only; it does not own scheduling, inference or durable state. |
| Output artifacts | `OutputEngine` + `AgentKernelStore` | Artifacts are separate projections from immutable lifecycle events and must be verified before a request is reported completed. |

## Telemetry integration

`AgentService.runTask` now increments the existing message counter and records
end-to-end request latency through `StatsService` and `PerformanceService`.
These are aggregate projections of the canonical durable request path: neither
service is allowed to enqueue execution, store prompts, or create a second
request/event journal.

`AnalyticsService` now writes bounded, content-free analytics facts to
`agent_events` through `AgentKernelStore.appendAnalyticsEvent` and reads its
aggregate counts from that same journal. It does not open a second analytics
database or duplicate every `AgentEventBus` lifecycle event. The historical
`analytics.db` file is left untouched on disk; it is not a competing source
for new runtime metrics.

## Voice boundary

The current Android voice boundary is `VoiceCaptureBridge` +
`LocalSpeechRecognitionService` + local Whisper, with local Arabic Nabra TTS.
The bridge captures 16 kHz PCM, uses platform AEC/NS/AGC when available and
emits energy-VAD boundaries. Capture stays active during assistant TTS; auto
barge-in is gated on reported AEC availability, with manual interruption as a
fallback. Platform effect quality remains device/route dependent; neural VAD,
custom software AEC and device-specific latency/thermal qualification are not
claimed complete.

## Durable retry contract

Only an executor error explicitly wrapped as `RetryableKernelFailure` is
eligible for automatic retry. The ceiling is three total attempts, the attempt
counter and retry/failure transitions are committed transactionally to SQLite,
and each retry is appended to the immutable event journal. Unclassified errors
fail immediately. `KernelRequestInterrupted` and work interrupted by process
death are never automatically retried because prior external side effects may
be ambiguous. UI caches in `TaskManager` are refreshed from SQLite and must not
normalize a live `running` row into a recovered `paused` state.

## Safe extension rules

1. Extend the existing owner instead of creating another queue, database,
   model runtime, event bus or session manager. Detached children use the
   execution kernel's existing FIFO, not a competing scheduler.
2. Keep request, task, step, attempt and tool-call identifiers distinct.
3. Persist factual lifecycle transitions; never infer execution progress from
   assistant prose.
4. Keep secrets, prompts, model outputs and raw tool arguments out of
   aggregate telemetry unless a feature explicitly requires them and applies
   access controls.
5. A request interrupted during a side effect is never replayed automatically.
6. Preserve legacy data and APIs until an explicit migration and compatibility
   plan exists.
