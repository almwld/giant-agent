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
| Recovery | Persistent `TaskManager` records interrupted running tasks as paused | Recovery state is persisted; end-to-end resume behavior still needs dedicated tests and UI verification. |
| Android lifecycle | Shared `AgentRuntime` and foreground service when a local model loads | Local model runtime path is wired; verify behavior under backgrounding, process death, and OpenRouter-only use on-device. |

## 3. Confirmed integration gaps / risks

1. **Tool dispatch boundary:** the canonical `ToolManager` registry now drives both the model prompt catalogue and runtime allow-list; `ModelService` remains the single platform dispatcher. Keep the two contracts synchronized with tests.
2. **Multiple legacy memory stores:** only `AgentMemoryService` is confirmed in the active model request path. The other memory classes must be reference-audited and either migrated or clearly retired; do not delete them blindly.
3. **Planning is heuristic:** `PlannerService` builds predetermined templates from keyword matching. It does not inspect tool capabilities, dynamically revise plans from intermediate results, or verify each step independently beyond response/error classification.
4. **Workflow completeness:** timeline events are truthful emitted lifecycle/tool events. They do not represent hidden model reasoning and should not be described as a complete trace of every internal operation.
5. **Python isolation boundary:** the Python runner itself states it is defense-in-depth, not an OS sandbox. Keep execution restricted and never claim process/container isolation.
6. **External service boundaries:** web search returns snippets; GitHub is read-only; cloud is upload-only. UI labels and agent prompts must continue to communicate those limits.
7. **Android storage permissions:** removed broad `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`, `MANAGE_EXTERNAL_STORAGE`, and `requestLegacyExternalStorage` declarations. Model import and file attachments use Storage Access Framework/content URIs and app-private copies; still verify these flows on supported Android versions.
8. **Automated verification coverage:** tests now cover timeline serialization, planner templates, and the canonical tool registry. Add focused tests for kernel lifecycle/cancellation, memory session isolation, task recovery, native tool path validation, and provider failure behavior.
9. **CI analyzer gate:** the latest preceding run failed because three conversation actions were unused. The actions have now been restored to the overflow menu; the new run must confirm the analyzer and subsequent build stages.

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
- Removed broad external-storage permissions after confirming model import and attachment flows use document/content pickers and app-private storage.
- CI run `41976790710` on commit `54716a43ad1801c01bb492fa0c43b53a97e2789b`: Flutter analysis and unit tests passed; universal APK build was still running at the time of this note. This is not a full CI success or device verification.
