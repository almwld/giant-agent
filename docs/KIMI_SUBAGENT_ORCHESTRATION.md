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
- Child resume is now a durable, explicit operation exposed by `AgentService`.
  SQLite atomically claims an interrupted/failed child, rejects completed or
  cancelled children, reconstructs completed dependency outputs, and records
  the user's side-effect disposition before execution.
- Full child outputs are persisted separately from bounded Timeline summaries,
  so downstream recovery can reconstruct dependency context without relying on
  truncated display text.
- Recovered children execute through the existing `AgentKernel` and shared
  `ModelService`; role-based tool permissions remain enforced. A process death
  during resume is reconciled back to an interrupted state and requires a new
  explicit authorization.
- Durable requests and explicit child recovery now acquire an Android foreground
  service for the duration of active work. The native notification is updated
  with the current lifecycle step, and a reference count prevents one queued
  request from stopping the service while another remains active.
- `AgentRuntime` retains the Activity's single `FlutterEngine` at process scope;
  `MainActivity` reuses it after Activity recreation and does not destroy it on detach.
  This keeps the same Dart isolate and shared `ModelService`/`LlamaService` facade
  alive while the foreground service protects the process. No second inference
  runtime is created for background work.
- If Android recreates the foreground service after process death, its
  notification explicitly requests recovery; it never claims that model work
  resumed. SQLite reconciliation marks in-flight requests/children interrupted
  and requires explicit user authorization before child execution resumes.
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

1. Richer subagent management: pause/resume controls and explicit child-level
   retry policy for completed work. The Timeline now exposes explicit recovery
   for interrupted/failed children with a side-effect review decision.
3. Device/OEM-specific background restrictions, force-stop behavior, and
   battery-optimization behavior still require deployment validation. A force
   stop or process death terminates active inference; SQLite recovery then marks
   it interrupted and requires explicit user action rather than replaying it.
4. True parallel model execution. It must not be enabled by creating duplicate
   LlamaService/JNI runtimes or bypassing the shared runtime lock.
5. End-to-end device validation of tool permissions, cancellation, restart
   recovery, background execution, and Timeline replay.

No event contains private chain-of-thought. Timeline records factual task
transitions, tool operations, statuses, and final results only.
