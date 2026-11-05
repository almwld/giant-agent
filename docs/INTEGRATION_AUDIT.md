# Giant Agent X — Integration Architecture Audit

**Audit branch:** `feat/integrated-agent-completion`  
**Audit baseline:** `14b688dda28afbfb3094ac2505cb90220a611d13` (UI follow-up fixes are committed after this baseline)  
**Purpose:** Record the actual integration boundaries and remaining work before declaring the agent complete.

## 1. Current runtime path

```text
ChatScreen
  └─ AgentService.runTask(prompt, conversationId)
      └─ AgentKernel.execute(AgentRequest)
          ├─ admission / lifecycle / cancellation events
          ├─ PlannerService (deterministic rule-based plan)
          └─ ModelService.processInput(...)
              ├─ AgentMemoryService (SQLite, session-scoped turns + global facts)
              ├─ OpenRouterService (optional inference provider)
              └─ LlamaService → Android MethodChannel → shared JNI llama.cpp runtime
                  └─ bounded tool loop → native workspace / embedded Chaquopy Python
      └─ AgentTimelineEvent stream
          └─ ChatScreen persists events per session and publishes them to AgentWorkflowScreen
```

The Flutter `ModelService` and the kernel/service facades use a factory singleton, so they resolve to the same in-process model service. The native `AgentRuntime` also shares one JNI bridge and executor between the Activity and foreground service.

## 2. Integration status by subsystem

| Subsystem | Current implementation | Status / boundary |
|---|---|---|
| Agent Core | `AgentService` facade and singleton `AgentKernel` | Connected to ChatScreen; request admission prevents overlapping kernel requests. |
| Reasoning / Planning | `PlannerService` selects fixed step templates using keyword rules | Connected, but not yet adaptive reasoning or dynamic plan revision. |
| Tool execution | `ToolManager` is now the canonical model-facing catalogue and runtime allow-list; `ModelService._executeTool` performs the platform dispatch for create/read/write file and Python calls | Registry and dispatch are connected; add handler-level contract tests before expanding tools. |
| Workflow / Timeline | Kernel lifecycle events plus native tool events | Persisted in the chat database by session and displayed in the workflow screen. Kernel phase IDs now remain stable across start/terminal updates so completed steps replace their running records. The UI displays emitted events, not every internal model operation or private chain-of-thought. |
| Memory | `AgentMemoryService` SQLite turns scoped by conversation and ranked explicit facts | This is the active memory path. Separate legacy stores (`MemoryService`, `LongTermMemory`, `ConversationMemory`) also exist; verify references/migration before removal. |
| Workspace | Native file operations in app-private `agent_workspace`; Flutter editor and WebView preview | Connected. HTML/JS can be previewed; non-HTML source is shown as code and is not compiled/executed. |
| Local intelligence | llama.cpp JNI through `LlamaService`; embedded Chaquopy Python parser/runner | Local-first path is present. Python AST restrictions are defense-in-depth, not an OS-level sandbox. |
| External inference | Optional OpenRouter provider | Connected as an inference alternative; network request cannot be force-aborted mid-flight, cancellation is observed at safe boundaries. |
| Web search | DuckDuckGo HTML search snippets | Context enrichment only; not a full browser, crawler, or source-verification engine. |
| GitHub | Repository metadata, bounded tree, README context | Read-only. It does not edit files, commit, or push to repositories. |
| Cloud storage | Nextcloud/WebDAV workspace ZIP upload | Upload path only; no restore/download workflow is currently exposed. |
| Recovery | `TaskManager` records task lifecycle for ChatScreen, HomeScreen, NuclearScreen, and document analysis; ChatScreen persists prompt/session/task ID, while Home/Nuclear offer resume/cancel dialogs for paused tasks by conversation scope | Task state and recovery prompts are connected across the three agent entry points; verify process-death flows on-device. |
| Android lifecycle | Shared `AgentRuntime` and foreground service when a local model loads | Local model runtime path is wired; verify behavior under backgrounding, process death, and OpenRouter-only use on-device. |

## 3. Confirmed integration gaps / risks

1. **Tool dispatch boundary:** the canonical `ToolManager` registry now drives both the model prompt catalogue and runtime allow-list; `ModelService` remains the single platform dispatcher. Keep the two contracts synchronized with tests.
2. **Multiple legacy memory stores:** only `AgentMemoryService` is confirmed in the active model request path. The other memory classes must be reference-audited and either migrated or clearly retired; do not delete them blindly.
3. **Planning is heuristic:** `PlannerService` builds predetermined templates from keyword matching. It does not inspect tool capabilities, dynamically revise plans from intermediate results, or verify each step independently beyond response/error classification.
4. **Workflow completeness:** timeline events are truthful emitted lifecycle/tool events. They do not represent hidden model reasoning and should not be described as a complete trace of every internal operation.
5. **Python isolation boundary:** the Python runner itself states it is defense-in-depth, not an OS sandbox. Keep execution restricted and never claim process/container isolation.
6. **External service boundaries:** web search returns snippets; GitHub is read-only; cloud is upload-only. UI labels and agent prompts must continue to communicate those limits.
7. **Android storage permissions:** removed broad `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`, `MANAGE_EXTERNAL_STORAGE`, and `requestLegacyExternalStorage` declarations. Model import and file attachments use Storage Access Framework/content URIs and app-private copies; still verify these flows on supported Android versions.
8. **Automated verification coverage:** tests now cover timeline serialization, planner templates, and the canonical tool registry. Add focused tests for kernel lifecycle/cancellation, memory session isolation, native tool path validation, and provider failure behavior. Verify HomeScreen and NuclearScreen resume/cancel dialogs on-device after process death, including multiple paused tasks and failed resumes. Unit tests verify `TaskManager` restores interrupted task/step states and transitions through running, paused, and completed. Chat and the Home/Nuclear task entry points now use the manager; Home/Nuclear now query paused tasks by conversation and offer resume/cancel; process-death behavior still needs device verification.
9. **CI gate:** the earlier analyzer and memory-fixture failures were corrected. On commit `69842836f0f93a1a26acd1cf8602c3b74dcd9cc2`, Flutter analysis and the complete unit-test step both passed; the four APK builds and artifact checks were still running at the time of this audit refresh.

