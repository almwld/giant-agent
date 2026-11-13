# Giant Agent — Enterprise Agent Runtime Architecture (v2)

**Status:** Architecture baseline / implementation contract  
**Target branch:** `main` (delivered through an isolated documentation branch)  
**Scope:** Flutter + Android agent runtime, local/cloud inference, tool execution, Zion native PTY integration, durable orchestration, safety, recovery and observability.

> This document defines the target architecture and its acceptance contracts. It does not claim that every component is already implemented. Implementation status must be established from code, tests and device-level evidence—not from this document or a successful APK build alone.

---

## 1. Architecture objectives and non-negotiable principles

Giant Agent is an execution system, not a chat screen with tool buttons. It must be able to plan, execute, inspect evidence, recover safely, and deliver verifiable results.

### Product objectives

1. Multi-step autonomous task execution with bounded planning and explicit completion verification.
2. Provider independence: local GGUF/llama.cpp and cloud providers behind one model contract.
3. Real terminal execution through Zion's native PTY/Userland integration—not a simulated terminal and not `Process.start`.
4. Durable FIFO scheduling, resumable task state, and an append-only event history.
5. Human approval for consequential actions, with auditable decisions.
6. Live, replayable Timeline: one stable step per logical action, incrementally updated.
7. Context-aware execution for small local models and large tool outputs.
8. Android lifecycle-aware background operation, cancellation and crash recovery.
9. Explicit boundaries between model output, trusted orchestration, tools, storage and UI.

### Engineering invariants

- The model never receives direct access to platform channels, filesystem APIs, shell handles, secrets or database writes.
- The Kernel is the sole authority for task admission, scheduling, cancellation and state transitions.
- The Harness is the sole authority for interpreting model actions and deciding whether a tool call is valid.
- Every tool call has a unique `executionId`, a parent `requestId`, and a stable `stepId`.
- Every event is correlated, timestamped, versioned and persisted before it is considered committed.
- UI state is a projection of persisted domain state; widgets are not the source of truth.
- Tool results distinguish success, failure, timeout, cancellation, denial and interruption. These states must never be collapsed into plain strings.
- A process restart must not silently replay a non-idempotent or potentially destructive action.
- No automatic retry may duplicate a side effect unless the tool declares and enforces idempotency.
- A successful build proves compilation only. Production readiness requires contract, integration, security and device tests.

---

## 2. Logical system topology

```text
 Flutter Presentation
 ├── Chat Composer / Session Browser
 ├── Task Timeline (projection, replayable)
 ├── Terminal Surface (xterm, read-only output by default)
 ├── Approval / Permission Cards
 └── Runtime & Provider Settings
              │ typed application commands / view state
              ▼
 Application Facade
 ├── AgentController
 ├── SessionController
 └── TimelineProjection
              │
              ▼
 Agent Kernel (single orchestration authority)
 ├── Admission & validation
 ├── Durable FIFO scheduler
 ├── Concurrency/resource leases
 ├── Cancellation & deadlines
 ├── Recovery coordinator
 └── Request state machine
              │
              ▼
 DSH Harness (bounded agent loop)
 ├── Context assembler
 ├── Planner / action decoder
 ├── Policy decision point
 ├── Tool dispatcher
 ├── Observation normalizer
 ├── Retry / repair controller
 └── Completion verifier
       │              │                 │
       ▼              ▼                 ▼
 Model Gateway     Tool Runtime      Memory Gateway
 ├─ Local          ├─ Zion PTY        ├─ Session memory
 ├─ Cloud          ├─ Python          ├─ Project index
 ├─ Router         ├─ Workspace       └─ User-approved
 └─ Protocol       ├─ Git             long-term facts
    adapters       └─ Search
       │              │
       └──────┬───────┘
              ▼
 Durable Platform Services
 ├── SQLite transactional store + migrations
 ├── Append-only event journal
 ├── Artifact / output store
 ├── Secret store (Android Keystore-backed)
 ├── Audit / telemetry
 └── Recovery checkpoints
              │
              ▼
 Android Runtime Boundary
 ├── Zion PTY Bridge (MethodChannel + EventChannel)
 ├── Native PTY/JNI session adapter
 ├── Foreground service (user-visible long task only)
 └── Lifecycle / notification / permission adapter
```

