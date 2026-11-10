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
  AgentEventBus. AgentService persists child snapshots (role, prompt,
  dependencies, status and latest bounded details) alongside immutable SQLite
  task and parent-request event journals.
- Startup recovery marks pending/running child snapshots as interrupted and
  exposes them for explicit recovery. It never automatically replays a child
  or a side-effecting operation.
- When worker results contain failed or skipped tasks, the coordinator may
  request one bounded evidence-driven repair plan. The repair batch receives
  unique IDs, does not automatically rerun completed tasks, and cannot loop
  indefinitely.
- Global cancellation stops pending children and propagates to the active shared
  inference call. A user can also stop one selected pending/running child from
  the Timeline; interrupted children are distinguished from failed children.
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

1. Explicit user-authorized child resume from persisted snapshots. Recovery
   currently marks interrupted children and exposes their prompts/dependencies;
   it does not silently replay work.
2. Richer subagent management: pause/resume, explicit child-level retry, and
   full (untruncated) child result retrieval. The Timeline currently exposes
   child roles, identities, statuses, bounded result summaries, and targeted stop.
3. Detached/background execution with Android lifecycle guarantees and durable
   notification/progress behavior.
4. True parallel model execution. It must not be enabled by creating duplicate
   LlamaService/JNI runtimes or bypassing the shared runtime lock.
5. End-to-end device validation of tool permissions, cancellation, restart
   recovery, background execution, and Timeline replay.

No event contains private chain-of-thought. Timeline records factual task
transitions, tool operations, statuses, and final results only.
