# Durable Task Engine — Implementation Specification and Repository Review

**Status:** Reviewed implementation contract; documentation-only change  
**Reviewed base:** `replay/verified-onto-425197` at `74a15a3342f342af6920d8b035b34624787ba161`  
**Target:** Giant Agent Flutter/Android runtime  
**Decision:** Do not add multi-agent workers yet. First unify the existing durable queue, active execution kernel, task history and Timeline around one source of truth.

> This document records what the repository actually contains and defines the next implementation contract. It does not claim that the target architecture is already integrated or production-ready.

## 1. Executive finding

Giant Agent already contains meaningful pieces of a durable task system:

- `lib/domain/kernel/agent_kernel.dart` implements a FIFO request pump and delegates execution through an injected executor.
- `lib/domain/kernel/agent_kernel_store.dart` persists requests and append-only request events in SQLite.
- `test/domain/kernel/agent_kernel_test.dart` verifies FIFO ordering, duplicate-ID rejection, queued-request restoration and safe interruption of a running request after restart.
- `lib/agent/task_manager.dart` persists task history and a resumable status in SharedPreferences.
- `lib/agent/architecture/agent_kernel.dart` is the active execution coordinator used by `AgentService`, with model readiness checks, planner integration, cancellation and transient Timeline events.

The primary gap is therefore **not the absence of a durable queue**. It is that the durable queue is not the runtime path used by the application. The repository currently has two different classes named `AgentKernel`, a separate SharedPreferences `TaskManager`, and a transient event stream. The tested SQLite queue and event journal are not composed into the user-facing execution path.

The next milestone is an integration and ownership correction, not a wholesale rewrite.

## 2. Current execution topology (verified)

The user-facing path currently follows:

```text
ChatScreen / Voice Assistant
        |
        v
AgentService.instance.runTask(...)
        |
        v
lib/agent/architecture/AgentKernel.instance
        |
        +--> PlannerService
        +--> ModelService / shared local runtime
        +--> OpenRouter readiness
        +--> transient broadcast Timeline stream
        |
        v
String output
```

ChatScreen separately wraps this path with:

```text
TaskManager (SharedPreferences snapshot)
  createTask -> markRunning -> AgentService.runTask
             -> markCompleted / markFailed / markInterrupted
```

A second, independently implemented path exists:

```text
lib/domain/kernel/AgentKernel
        |
        v
AgentKernelStore (SQLite FIFO + append-only request events)
        |
        v
injected KernelRequestExecutor
```

The durable path has unit tests, but the inspected `AgentService` imports `../agent/architecture/agent_kernel.dart`, not the durable kernel in `lib/domain/kernel`. Do not mistake passing tests for proof that the application currently executes through the SQLite queue.

## 3. File-by-file review and required changes

