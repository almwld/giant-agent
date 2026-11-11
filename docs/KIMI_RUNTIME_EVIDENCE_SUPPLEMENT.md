# Kimi runtime evidence supplement — 2026-11-11

This supplement records findings from the second JADX export uploaded to
`almwld/Mylib` under `Kimi_Subagent_Runtime_Contents/Kimi_Subagent_Runtime_Refs`.
It intentionally distinguishes directly observed behavior from inferred
behavior. No Kimi implementation code is copied into Giant Agent.

## Newly confirmed runtime behavior

### 1. Swarm snapshot cache and refresh coordinator — `Ae/f.java`

The exported `Ae.f` is a singleton-style SwarmDataCenter with:
- a per-chat map of `List<Subagent>` snapshots;
- lookup by `(chatId, agentId)`;
- per-chat filtering of snapshots in PENDING or RUNNING state;
- a refresh job map keyed by chat ID, with cancellation/replacement of an
  existing refresh job;
- a two-second refresh throttle for non-forced refreshes;
- timestamp tracking for the last successful refresh;
- coroutine-backed network refreshes, then publication of the returned
  snapshot list into observable state.

The network refresh paths instantiate `ld.M` and `ld.N` request objects and
consume a response whose payload contains a swarm/subagent list. The decompile
does not expose enough of those request classes to safely state endpoint names,
request parameters, pagination, or retry semantics.

### 2. Confirmed status vocabulary — `ld/C3867t.java` and variants

The serialized status enum maps:
- `STATUS_UNSPECIFIED`
- `STATUS_IDLE`
- `STATUS_RUNNING`
- `STATUS_PENDING`
- `STATUS_TERMINATED`

The current export does not prove separate SUCCEEDED, FAILED, or CANCELLED
wire states. Giant must not invent those as Kimi wire values. Giant may retain
its richer internal lifecycle states and map them explicitly at the adapter
boundary.

### 3. Status event contract and consumer — `Uc/C2011a3.java`,
`Uc/Y2.java`, `Hf/C1164q3.java`

The typed event contains:
- `chatId`
- `agentId`
- `status`
- nullable `progressPercent`

The consumer filters to the currently active chat, looks up the prior snapshot
by chat and agent ID, compares old/new status, emits a stream event for the
agent's active/non-active state, and triggers a swarm snapshot refresh. The
boolean sent in the stream event is derived by excluding PENDING and RUNNING;
it is not a complete terminal-state taxonomy.

### 4. Parent chat orchestration and tool-output handling — `Hf/A3.java`,
`Hf/C1122j3.java`

`Hf/A3` is a chat-specific event handler registered for a family of typed
internal events. Its `I(selectedAgentId, messageId)` method updates the
selected-agent/message context, reads the swarm snapshot, determines whether
the selected agent is currently active, and emits a corresponding stream
event. It does not itself establish the create/delete operation dispatcher.

`Hf/C1122j3` consumes a completed/updated assistant message and inspects
special tool blocks. For the recognized spawn-subagent block it checks
existing task-graph entries and can select the next agent through `A3.I`;
for other recognized agent/task blocks it updates the selected agent or
continues the existing task flow. It also refreshes swarm state after relevant
subagent results. This is evidence of a tool-output-to-chat/task-graph bridge,
not proof of the full request handler for all four lifecycle operations.

### 5. Stream service boundary — `ue/C4801l.java`, `Df/b.java`,
`Cf/C0439y6.java`

`ue.C4801l` is the shared chat StreamService implementation. It owns the
stream API, chat context, plugin/event handlers, observable chat/message
state, and dispatches typed stream events to registered handlers. The
`Df.b` interface is a plugin/handler lifecycle contract. `Cf.C0439y6`
registers chat event handlers and delegates stream work to the shared service.
These are useful architectural patterns for a single event bus and plugin
boundary; they are not themselves the subagent runtime or a separate model
runtime.

## Revised evidence boundary

The new export materially improves the evidence for snapshot storage,
refresh, status vocabulary, event correlation, active-agent selection, and
the bridge from assistant tool output into chat/task state.

It still does **not** reveal a complete, trustworthy dispatcher/handler
implementation for `create_subagent`, `spawn_subagent`, `delete_subagent`,
`check_subagent_status`, `send_message`, `wait_for_message`,
`ask_user`, or `update_goal`. The operation-name registry remains direct
evidence for vocabulary only. Some large coroutine bodies are omitted by
JADX, and referenced request/handler classes are absent from this export.

## Implementation decisions for Giant Agent

1. Keep the existing shared `ModelService`/`LlamaService` and existing
   orchestration/kernel. Do not add another inference runtime.
2. Model the Kimi wire states explicitly at the adapter boundary:
   `unspecified`, `idle`, `running`, `pending`, `terminated`.
   Keep Giant's richer terminal states internal unless an actual wire mapping
   is established.
3. Keep chat-scoped parent/child ownership and stable child IDs. Status events
   must be correlated by both conversation/chat ID and child ID; progress is
   nullable and must remain nullable.
4. Treat snapshot refresh as authoritative reconciliation, not as a substitute
   for durable local lifecycle journaling.
5. Preserve the semantic separation between configuration/registration
   (`create`) and execution (`spawn`). Do not infer that creation executes.
6. Keep deletion as a safe, auditable lifecycle operation in Giant; do not
   physically erase history or cancel active work implicitly.
7. Implement model-facing tools only with validated schemas, bounded depth,
   child count/concurrency, per-child cancellation, and durable state changes.
   The exact remote Kimi arguments and side effects remain unverified.
8. Keep messaging, waiting, ask-user, and goal-update as a separate protocol
   tranche until their handlers and argument schemas are extracted.

## Source paths inspected

- `Ae/f.java`
- `Hf/A3.java`
- `Hf/C1122j3.java`
- `Hf/C1164q3.java`
- `Uc/C2011a3.java`
- `Uc/Y2.java`
- `ld/C3867t.java`
- `ld/C3868u.java`
- `ld/C3869v.java`
- `ld/C3870w.java`
- `ld/C3871x.java`
- `ue/C4801l.java`
- `Df/b.java`
- `Cf/C0439y6.java`
- `ve/C5150s0.java`
- `tf/C4503a.java`
- `ye/C5726a.java`
- `ye/C5729d.java`
- `ti/C4532b.java`

Source repository: `almwld/Mylib`, main tree commit
`ede401bf7b30d95ba776889fbe90bd873b195946`.
