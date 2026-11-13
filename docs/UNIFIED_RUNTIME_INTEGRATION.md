# Unified Runtime Integration — Preservation Ledger

**Working branch:** `integration/unified-agent-runtime-v2`  
**Starting point:** `7355b5c45547132860c6b9212b15fe4266d2c3e9` (PR #55 head at the start of this integration increment)  
**Policy:** integration and ownership consolidation only. No existing feature, source file, schema, model, provider, workflow, or user-data store is deleted as part of this work.

## 1. Canonical application execution path

```text
Chat / Home / Nuclear / Voice / Workflow UI
                    |
                    v
       TaskManager (durable user task wrapper)
                    |
                    v
          AgentService.instance
          (application-facing facade)
                    |
          +---------+----------+
          |                    |
          v                    v
 durable AgentKernel       AgentKernel (execution)
 SQLite FIFO/admission     planner, lifecycle,
 request recovery          request cancellation
          |                    |
          +---------+----------+
                    |
                    v
           ModelService (singleton)
                    |
          +---------+------------------------------+
          |                 |                      |
          v                 v                      v
 LlamaService (singleton) OpenRouter provider   Context + memory
          |                 |                 AgentMemoryService
          +-----------------+                      |
                    |                              v
                    +----------------------> ToolManager
                                               (canonical catalogue
                                                and allow-list)
                                                     |
                    +--------------------------------+----------------+
                    |              |          |       |                |
                    v              v          v       v                v
                 Gain PTY        Python     Browser   MCP          Media providers
                 approval       sandbox    session  Streamable     capability
                 + JNI          + REPL      tools    HTTP           registry
                    |
                    v
              Native workspace

Factual events from execution/tools/subagents
                    |
                    v
              AgentEventBus
                    |
                    v
     AgentService serialized journal subscriber
                    |
                    v
 AgentKernelStore / SQLite append-only event journal
          |                |                 |
          v                v                 v
   request replay     observability      recovery
                      + diagnostics
```

The two kernel classes are deliberately distinguished by responsibility: the durable kernel owns admission, FIFO order and restart reconciliation; the execution kernel owns model/tool execution and its active cancellation state. They are not permission to create a second model runtime. Both must continue to use the one `ModelService` and one `LlamaService.instance`.

## 2. Consolidation performed in this integration branch

- Added conversation-scoped observability query methods to `AgentService`, backed by its existing `AgentKernelStore`.
- Changed `AgentObservabilityScreen` to read through `AgentService.instance` instead of constructing and closing a second store connection itself.
- Bound `ModelService` dynamic subagent persistence to the exact `AgentKernelStore` instance owned by production `AgentService`; the injected-executor seam remains isolated for tests.
- Added durable detached child admission via `spawn_subagent(run_in_background: true)`. It appends to the existing execution-kernel FIFO, runs only after the parent releases the shared model runtime, and does not introduce a second queue or inference instance.
- Pending async children that have not started are re-enqueued after restart; children interrupted after execution began remain subject to explicit side-effect-aware recovery.
- Kept the underlying SQLite schema, append-only event journal, pagination, filters, counters and event payloads unchanged. This is an ownership/facade consolidation, not a data migration.
- The chat workflow continues to use `AgentService`; Home and Nuclear continue through `TaskManager`, whose execution step calls the same `AgentService.runTask`. Their legacy chat transcript database is separate from agent memory and is not deleted or silently migrated.

## 3. Existing systems and ownership map

| Capability | Existing implementation / owner | Integration rule |
|---|---|---|
| Application request boundary | `AgentService` | All UI task execution must enter here. |
| Durable FIFO, request state, restart reconciliation | `lib/domain/kernel/agent_kernel.dart`, `AgentKernelStore` | One durable request queue/store; never add another database. Detached child admission is serialized by the existing execution-kernel FIFO, not a second competing queue. |
| Execution planning and model loop | `lib/agent/architecture/agent_kernel.dart` | Retain planner, bounded tool loop, cancellation and lifecycle behavior. |
| Local inference | `ModelService` + `LlamaService.instance` + JNI | One shared local model/runtime. |
| Cloud inference and SSE | Existing OpenRouter/provider adapter and SSE parser | Keep provider routing in the same ModelService path; do not add a second chat controller/runtime. |
| Tool definitions and allow-list | `ToolManager` | Single canonical catalogue; platform dispatch remains in ModelService. |
| Per-tool identity/cancellation | `ToolCallRegistry` and request-scoped cancellation paths | Preserve independent `tool_call_id`; never cancel the shared model as a side effect of cancelling one tool. |
| MCP | `McpClient`, typed `McpToolResult` | Reuse one MCP client/session cache; preserve text, media, resource links, structured content, metadata and errors. |
| Terminal | `GainPtyClient`, `GainTerminalTool`, `TerminalToolCoordinator`, Android JNI/bridge | One PTY owner, approval gate, scoped cancellation and output parser. |
| Python | `PythonExecutor`, restricted sandbox and chat-scoped REPL | Preserve both one-shot execution and persistent REPL; neither is represented as an OS/container sandbox. |
| Browser | `BrowserSessionService` | One visible session/controller; preserve approval for mutating/sensitive fields and URL restrictions. |
| Media | `MediaProviderRegistry` and adapters | Keep capability adapters. A registered capability is not proof that a real provider is connected. |
| Memory used by the active model path | `AgentMemoryService` | Sole active memory service for turns, facts, edits, workspace versions and recall. |
| Legacy memory stores | `MemoryService`, `LongTermMemory`, `ConversationMemory` | Retain files and databases. Do not delete or merge without an explicit data migration, backup and compatibility tests. |
| Skills | `AgentSkillRegistry` | Prompt/routing hints only; skills must not grant permissions or bypass ToolManager. |
| Durable task UI/history | `TaskManager` + `AgentKernelStore` | Task snapshots and request journal stay correlated by conversation/request IDs. |
| Output verification | `OutputEngine` | Preserve artifact collection/finalization; a model response alone is not verified completion. Detached child artifact finalization remains a follow-up integration detail before declaring parent output coverage complete. |
| Event bus and timeline | `AgentEventBus`, typed `AgentTimelineEvent`, `AgentKernelStore` | One factual event stream and one durable journal. No private chain-of-thought is stored. |
| Local diagnostics | `AgentObservabilityScreen` via `AgentService` | Read-only projection of the same store used by execution. |
| Android long-running lifecycle | `AgentBackgroundExecutionService`, native `AgentRuntime` | Reuse shared runtime; verify process-death/background behavior on device. |
| Offline Arabic voice | Whisper ASR, Nabra TTS, shared chat/runtime | Preserve local-only policy and current half-duplex limitation until VAD/AEC is implemented and tested. |

## 4. Multiple databases are not automatically duplicates

The repository has separate persistence domains with different data contracts:

- Agent request/event/task/subagent/output journal in `AgentKernelStore`.
- Conversation turns, facts, memory edits and workspace versions in `AgentMemoryService`.
- Legacy memory databases in the three retained legacy memory classes.
- Home/Nuclear legacy transcript storage in `DatabaseService`.
- MCP server configuration and credentials in secure storage.
- Custom skill definitions in preferences.

Do not combine these stores by renaming tables or deleting classes. Any consolidation requires versioned migrations, idempotent import, rollback, backup, and tests proving old records remain readable.

## 5. Open PRs and isolated branches — preservation / porting ledger

The repository has several independent histories. A branch being present is not proof it is safe to merge wholesale. The following is the current inventory of open work discovered during this integration pass.

| PR | Scope | Decision |
|---:|---|---|
| #56 | Searchable Gain Agents timeline; stacked directly on #55 | Adds parameterized local event search through the existing durable journal and AgentService facade; preserves stable cursor pagination and type/status filters. Current CI is required. |
| #55 | Local Arabic Whisper/Nabra voice path; currently the base of this integration branch | Preserve in full. Keep open; do not merge automatically. |
| #53 | Native Gain Agents observability journal | Already included in PR #55 ancestry. Preserve as dependency until its own review/merge decision. |
| #54 | CI verification of native Gain observability | Verification-only branch; retain its useful workflow evidence, avoid duplicating implementation. |
| #36 | Separate production Timeline engine, second timeline SQLite database, advanced timeline widget, cancellation-token proposal | Do not merge wholesale: it is 1,025 commits behind/diverged from current main and introduces a parallel timeline store. Port useful filters, progress projection and interaction into the existing event journal/UI without losing existing event contracts. |
| #27 | Android launch/black-screen fix | Old divergent base. Inspect its manifest/styles/main changes against current Android lifecycle before selectively porting. |
| #32 | Codemagic release workflow | Old divergent base. Review signing/secrets/Flutter versions and port only a validated workflow; do not overwrite current GitHub Actions release path. |
| #1 | Separate ChatGPT-style assistant foundation, React provider, gateway and assistant database | Old divergent base and parallel chat/provider architecture. Preserve as source material; port only unique validated protocol/security capabilities through current AgentService/ModelService contracts. |
| #5 | Enterprise runtime architecture specification | Documentation-only target contract. Keep as reference; reconcile with actual code rather than treating all target boxes as implemented. |
| #8 | Durable task-engine review/specification | Documentation-only, old replay lineage. Its historical gap is superseded in part by the current AgentService → durable-kernel composition; retain the review as provenance and update status against current code. |
| #24 | Gain PTY Android emulator smoke workflow | Old integration lineage. Preserve the test design and port onto the current release workflow after validating emulator/runtime compatibility. |
| #17 | Chat bubble sizing/toasts | Independent UI work; retain and reconcile against current chat/voice layout. |
| #12 | Sehatak brand identity | Independent UI/design work; retain and reconcile rather than silently discard. |

Other closed PRs already represented in the current lineage include Kimi subagent orchestration, dynamic subagent lifecycle, Mylib transfer, MCP typed results/tool-call IDs/SSE, cancellation isolation for browser/MCP/Python/media/terminal, Hermes-style memory retrieval/skills, and SQLite task recovery. Their files and tests remain part of the current branch; no replacement is authorized.

## 6. Timeline PR #36: features to preserve while avoiding duplicate infrastructure

The following capabilities are valuable and must not be lost:
- Searchable and filterable event views by type/status.
- Progress normalization and progress indicators.
- Stable event ordering and clear terminal-state behavior.
- Per-tool cancellation with an independent invocation token and explicit reason.
- Event details, metadata and duration display.
- Session isolation and persistence/replay.

The implementation target is the existing `AgentEventBus` + `AgentKernelStore` journal and current workflow/observability screens. Do not add `giant_agent_timeline.db` as a second source of truth or replace the existing typed event and request correlation model.

## 7. Required integration gates

1. Audit every app entry point and prove it reaches `AgentService` or an explicitly documented non-agent utility path.
2. Trace each ToolManager definition to exactly one dispatcher and a real handler or an explicit unavailable-provider result.
3. Verify request/session/task/step/tool-call correlation across event bus, durable journal, UI replay and cancellation.
4. Verify MCP typed results, approvals, pagination, session invalidation and per-call cancellation.
5. Verify terminal/Python/browser/media adapters share the existing request cancellation and approval contracts.
6. Verify local and cloud provider selection through one model service, with no parallel runtime.
7. Verify memory reads/writes and legacy stores by reference audit; preserve all databases until a safe migration is proven.
8. Verify skills are discoverable and injected without becoming an authorization mechanism.
9. Verify task/subagent recovery never silently repeats uncertain side effects.
10. Run analyzer, all Flutter tests, Python tests, all Android ABI builds, artifact verification and current-head CI.
11. Run device checks for model import/load, local inference, cloud streaming, MCP, PTY, workspace, process restart, microphone, ASR/TTS, thermal and battery behavior.

## 8. Evidence policy

A source file or UI control is not proof of a working feature. Each row must be marked separately as code-inspected, unit-tested, integration-tested, CI-built, or device-verified. Unknown provider credentials, missing external services, unsupported hardware and untested device behavior must remain explicit blockers—not be replaced with stubs or success claims.


## 9. Dormant and overlapping service inventory (reference audit)

A repository code-search pass on the current mainline found these components without active call sites beyond their own definitions, or with a separate active sibling. They are retained intentionally; this is a wiring backlog, not authorization to delete them.

| Component | Search evidence | Current disposition |
|---|---|---|
| `MemoryService` | Constructor search returned only its class definition. | Dormant legacy memory store; preserve its database and source until migration/backup plan exists. |
| `LongTermMemory` | Constructor search returned only its class definition. | Dormant legacy store; inspect schema/data before any consolidation. |
| `ConversationMemory` | Constructor search returned only its class definition; active chat memory calls `AgentMemoryService`. | Dormant legacy store; preserve. |
| `StatsService` | Constructor search returned only its class definition. | Unwired statistics implementation; compare its contract with active `StatisticsService` before connecting. |
| `StatisticsService` | Used by `StatisticsCard`. | Current widget-facing statistics path; verify data source and accuracy. |
| `PerformanceService` | Constructor search returned only its class definition. | Dormant performance/cache service; do not assume it feeds the active dashboard. |
| `PerformanceMonitor` | Used by `PerformanceDashboard`. | Current dashboard-facing in-memory measurement path; inspect persistence and instrumentation coverage. |
| `AnalyticsService` | Constructor search returned only its class definition. | Unwired analytics implementation; keep local/privacy policy explicit before activation. |
| `ModelRunner` and `RealModelRunner` | Both wrappers resolve `ModelService()`; their call sites require a separate usage audit. | Do not treat them as separate inference runtimes; verify whether either wrapper is still needed and keep both source files until proven safe to retire. |

This search is against the repository default branch and is not a substitute for a full symbol/reference scan of every PR head. The current integration branch must repeat the reference audit before any component is reclassified as unused.

## 10. Immediate follow-up implementation queue

- [x] Port text search from the useful PR #36 Timeline interaction set onto the existing durable event query contract, with parameterized local SQL, debounced UI input and regression coverage. Keep one SQLite journal.
- [ ] Port normalized progress, duration details and explicit per-tool cancellation affordances from PR #36 onto the existing event journal/UI; do not import its parallel timeline database.
- Trace every `ToolManager` definition to its switch/handler in `ModelService`; classify unsupported media providers and other missing external capabilities visibly instead of presenting adapters as connected services.
- Audit all entry points for direct `ModelService.processChat` use. Keep it only for explicitly simple conversational paths; all autonomous/tool-capable tasks must go through `AgentService.runTask`.
- Review the overlapping statistics/performance services and connect their useful metrics to one source of truth without losing current widget contracts.
- Review the dormant memory stores and the legacy transcript database with data-preserving migrations; do not delete, rename or overwrite any of them.
- Port validated Android launch and emulator smoke fixes from PRs #27 and #24, and validate the Codemagic workflow from PR #32 as an additional CI path rather than a replacement.


## 11. Current integration increment — PR #56

- Working branch: `integration/unified-agent-runtime-v2`, based on the current PR #55 head.
- PR #56 adds case-insensitive search across the existing persisted event metadata, exposed through `AgentService.observabilityEventsForConversation`.
- The screen debounces search input and retains the existing event-type/status filters and row-id cursor pagination.
- Search is local to the current conversation query; the query is parameterized and does not add a new persistence store or event payload.
- Added regression assertions for case-insensitive matching and conversation isolation.
- CI workflows now include the stacked integration branch and PR base so this branch receives tests and Android build validation.
- No existing runtime, model, database, source file, provider or workflow was removed.
- Remaining PR #36 interactions are progress normalization, duration details and explicit per-tool cancellation UI; these must use the existing event and cancellation owners.
