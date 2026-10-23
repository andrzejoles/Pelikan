# AI agents

Pelikan provides tools to AI agents running in the terminal (Claude Code, Codex, Grok, Antigravity) through an MCP
server available only to the given session. The agent works in the **Agent panel** next to the windows.

## Security rules

- The agent sees connections only by name (alias) — never passwords, addresses or user names.
- The agent has **its own database session** (marked in V$SESSION), optionally through a proxy user with restricted
  privileges. It executes queries in a read-only transaction, with row and time limits.
- Changes (DML, DDL, compilation) require **your consent** in a consent dialog with a preview of the statement and the
  objects affected. DML stays uncommitted until you agree to a COMMIT.
- On production connections the agent has read-only access. The agent has no access to the Command Window, operating
  system commands, the debugger or AWR/ASH reports.
- Selected columns can be masked in results returned to the agent.
- **Revert agent session** restores the objects changed by the agent to their state before the changes (with conflict
  detection).

Privileges, the list of programs and the activity log are in **Preferences › Agents**.
