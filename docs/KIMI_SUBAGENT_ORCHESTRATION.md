# Kimi-style delegated-agent orchestration

This change adds the worker-coordination primitive for the Kimi patterns identified
in the reverse-engineering notes: child-agent identities, dependency-aware
scheduling, bounded fan-out, factual lifecycle events, and aggregated results.

The child agent is a task record, not a second model/runtime instance. The
executor must be the application's shared AgentService/runtime boundary.
Independent children may be scheduled concurrently up to a hard limit of 1–8.
A child starts only after all dependencies complete successfully. Failed
prerequisites cause dependent children to be skipped. Cancellation prevents
pending children from starting; already-running work is allowed to settle.

Events contain operational metadata and outputs/errors only, never private
chain-of-thought. The app integration must persist emitted events into the
append-only SQLite event journal keyed by task/session/request IDs.

This commit provides a tested scheduler contract. It does not claim that chat
requests are already decomposed into child agents or that SQLite persistence is
wired by this primitive alone. The next integration step is to connect the
planner's structured delegation output to this scheduler and the existing
shared runtime without creating a second ModelService or LlamaService.