The topology is logical. It does not prescribe one class per box; classes may be consolidated where the current repository requires it, provided the contracts and dependency directions remain intact.

---

## 3. Dependency direction and module boundaries

Use a ports-and-adapters (hexagonal) design.

- **Domain:** immutable IDs, task state, action/result types, policies and state transition rules. No Flutter, Android, SQLite or provider imports.
- **Application:** Kernel, Harness, use cases, schedulers and orchestration ports. Depends on Domain only.
- **Infrastructure:** SQLite, model adapters, platform channels, file access, Python runtime, notifications and network clients. Implements Application ports.
- **Presentation:** Flutter screens and widgets. Calls application commands and observes projections; it never executes tools directly.

Forbidden dependency directions:

- UI → MethodChannel / shell / raw database.
- Model adapter → Tool implementation.
- Tool → Kernel internals.
- Android service → Flutter widget state.
- Timeline widget → mutable execution buffer as its only copy.
- Memory service → unrestricted access to secrets or arbitrary external account data.

Use dependency injection at the composition root. Keep a single owner for each native PTY session and each active request.

---

## 4. Core domain model and identity

Use strongly typed identifiers (UUID v4 or another collision-resistant scheme):

- `SessionId`: conversation/task workspace.
- `RequestId`: one user-submitted task.
- `RunId`: one execution attempt of a request.
- `StepId`: stable Timeline step across streaming updates.
- `ExecutionId`: one tool invocation, including one terminal command.
- `ApprovalId`: one approval challenge.
- `EventId`: globally unique journal event.
- `ArtifactId`: persisted file/output artifact.

Do not use millisecond timestamps as IDs. Timestamps are metadata, not identity.

### Request lifecycle

```text
accepted → queued → preparing → running
                         │         │
                         │         ├── waiting_for_tool → running
                         │         ├── waiting_for_approval → running
                         │         ├── recovering → running
                         │         └── verifying
                         └───────────────────────────────
running/verifying → completed | failed | cancelled | interrupted
```

Terminal states are immutable. A retry creates a new `RunId` linked to the same request; it does not rewrite a completed or failed run.

### Step lifecycle

`created → running → completed | failed | cancelled | waiting_for_approval | interrupted`

Streaming output updates the existing step by `StepId`; it must not create a new Timeline row for every chunk.

---

## 5. Agent Kernel: durable scheduling and resource control

The Kernel owns request admission and execution.

### Responsibilities

- Validate request size, session ownership and runtime availability.
- Persist request and queue position before acknowledging admission.
- Schedule FIFO by default, with explicit priority classes only if product requirements later justify them.
- Enforce a configurable global active-run limit and per-resource locks.
- Prevent simultaneous commands from writing to the same PTY session.
- Support queued cancellation and active cancellation.
- Apply deadlines and resource budgets.
- Coordinate pause/resume/recovery and foreground-service lifecycle.
- Publish state changes through the event journal.

### Queue semantics

- FIFO order is defined by a durable monotonic sequence, not wall-clock ordering.
- One scheduler loop owns dequeue/claim transitions.
- Claiming a request is an atomic database transaction.
- A process-level mutex alone is insufficient; persisted leases protect against duplicate workers after restart.
- Leases have owner IDs, expiry and heartbeat. Expired leases enter recovery, not blind replay.
- Use separate resource locks for the shared PTY, Python runtime, and workspace mutation domain.
- Read-only operations may run concurrently only when their adapters explicitly declare safe concurrency.

### Idempotency

Every admitted request may include a client-generated idempotency key. Every tool invocation records a stable operation key. Tools declare one of:

- `read_only`: safe to retry.
- `idempotent`: repeated execution has the same intended effect.
- `non_idempotent`: must not be replayed automatically.
- `unknown`: treated as non-idempotent.

A crash between side effect and result persistence is an ambiguous outcome. Mark it `interrupted/needs_reconciliation` and inspect state before any retry.

---

## 6. DSH Harness: controlled ReAct execution

The Harness runs a bounded loop. It does not expose private chain-of-thought. Timeline events describe observable actions, tool calls, policy decisions and results only.

### Loop stages

