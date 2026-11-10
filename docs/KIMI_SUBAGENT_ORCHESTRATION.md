# Kimi-style delegated-agent orchestration

## Implemented in this branch

- Complex requests first receive a tool-free structured delegation pass from
  the selected model. The JSON task graph is validated (roles, IDs, dependency
  references, cycles, task count and prompt bounds) before execution. Invalid
  output falls back to the deterministic PlannerService plan.
- The planner's multi-step requests are dispatched as child-agent tasks rather
  than executed by one generic sequential loop.
- Child identities are stable within a parent request and carry an agent role:
  `explore`, `plan`, `coder`, or `reviewer`.
- Each child receives a dedicated conversation ID. Parent history and sibling
  contexts are not automatically injected into that context.
- Dependency results are passed explicitly to downstream children.
- Explore, plan, and reviewer agents are restricted at both prompt-catalog and
  runtime-validation layers to `read_file` and `list_files`. Coder agents can
  use the registered workspace tools; terminal execution still requires the
  existing literal user-approval flow.
- Child lifecycle events are emitted through the existing AgentKernel and
  AgentEventBus. AgentService appends request-scoped runtime and tool events to
  the existing immutable SQLite event journal.
- Cancellation stops pending children and propagates to the active shared
  inference call. Interrupted children are distinguished from failed children.
- Final synthesis uses only collected child outputs and cannot invoke tools.

## Shared-runtime safety

A child is a task/context, not a new model, terminal, JNI bridge, or tool
runtime. All children call the existing ModelService. The current llama.cpp
JNI context is mutable and protected by one FIFO lock, so production execution
uses a concurrency limit of one until isolated inference contexts are
implemented and verified. The scheduler itself supports bounded concurrency
and is tested independently.

## Explicitly not complete yet

This is an integrated first implementation, not a claim of feature parity with
Kimi Agent Swarm. Remaining work includes:

1. Iterative replanning: the current model-generated plan is created once at
   request start. The parent does not yet revise the graph dynamically in
   response to intermediate worker findings or spawn follow-up agents.
2. Persisted child-task snapshots and safe child-level recovery/resume after
   process restart. Current request recovery deliberately marks interrupted
   work instead of replaying side effects.
3. User-facing subagent management UI: live child list, per-child output,
   pause/resume, and targeted cancellation.
4. True parallel model execution. It must not be enabled by creating duplicate
   LlamaService/JNI runtimes or bypassing the shared runtime lock.
5. End-to-end device validation of tool permissions, cancellation, background
   execution, and Timeline replay.

No event contains private chain-of-thought. Timeline records factual task
transitions, tool operations, statuses, and final results only.
