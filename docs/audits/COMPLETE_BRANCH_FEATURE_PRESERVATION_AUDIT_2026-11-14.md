# Giant Agent — Complete Branch & Feature Preservation Audit
**Audit date:** 2026-11-14  
**Repository:** `almwld/giant-agent`  
**Baseline:** `main`  
**Audit branch:** `audit/complete-branch-feature-inventory-20261114`

## Executive result

A live GitHub inventory returned **67 branches** and **59 pull requests**. All 66 non-main branch refs were compared against `main`. This is an inventory and preservation plan, not a claim that all features are production-ready.

**No feature branch was merged, deleted, rebased, force-pushed, or closed during this audit.** The only repository mutation is this audit branch and this report.

The branch graph is not a clean stack. Several branches contain long histories based on old or unrelated integration points. Therefore, raw ahead/behind counts are not a measure of unique feature value. For example, some PRs are already merged while their old source branches now appear heavily diverged from current main. The authoritative inclusion test is the merged PR and the actual current implementation/tests, not branch age or commit count alone.

## Important findings: features that must be preserved

### A. User-facing assistant foundation — PR #1
Open PR `feat/chatgpt-experience-foundation` contains a separate assistant foundation:
- conversation-scoped SQLite persistence, streaming controller, cancellation/retry/search;
- strict ReAct JSON decision protocol, schemas, argument type checks, bounded execution and duplicate-action blocking;
- Node streaming gateway with OpenAI Responses and OpenRouter/Gemini-compatible SSE;
- JWT verification, server-managed credentials/BYOK, rate limiting and attachment transport;
- backend tests and dedicated Flutter workflow.

**Disposition:** Do not discard because current `main` has a different ReAct/runtime implementation. Compare each capability and test contract, then port only missing behavior into the canonical runtime. Resolve overlapping chat/database/provider ownership first.

### B. Durable execution, SQLite and Gain PTY
Historical work across `feat/runtime-foundation-gain-pty`, `feat/consolidate-sqlite-runtime`, `feat/phase-0-durable-agent-service`, `feat/phase-1-durable-task-manager`, `feat/gain-pty-reliability`, `docs/durable-task-engine-review`, replay and verification branches includes:
- native Android PTY bridge (C/Kotlin), PTY client/parser and session ownership;
- approval-gated terminal tool and serialized coordinator;
- durable SQLite request admission/FIFO/event journal and restart reconciliation;
- TaskManager persistence/recovery and AgentService integration seams;
- PTY partial-write handling, child lifecycle hardening and smoke tests.

PR #6 was closed without merge to main; later PR #38 merged the integrated stack. PRs #9–#11 and several replay branches are historical stacked work. PR #8 is an open documentation review that explicitly identifies the former split between the in-memory execution kernel, SQLite durable kernel and SharedPreferences TaskManager.

**Disposition:** Verify the current application call path end-to-end. Do not reintroduce a second queue/store/kernel. Preserve native PTY safety constraints and approval semantics. Reuse the strongest current implementation and its tests.

### C. Local inference and model provider support
- PR #2 `feat/local-gguf-llama-cpp` is merged to main: ARM64 llama.cpp JNI, GGUF import, model load/generate/cancel/unload bridge. The old branch is stale; do not re-port it wholesale.
- `fix/openrouter-only-provider-policy-v2` has a distinct 7-commit/7-file delta and includes provider routing/settings and tests; review against current provider policy before adopting.
- Open PR #58 `feat/pollinations-agent-provider` adds a zero-config/Pollinations adapter, provider selection persistence, chat/runtime wiring and parser tests. Its own description correctly warns that legacy keyless endpoint availability is not guaranteed. Treat it as experimental until current endpoint behavior and rate limits are verified.
- `fix/runtime-provider-routing-gemini` is behind main; verify merged coverage before considering it closed.

**Disposition:** One provider registry/settings contract and one ModelService execution path. Do not claim a no-key provider is guaranteed or unlimited.

### D. Local Arabic voice
Open PR #55 `feat/local-offline-voice-pipeline` (112 commits ahead of main in the current comparison; 26 changed files) carries:
- local Whisper transcription and Nabra/Kokoro sherpa-onnx Arabic TTS;
- persistent worker isolate, text chunking and shared voice orb;
- native AudioRecord capture bridge, VAD/AEC integration details in stacked PR #56;
- model/provider switching guard and local-only voice flow;
- Flutter/Python tests and native build changes.