1. **Prepare:** load request, project scope, recent events and memory references.
2. **Plan:** request a structured next action from the selected model.
3. **Decode:** parse a strict action envelope; validate schema and size.
4. **Policy:** check tool existence, argument schema, risk, permissions, budgets and approval requirements.
5. **Execute:** dispatch through the typed Tool Registry.
6. **Observe:** normalize result, persist artifacts, summarize output and append evidence.
7. **Evaluate:** decide whether to continue, ask the user, retry safely, or verify completion.
8. **Finalize:** produce a user-facing result with evidence and artifacts.

### Structured action contract

The provider adapter must normalize model-specific output into a typed union:

- `FinalAnswer(text, evidenceRefs)`
- `ToolCall(name, arguments, rationaleSummary)`
- `AskUser(question, choices?)`
- `PlanUpdate(plan)`

Reject malformed JSON, unknown tools, invalid arguments, oversized payloads and unexpected action types. Parsing repair is bounded (for example, one corrective attempt); never execute free-form shell text merely because it appears in a model response.

### Harness budgets

Enforce independent limits for:

- maximum iterations;
- wall-clock request deadline;
- per-tool deadline;
- model token/context budget;
- tool output bytes;
- total artifact storage;
- retries per tool and per run;
- maximum parallel child actions (default 1 for shared PTY).

The completion verifier must require explicit evidence for tasks that claim a side effect (file created, build produced, test passed, deployment completed). A model assertion alone is not evidence.

---

## 7. Model Gateway: provider-neutral inference

Define a provider contract that supports capabilities, not assumptions.

### Capabilities

- text generation / streaming;
- structured output or constrained JSON where supported;
- tool/action selection;
- cancellation where supported;
- context-window and token-budget reporting;
- model identity and version;
- local model readiness and load state;
- provider error classification.

### Adapters

- Local llama.cpp / GGUF adapter.
- OpenRouter/cloud adapter.
- Future providers behind the same gateway.

The router selects a provider based on explicit user preference, availability, capability requirements, privacy policy and cost policy. It must not silently upload private project contents to a cloud provider. Cloud fallback requires a configured policy and clear user-visible setting.

### Small-model reliability

- Keep tool schemas compact and unambiguous.
- Use deterministic decoding settings for action selection where appropriate.
- Validate every action outside the model.
- Use a planner/executor split only when it measurably improves success; avoid adding model calls for simple tasks.
- Maintain a bounded action history and compact observations.
- Never present internal reasoning traces as user-facing Timeline content.

---

## 8. Tool Runtime and registry

Every tool implements a typed contract:

```dart
abstract interface class AgentTool {
  String get name;
  String get description;
  ToolSchema get inputSchema;
  ToolRisk get risk;
  ToolConcurrency get concurrency;
  ToolRetryPolicy get retryPolicy;

  Future<ToolResult> execute(
    ToolArguments arguments,
    ToolExecutionContext context,
  );
}
```

`ToolExecutionContext` carries immutable correlation IDs, cancellation token, deadline, scoped permissions, artifact store and event sink. It must not expose arbitrary global services.

`ToolResult` is structured:

- status: success / failure / timedOut / cancelled / denied / interrupted;
- typed output payload;
- exit code (when applicable);
- stdout/stderr references;
- artifact references;
- duration and resource usage;
- safe diagnostic code/message;
- retryability and reconciliation requirement.

### Initial tool families

1. Zion terminal.
2. Workspace read/list/create/update with canonical-path containment.
3. Python execution in the existing isolated runtime.
4. Git operations, constrained to the selected workspace.
5. Search/network tools with source attribution.
6. Export/share tools.

Do not ship dynamic executable plugins in the initial production architecture. Later extensions must be signed or explicitly trusted, sandboxed, permission-scoped, versioned and revocable. A model-generated script must never auto-register itself as a trusted tool.

---

## 9. Zion PTY integration contract

Zion is the authoritative terminal environment. Giant Agent owns an adapter, not a fork of Zion's terminal implementation.

### Native boundary

Dart `ZionPtyClient` ↔ Flutter MethodChannel/EventChannel ↔ Kotlin bridge ↔ Zion native PTY/JNI ↔ Zion Userland.

The bridge must be based on the actual Zion PTY API and its lifecycle. Placeholder `ZionPtySession` implementations are not acceptable in production. No shell emulation and no Android `Process.start` fallback.

