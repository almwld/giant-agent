# Phase 2 technology transfer

This phase adds original, first-party implementations inspired by the requested
project studies. It does not copy source code from those projects.

## Included in code

- Hermes-style skills: request-matched skill activation, bounded skill prompts,
  persistent custom skill definitions, and built-in software/research/planning/
  mobile/tool-safety skills. Skills are guidance only and cannot grant tools.
- Memory/context compaction: relevance-ranked facts and conversation excerpts,
  importance-aware ordering, complete-record budgeting, and a conservative
  character-to-token estimate rather than a blind final substring.
- OpenRouter remains on the existing singleton provider and SSE parser.
  The current local GGUF runtime remains the single local inference path.
- Existing orchestration retains dependency-aware subagents and bounded
  parallelism; shared workspace writes remain serialized by ModelService.
- Existing MCP client retains structured content/resource links and request
  cancellation. Existing durable task journal/recovery remains the source of
  execution history; uncertain side effects are not automatically replayed.

## Source-inspired mapping

- OpenHands: shared runtime/session/event architecture already in the kernel,
  event bus, durable request journal and workspace services.
- Hermes: persistent local memory plus the new skill registry and prompt
  activation layer.
- EvoAgent: ReAct/tool dispatch, MCP structured results, SSE parsing and
  cancellation/recovery paths already in the runtime.
- Deep Agents: planner, dependency graph, subagent coordinator and parallel
  execution already in the kernel.
- AnythingLLM Mobile: Flutter/mobile-first UI and local GGUF/cloud provider
  routing already exist; this phase preserves the single local runtime.
- Postal: OpenRouter streaming and coding-tool execution stay on the existing
  provider/tool path; no second provider runtime is introduced.

## Important boundary

These are code-level integrations, not claims of runtime verification.
No tests, analyzer, CI workflow, or build were run as part of this transfer.
