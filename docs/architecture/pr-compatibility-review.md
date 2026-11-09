# PR #1 / PR #3 Compatibility Review — Runtime Architecture v2

Review baseline: repository `almwld/giant-agent`, default branch `main`, architecture reference `docs/architecture/agent-platform-v2.md`.

## Pull request snapshots

| PR | Head | Scope | GitHub merge state at review | Decision |
|---|---|---:|---|---|
| #1 — harden ReAct execution and decision protocol | `feat/chatgpt-experience-foundation` | 31 files, 2,759 additions, 337 deletions, 68 commits | Open, Draft, dirty / not mergeable | Reuse selected protocol and gateway ideas only; do not merge wholesale |
| #3 — integrate agent runtime, workflow, workspace and local services | `feat/integrated-agent-completion` | 84 files, 7,888 additions, 3,003 deletions, 343 commits | Open, non-draft, clean / mergeable | Reuse selected runtime and UI work after file-level validation; do not merge wholesale |

These are live snapshots from the review; GitHub state may change.

## Compatibility matrix

| Component | PR #1 | PR #3 | Compatible with v2? | Decision |
|---|---|---|---|---|
| FIFO admission | No durable kernel queue identified; conversation controller serializes its own generation path | Adds `FifoTaskQueue` and `AgentKernel` | Partially. Queue is in-memory, so queued requests disappear on process death | Rebuild as SQLite-backed durable admission queue |
| Request lifecycle | Conversation/message statuses and cancellation | Typed request/response and lifecycle states | Useful concepts, but not the full persisted request state machine | Reuse state vocabulary; implement persistence and recovery explicitly |
| Append-only event journal | SQLite is for conversations/messages, not a proven append-only execution journal | Broadcast timeline events; no durable append-only journal demonstrated | No | Implement separate SQLite event journal with immutable event rows |
| Tool registry | Adds a small typed ReAct registry (calculator/time) | Modifies existing ToolManager and adds registry tests | Partially. Contracts/risk/approval/idempotency are not at v2 level | Retain only real tool handlers; rebuild registry contracts around v2 |
| ReAct / structured decisions | Strongest reusable piece: bounded strict JSON action protocol, schema checks, duplicate-action guard and regression tests | Existing local orchestration and bounded tool loop; no reason to replace with PR #1 wholesale | Partially | Port the validated decision parser/contract into DSH Harness after kernel and provider boundaries exist |
| Model gateway | Adds authenticated streaming gateway and provider abstraction; local inference remains an interface, not a concrete engine | Preserves shared local GGUF runtime and adds OpenRouter service | Partially | Keep Giant Agent's single shared local runtime; adapt provider selection behind one gateway contract |
| SQLite persistence | Conversation/message persistence | Agent memory plus persistent task history via SharedPreferences | Not sufficient for durable kernel scheduling/event sourcing | Keep conversation DB if useful; do not mistake it for kernel journal |
| Recovery | Chat cancellation/retry; not durable job recovery | Task history recovers interrupted work as paused/resumable; writes serialized | Partial. Task history is not an atomic queue + event journal; replay policy needs per-tool idempotency | Reuse paused/resumable UX concept; rebuild reconciliation in the kernel |
| Foreground service | No complete Android long-running task guarantee | Existing background/notification integrations, with device validation outstanding | Not proven as a durable execution host | Inspect and adapt only after persistent kernel is stable |
| Zion native PTY | No Zion PTY integration | No Zion PTY integration | No | Port the required native PTY runtime from Zion into isolated Gain bridge files |
| xterm | Existing dependency / no need to add again | Existing dependency / no need to add again | Yes, dependency already exists on main | Reuse existing dependency; no duplicate addition |
| UI / workflow | Adds assistant feature foundation, separate from existing app route | Adds workflow UI and broad app changes | Mixed; large unrelated UI and behavior changes | Cherry-pick only after visual and route regression review |

## Key findings

1. PR #3 contains the closest starting point for the kernel: `lib/agent/architecture/agent_kernel.dart` and `fifo_task_queue.dart`. However, its FIFO queue is process-memory only. It is not the durable SQLite queue required by v2 and must not be accepted as satisfying the persistence criterion.
2. PR #3's `AgentKernel` delegates execution to existing `ModelService` / `PlannerService`; it is not yet the provider-independent DSH Harness described by v2. Reuse lifecycle/event vocabulary and carefully selected cancellation behavior, not the whole implementation.
3. PR #1's `ReActAgentProvider` is a useful source for strict structured action parsing, argument validation, bounded tool calls and duplicate-action prevention. Its conversation database does not implement the kernel event journal.
4. The kernel reserves request IDs before asynchronous database lookups to prevent concurrent duplicate submissions from overwriting completion waiters. Tests cover FIFO execution, restart restoration, interrupted-request non-replay and duplicate-ID rejection.
5. Neither PR provides Zion PTY. Zion's current native PTY implementation is integrated into a very large `MainActivity.kt`, a JNI C implementation, and a Dart adapter. Copying the entire Zion `MainActivity` or its full terminal feature would import unrelated app-specific features, Termux/Kali setup, package identity assumptions and permissions.
6. Gain extracts only the PTY lifecycle into `gain_pty.c`, adds an isolated `GainPtyBridge.kt`, and provides `GainPtyClient` / `GainTerminalTool`. The native launch contract is deliberately restricted to Android `/system/bin/sh`; the native implementation contains no Zion app paths, Userland filesystem, PRoot, Kali or root execution. Zion OS itself remains untouched.
7. The current Giant Agent main branch has no `lib/agent/architecture/AgentKernel` or durable kernel queue. It has a legacy `ToolManager` with simulated handlers; those handlers must not be promoted to production tools just because a registry entry exists.

## Implementation order

- **Phase 1:** implement SQLite-backed request admission, append-only event journal, recovery reconciliation and deterministic FIFO tests. A request left in `running` after process death must become `interrupted/needs_reconciliation`, not be blindly replayed.
- **Phase 2 (isolated shell port):** build the native PTY engine around Android `/system/bin/sh` only; test the incremental completion-marker parser, exit codes and bounded output; validate JNI signatures and Kotlin/Dart channel contracts. Keep one process-owned PTY session; subscribe before command writes; expose cancellation, timeout, exit code and session-loss distinctly. Physical-device execution remains required.
- **Phase 3:** add GainTerminalTool to the v2 tool contracts and connect it to the DSH Harness.
- **Phase 4:** connect the existing xterm package to durable timeline projections and live PTY output.
- **Phase 5:** approval policy, bounded output artifacts, watchdog and device verification.

## Explicit non-goals for this review

- Do not merge either PR wholesale.
- Do not modify the Zion OS repository.
- Do not add xterm again.
- Do not claim Android background survival, PTY reliability or production readiness without real-device tests.
- Do not auto-replay shell commands after process death unless their execution state is proven and their effects are idempotent.
