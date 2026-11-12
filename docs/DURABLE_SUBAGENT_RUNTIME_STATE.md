# Durable dynamic subagent state

The dynamic subagent lifecycle manager now has an explicit persistence contract.
Its request-scoped current goal and pending mailbox messages are stored in the
existing SQLite kernel database, not only in process memory.

- Database schema v5 adds `agent_subagent_runtime_state`.
- Goal updates and mailbox enqueue/dequeue operations persist an atomic JSON
  snapshot keyed by parent request ID.
- Mailboxes are bounded to 100 pending messages per child.
- The execution kernel exposes `restoreSubagentState(requestId)`; callers must
  restore before using synchronous reads such as `currentGoal` or `forRequest`.
- The lifecycle manager publishes its lifecycle events through the existing
  process-wide AgentEventBus. It does not create another event bus or runtime.
- Existing durable child task snapshots and immutable event journal remain
  authoritative for child lifecycle/recovery. This table stores only ephemeral
  coordination state (goal and pending messages).

Recovery deliberately does not restart a child automatically. Interrupted
children still require the existing explicit resume flow and side-effect
disposition.