PR #56 stacks the Timeline/unified runtime integration on top of PR #55. Its own description records important limitations: device-dependent platform AEC, energy VAD rather than semantic VAD, serialized local inference (not parallel local workers), and physical-device audio/RAM/thermal validation still required.

**Disposition:** Preserve the complete local voice pipeline; do not replace it with a cloud-only voice screen. Verify current-head CI, APK packaging, model download/checksum, microphone lifecycle, interruption, and physical-device performance.

### E. Timeline and observability — multiple non-equivalent implementations
- PR #36 `feat/production-timeline-engine`: separate timeline engine, database, cancellation manager, advanced widget and tests (8 files; 1,316 additions). It is an alternative/earlier design and must be compared semantically, not copied wholesale.
- PR #53 `chore/boosthis-mcp-mainline`: native local Gain Agents journal and observability screen, backed by AgentEventBus/AgentService/AgentKernelStore. The PR description states that Timeline is now wired to the same canonical store, refreshes while open, retains cursor-loaded rows and supports filters/search/progress/duration/tool metadata/cancellation. This PR is open.
- PR #54 is a temporary verification PR for the #53 head, not an independent feature.
- PR #56 adds searchable, cursor-paginated Timeline to the unified runtime branch and voice line.
- `feat/native-gain-observability` and `feat/verified-agent-orchestration-events` are related historical/verification work.

**Disposition:** Select one canonical event schema, persistence store, event bus and Timeline projection. Do not create a second Timeline database or display model-generated “thoughts” as execution events. The UI must render persisted, correlated execution events from the actual AgentService path.

### F. Kimi-style dynamic subagents and Hermes memory/skills
Merged PRs #26, #28–#30, #33, #40–#47 and #41–#42 introduced or extended:
- dynamic subagent creation/spawn/status/goal/mailbox/wait/ask-user lifecycle;
- MCP typed result contracts, independent tool-call identity and OpenRouter SSE;
- Mylib technology transfer and lifecycle persistence;
- persistent skills and relevance-aware context compaction;
- hybrid long-term memory retrieval;
- evidence-aware context transfer and adaptive orchestration;
- scoped cancellation for browser, web search, Python, MCP, media, PTY/local inference and shared model runtime.

Open/closed historical branches `feat/kimi-subagent-orchestration`, `feat/kimi-dynamic-subagent-lifecycle`, `feat/kimi-runtime-dynamic-orchestration`, `feat/mylib-durable-subagent-recovery`, `feat/mylib-technology-transfer`, and `feat/mylib-transfer-validation` overlap substantially.

**Disposition:** Merged PRs are the starting point, but validate the live code path and tests. Keep one subagent lifecycle manager, one durable state model, one mailbox/goal contract and scoped cancellation. Do not merge old branch snapshots over current main.

### G. AgentsOS control center — PR #57
Open PR #57 adds six control-center surfaces: Dashboard, Task Manager, Agent Fleet, Battle Cards, Integrations and Advanced Configuration. Its stated design is a read model over the existing AgentService, durable observability store, TaskManager and MCP configuration, with no second executor/queue/model runtime/database. It includes task resume confirmation and cancellation controls.

**Disposition:** Important UI feature, but its base is `integration/unified-agent-runtime-v2`, not main. It must be reviewed and retargeted only after its runtime dependencies are reconciled. Its own verification section says analyzer, widget test execution, Android build and device validation remain outstanding.

### H. Other important open work
- PR #12 / `feat/sehatak-brand-identity`: large UI/theme/branding redesign and expanded validation/build pipeline (66 files). Review visual/product decisions and keep only compatible Giant Agent identity assets; do not assume all changes belong in the runtime.
- PR #17 / `feat/chat-bubble-resize-teal-toasts`: resizable chat bubble and visual toast changes; PR #25 for embedded resizable voice orb is already merged on a different base. Verify current main before adopting.
- PR #24 / `test/gain-pty-emulator-smoke`: Android emulator integration smoke test, ABI/native-library verification and APK component size report. Open; preserve as a validation asset.
- PR #27 / `fix/android-launch-black-screen`: Android launch theme/manifest and startup initialization changes. Open; verify against current main and test cold launch.
- PR #32 / `ci/codemagic-android-release`: Codemagic release workflow, document parser tests and ABI APK build/checksum. Open and based on SQLite v2; reconcile CI configuration before use.
- PR #18 / `ci/upload-split-apk-artifacts`: closed without merge. Contains split ABI APK/checksum and Chaquopy ABI filter changes; assess its useful CI/build logic independently of its old code snapshot.
- PR #5 / `docs/enterprise-agent-architecture`: architecture contract only, not implementation.
- PR #37 Boosthis connection is closed without merge and is superseded in direction by native observability PR #53.