### Session model

- One managed PTY session per agent terminal workspace unless the underlying Zion API explicitly supports isolated sessions.
- Session state: starting / ready / busy / disconnected / restarting / closed / failed.
- Session creation is independent of EventChannel listener attachment; attaching a UI listener must not unexpectedly create or destroy the native shell.
- Register native event listeners before accepting command writes.
- Keep the native session alive across commands; cleanly close it on explicit shutdown or unrecoverable failure.
- Support terminal dimensions and resize events if the PTY is interactive.
- Keep terminal input separate from agent command execution. Interactive prompts require an explicit interaction mode and UI.

### Event protocol (versioned)

All events include `protocolVersion`, `sessionId`, `executionId` (nullable only for session events), `sequence`, and `timestamp`.

- `session_ready`
- `session_state`
- `command_accepted`
- `command_started`
- `command_output` (stream chunk, channel stdout/stderr, byte/sequence metadata)
- `command_end` (exit code, duration)
- `command_cancelled`
- `command_error`
- `session_lost`
- `session_restarted`

Dart must detect sequence gaps and report stream discontinuity. EventChannel reconnection must replay persisted output/event references where possible; it must not fabricate missing terminal output.

### Sentinel / command completion

Do not rely on a naive `echo "$sentinel$?"` wrapper. The adapter must capture the exit status immediately after the intended command and emit a machine-parseable completion frame. The parser must:

- tolerate arbitrary chunk boundaries, split UTF-8 sequences and ANSI control sequences;
- match the exact active `ExecutionId`;
- avoid treating command output that resembles a sentinel as a valid completion;
- preserve user-visible output while stripping only the protocol frame;
- bound parser memory and retain a rolling tail plus full output in artifact storage;
- handle shell state changes, `set -e`, shell exits, background jobs and interactive commands through an explicit command execution policy.

The implementation must be proven against the real Zion PTY contract before the protocol is declared stable. If a robust native completion callback exists, prefer it over shell-level sentinel injection.

### Cancellation and timeouts

Cancellation is execution-scoped. Send an interrupt to the active process group/PTY command where supported, wait for a bounded acknowledgement, then escalate according to policy. Do not close the entire persistent PTY for every command timeout unless the native runtime requires it. Distinguish command timeout from session loss.

---

## 10. Timeline: durable event projection and terminal surface

The Timeline is a read model derived from persisted events.

### Event envelope

```json
{
  "eventId": "uuid",
  "schemaVersion": 1,
  "sessionId": "uuid",
  "requestId": "uuid",
  "runId": "uuid",
  "stepId": "uuid",
  "executionId": "uuid-or-null",
  "sequence": 42,
  "type": "tool.output",
  "occurredAt": "ISO-8601",
  "payload": {}
}
```

### Projection rules

- One logical action maps to one stable step.
- Output chunks append to the same step/output artifact.
- The event journal is append-only; projections may be rebuilt.
- Late events are ordered by sequence, not arrival time.
- Duplicate events are ignored by `eventId`.
- A step's terminal status is derived from its authoritative completion event.
- UI reconnect rehydrates state from storage, then subscribes to new events.
- Timeline may collapse verbose output while preserving full output access.

### Terminal UI

Use xterm only as a renderer for the real PTY stream, not as the execution engine. The agent output surface should be read-only by default. If interactive input is enabled, it must be a separate, explicitly authorized interaction mode. Preserve ANSI formatting safely; do not allow terminal escape sequences to trigger arbitrary app actions. Support copy, search, scrollback limits, output export and clear-view (without deleting the audit record).

---

## 11. Persistence, event journal and artifacts

Use SQLite with explicit migrations, foreign keys, transactions and WAL where supported.

### Core tables

- `sessions`
- `requests`
- `runs`
- `queue_entries`
- `steps`
- `tool_executions`
- `events`
- `approvals`
- `resource_leases`
- `checkpoints`
- `artifacts`
- `project_memory_records`
- `schema_migrations`

### Storage policy

- Store metadata and event envelopes in SQLite.
- Store large stdout/stderr, generated files and binary outputs as artifacts on disk; store hashes, size, MIME type, safe path and retention metadata in SQLite.
- Never store API keys in event payloads, prompts, logs or artifacts.
- Encrypt sensitive provider credentials using Android Keystore-backed secure storage.
- Use atomic file writes and content hashes for artifacts.
- Apply quotas and retention policies; user-visible deletion must not corrupt active runs.
- Use schema migrations and test upgrades from the last released database version.

