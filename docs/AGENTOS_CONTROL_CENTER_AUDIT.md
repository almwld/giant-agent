# AgentsOS Control Center — Integration Audit

**Working branch:** `feat/agentsos-control-center`  
**Base:** `integration/unified-agent-runtime-v2`  
**Base commit inspected:** `aebd6c48e4a1ed7bc57d923def57f60e30b744f8`  
**Scope:** map the six supplied AgentsOS screens to existing Giant Agent capabilities before introducing UI or changing application entry points.

## Executive result

The six supplied screen files and `ProTheme` do not currently exist in the inspected integration branch. The repository already contains several real backend capabilities that can power the control center, but it does not contain a ready-made six-screen AgentsOS module. The implementation must therefore be a new presentation layer over existing services, not a replacement runtime.

The default application route is already `ChatScreen` (after the first-launch welcome screen). Preserve that behavior. Do not change `main.dart` to make a dashboard the startup screen.

## Existing capability map

| Supplied screen | Existing source of truth | Audit result / integration boundary |
|---|---|---|
| Dashboard | `AgentService`, `AgentKernelStore`, `AgentObservabilityScreen`, `AgentObservabilitySummary`, `StatsService`, `PerformanceService` | Real request counts, event counts, tool outcomes, latency aggregates and persisted events are available. Do not invent lead volumes, accuracy, uptime or incident counts. |
| Task Manager | `TaskManager`, `AgentKernelStore`, `AgentService` | Durable task snapshots, conversation-scoped retrieval, progress, cancellation and explicit recovery exist. Read from `TaskManager.getTasks()` / `getTasksForConversation()`; do not maintain a second task list. |
| Agent Fleet | `AgentService.subagentsForConversation()`, `subagentStatus()`, `cancelSubagent()`, `resumeSubagent()`, `dismissSubagent()`, `ModelService` lifecycle manager | Durable child-agent snapshots and lifecycle actions exist. Categories, icons and worker presentation metadata must be derived from stored worker roles/metadata; no fabricated fleet metrics. Local inference remains serialized through the shared FIFO. |
| Battle Cards | No competitor intelligence domain/service/source found | This is a new domain, not a skin over current telemetry. Do not present hard-coded competitors, win rates, pricing or ratings as real. Build an honest empty/configuration state until a source/import contract is implemented. |
| Integrations | `McpClient.instance`, `AgentService.mcpServers()`, `addMcpServer()`, `removeMcpServer()`, `refreshMcpTools()`, existing `McpSettingsScreen`; GitHub/browser/cloud services | MCP server configuration, secure bearer-token storage, discovery of tools/resources and endpoint validation exist. MCP is the first real integration provider. Do not claim GitHub/Data Pipelines, Claude/Figma or Slack/Notion are connected unless their actual adapters exist and pass a connection check. |
| Advanced Configuration | `AppPreferences`, `ModelProviderSettings`, `OpenAICompatibleProvider`, `AdvancedSettingsScreen`, `McpClient` | Theme/locale and local-vs-OpenRouter selection have real owners; OpenRouter credentials use secure storage. Generic crawler-rate, expiry and social-network API-key settings have no matching runtime contract and must not be exposed as live controls. |

## Canonical architecture to preserve

- Application task admission: `AgentService.instance`.
- Durable request queue, journal, recovery and projections: one shared `AgentKernelStore`.
- Actual model/tool execution and cancellation: existing execution `AgentKernel` and singleton `ModelService` / `LlamaService`.
- Dynamic child lifecycle: existing `SubagentLifecycleManager` bound to the production store.
- MCP sessions: one `McpClient.instance`; MCP must not own or instantiate inference.
- Timeline and diagnostics: existing `AgentEventBus` → `AgentService` → canonical SQLite journal.
- The six new pages are read/control projections over these owners. No parallel queue, database, event bus, model service, or task manager is permitted.

## Navigation and application entry

- `main.dart` currently selects `ChatScreen` as the normal home route; keep it unchanged.
- `ChatScreen` already exposes workflow, Gain observability, workspace, settings and integration/provider actions.
- Add a single AgentsOS entry from the existing chat navigation/menu, then navigate among the six control-center destinations from that hub.
- Existing Workflow, Workspace, MCP settings, provider configuration and diagnostics screens remain reachable and must not be deleted or silently replaced.

## Source-level issues in the supplied prototypes

1. The supplied `ProAdvancedConfig._buildSlider` reads `context` without receiving it; this does not compile as written.
2. Several screens use constant demo lists and switches whose callbacks do nothing. Those are prototypes, not functional integrations.
3. The Integrations sample labels Claude + Figma but describes Linear; provider identity and description are inconsistent.
4. The supplied integrations count (7 connected / 5 available), competitor win rates, lead counts, accuracy, uptime and processing metrics are unsupported by current persisted sources.
5. The Battle Card page has no competitor data provider or domain model in the inspected repository.
6. Orbitron / ShareTechMono are not declared as bundled fonts in the current `pubspec.yaml`; do not reference missing font assets. Use declared/system monospace fallbacks until fonts are added and licensed assets are checked.
7. The requested grid must be responsive; a fixed two-column grid would overflow on narrow phones. Use width-aware layout or a one-column fallback.
8. API secrets must remain in `FlutterSecureStorage`; never put them in UI state snapshots, logs, timeline events, analytics or plain SharedPreferences.

## Verification observed before this UI branch

For base commit `aebd6c48e4a1ed7bc57d923def57f60e30b744f8`:

- GitHub Actions run `43363062952` — Python parser/REPL tests: **success**.
- The same run — Flutter unit tests: **success**.
- GitHub Actions run `43363057093` — Android APK matrix/build job: **success**.

These are baseline results for the integration branch, not test results for this new AgentsOS branch. No AgentsOS code has been added or tested at the time this audit was written. Physical-device qualification remains separate from CI.

## Implementation sequence and acceptance gates

1. Add a reusable AgentsOS visual system and shared page shell without adding undeclared font assets or dependencies.
2. Add a control-center hub reachable from ChatScreen while keeping ChatScreen the default home.
3. Implement Dashboard, Task Manager and Agent Fleet against the canonical observability/task/subagent APIs, including loading, empty, error, refresh and narrow-screen states.
4. Implement Integrations as a truthful MCP-first view and reuse the existing MCP management/discovery flows. Other provider cards remain unavailable until real adapters are present.
5. Implement Advanced Configuration only for settings with real owners and secure persistence. Keep unsupported harvest/social API settings out of the live controls.
6. Implement Battle Cards as a clearly marked unconfigured/import-required domain view; do not synthesize competitor intelligence.
7. Add widget tests for navigation, filters, empty/loading/error states, responsive layout, secure-secret masking and service interactions. Add unit tests for any new state/controller logic.
8. Run formatter, `flutter analyze --no-pub`, full `flutter test --no-pub`, Python tests and all configured Android APK variants on the resulting head. Do not mark ready or merge until current-head CI is green.

## Preservation constraints

- Do not edit `main.dart` or change the default ChatScreen route.
- Do not merge PR #56 or change its draft/review state.
- Do not remove existing screens, services, data stores, integrations or workflows.
- Do not represent demo values or UI toggles as real execution state.
- Keep implementation commits scoped and separately verifiable.
