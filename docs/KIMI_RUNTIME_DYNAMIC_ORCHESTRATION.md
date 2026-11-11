# Kimi Runtime Dynamic Orchestration

This tranche connects the model-facing tool loop to the active in-memory subagent scheduler. It does not create another model provider, llama.cpp instance, or JNI runtime.

## Model-facing tools

- `create_subagent`: registers a child beneath the currently executing worker. Creation does not start it.
- `spawn_subagent`: schedules a registered child. The scheduler starts it when a worker slot and completed dependencies are available.
- `delete_subagent`: requests cancellation; it does not erase the append-only event history.
- `check_subagent_status`: returns created, pending, running, or terminal state and the result/error when available.
- `send_message` / `wait_for_message`: exchange bounded messages between workers. Message envelopes are also written to the lifecycle timeline.
- `update_goal`: updates the shared coordination goal; workers started afterward receive the updated goal in their task context.

## Bounds and scheduling

- Maximum eight tasks per parent request.
- Maximum nesting depth two.
- Roles remain `explore`, `plan`, `coder`, and `reviewer`.
- A spawned child cannot start until declared dependencies have completed successfully.
- Existing concurrency rules remain: local llama.cpp execution is single-worker; OpenRouter uses the existing bounded parallel path; coder workers hold the exclusive workspace lease.
- Child workers use the same ModelService and existing tool implementations. No second model/JNI runtime is constructed.
- Cancellation is task-scoped and the event journal remains append-only.

## Deliberate scope boundary

`ask_user` is not exposed yet. A correct implementation needs a user-facing pending-input surface in the chat UI, durable correlation from the request to that prompt, timeout/cancellation behavior, and a response API. Emitting a fake question event without a response path would falsely imply a working interaction. This remains a separate UI/runtime contract and is not claimed as complete.

The existing service-level create/spawn/status/soft-delete APIs remain available for recovery and external callers. The new model-facing tools operate against the active orchestrator so a worker can add children without enqueueing behind and deadlocking the parent request.
