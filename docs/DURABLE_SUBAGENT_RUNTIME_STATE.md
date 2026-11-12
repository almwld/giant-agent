# Durable dynamic subagent state

The dynamic subagent lifecycle manager now persists its complete request-scoped
coordination snapshot in the existing SQLite kernel database.

- Database schema v5 adds `agent_subagent_runtime_state`.
- The snapshot includes dynamic child records, current goal, and pending mailbox
  messages; child status changes and mailbox enqueue/dequeue operations persist.
- Mailboxes are bounded to 100 pending messages per child.
- The execution kernel exposes `restoreSubagentState(requestId)`; callers must
  restore before using synchronous reads such as `currentGoal`, `get`, or
  `forRequest`.
- The lifecycle manager publishes lifecycle events through the existing
  process-wide AgentEventBus. It does not create another event bus or runtime.
- Existing durable child task snapshots and immutable event journal remain the
  audit/recovery source for orchestrated tasks. This runtime snapshot restores
  the dynamic lifecycle manager's own records and coordination state.

Recovery deliberately does not restart a child automatically. Interrupted
orchestrated children still require the existing explicit resume flow and
side-effect disposition.