## Pull request disposition from live listing

### Open (18)
#1 ReAct/assistant foundation; #5 enterprise architecture documentation; #8 durable task engine review; #12 Sehatak brand identity; #17 chat bubble sizing; #24 PTY emulator smoke test; #27 Android launch black screen; #32 Codemagic release; #36 production Timeline; #53 native Gain observability; #54 observability verification; #55 local Arabic voice; #56 unified runtime + Timeline integration; #57 AgentsOS control center; #58 Pollinations provider; #59 SQLite WAL pragma fix.

### Merged (26)
#2 local GGUF; #3 integrated agent runtime/workflow/workspace/local services; #4 OpenRouter format fix; #14 SQLite task persistence consolidation; #21 voice terminal approval; #22 OpenRouter-only cloud policy; #23 voice orb in chat; #25 embedded resizable voice orb; #26 Kimi subagent orchestration; #28 MCP result contracts/tool identity/SSE; #29 dynamic subagent lifecycle; #30 model-facing dynamic orchestration; #31 Appetize cloud Android testing; #33 Mylib transfer; #38 full agent stack integration; #39 Gain PTY/local inference cancellation; #40 persistent skills/context compaction; #41 subagent goals/mailboxes; #42 durable lifecycle; #43 tool cancellation isolation; #44 MCP cancellation; #45 Python cancellation; #46 adaptive orchestration/evidence-aware context; #47 Hermes hybrid memory; #48 browser cancellation; #49 web-search cancellation; #50 context index fix; #51 media cancellation; #52 preserve initial instructions.

### Closed without merge (15)
#6 durable kernel/Gain PTY; #7 shared-runtime voice assistant; #9 AgentService durable integration phase; #10 TaskManager SQLite persistence; #11 PTY lifecycle hardening; #13 old SQLite consolidation attempt; #15 duplicate SQLite v2 PR; #16 earlier chat bubble polish; #18 split APK CI; #19 PTY integration PR; #20 voice integration PR; #34 watchdog progress fix; #35 Mylib transfer validation; #37 Boosthis connection. These are not automatically discarded: inspect their unique behavior/tests only where not represented by merged descendants or current main.

> Counts above are the live PR list returned by GitHub at audit time. PR status must be refreshed before any merge decision.

## Complete branch inventory (67)

The following refs were present at audit time. Each was compared to main; old/diverged refs are preserved and are not deletion candidates:

1. `chore/boosthis-mcp-connection`
2. `chore/boosthis-mcp-mainline`
3. `ci/appetize-cloud-device-testing`
4. `ci/codemagic-android-release`
5. `ci/upload-split-apk-artifacts`
6. `ci/verify-native-gain-20261113`
7. `docs/durable-task-engine-review`
8. `docs/enterprise-agent-architecture`
9. `feat/agentsos-control-center`
10. `feat/chat-bubble-resize-teal-toasts`
11. `feat/chat-embedded-resizable-voice-orb`
12. `feat/chatgpt-experience-foundation`
13. `feat/consolidate-sqlite-runtime`
14. `feat/consolidate-sqlite-runtime-v2`
15. `feat/full-reference-architecture-transfer`
16. `feat/gain-pty-reliability`
17. `feat/hermes-hybrid-memory-retrieval`
18. `feat/hermes-skills-context-compaction`
19. `feat/integrated-agent-completion`
20. `feat/kimi-dynamic-subagent-lifecycle`
21. `feat/kimi-runtime-dynamic-orchestration`
22. `feat/kimi-subagent-orchestration`
23. `feat/local-gguf-llama-cpp`
24. `feat/local-offline-voice-pipeline`
25. `feat/mcp-toolcall-sse-integration`
26. `feat/mylib-durable-subagent-recovery`
27. `feat/mylib-technology-transfer`
28. `feat/mylib-transfer-validation`
29. `feat/native-gain-observability`
30. `feat/phase-0-durable-agent-service`
31. `feat/phase-1-durable-task-manager`
32. `feat/pollinations-agent-provider`
33. `feat/production-timeline-engine`
34. `feat/runtime-foundation-gain-pty`
35. `feat/sehatak-brand-identity`
36. `feat/unified-kernel-v2`
37. `feat/verified-agent-orchestration-events`
38. `feat/voice-orb-in-chat-session`
39. `feature/voice-assistant-integration`
40. `fix/android-launch-black-screen`
41. `fix/browser-tool-call-scoped-cancellation`
42. `fix/context-compactor-index-types`
43. `fix/context-compactor-never-truncate-contract`
44. `fix/durable-subagent-mailboxes-and-goals`
45. `fix/mcp-tool-call-cancellation-through-approval`
46. `fix/media-tool-call-cancellation-contract`
47. `fix/openrouter-format-exception`
48. `fix/openrouter-only-provider-policy`
49. `fix/openrouter-only-provider-policy-v2`
50. `fix/python-tool-call-cooperative-cancellation`
51. `fix/runtime-provider-routing-gemini`
52. `fix/sqlite-wal-pragma-monitoring`
53. `fix/tool-call-cancellation-isolation`
54. `fix/tool-call-scoped-gain-cancellation`
55. `fix/voice-terminal-approval-stabilization`
56. `fix/web-search-tool-call-cancellation`
57. `integration/giant-agent-stabilization`
58. `integration/unified-agent-runtime`
59. `integration/unified-agent-runtime-v2`
60. `main`
61. `rebuild/build-756-to-1011`
62. `rebuild/verified-replay-425197-to-425351`
63. `replay/verified-onto-425197-clean`
64. `replay/verified-onto-425197`
65. `test/gain-pty-emulator-smoke`
66. `verify/gain-replay-ci`
67. `verify/gain-replay-ci-2`

## Comparison highlights (main...branch)

These are GitHub compare endpoint results, useful for triage only:
- `feat/agentsos-control-center`: ahead 275, 55 changed files.
- `integration/unified-agent-runtime-v2`: ahead 222, 40 changed files.
- `feat/local-offline-voice-pipeline` and `integration/unified-agent-runtime`: ahead 112, 26 changed files each (same feature lineage).
- `feat/local-gguf-llama-cpp`: old branch; PR #2 merged, so its 111-ahead/23-file comparison is not a reason to re-port.
- `feat/gain-pty-reliability`: ahead 74, 25 files; old stacked lineage and overlapping durable runtime.
- `feat/chatgpt-experience-foundation`: ahead 68, 31 files; separate assistant/gateway foundation.
- `feat/kimi-dynamic-subagent-lifecycle`: ahead 70, 19 files; overlaps merged descendants.
- `feat/production-timeline-engine`: ahead 17, 8 files; independent Timeline design.
- `feat/pollinations-agent-provider`: ahead 10, 6 files; open PR #58.
- `fix/sqlite-wal-pragma-monitoring`: ahead 3, 3 files; open PR #59.
- `ci/codemagic-android-release`: ahead 2, 1 file; open PR #32.
- `ci/upload-split-apk-artifacts`: ahead 3, 3 files; closed unmerged PR #18.
- `feat/chat-bubble-resize-teal-toasts`: ahead 5, 2 files; overlaps merged PR #25 and open PR #17.
- Several old branches are fully behind main (including merged feature branches); those should be treated as historical sources, not as missing current features.

## Canonical integration map — required owners