| File | Verified responsibility today | Finding / risk | Required change |
|---|---|---|---|
| `lib/services/agent_service.dart` | Public facade; creates request IDs and calls the active execution kernel | Bypasses the tested SQLite queue; request ID is generated internally and cannot be supplied by TaskManager/UI | Make this the sole application entry point into the unified durable kernel. Accept or create a stable request ID, return a typed result, expose persisted event replay and cancellation |
| `lib/agent/architecture/agent_kernel.dart` | Active model execution, planning, cancellation, runtime readiness and event emission | Holds active request state and event sequence only in memory; not restart-durable; class name conflicts with the domain kernel | Rename/refactor into an execution engine or fold its responsibilities into one durable orchestration authority. Preserve its model/runtime behavior and cancellation semantics |
| `lib/domain/kernel/agent_kernel.dart` | SQLite-backed FIFO scheduler with injected executor | Has no cancellation, deadline, lease, step/checkpoint model or typed tool outcomes; catches execution/persistence errors in a way that can obscure a failed state transition | Promote this implementation as the queue/admission owner only after hardening. Keep model execution behind an injected adapter. Never swallow a failed persistence transition as if the request completed |
| `lib/domain/kernel/agent_kernel_store.dart` | SQLite request records and append-only request event journal | Schema is v1; request-level events only; no run/step/tool execution/checkpoint/idempotency tables; attempts is set to 1 rather than incremented | Add versioned migrations and normalized run, step, execution, checkpoint and approval records. Keep event journal append-only and correlate every event with request/run/step/execution IDs |
| `lib/agent/task_manager.dart` | SharedPreferences task list; one synthetic step; pause/resume wrapper | Duplicates persistence and lifecycle state; uses timestamp-derived IDs; resume reruns the full prompt with a text note rather than restoring a verified checkpoint | Replace with a compatibility facade over the durable store, then migrate existing `giant_agent.tasks.v1` data before retiring the preference key. Do not maintain two authoritative task states |
| `lib/agent/architecture/agent_timeline_event.dart` | Serializable user-safe event model | Good privacy boundary, but envelope lacks schema version, run/step/execution IDs, sequence and durable replay metadata | Extend/version the event contract and map persisted events into this presentation-safe type |
| `lib/services/planner_service.dart` | Rule-based task classification and fixed plan templates | Useful heuristic, not a dynamic planner; plan is not persisted as executable step state | Keep simple requests direct. For multi-step tasks persist a validated plan, dependency graph, step status, attempt count and evidence references. Model-proposed updates must pass validation |
| `lib/services/agent_memory_service.dart` | SQLite conversation turns and explicit facts | Conversation memory is not task state; it cannot prove which side effects already happened | Keep it separate. Task checkpoints and tool execution records belong to the task store; memory must not be used as the source of truth for recovery |
| `lib/services/model_service.dart` | Shared model/provider runtime, context and tool execution | Must remain the single inference/tool-execution adapter; do not instantiate a second local model as part of the durable queue | Expose a narrow executor interface to the durable kernel. Return typed outcomes/evidence rather than forcing orchestration to infer status from response-string prefixes |
| `lib/screens/chat_screen.dart` | Starts requests, receives transient events, stores UI events and calls TaskManager | Orchestrates task lifecycle at the presentation layer; creates a second task record around AgentService; in-memory Timeline list is not sufficient for restart replay | Remove lifecycle ownership from the widget. Submit once through AgentService; render persisted events by request ID; subscribe for live updates and reload the journal after screen/app restart |
| `lib/screens/ai_voice_assistant_screen.dart` (voice PR branch) | Voice input/output UI using AgentService | Should not become a second task scheduler | Keep it as a thin client of the same AgentService API; ensure it receives request ID and persisted task status from the unified path |
| `test/domain/kernel/agent_kernel_test.dart` | Tests durable queue FIFO and restart behavior | Strong starting tests, but test the isolated kernel, not the app composition root | Add integration tests proving AgentService uses the durable store and the same ModelService instance |
| `test/agent/task_manager_recovery_test.dart` | Tests SharedPreferences recovery and status classification | Locks in a parallel lifecycle implementation that should be retired after migration | Replace with migration and compatibility tests; preserve regression coverage for paused/interrupted/failed states |
| `.github/workflows/build.yml` | Runs analyze, unit tests and APK builds | Existing durable-kernel tests run, but no explicit composition/recovery contract suite | Add the new integration, migration, idempotency and recovery tests as required CI gates |

### Additional repository observations

1. The active kernel emits events through a broadcast stream. A listener that attaches late cannot reconstruct the complete event history from that stream alone.
2. The SQLite event table has append-only triggers, which is a useful invariant to retain.
3. The durable store deliberately marks requests found in `running` state after process restart as `interrupted` and does not replay them. This is the correct conservative default for potentially non-idempotent operations.
4. Queued requests are eligible to run after initialization. That behavior needs a documented policy: queued work may be started automatically, but an interrupted in-flight side effect must require reconciliation before retry.
5. The current TaskManager's resume operation re-submits the task prompt plus a textual recovery note. This is not equivalent to restoring completed steps or proving that an earlier terminal/file/network side effect did not already occur.
6. The existing test coverage is valuable and must be preserved. Do not delete the SQLite kernel merely because it is not yet wired into AgentService.

## 4. Target architecture and ownership

There must be one authoritative lifecycle owner:

```text
Chat / Voice / Workspace UI
          |
          v
      AgentService
          |
          v
  Durable Agent Kernel
  - admission / stable IDs
  - FIFO scheduler
  - state machine
  - cancellation / deadlines
  - recovery coordination
          |
          +--------------------+
          |                    |
          v                    v
  Task Store + Event Log   Execution Adapter
  - requests               - existing model runtime
  - runs                   - planner / harness
  - steps                  - typed tool registry
  - tool executions       - existing local/cloud providers
  - checkpoints
  - approvals
          |                    |
          +----------+---------+
                     |
                     v
          persisted evidence/results
                     |
                     v
           Timeline projection
```

