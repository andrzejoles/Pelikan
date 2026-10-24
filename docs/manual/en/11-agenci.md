# AI agents

Pelikan lets you work with an AI agent running in a terminal built into the window — e.g. Claude Code — which sees your
windows and the database only through Pelikan's tools and on rules that you control. The agent can read code and data,
analyze plans, write and format code in windows, and it makes changes in the database only after your consent.

## Supported programs

| Agent | Command | How it gets Pelikan's MCP server |
|---|---|---|
| Claude Code | `claude` | `--mcp-config` for this session only |
| Codex CLI | `codex` | `-c mcp_servers…` for this session only |
| Grok CLI | `grok` | the `GROK_CONFIG` variable for this session only |
| Antigravity | `agy` | a one-time registration of the “pelikan” server — only with your consent |

You install the agent program yourself and log in to it with your provider account. Pelikan looks for the command in the
`PATH` of your login shell. You change the list of programs in **Preferences › Agents** (**Add CLI**, **Restore
defaults**).

Pelikan's MCP server is available only to a session started from Pelikan: communication goes through a Unix socket
accessible only to your account (no network ports), and each session has its own one-time token passed to the program in
the environment and revoked when the session ends. Antigravity does not allow specifying a server for a single session,
so Pelikan asks for consent to a permanent registration; outside sessions started from Pelikan, the registered server
rejects every connection.

## Starting an agent

1. Choose **Tools › AI agent › Run Claude Code** (or another program).
2. The **session permission matrix** appears: a list of tools with their access levels. You can lower the level of
   selected tools or click **Everything read-only**. Raising a level is not possible. Click **Run**.
3. The **agent panel** with the program's terminal opens on the right side of the window. You work with the agent as in
   an ordinary terminal.

The agent's working directory is the folder of the active window's file (e.g. a project), and when the window has no
file — a temporary session directory. You show and hide the panel with **View › Agent panel**.

![Agent panel on the right side of the main window](../img/panel-agenta.png)

Below the terminal the panel shows the **agent activity**: each tool call with its time, state (in progress, approved,
rejected, error), parameters and result, and also a counter of requests waiting for consent. Buttons: **Revert
session…**, **Quit** and **Log**.

## Access levels

Every Pelikan command has an agent access level:

- **None** — the agent does not see this feature;
- **Read** — the agent sees the state or the result and changes nothing;
- **With consent** — the agent submits the operation, and you approve it after looking at the preview;
- **Full** — the agent performs the operation without asking, but only one that can be undone (e.g. a text change in a
  window), and everything goes to the log.

The lowest of the levels applies: that of the command, of the session matrix and of the connection. On a **read-only**
connection, or one without consent to changes (the **AI agent** tab of the connection definition), the agent has at most
**Read**. On production connections, consent to changes is off by default.

The agent's tools in brief:

- **Read**: list of connections (aliases only), window state and editor content, searching and describing objects,
  sources, DDL, dependencies and usages, queries, execution plan, compilation errors, DBMS_OUTPUT, utPLSQL tests and
  their results, coverage, list of sessions;
- **Full** (undoable): opening an object or a new window, inserting and replacing text, formatting, going to a line;
- **With consent**: compilation, executing a statement and a script, COMMIT, ROLLBACK, creating and generating a test
  package, running utPLSQL tests, installing utPLSQL.

The agent has **no** access to the Command Window and the HOST command, the system shell through Pelikan, the debugger,
the Sessions window (apart from reading the list of sessions) and killing sessions, SQL Trace, AWR/ASH/ADDM reports, SQL
Monitor and SQL Tuning Advisor, the Pro*C remote build, user tools, or the passwords, hosts, ports and user names of
connections.

## Consent window

When the agent wants to change the database, Pelikan shows the **Agent operation approval** window with a full preview:
the statements, the objects they affect (with tables, triggers and dependent objects), the estimated number of rows, the
execution plan and the arguments. When a change cannot be undone (COMMIT, DDL on a table), the window says so plainly
with a red warning.

![Agent operation approval window](../img/zgoda-agenta.png)

The window is designed so that nothing gets approved by accident:

- there is no default button — ↩ (e.g. pressed while typing in the agent terminal) approves nothing;
- **Commit** becomes active only after 0.8 seconds;
- Esc rejects the request (**Discard**);
- further requests wait in a queue until you have dealt with the current one.

## Transactions and undo

- The agent has **its own database sessions** — it does not see your uncommitted transaction and cannot commit it. In
  V$SESSION its sessions have MODULE “Pelikan agent”, and ACTION — the name of the tool.
- The agent's queries run in a read-only transaction, with limits on the number of rows, time and result size
  (**Preferences › Agents › Agent queries**; by default 500 rows, 30 s and 1 MB) and a limit of calls per minute. A
  query must be a single SELECT/WITH statement, without `FOR UPDATE` and without functions defined in the WITH clause.
- **The agent's DML stays uncommitted** until you separately consent to a COMMIT. Closing the agent session rolls back
  uncommitted changes (ROLLBACK). The agent's DDL is rejected when the agent has uncommitted DML (DDL would commit it
  implicitly).
- Before changing an object's code (package, procedure, view…) Pelikan saves the previous version. **Tools › AI agent ›
  Revert agent session…** (or **Revert session…** in the panel) restores the code of objects from before the session,
  drops objects created by the agent, undoes text changes in windows and closes windows opened by the agent. An object
  changed later by someone else is a conflict — it is skipped unless you choose **Force revert**. Committed changes
  (COMMIT) and DDL on tables cannot be undone.
- **Tools › AI agent › End agent session** ends the agent program, revokes the token, rolls back the agent's uncommitted
  changes and closes its database sessions.

## Connection settings for the agent

The **AI agent** tab in the connection definition:

- **Agent can see this connection (alias and environment only)** — turn it off to hide the connection from the agent.
- **Agent may change data and objects (with consent)** — off by default for the production environment.
- **Separate database user for the agent** — the agent connects through the proxy `main[agent]` as a user with limited
  privileges (e.g. SELECT only). An administrator must grant `ALTER USER agent GRANT CONNECT THROUGH main`; a second
  password is not needed. Recommended for production.
- **Columns masked for the agent** — column names (e.g. `PESEL, EMAIL`) or `SCHEMA.TABLE.COLUMN`. The values are masked
  in results, and queries referring to these columns are rejected.

Remember: everything the agent reads (code, query results) goes to the AI model provider. Masking works by column name
and is a convenience, not a security boundary — a column can be read e.g. through a view with a different name. The real
boundary is the privileges of the database user the agent uses. Functions called in queries can have side effects (e.g.
autonomous transactions) — here, too, only privileges protect you.

## Strict mode

**Preferences › Agents › Strict mode** (on by default) starts the agent program without its own shell and file editing —
only with Pelikan's tools, as far as the program allows it. When it does not, the agent panel shows a warning. An agent
program in full mode runs with the privileges of your macOS account — Pelikan warns about it but does not restrict it.

## Agent log

Every tool call — also a rejected one — goes to the log (JSONL files in Pelikan's data directory, without the token and
passwords). **Tools › AI agent › Agent log…** (or **Log** in the panel) opens the log viewer with the time, tool,
decision, arguments and result.
