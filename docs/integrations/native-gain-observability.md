# Native Gain Agents observability

## Decision

Giant Agent owns its observability pipeline. The application does not require Boosthis, a vendor SDK, a project key, a remote telemetry endpoint, or outbound trace-header injection.

The existing runtime already provides the core of this system:

- `AgentEventBus` publishes factual lifecycle, tool, task, and subagent events.
- `AgentService` subscribes to the event bus and serializes durable journal writes.
- `AgentKernelStore` stores request and event records in the app-private SQLite database.
- `agent_events` is append-only (database triggers reject update/delete), and event IDs are idempotent on stream retries.
- `stream_token` deltas are intentionally excluded from the durable journal to prevent unbounded growth.
- `eventsFor(requestId)` replays a request's timeline in insertion order.
- `AgentKernelObservability` adds conversation-scoped event pagination with stable SQLite row cursors, type/status filters, and privacy-preserving aggregate metrics.
- `AgentEventBus` normalizes common correlation aliases, supplies a process sequence, and carries request/session/attempt identifiers where known.

## Event flow

```text
Agent / Tool / Subagent
        |
        v
AgentEventBus (process-wide factual event stream)
        |
        v
AgentService journal subscriber (serialized writes)
        |
        v
AgentKernelStore / SQLite (app-private, durable, append-only)
        |
        +--> Timeline replay by request
        +--> Task/subagent lifecycle history
        +--> Recovery and diagnostics
```

This is local-first observability. It does not transmit prompts, tool output, file contents, model responses, device identifiers, or trace headers to a third party.

## Event contract

Every durable event should carry, when applicable:

- `id`: stable unique event identifier (deduplication key).
- `request_id`, `session_id`, `task_id`, `step_id`, `tool_call_id`: correlation identifiers.
- `type`: factual lifecycle event name (for example `request_started`, `tool_start`, `tool_output`, `subagent_started`, `task_completed`).
- `status`: state of the event or operation.
- `timestamp`: ISO-8601 timestamp.
- `sequence`: producer sequence where available.
- `title`, `details`, `output`: optional presentation/debug fields. Sensitive payloads must not be added by default.

Never persist hidden model reasoning. Timeline records describe observable execution events and outcomes only.

## Query and metrics contract

The read-only observability extension exposes:

- Newest-first conversation event pages with a bounded page size (1–200) and a stable `beforeRowId` cursor. New events do not shift an already-issued cursor.
- Optional exact event-type and status filters.
- Conversation aggregates for request states, event counts, distinct tool calls, tool failures, tool success rate, and average reported tool latency.
- Aggregate responses never include prompts, model responses, tool arguments, or tool output. Full event details remain available only through the local app database API.
- The chat app bar opens the local Gain Agents diagnostics screen for the active conversation. It provides summary cards, status filtering, refresh, and cursor-based older-event loading.

Tool latency is reported only when a producer includes a non-negative `duration_ms` or `latency_ms` field. Missing measurements remain absent; they are never treated as zero.

## Operational guarantees

1. Event writes are serialized by `AgentService` and remain supplemental to the durable execution kernel.
2. Event IDs are unique; retries use conflict-ignore semantics.
3. The journal is append-only.
4. A process restart reconciles in-flight requests as interrupted; it does not replay uncertain side effects automatically.
5. Token streaming is not journaled.
6. A telemetry/journal write failure must not falsely mark a request successful or corrupt execution state.
7. No network reporting is enabled by this design.

## Verification

The durable-service tests cover request persistence, FIFO execution, and subagent event journaling. Dedicated observability tests cover stable cursor pagination, type/status filtering, conversation isolation, request-state aggregates, distinct tool outcomes, and latency aggregation. Event-bus tests cover correlation normalization and process sequence metadata. The chat app bar exposes the diagnostics screen without adding a remote service or a second runtime. Extend these tests whenever the event contract, persistence policy, or recovery behavior changes. CI must run Flutter analysis, unit tests, and release APK builds before merge.

## Removed vendor integration

The former Boosthis MCP project configuration and vendor-specific setup instructions have been removed. There is no external telemetry dependency to configure. The native SQLite journal is the source of truth for Giant Agent execution observability.