### Event commit semantics

Persist the event and update the relevant projection in one transaction where possible. The UI is notified only after commit. A failed write is a runtime fault; do not report a step completed if its authoritative completion event was not durably recorded.

---

## 12. Context and memory architecture

Memory is layered and provenance-aware.

### Session context

Recent user turns, plan state, tool outcomes and unresolved questions. Compact by semantic importance and references, not by blindly keeping the first and last N messages.

### Project memory

A scoped index of the active workspace:

- directory tree (filtered for build/cache/vendor/secret paths);
- file metadata and content hashes;
- selected manifests and project configuration;
- symbol/semantic index when available;
- recent modifications and test/build evidence.

Project indexing is incremental and permission-scoped. Do not send the entire tree or source files to a cloud provider by default.

### Long-term memory

Only stable, useful and policy-appropriate facts. Every memory record has provenance, timestamp, confidence, scope and deletion/update behavior. The agent must not invent project facts when an index is stale; it should re-read the source.

### Output management

Keep complete output in artifact storage. Build a bounded observation for the model using:

- command status and exit code;
- detected error/warning sections with surrounding context;
- first/last lines where useful;
- relevant file paths and test summaries;
- a reference to the full output artifact.

Sanitization must remove secrets and terminal control hazards without destroying diagnostic evidence. The model can request a specific range or search term from the full artifact.

---

## 13. Security model and approval gate

Use defense in depth. A keyword blacklist is not a security boundary.

### Policy decision inputs

- tool identity and declared risk;
- normalized command/arguments;
- workspace scope and canonical paths;
- requested filesystem/network permissions;
- operation impact and reversibility;
- current user policy;
- whether the action is remote or local;
- whether it affects user data or system configuration.

### Risk tiers

- **Read:** bounded listing, reading, inspection. Allowed only within granted scope.
- **Write:** create/update files, install dependencies, modify project state. Require scoped permission; prompt when policy says consequential.
- **Destructive / privileged:** recursive deletion, permission changes, credential access, external publication, deployment, system-level changes. Require explicit per-action approval or deny by policy.

Approval records bind to the exact canonical action, arguments hash, scope, request/run/execution IDs, expiry and user decision. If the action changes after approval, approval is invalid. Never interpret an old approval as blanket authorization.

### Workspace boundary

Resolve canonical paths, reject traversal and symlink escapes, enforce size limits, and validate destination before write. Keep secrets, app-private data and unrelated storage outside the workspace scope.

### Network and secrets

- Use TLS and provider-specific error handling.
- Store API keys in secure storage.
- Redact keys, auth headers, tokens and likely secrets before logs, model context and UI.
- Require explicit policy for uploading project content to cloud inference/search.
- No dynamic code execution from downloaded tools without sandboxing and trust verification.

---

## 14. Fault tolerance, watchdog and recovery

Monitor health independently from output activity. A silent command is not necessarily a dead PTY.

### Health signals

- PTY session state and native heartbeat/health probe.
- Event sequence continuity.
- Python runtime state.
- Model generation progress/deadline.
- Database availability and disk space.
- Foreground service state where applicable.

### Recovery matrix

| Failure | Required behavior |
|---|---|
| UI/widget disposed | Runtime continues if request is admitted; projection reconnects |
| EventChannel detached | Native execution state remains authoritative; reattach/replay |
| PTY command timeout | Cancel that execution, preserve session if healthy |
| PTY session lost | Mark active execution interrupted; restart session; reconcile before retry |
| Model provider timeout | Cancel generation; retry only within policy/budget |
| Python runtime crash | Mark tool interrupted; recreate runtime; do not claim success |
| App process killed | Recover durable requests/leases; reconcile ambiguous side effects |
| SQLite write failure | Stop acknowledging durable progress; surface recoverable storage error |
| Disk quota reached | Stop artifact growth safely and preserve minimal diagnostic metadata |

A watchdog uses missed health probes and explicit native state, not “no output for N seconds”. Recovery actions are rate-limited with backoff and circuit-breaker behavior to avoid restart loops.

