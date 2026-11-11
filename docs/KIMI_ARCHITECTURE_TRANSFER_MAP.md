# Kimi architecture transfer map for Giant Agent

## Evidence boundary

The Mylib main branch now contains 19 text exports from JADX under
`Kimi_Agent_Sources/` (commit supplied by the repository owner). These files
provide concrete protocol and data-model evidence, not a complete executable
implementation of Kimi's orchestration engine.

Important limitations found during inspection:

- `Kimi_Agent_Sources/Qk/O.java` is empty in the committed export (zero bytes).
  It is the highest-signal class in the earlier scan (180 AGENT-related hits),
  so its method behavior is still unavailable.
- `Qk/AbstractC0417z.java` and `Qk/AbstractC0374d.java` are very large
  generated Compose resource mappings. Their relevant strings are resource
  names such as `tasksubagent` and `anim_tool_create_subagent`; they do not
  establish orchestration semantics.
- `Zd/B.java` is an operation-name enum-like registry. It proves the wire/tool
  names, but not their argument validation, state transitions, or execution.
- `Dc/*`, `Uc/*`, and `ld/*` are predominantly Kotlin serialization
  descriptors and data classes. Their field names and types are useful
  contracts, but not proof of runtime behavior.
- `ve/C5157w.java` contains a status-event consumer/logging path, but does not
  reveal the complete producer or all state-transition rules.

No proprietary Kimi implementation code has been copied into Giant Agent. The
transfer below is a clean implementation based on observed contracts.

## File-by-file findings

| Kimi source | Directly observed evidence | What it establishes | What it does not establish |
|---|---|---|---|
| `Qk/O.java` | Empty source export; prior scan reports 180 AGENT hits | A high-priority orchestration hotspot exists | Any method or execution semantics |
| `Qk/AbstractC0417z.java` | Generated resource map includes `tasksubagent` | UI/resource support for subagent task affordances | Agent creation or execution |
| `Qk/AbstractC0374d.java` | Generated resource map includes `anim_tool_create_subagent` | UI animation/resource for create-subagent tool | Tool runtime semantics |
| `Dc/I6.java` | `ToolBlock` serialization descriptor includes `toolCallId`, `name`, `args`, `isError`, `errorCode`, `createSubagent`, `subagent`, `task`, `mcp` and other tool variants | Tool calls are represented as typed blocks with an independent call ID and typed metadata alternatives | How each tool is executed |
| `Dc/C0665x7.java` | `ToolMetaCreateSubagent(name, workers)` | Create-subagent metadata contains a name and worker list | Whether creation starts execution immediately |
| `Dc/C0683z7.java` | Create metadata data class: `name: String`, `workers: List` | Worker configuration is a first-class part of create metadata | Worker limits, validation, or scheduler policy |
| `Dc/O7.java` | `ToolSubagentWorker(name, iconUrl, motto)` | Each configured worker exposes a name, icon URL, and motto | Its actual system prompt or capabilities |
| `Dc/I7.java` | `ToolMetaSubagent(agentId, agentIndex, agentIcon, agentName, agentType)` | Subagent tool metadata has stable identity, index, display metadata, and type | Parent ownership or persistence rules |
| `Dc/K7.java` | Matching data class fields for agent ID/index/icon/name/type | Confirms the typed metadata shape | Runtime lifecycle semantics |
| `Dc/Z6.java` | ToolBlock data model contains create-subagent and subagent metadata fields among its typed variants | Create and individual-subagent results are separate protocol variants | The transition between the variants |
| `Zd/B.java` | Operation identifiers: `create_subagent`, `spawn_subagent`, `delete_subagent`, `check_subagent_status`; also `send_message`, `wait_for_message`, `ask_user`, `update_goal` | Confirms the model-facing operation vocabulary and that the design extends beyond simple task fan-out | Argument schemas, authorization, idempotency, and exact state transitions |
| `Zd/D.java` | Tool presentation categories `CreateSubagent` and `CheckSubAgent` | Separate create and status-check UI/tool categories exist | Whether every operation has a separate UI |
| `Uc/Y2.java` | `SubagentStatusEvent(chatId, agentId, status, progressPercent)` | Status updates carry chat/agent identity, status, and progress | The full status enum or progress semantics |
| `Uc/W.java` | Gateway event envelope includes `subagentStatus` | Subagent status is delivered as a typed event variant | Delivery guarantees/reconnect behavior |
| `Uc/C2011a3.java` | Status event data class with chat ID, agent ID, status, and nullable progress percentage | Confirms event payload shape | Whether events are persisted |
| `ve/C5157w.java` | Status consumer recognizes the subagent-status event and logs its agent/status fields | Confirms a consumer path exists | Complete event-to-UI mapping or lifecycle transitions |
| `je/C1.java` | Tool/request data includes fields named `systemPrompt`, `prompt`, `agent`, `agentType`, `runInBackground`, and `workDir` | Agent execution can be parameterized by system prompt, task prompt, role/type, background flag, and working directory | Whether each field is mandatory or how background work is scheduled |
| `ld/C3841H.java` | Swarm Subagent serialization descriptor: `id`, `index`, `name`, `iconUrl`, `motto`, `status`, `progressPercent`, `description`, `type`, `isAsync` | Swarm subagent snapshots include identity, presentation, status/progress, description/type, and async marker | State machine transitions and cancellation semantics |
| `ld/C3843J.java` | Matching Subagent data class fields, including nullable progress and `isAsync` | Confirms the snapshot schema | Whether async means detached execution, queueing, or another mode |

