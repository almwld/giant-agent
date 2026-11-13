# Unified Runtime Ownership

This document records the operational ownership boundaries on
`integration/unified-agent-runtime-v2`. It is an implementation map, not a
claim that device validation or every optional capability is complete.

## Canonical ownership

| Capability | Canonical owner | Integration contract |
| --- | --- | --- |
| Application task admission | `AgentService` | The only application-facing request boundary. |
| Durable request queue and recovery | `domain/kernel/AgentKernel` + `AgentKernelStore` | SQLite owns FIFO sequence, request projection, append-only event journal, output artifacts and restart reconciliation. |
| Actual execution | `agent/architecture/AgentKernel` | Existing process-wide execution kernel owns planner, model facade, tool execution and cancellation. |
| Model/runtime selection | `ModelService` + `ModelProviderSettings` + `OpenAICompatibleProvider` | Local GGUF and OpenRouter are provider modes behind the existing model facade; do not instantiate another inference runtime in services. |
| Agent lifecycle and UI event fan-out | `AgentEventBus` | Stable request/session/task/step/tool-call correlation; token deltas are excluded from the durable journal. |
| Timeline and Gain diagnostics | `AgentService` + `AgentKernelObservability` | Read the canonical kernel database; cursor pagination is based on immutable event row IDs. |
| MCP sessions and remote tools | `McpClient` | Owns MCP server configuration/session lifecycle only; it never owns inference. Tool results retain content blocks, structured content and metadata. |
| Tool cancellation | `AgentService.cancelToolCall` -> `ModelService` | Cancellation is scoped by independent `tool_call_id`; do not substitute request IDs. |
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

`AnalyticsService` currently owns a legacy `analytics.db` schema and is not
the canonical execution history. Do not write a second copy of every
`AgentEventBus` event into it. Future analytics screens should project from
`AgentKernelStore` or perform an explicit, lossless migration before changing
ownership. Existing legacy analytics files must not be deleted.

## Voice boundary

The current on-device speech service captures a completed utterance and runs
local Whisper transcription; the Arabic Nabra TTS service synthesizes speech
locally. This is not continuous full-duplex voice. VAD, acoustic echo
cancellation, barge-in arbitration and device-specific latency/thermal
qualification remain native/audio-pipeline work and must not be represented as
complete merely because recording and transcription work.

## Safe extension rules

1. Extend the existing owner instead of creating another queue, database,
   model runtime, event bus or session manager.
2. Keep request, task, step, attempt and tool-call identifiers distinct.
3. Persist factual lifecycle transitions; never infer execution progress from
   assistant prose.
4. Keep secrets, prompts, model outputs and raw tool arguments out of
   aggregate telemetry unless a feature explicitly requires them and applies
   access controls.
5. A request interrupted during a side effect is never replayed automatically.
6. Preserve legacy data and APIs until an explicit migration and compatibility
   plan exists.
