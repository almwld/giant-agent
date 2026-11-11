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
