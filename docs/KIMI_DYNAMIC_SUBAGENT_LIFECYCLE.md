# Kimi Dynamic Subagent Lifecycle Contract

This change adds the durable application service contract for dynamic child agents.

## Operations

- `createSubagent`: validates identity, role, prompt size, parent ownership, dependency ownership, and the per-parent worker cap; records a durable `subagent_created` event without starting work.
- `spawnSubagent`: accepts pending children only, verifies that every dependency completed with a non-empty result, and runs the child through the existing singleton execution kernel and shared ModelService.
- `checkSubagentStatus`: returns the latest durable child projection.
- `listSubagents`: returns children in durable creation order.
- `deleteSubagent`: soft-deletes terminal children from active management while preserving the append-only audit history. It refuses to remove a running worker.

## Safety and lifecycle rules

- Roles are limited to `explore`, `plan`, `coder`, and `reviewer`.
- At most eight children may be registered for one parent request.
- A child cannot start until all declared dependencies are completed and have a recorded result.
- Duplicate concurrent spawn attempts are rejected.
- Interrupted work is not silently replayed. The existing explicit `resumeSubagent` flow remains the recovery path and still requires a side-effect disposition.
- No new model/JNI runtime is constructed; child execution is routed through the existing AgentKernel queue.

## Scope boundary

These are durable service-level lifecycle operations. This commit does not claim that the model-facing tool-call bridge or the separate Kimi message/wait/ask-user/update-goal contracts are complete. Those require their own request-scoped dispatch and interaction semantics and must be tested independently.


## Model-facing integration — 2026-11-12

The durable service operations are now registered as first-class model tools:

- `create_subagent`: registers a pending child; does not execute it.
- `spawn_subagent`: starts a registered child inline while its parent is suspended at the tool call.
- `check_subagent_status`: returns a durable snapshot scoped to the active parent.
- `list_subagents`: lists only children owned by the active parent.
- `delete_subagent`: soft-dismisses a terminal child; it cannot remove a pending/running child.

The tool bridge is a separate adapter so `ModelService` does not import `AgentService` and create a circular service dependency. Every tool invocation retains its independent `tool_call_id`; child lifecycle events carry that correlation ID into the append-only journal.

### Important runtime detail: nested local inference

A naive spawn implementation that enqueues a child behind the currently executing parent deadlocks: the parent is waiting for the spawn tool, while the child waits for the parent queue slot. A second deadlock occurs if the child tries to reacquire the local model lock or tool FIFO lock held by its parent.

The implementation therefore:
- Executes a model-created child inline inside the active parent request; it does not enqueue behind that parent.
- Uses a request-scoped reentrant runtime lease so the child reuses the same process-wide `ModelService` / `LlamaService` and single JNI context.
- Does not hold the tool FIFO lock around orchestration tools, allowing the child to call its own allowed tools.
- Keeps child roles read-only or coder-scoped; child agents cannot recursively create/spawn/delete agents.
- Leaves explicit crash recovery on the existing queued, user-authorized resume path.

### Snapshot and event projection

Durable snapshots now retain:
- stable child ID, parent request ID, conversation ID, role and creation-order index;
- title, description, icon URL and motto;
- dependency IDs, status, bounded progress percentage and async marker;
- last result, dismissal marker and immutable event history.

Progress is currently emitted at known lifecycle boundaries (0% at start and 100% at verified completion). It is not an invented continuous estimate. The Kimi wire vocabulary remains distinct from Giant's richer internal states.

### Validation added

- Tool catalogue and parent/tool-call identity bridge contract tests.
- Durable service integration test for model-facing create, status, list, parent isolation and event correlation.
- Timeline progress serialization and bounds tests.

The exact Kimi dispatcher argument schemas and handler bodies remain unavailable in the Mylib export. These are Giant's explicit validated schemas and execution semantics, not a claim of wire-level equivalence.


### Targeted cancellation correction

The active `spawn_subagent` handler now receives the exact tool call's cancellation predicate. It is checked before child admission and during every child model/tool boundary. For local GGUF generation, cancelling that tool call also signals the existing native `LlamaService` cancellation entry point; it does not create a second runtime or set the parent-wide cancellation flag. Child lifecycle events retain the parent spawn call's `tool_call_id`, while tools invoked by the child receive their own IDs.
