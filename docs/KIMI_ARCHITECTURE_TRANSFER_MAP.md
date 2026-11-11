# Kimi architecture transfer map for Giant Agent

## Evidence boundary

The Mylib main-branch report records a scan of 26,983 decompiled Java files and
158 AGENT-related matches. The repository also contains Libkimi.zip and Libg.zip.
The GitHub file reader exposes the text reports but does not expose the Java
class bodies inside those binary archives. Consequently, class names and
matched symbols below are evidence of architecture surfaces, not proof of the
full implementation semantics. No proprietary binary code was copied.

## Kimi evidence mapped to Giant Agent

| Kimi evidence in Mylib | Evidence visible in the report | Giant Agent counterpart | Transfer status |
|---|---|---|---|
| Qk/O.java | Highest AGENT hotspot in the scan (180 matches) | AgentKernel, ModelService, SubagentOrchestrator | The execution path was traced in Giant; exact Kimi method semantics remain unverified without the class body. |
| Dc/I6.java | Registration strings for createSubagent and subagent | PlannerService, AgentKernel, SubagentOrchestrator | Static task graph creation, validation, dependency scheduling and worker execution already exist. Dynamic model-facing child creation is not yet equivalent. |
| Dc/Z6.java, Dc/O7.java, Dc/C0665x7.java, Dc/I7.java, Dc/K7.java, Dc/C0683z7.java | Protobuf/tool metadata names for subagent and worker types | SubagentTask, SubagentResult, AgentKernelStore task snapshots | Typed task identity, role, prompt, dependencies, result and persisted lifecycle are represented. Exact wire-format compatibility is not claimed. |
| Zd/B.java, Zd/D.java | Operation names include CREATE_SUBAGENT, SPAWN_SUBAGENT, DELETE_SUBAGENT and CHECK_SUBAGENT_STATUS | SubagentOrchestrator, SubagentRecoveryCoordinator, AgentKernelStore | Create/spawn lifecycle, status events and explicit recovery are present. A direct delete operation and dynamic in-run spawning are not yet exposed as agent tools. |
| Uc/Y2.java, Uc/W.java, Uc/C2011a3.java, ve/C5157w.java | SubagentStatusEvent, subagentStatus and status-handler strings | AgentTimelineEvent, AgentEventBus, append-only AgentKernelStore event journal | Structured lifecycle events and durable status history are present; event names are Giant-specific. |
| je/C1.java, ld/C3841H.java, ld/C3843J.java | Agent/agentType and Subagent identity fields | taskId, agentType, requestId, dependsOn and persisted child IDs | Core identity fields are represented in Giant's orchestration and recovery model. |
| Notion MCP OAuth URLs | OAuth authorize and callback URL patterns appear in NETWORK_URLS.txt | McpClient, secure server registry, bearer-token transport | Streamable HTTP and bearer credentials are implemented. Browser OAuth authorization/refresh is not implemented. |

## Work transferred in this branch

1. **MCP transport:** a shared Streamable HTTP client, initialize/session handling,
   paginated tool and resource discovery, tools/call, resources/read, JSON/SSE
   responses, secure server configuration and endpoint validation.
2. **Structured outputs:** typed text/media/resource blocks, file resource links,
   structuredContent, _meta, extension fields and error state. Resource links
   can be read by the agent instead of being flattened into prose.
3. **Tool identity:** each invocation has an independent tool_call_id, lifecycle
   events carry it, the timeline can cancel one active call, and cancellation
   is recorded as interruption rather than successful completion.
4. **Provider streaming:** OpenRouter uses the existing provider path with SSE
   deltas and cancellation. The existing shared local ModelService/LlamaService
   runtime is retained; no parallel local runtime was introduced.
5. **Subagent integration:** the existing planner/orchestrator/recovery workers
   can use MCP tools and resource reads within their role allow-lists.

## Remaining Kimi-equivalence work

- **Dynamic subagent lifecycle:** Giant currently validates and schedules a
  complete task graph before workers start. Kimi's report names create/spawn/
  delete/status operations, but the exact semantics are hidden in the ZIP
  class bodies. Do not add recursive or destructive child-management tools
  based only on symbol names. Extract the referenced class bodies first, then
  map lifecycle transitions and ownership explicitly.
- **OAuth:** add browser authorization, redirect validation, token refresh and
  secure credential rotation before claiming parity with Kimi's Notion MCP
  OAuth integration.
- **Transport scope:** this Flutter/mobile implementation supports Streamable
  HTTP. MCP stdio and legacy SSE-over-GET transports are intentionally not
  claimed.
- **Verification:** contract tests have been added, but no fresh GitHub CI
  status or real-server integration result is visible for the current PR head.
  Production readiness requires formatter/analyzer/tests, APK build and a
  real MCP server test.

## Exact Kimi source files needed for the next reverse-engineering pass

Extract these decompiled files from Libkimi.zip as plain UTF-8 source and commit
them under a text-only directory in Mylib:

- Qk/O.java
- Qk/AbstractC0417z.java
- Qk/AbstractC0374d.java
- Dc/I6.java
- Dc/Z6.java
- Dc/O7.java
- Dc/C0665x7.java
- Dc/I7.java
- Dc/K7.java
- Dc/C0683z7.java
- Zd/B.java
- Zd/D.java
- Uc/Y2.java
- Uc/W.java
- Uc/C2011a3.java
- ve/C5157w.java
- je/C1.java
- ld/C3841H.java
- ld/C3843J.java

These are the smallest high-signal set identified by the current report. Their
full method bodies are necessary before claiming file-by-file semantic parity.