### Ownership rules

- **AgentService:** public application facade; the only entry point used by Chat, Voice and other screens.
- **Durable Agent Kernel:** sole owner of request admission, FIFO scheduling, lifecycle transitions, cancellation and recovery decisions.
- **Execution Adapter:** wraps the existing active kernel/model runtime; does not own a second queue or task database.
- **Task Store:** sole source of truth for task/run/step/execution state.
- **Event Journal:** append-only audit history. UI state is a projection of this journal, not the authority.
- **TaskManager:** temporary compatibility adapter only; remove after existing preference records are migrated.
- **Timeline widgets:** read and display persisted state; they never decide task completion.

Do not keep two classes with the same public name. Prefer explicit names such as `DurableAgentKernel` and `AgentExecutionEngine` if the code remains split.

## 5. Data model contract

Use collision-resistant IDs. Timestamps are metadata, not identifiers.

### Request

- `request_id` (UUID)
- `conversation_id`
- `prompt`
- `status`: queued / preparing / running / waiting_for_approval / verifying / completed / failed / cancelled / interrupted / needs_reconciliation
- `sequence` (monotonic FIFO sequence)
- `created_at`, `updated_at`, `started_at`, `finished_at`
- `active_run_id`
- `result_ref` / `error_code`

### Run

A retry creates a new run; it never rewrites the prior run.

- `run_id`, `request_id`, `attempt`
- `status`, `started_at`, `finished_at`
- `model_provider`, `model_id`
- `deadline_at`, `budget_json`

### Step

- `step_id`, `run_id`, `sequence`
- `action_type`, `action_summary`
- `status`: pending / running / waiting_for_approval / completed / failed / interrupted / skipped
- `depends_on_json`
- `attempt_count`
- `input_ref`, `output_ref`, `evidence_refs_json`

### Tool execution

- `execution_id`, `step_id`, `tool_name`
- `operation_key` (stable idempotency key where supported)
- `risk`, `retry_class`: read_only / idempotent / non_idempotent / unknown
- `status`, `started_at`, `finished_at`
- `arguments_redacted_json`, `result_ref`, `exit_code`
- `reconciliation_state`

### Checkpoint

A checkpoint is committed only after the preceding step's result and evidence are durably stored.

- `checkpoint_id`, `run_id`, `after_step_id`
- `completed_step_ids_json`
- `plan_snapshot_json`
- `context_refs_json`
- `created_at`

### Event envelope

Every event must include:

- `event_id`
- `schema_version`
- `request_id`, `run_id`, optional `step_id`, optional `execution_id`
- monotonic per-request `sequence`
- `type`, `status`, `payload_json`
- UTC `created_at`

Events are append-only. A live Stream is only a notification channel; clients must be able to reload events from SQLite.

## 6. Recovery and side-effect safety

The restart policy is deliberately conservative.

| State found at startup | Required behavior |
|---|---|
| queued | eligible for FIFO execution after runtime readiness |
| running model-only step with no tool side effect | mark interrupted; may resume after context reconstruction and policy checks |
| running read-only tool | may retry only if the tool contract guarantees read-only behavior |
| running idempotent tool | retry only with the same enforced operation key |
| running non-idempotent or unknown tool | mark needs_reconciliation; never auto-replay |
| waiting_for_approval | restore pending approval; never infer consent from a prior session |
| completed / failed / cancelled | immutable historical state; new retry creates a new RunId |

A crash can occur after an external side effect but before its result is persisted. This ambiguous window cannot be solved by a prompt saying “do not repeat.” The tool adapter must either enforce idempotency, query/reconcile the external state, or stop and ask the user.

## 7. Implementation phases

### Phase 0 — Integration seam and contract tests (first)

1. Add an integration test around AgentService proving that a submitted request is persisted before execution and appears in the event journal.
2. Introduce a typed executor adapter around the existing active kernel/model runtime.
3. Choose one durable kernel as the lifecycle authority; remove duplicate ownership, not working model/runtime code.
4. Make request IDs flow from UI through AgentService to the store and Timeline.
5. Preserve existing FIFO and interrupted-on-restart tests.

**Exit criteria:** Chat and Voice both use one AgentService path; every accepted request is visible in SQLite; no second TaskManager state is created.

### Phase 1 — Durable steps and Timeline