## Kimi protocol conclusions supported by the exports

1. **Create is distinct from spawn.** The operation registry exposes both
   `create_subagent` and `spawn_subagent`; create metadata contains a named
   list of worker definitions. Giant must not collapse configuration and
   execution into one implicit action.
2. **Subagents have independent identities.** Tool metadata includes
   `agentId` and `agentIndex`; swarm snapshots include `id` and `index`.
3. **Status is event-driven and queryable.** The operation registry includes
   `check_subagent_status`; the gateway event envelope has a
   `subagentStatus` variant with chat ID, agent ID, status, and progress.
4. **Background/async execution is represented.** The request/tool model has
   `runInBackground`; swarm snapshots have `isAsync`. Exact semantics remain
   unverified.
5. **The protocol is broader than fan-out.** The same operation registry also
   names `send_message`, `wait_for_message`, `ask_user`, and `update_goal`.
   These should be treated as separate capabilities, not inferred from the
   four lifecycle operations.
6. **Tool invocation identity is explicit.** The ToolBlock descriptor contains
   `toolCallId`, which supports the independent tool-call identity already
   introduced in Giant Agent.

## Giant Agent mapping at current PR head

| Capability | Giant Agent implementation | Status |
|---|---|---|
| Typed child task identity and role | `SubagentTask`, `SubagentResult`, durable task snapshots | Present |
| Predeclared task graph and dependency scheduling | `SubagentOrchestrator.run` | Present; graph is currently fixed before execution |
| Child lifecycle journal and restart reconciliation | `AgentKernelStore.recordSubagentEvent`, `reconcileInterruptedSubagents` | Present |
| Explicit recovery of interrupted children | `SubagentRecoveryCoordinator`, `AgentKernel.executeRecoveredSubagent` | Present; requires explicit side-effect disposition |
| Status query API | `AgentService.subagentStatus` | Present as application API, not a model-facing tool |
| Safe dismissal | `AgentService.dismissSubagent` | Present as a soft-dismissal; audit history is retained |
| Dynamic model-facing create/spawn/delete/status operations | No corresponding tool definitions or runtime dispatch in the current branch | Missing |
| Worker metadata (icon/motto/index) | Current task model stores role/title/prompt/dependencies only | Partial |
| Progress percentage and async snapshot | Timeline has lifecycle statuses but no dedicated progress percentage or async projection | Partial |
| Message/wait/ask-user/update-goal operations | No equivalent model-facing tool family | Missing |
| MCP Streamable HTTP and typed results | `McpClient`, `McpToolResult` | Present in this branch |
| Independent tool-call ID and per-call cancellation | `ToolCallRegistry`, timeline `tool_call_id` | Present in this branch |
| OpenRouter incremental SSE | Existing provider singleton with cancellation and UTF-8-safe SSE parser | Present in this branch |
| Shared local inference runtime | Existing singleton `ModelService` and `LlamaService` | Preserved; no second local runtime |

## Work transferred in this branch

1. Shared Streamable HTTP MCP client, secure server configuration, endpoint
   validation, JSON-RPC initialization/session handling, paginated discovery,
   `tools/call`, `resources/read`, and JSON/SSE responses.
2. Typed MCP outputs preserving ordered text/media/resource blocks,
   resource links, `structuredContent`, `_meta`, extension fields, and errors.
3. Independent `tool_call_id` values, lifecycle events, targeted cancellation,
   and interrupted classification.
4. Incremental OpenRouter SSE streaming through the existing provider path,
   including cancellation while awaiting headers or during a stalled stream.
5. MCP tool/resource access from the existing subagent roles.
6. A durable task graph, lifecycle journal, restart reconciliation, and
   explicit child recovery through the shared local/cloud execution path.

## Remaining work before claiming Kimi-style dynamic orchestration

- Add a model-facing, typed lifecycle tool contract for create, spawn, delete,
  and status. Keep create (configuration/registration) separate from spawn
  (execution).
- Extend the scheduler to accept validated child tasks while a parent is
  running, with strict depth, count, concurrency, and workspace-lease limits.
- Persist worker metadata, parent/child ownership, progress, async mode, and
  terminal state transitions atomically.
- Make deletion a safe lifecycle operation: reject active children unless a
  separately authorized cancellation path has completed; preserve immutable
  audit history rather than physically deleting records.
- Add status-event correlation and progress updates, and make status queries
  return durable snapshots rather than model-generated claims.
- Treat send/wait/message, ask-user, and goal-update as a separate later
  protocol tranche. Their names are observed, but their exact contracts are
  not yet available.
- Inspect the empty `Qk/O.java` export and extract the missing runtime classes
  and status enum before asserting exact Kimi execution semantics.
- Run formatter, analyzer, tests, APK build, and real MCP-server integration.
  At the time of this update, PR #28 has no visible workflow run or combined
  commit status for its current head. Do not merge based on contract tests alone.

## Additional JADX evidence needed

The following local searches should locate the actual operation dispatch and
state transitions across the already-decompiled source tree:

```sh
grep -RIn --include='*.java' -E \
  'create_subagent|spawn_subagent|delete_subagent|check_subagent_status|send_message|wait_for_message|runInBackground|SubagentStatusEvent' \
  dex_parts/out1/sources dex_parts/out2/sources dex_parts/out3/sources
```

Also export the status enum/type referenced by `Uc/C2011a3.java`
(`ld/AbstractC3834A.java` appears in the decompiled signature) and the event
wrapper class referenced by `ve/C5157w.java` (`Uc/Y.java`). These are needed
to map status values and event dispatch without guessing.