## 4. Completion gates

Do not mark the integrated agent complete until all of the following are evidenced:

- One authoritative tool registry and one documented runtime dispatch path.
- One active memory implementation with verified per-session isolation and safe migration/retirement of legacy stores.
- Planning and task recovery have deterministic, testable lifecycle contracts.
- Kernel and native events are correctly correlated to the active request and conversation.
- Workspace path validation, file operations, and preview boundaries have automated coverage.
- Local model, OpenRouter, cancellation, and failure paths have explicit tests or reproducible device evidence.
- Excess Android permissions are justified or removed without breaking supported file workflows.
- CI completes analysis, unit tests, all configured APK variants, output verification, and artifact upload.
- A real-device smoke test covers model import/load, prompt/response, tool execution, cancellation, session switching, backgrounding, and workspace export.

## 5. Working rule

Complete and stabilize the current subsystem before expanding the feature surface. Record each change group in a separate commit, and distinguish code inspection, automated CI evidence, and on-device verification in all status reports.


## 6. Progress recorded during this audit

- Restored the overflow-menu actions for conversation history, conversation sharing, and agent information; kept destructive history clearing as a separate action.
- Added the canonical tool registry and made the model prompt catalogue and runtime allow-list derive from it.
- Added registry tests for supported tools and prompt formatting.
- Added a persistent-task recovery test for interrupted process state.
- Removed broad external-storage permissions after confirming model import and attachment flows use document/content pickers and app-private storage.
- CI run `41976790710` on commit `54716a43ad1801c01bb492fa0c43b53a97e2789b`: Flutter analysis and unit tests passed; universal APK build was still running at the time of this note. This is not a full CI success or device verification.

- Connected persistent task lifecycle tracking to the ChatScreen, HomeScreen, and NuclearScreen agent entry points. Chat task and document-analysis recovery now persist a task ID alongside the pending prompt/session.
- Changed `TaskManager` so interrupted/bounded results remain paused instead of being incorrectly marked completed; execution-lock cleanup now covers persistence failures.
- Added conversation-scoped task retrieval and resume/cancel dialogs to HomeScreen and NuclearScreen so paused tasks are no longer orphaned after process death.

- CI run `41977233732` on commit `492d6c09dc45fcf8c20ef012fc60afaf97bc7a27` completed successfully: Flutter analysis, unit tests, universal APK, arm64-v8a, armeabi-v7a, x86_64, checksum verification, and all five artifact uploads passed.
- Subsequent task-lifecycle/recovery integration commits are newer than that green baseline and remain subject to their own CI run and device verification.
- Centralized completed/interrupted/failed result classification in `TaskManager`; ChatScreen and the Home/Nuclear execution path now use the same task outcome contract. Added tests for all three classifications.


## 7. Follow-up verification — 2026-11-05

- The legacy-store reference audit searched the repository for constructor calls to `MemoryService`, `LongTermMemory`, and `ConversationMemory`. Each search returned only its own class definition. They are not referenced by the active app code at this revision. The files are intentionally retained for now: their separate SQLite databases may contain user data, and no migration/retirement path has been implemented.
- The active `AgentMemoryService` remains the only memory implementation used by `ModelService`. Its schema migration now ensures the `facts` table and session index exist for older v1/v2 databases; migration and facts-recovery tests were added.
- Session-recall tests use matching English tokens for the second session. The prior fixture queried Arabic text while expecting an unrelated Arabic phrase from an English-only turn, so the empty context was correct behavior rather than a session-isolation failure.
- Workspace dispatch was inspected end-to-end: the model-facing tool catalogue and runtime allow-list both come from `ToolManager`; `ModelService` validates tool names and argument object shape; Android native handlers enforce app-private workspace containment, reject absolute/traversal paths and symbolic links, restrict file extensions, cap file reads/writes at 1 MB, and prevent create-file overwrite. Workspace export also checks canonical paths and excludes symbolic links.
- Remaining workspace test gap: the Android path policy is currently embedded in `MainActivity`; a dedicated native unit-test seam would improve automated traversal/symlink coverage. Do not weaken or duplicate the native policy merely to make it testable.
- Latest observed CI run for commit `69842836f0f93a1a26acd1cf8602c3b74dcd9cc2` passed parser checks, Flutter analysis, and Flutter unit tests; universal APK packaging was in progress. Full CI and on-device lifecycle verification remain completion gates.