---

## 15. Android background execution and lifecycle

The Foreground Service is a lifecycle adapter, not the agent engine itself.

- Start it only for a user-visible, user-initiated long-running task that meets Android foreground-service requirements.
- Show a truthful notification with task progress and a stop action.
- Respect Android version-specific service type and permission requirements.
- Do not promise survival against force-stop, reboot or OS policy termination.
- Persist all resumable state before background transition.
- On service recreation, rehydrate from Kernel storage and reconcile leases.
- UI process death must not erase task state.
- Provide a clear user control to stop the task and release resources.

The native PTY lifecycle must be tested separately: an Android service surviving does not automatically prove the PTY shell survives.

---

## 16. Observability and diagnostics

Use structured, correlated diagnostics.

Every log/metric carries relevant IDs, component, event type, timestamp and severity. Redact secrets and user content by default.

### Key metrics

- queue wait time and active run count;
- request success/failure/cancel/interruption rates;
- model latency, tokens and provider failures;
- tool latency, timeout and retry rates;
- PTY reconnects, sequence gaps and command completion latency;
- approval wait time and denial rate;
- context size and output truncation;
- recovery outcomes and ambiguous side effects;
- storage usage and event journal growth.

Expose a diagnostic export that excludes secrets and allows the user to inspect failures. Do not log private model reasoning.

---

## 17. Testing strategy and release gates

Testing is layered. A green build is necessary, never sufficient.

### Unit tests

- state machines and legal transitions;
- FIFO ordering, durable claims and lease expiry;
- idempotency/reconciliation rules;
- action schema parser and invalid model output;
- risk classification and approval binding;
- output sanitizer and secret redaction;
- Sentinel incremental parser with arbitrary chunk boundaries;
- context compaction and artifact references;
- Timeline projection replay and duplicate event handling.

### Contract tests

- every Tool adapter conforms to the same result and cancellation contract;
- every Model adapter normalizes errors, streaming and action outputs;
- Dart/Kotlin PTY protocol schema and version compatibility;
- database migrations and artifact-store contract.

### Integration tests

- submit two requests and verify FIFO/no overlap;
- execute a real PTY command and capture the actual exit code;
- command output split at every possible sentinel boundary;
- output containing sentinel-like text;
- long-running and silent commands;
- cancellation while output is streaming;
- session loss during execution;
- approval accept/reject/expiry/action mutation;
- create file → read file → verify hash/content;
- large build output → bounded model observation + full artifact;
- app restart → recover state without duplicate side effects;
- Timeline detach/reattach → replay without duplicate rows.

### Device tests

- supported Android versions and target hardware;
- actual Zion PTY/JNI/Userland environment;
- screen rotation, backgrounding and process recreation;
- notification permission and foreground-service behavior;
- low storage, network loss, thermal/memory pressure;
- local GGUF load/unload and cloud provider timeout.

### Release gates

A phase is accepted only when:
1. static analysis and formatting pass;
2. unit and contract tests pass;
3. integration tests pass for the changed boundary;
4. Android build succeeds;
5. device evidence exists for native PTY/background claims;
6. no regression in existing chat, local model, Python or workspace flows;
7. PR review confirms no unscoped permissions, secrets or unsafe retry behavior.

---

## 18. Implementation roadmap (dependency-ordered)

Do not implement all layers in one change. Each phase is a separately reviewable commit/PR with its own tests and acceptance evidence.

### Phase 0 — Baseline and architecture alignment
- Inventory current main and open feature branches.
- Identify existing implementations worth reusing.
- Resolve duplicate services and inconsistent contracts.
- Establish compile/test baseline; record existing failures separately.
- Freeze a single source of truth for IDs, event schema and status enums.

**Exit:** verified repository map, no conflicting ownership of runtime state, baseline recorded.

### Phase 1 — Domain contracts and durable Kernel
- Typed IDs, request/run/step/execution models.
- Durable queue, atomic claim and resource leases.
- Request state machine, cancellation and deadlines.
- SQLite migrations and event journal.

**Exit:** FIFO, restart recovery and no duplicate claims pass automated tests.

