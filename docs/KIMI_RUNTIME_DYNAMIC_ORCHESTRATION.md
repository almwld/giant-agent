# Kimi Runtime Dynamic Orchestration

This tranche connects the model-facing tool loop to the active in-memory subagent scheduler. It does not create another model provider, llama.cpp instance, or JNI runtime.

## Model-facing tools

- `create_subagent`: registers a child beneath the currently executing worker. Creation does not start it.
- `spawn_subagent`: schedules a registered child. The scheduler starts it when a worker slot and completed dependencies are available.
- `delete_subagent`: requests cancellation; it does not erase the append-only event history.
- `check_subagent_status`: returns created, pending, running, or terminal state and the result/error when available.
- `send_message` / `wait_for_message`: exchange bounded messages between workers. Message envelopes are also written to the lifecycle timeline.
- `update_goal`: updates the shared coordination goal; workers started afterward receive the updated goal in their task context.
- `ask_user`: opens a correlated question dialog in the active chat, waits for the user's answer, and returns the answer to the calling worker. Requests are bound to the parent request, child task and chat session, and are cancelled or timed out safely.

## Bounds and scheduling

- Maximum eight tasks per parent request.
- Maximum nesting depth two.
- Roles remain `explore`, `plan`, `coder`, and `reviewer`.
- A spawned child cannot start until declared dependencies have completed successfully.
- Existing concurrency rules remain: local llama.cpp execution is single-worker; OpenRouter uses the existing bounded parallel path; coder workers hold the exclusive workspace lease.
- Child workers use the same ModelService and existing tool implementations. No second model/JNI runtime is constructed.
- Cancellation is task-scoped and the event journal remains append-only.

## User interaction

The `ask_user` tool publishes a request event through the existing event bus. ChatScreen presents a text-entry dialog and submits the response through a request-ID-correlated broker. The broker persists request/answer/timeout/cancellation events through the existing journal path and bounds waits to three minutes. It does not treat an empty answer or a dismissed dialog as approval.

The existing service-level create/spawn/status/soft-delete APIs remain available for recovery and external callers. Informational message and goal events preserve the worker's current lifecycle state in the durable task projection. The new model-facing tools operate against the active orchestrator so a worker can add children without enqueueing behind and deadlocking the parent request.
