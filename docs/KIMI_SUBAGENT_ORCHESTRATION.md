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
- The scheduler now runs up to three independent child workers concurrently
  when the configured OpenRouter provider is active. Local GGUF inference remains
  strictly single-worker because llama.cpp exposes one mutable JNI context.
- Cloud workers carry request-scoped Zone context for event correlation and
  cancellation. A child cancellation does not cancel its siblings; parent
  cancellation is propagated to all workers.
- Workspace tool effects and their independent verification share one FIFO
  critical section. This prevents concurrent file mutations from racing with
  verification, while independent cloud inference requests can overlap.
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
- Once every interrupted child has been explicitly resumed, the parent is
  re-synthesized from the full durable child results. The parent request is
  promoted from interrupted to completed only after the Output Engine verifies
  the final text and all referenced workspace artifacts.
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
- The Output Engine runs inside the durable request executor, before SQLite
  marks the parent request completed. It stores the final synthesis, complete
  child results, and discovered workspace artifacts in a dedicated indexed
  SQLite table linked to request and conversation IDs. The Timeline shows
  incremental artifact cards with text/code previews and verification status;
  supported images can be previewed on demand, and the workspace ZIP is shared
  through Android's FileProvider rather than exposing a raw cache path.
- File outputs are classified as source/code, text, image, document, or generic
  file. The engine verifies workspace presence and reads text/code content where
  supported; unverified or missing files produce a partial-output state and keep
  the parent request interrupted instead of reporting false completion.
- Output lifecycle events expose artifact identity, type, path, verification
  status and bounded previews to the Timeline. The workspace export action
  packages the generated files for transfer; the durable artifact API also
  supports retrieval by request or conversation.

## Shared-runtime safety

A child is a task/context, not a new model, terminal, JNI bridge, or tool
runtime. All children call the existing ModelService. Local GGUF inference
continues to use one mutable llama.cpp JNI context behind a strict FIFO lock.
When OpenRouter is selected, up to three independent provider requests can
overlap using request-scoped Zone values for cancellation and event identity.
Workspace mutations and their verification remain serialized in a separate
FIFO critical section. This provides real bounded cloud-worker concurrency
without creating duplicate local inference runtimes.

## Explicitly not complete yet

This is an integrated implementation, not a claim of feature parity with Kimi
Agent Swarm. Remaining work includes:

1. Richer child management: pause/resume controls and an explicit retry policy
   for already completed children. Interrupted/failed child recovery is present.
2. Device/OEM-specific background restrictions, force-stop behavior, and
   battery-optimization behavior still require deployment validation. A force
   stop or process death terminates active inference; SQLite recovery marks it
   interrupted and requires explicit user action rather than replaying it.
3. Isolated local inference contexts for parallel GGUF workers. Until the JNI
   layer provides independent safe contexts, local-model concurrency remains 1.
4. End-to-end device validation of tool permissions, cancellation, restart
   recovery, foreground execution, artifact preview/export, and Timeline replay.

No event contains private chain-of-thought. Timeline records factual task
transitions, tool operations, statuses, and final results only.