### Phase 2 — Native Zion PTY adapter
- Inspect the actual Zion native PTY implementation and API.
- Implement a narrow Kotlin adapter without modifying Zion's source repository.
- Define versioned channels and event contract.
- Session lifecycle, output sequencing, resize and cancellation.

**Exit:** device test proves real shell output and session lifecycle. No mock implementation accepted.

### Phase 3 — Sentinel/completion and Dart terminal tool
- Robust protocol framing/parser or native completion callback.
- Per-execution correlation, stdout/stderr, actual exit status.
- Bounded output capture and artifact persistence.
- Timeout, cancellation and reconciliation.

**Exit:** real success/failure, split chunks, silent command, cancellation and session-loss tests pass.

### Phase 4 — Timeline event projection
- Persisted event-to-step reducer.
- Stable step IDs and live output append.
- Replay, reconnect, output artifact viewer and terminal renderer.

**Exit:** live and replayed Timeline are equivalent; no duplicate steps/chunks.

### Phase 5 — DSH Harness and model gateway
- Strict action protocol and provider normalization.
- Policy gate and tool dispatcher.
- Bounded ReAct loop, observation compaction and completion verifier.

**Exit:** model uses tool result as next observation and completes a verified multi-step task.

### Phase 6 — Safety, context and memory
- Risk policy and approval workflow.
- Secret redaction and output sanitizer.
- Project indexing and provenance-aware memory.

**Exit:** sensitive action cannot run without exact approval; large outputs remain inspectable without flooding context.

### Phase 7 — Recovery and background runtime
- Watchdog, circuit breakers, checkpointing and reconciliation.
- Foreground service lifecycle and notification controls.
- Process-death recovery.

**Exit:** device tests prove safe recovery without blind replay.

### Phase 8 — Hardening and release
- Performance, accessibility, privacy and security review.
- Migration, storage quota and long-session tests.
- End-to-end regression suite and signed release artifact.

**Exit:** all release gates pass and evidence is attached to the release/PR.

### Deferred

Dynamic tool/plugin loading, multi-agent parallel execution, remote workers and automatic code-generated tools are deferred until the single-agent runtime is stable, audited and measurable. They are not prerequisites for a professional first release.

---

## 19. Repository alignment notes (verified against current `main` snapshot)

The current `main` tree contains existing pieces that should be inspected and reused where sound, including:

- `lib/agent/task_manager.dart`
- `lib/services/agent_service.dart`
- `lib/tools/tool_manager.dart`
- `lib/services/database_service.dart`
- `lib/services/conversation_memory.dart`
- `lib/services/long_term_memory.dart`
- `lib/services/llama_service.dart`
- `lib/services/gguf_runner.dart`
- `android/app/src/main/kotlin/com/example/giant_agent/MainActivity.kt`
- `android/app/src/main/kotlin/com/example/giant_agent/AgentForegroundService.kt`

The inspected `main` snapshot already has a foreground-service class, local-model/native integration, Python/workspace channels and xterm dependency. However, the inspected `MainActivity.kt` does **not** expose the Zion PTY MethodChannel/EventChannel contract described above. A foreground-service class existing does not prove durable task execution or recovery. The current tool manager also contains placeholder/simulated tools; these must not be described as production integrations without replacement and tests.

There are open feature PRs in the repository. Before implementation, compare their commits against current `main` and selectively reuse verified changes. Do not merge an entire branch solely because its title suggests completion. This architecture document is intentionally additive and does not merge or close any feature PR.

---

## 20. Definition of done

Giant Agent reaches the target only when an end-to-end, device-verified task demonstrates all of the following:

1. User submits a task; Kernel durably admits and queues it.
2. Harness obtains a structured action from local or cloud model.
3. Policy authorizes or requests exact human approval.
4. Tool Registry invokes the real Zion PTY through the native bridge.
5. Timeline displays the live output in one stable step.
6. Completion protocol returns the actual exit code and durable output artifact.
7. Harness consumes the observation and chooses a valid next action.
8. A completion verifier checks the requested outcome using evidence.
9. Event history and task state survive UI detach and process restart where Android permits.
10. Failure, timeout, cancellation and ambiguous outcomes are represented honestly and never silently reported as success.

**Final product principle:** professional quality comes from explicit contracts, durable state, safe boundaries, observable behavior and reproducible tests—not from the number of architecture classes or the size of the feature list.