1. Add schema migrations for runs, steps, executions and checkpoints.
2. Persist each logical step transition and tool invocation before reporting it to the UI.
3. Add stable IDs and sequence numbers.
4. Implement `eventsForRequest` and a Timeline projection that loads history, then subscribes to new events.
5. Keep model-private reasoning out of event payloads.

**Exit criteria:** killing/reopening the app restores the exact persisted task Timeline, including completed and failed steps.

### Phase 2 — Safe recovery and idempotency

1. Add tool retry classifications and operation keys.
2. Reconcile ambiguous in-flight tool executions.
3. Resume from the last verified checkpoint, not by resubmitting the entire task blindly.
4. Add bounded retries, deadlines and cancellation persistence.
5. Add explicit approval restoration for sensitive actions.

**Exit criteria:** a simulated crash at each persistence boundary never duplicates a non-idempotent operation and never marks an incomplete task completed.

### Phase 3 — Dynamic planning and evaluation

1. Persist a validated plan and its dependencies.
2. Allow bounded PlanUpdate actions after observed results.
3. Keep simple requests on the direct path.
4. Build deterministic evaluation scenarios for planning, tool selection, malformed model output, repeated tools, cancellation and recovery.
5. Report task completion only when required evidence exists.

**Exit criteria:** the same scenario produces a valid state transition and evidence-backed result across local and cloud providers.

### Phase 4 — Background execution and Multi-Agent

Only after Phases 0–3 pass:

- lifecycle-aware Android foreground service for user-visible long tasks;
- resource leases and global execution budgets;
- bounded worker pool;
- specialist workers with scoped tools;
- shared task/event store and explicit result review.

Multi-agent is not part of the first durable-task milestone.

## 8. Required test matrix

| Test | Expected assertion |
|---|---|
| concurrent admission | unique IDs and deterministic FIFO sequence |
| duplicate request ID | rejected without losing the original waiter |
| app restart with queued tasks | queued tasks remain ordered and eligible |
| app restart during model-only inference | interrupted state restored; no false completion |
| crash before tool starts | safe retry if no side effect began |
| crash after non-idempotent tool starts | needs_reconciliation; no automatic replay |
| crash after tool result persisted | completed step is not repeated |
| duplicate idempotent operation | adapter enforces the same operation key |
| cancellation while queued | task becomes cancelled without execution |
| cancellation during tool execution | tool outcome is explicit; request not marked completed |
| approval pending at restart | approval remains pending; no implicit consent |
| Timeline opens late | historical events load from SQLite before live subscription |
| event schema migration | old events remain readable |
| persistence failure | request cannot be reported completed |
| local model unavailable | request fails clearly without creating a false success event |
| cloud fallback disabled | no silent upload or provider switch |
| malformed model action | rejected or bounded-repaired; never dispatched as raw shell |
| repeated tool call without progress | bounded stop with incomplete/interrupted status |

## 9. CI and device verification

Required CI gates:

1. `flutter analyze --no-pub`
2. all existing Flutter tests
3. SQLite migration tests from every supported schema version
4. durable-kernel FIFO and recovery tests
5. AgentService composition/integration tests
6. tool idempotency and crash-boundary tests
7. Timeline replay tests
8. APK build and artifact verification

Required Android device tests (not replaced by CI):

- force-stop during model generation;
- force-stop during terminal command;
- reopen and inspect task state;
- verify that terminal side effects are not repeated;
- approve/deny a restored approval request;
- background/foreground lifecycle and notification behavior;
- low-memory process death;
- local GGUF runtime readiness after restoration.

A green build is compilation evidence, not proof of device-level durability.

## 10. Explicit non-goals for this milestone

- No swarm or multi-agent workers.
- No replacement of llama.cpp / ModelService.
- No new provider framework.
- No dynamic plugin execution.
- No terminal architecture rewrite or fake PTY fallback.
- No UI redesign beyond loading persisted task state and rendering its Timeline.
- No automatic replay of ambiguous side effects.

## 11. Go / no-go decision

**GO:** integrate and harden the existing SQLite durable kernel, preserving the active model/runtime and the current approval-gated terminal.

**NO-GO:** merging the current durable queue into the app by simply wrapping `AgentService.runTask` while leaving SharedPreferences TaskManager and transient Timeline as independent authorities.

The first code change should be a small, testable composition-root integration with typed results and stable request IDs. Only after that should the schema and recovery model expand. This minimizes risk and avoids replacing working components unnecessarily.