| Capability | Canonical owner to establish | Required proof |
|---|---|---|
| App entry/session/chat | Existing app router + ChatScreen | cold launch, session restore, no duplicate controller |
| Request admission/FIFO/recovery | One durable AgentService + one kernel/store | FIFO, duplicate request, restart, interruption, no unsafe replay |
| Model inference | One ModelService/provider registry + shared local runtime | local GGUF, cloud, cancellation, provider persistence |
| ReAct/harness | One trusted action decoder/policy/harness | malformed JSON, invalid schema, duplicate side effect, completion verification |
| Tool execution | One ToolManager/registry and per-call identity | typed results, scoped cancellation, approvals |
| PTY | GainPtyClient/bridge + coordinator | JNI smoke, partial writes, exit/timeout/session loss, explicit approval |
| Subagents | One lifecycle manager + durable state/mailboxes | spawn, wait, ask-user, progress, cancellation, restart reconciliation |
| MCP | One MCP client/session and typed result envelope | discovery, SSE, approval, cancellation, content/resource preservation |
| Memory/skills/context | One memory service and skill registry | retrieval relevance, persistence, instruction preservation, bounded context |
| Timeline/observability | One EventBus + AgentKernelStore journal + UI projection | persisted event correlation, paging/search/filter, live refresh, metrics |
| Local Arabic voice | Local ASR/TTS services + native capture bridge | download integrity, Arabic quality, mic permissions, interrupt, device resource profile |
| AgentsOS | Read-only control-center projections over canonical services | all six screens, correct task state, guarded resume/cancel |
| Release/CI | One source-of-truth Flutter 3.16 compatible pipeline plus optional Codemagic | analyze, full tests, native build, universal/ABI APK and SHA256, emulator smoke |

## Ordered integration plan

### Phase 0 — preserve and freeze
- Keep all 67 branch refs and all PR records intact.
- No feature branches or duplicate runtimes are created while inventory is active.
- Record current main SHA, open PR head SHAs, CI runs and artifacts before every later transfer.
- Keep the current Flutter 3.16 compatibility baseline unless an explicit, isolated build decision is approved.

### Phase 1 — verify current main
- Run full Flutter analysis and unit tests; inspect all current workflows and latest run results.
- Inspect actual source call graph from Chat/Voice -> AgentService -> Kernel -> ModelService -> ToolManager -> Store/EventBus.
- Verify that the Timeline screen queries the same store used by execution.
- Verify SQLite WAL uses rawQuery where the pragma returns rows.
- Verify main contains the merged local GGUF, Kimi/Hermes, MCP and cancellation behavior through tests, not filename presence.

### Phase 2 — reconcile open PRs by dependency order
1. #59 WAL correctness (small prerequisite; test both production and test database factories).
2. #53 native Gain observability + Timeline, after checking its current head and CI.
3. #55 local Arabic voice, then #56 integration with canonical runtime/Timeline.
4. #57 AgentsOS UI, after its base is reconciled to the validated runtime.
5. #1 assistant/gateway foundation: selectively port missing contracts without introducing a second chat/database/provider architecture.
6. #24 emulator PTY validation, #27 cold-launch fix, #32 Codemagic pipeline, #12 identity, #17 chat polish, and #8/#5 documentation as independent review tracks.
7. #36 production Timeline is an alternative design: retain only unique contracts/tests not already fulfilled by #53/#56.

### Phase 3 — feature-preservation verification
- For every unique capability found in old closed PRs and branch-only commits, record: source branch/PR, exact files, current-main equivalent, chosen implementation, tests, status.
- Explicitly compare the document parser (PDF/DOCX/XLSX), workspace/file browser, GitHub/browser/search, Python/terminal, MCP, local inference, voice, analytics and build pipeline.
- Keep source behavior and regression tests even when implementation is refactored.

### Phase 4 — one integration candidate
- Build one integration candidate from current main only after the matrix is complete.
- Transfer feature-sized, dependency-ordered changes; never copy an old branch snapshot wholesale.
- Run targeted tests after each feature group, then full analyze/tests and Android APK matrix.
- Open one consolidated review PR to main only after the candidate is green. Do not auto-merge it.

## Completion criteria

The audit is **not** considered complete until:
1. Each of the 67 branches has a recorded disposition (merged equivalent / historical duplicate / unique behavior to port / CI-only / docs-only / no unique diff).
2. Each of the 59 PRs has a final status and feature-preservation mapping.
3. Every unique feature has a canonical owner and regression test.
4. No duplicate runtime, SQLite store, queue, event bus, provider registry or Timeline database remains.
5. Flutter analyze, full Flutter/Python tests, native Android builds and emulator/device tests pass on the final candidate.
6. The final candidate has a reviewed PR; main is not changed without explicit merge authorization.

**Audit conclusion:** The mainline contains substantial integrated technology, but several important capabilities remain in open PRs or historical branches. The correct next action is controlled preservation and integration—not deleting branches, cherry-picking large histories, or merging all PRs indiscriminately.
