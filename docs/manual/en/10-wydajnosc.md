# Execution plan, sessions and administration

## Execution plan (Explain Plan)

Place the cursor on a statement (or select it) and press F5 (**Tools › Explain Plan**). Pelikan opens a Explain Plan Window with
the plan from PLAN_TABLE. In PL/SQL code, variables are replaced with bind variables and `INTO` is skipped, so you get
the plan of a query from a procedure without rewriting it. You open an empty Explain Plan Window with **File › New › Explain
Plan Window**; Pelikan can create a missing PLAN_TABLE.

![Explain Plan Window — Diagram view](../img/plan-diagram.png)

- **Refresh plan** recalculates the plan for the text in the Explain Plan Window's editor, and **Optimizer goal** (*Same as session*,
  ALL_ROWS or FIRST_ROWS_n) adds a hint.
- A new plan opens fully expanded. The **Expand all branches** and **Collapse all branches** arrows next to the view
  selector above the plan tree (also on the **Plan** ribbon tab) expand every branch at once or collapse the tree to
  its root.
- Views: **Tree** (operations with cost, number of rows, bytes, time, execution order, and access and filter
  predicates), **Diagram** (a node per operation with cost, cardinality and step number), **Flame graph** (the cost of
  operations proportional to the parent) and **Text** (DBMS_XPLAN).
- The navigation buttons move through the operations in execution order: first, previous, next and last step.
- **Compare** puts the plan side by side with the window's previous plan or with the plan in a second Explain Plan Window: it
  matches operations and shows differences in cost, cardinality, order and predicates.
- **Save** saves the plan as text, HTML or XML (DBMS_XPLAN).

The plan is calculated in a separate tool session, so it does not affect the window's transaction.

## Autotrace

**Tools › Autotrace** (or the **Autotrace** button in the Explain Plan Window) executes the statement with measurement and shows
the actual plan: Starts, estimated (E-Rows) and actual (A-Rows) row counts with large discrepancies highlighted, times,
buffers and reads, as well as the change in session statistics before and after execution. DML statements are rolled
back after the measurement. Autotrace does not require the Tuning Pack.

Autotrace asks for variables in the statement like the SQL Window: bind variables (`:name`) get values from the
**Variables** window (remembered in the window), and substitution variables (`&name`) only when substitution is enabled
in the window; when it is disabled, `&` stays in the text without a question.

## Oracle Diagnostics and Tuning Packs

The **Tools › Performance (Oracle packs)** menu contains tools that use paid Oracle packs:

| Command | Pack | What it does |
|---|---|---|
| AWR report | Diagnostics | HTML report from AWR snapshots |
| ASH report | Diagnostics | HTML report of active sessions from the last minutes |
| ADDM report | Diagnostics | ADDM recommendations |
| SQL Monitor | Tuning | list of monitored queries (V$SQL_MONITOR) with a report for the selected one |
| SQL Monitor report | Tuning | HTML report of a monitored query |
| SQL Tuning Advisor | Tuning | recommendations for the statement under the cursor; the advisor task is deleted afterwards |

**Important — licenses.** Use these features only when the database is licensed for the corresponding pack (the Tuning
Pack also requires the Diagnostics Pack). On first use Pelikan asks which license the database has and remembers the
answer in the connection definition (the **Advanced** tab › **Diagnostics/Tuning Pack license**). Without a declared
license, or when the database parameter `CONTROL_MANAGEMENT_PACK_ACCESS` is `NONE` (or `DIAGNOSTIC` for Tuning Pack
features), the feature will not start. AI agents have no access to these tools. You can save the reports as HTML.

## Database sessions

**Tools › Sessions** shows the database sessions (V$SESSION):

- **Filter** selects the list query (e.g. *User sessions*); **Refresh every** n seconds turns on automatic refresh.
- Detail tabs of the selected session: **Current SQL**, **Open cursors**, **Locks**, **Statistics**, **Wait**.
- **Kill session** and **Kill immediately** end the session (`ALTER SYSTEM KILL SESSION`) after confirmation.
- **Actions** — among others enabling SQL Trace for the session (DBMS_MONITOR).
- **Queries…** lets you define your own filters (a WHERE condition), detail tabs (with `:sid`, `:serial#`) and actions.

Pelikan's sessions have the value “Pelikan” in the MODULE column, and AI agents' sessions — “Pelikan agent”.

## DBA panel and Instance Viewer

**View › DBA panel** collects administrative information: tablespaces with usage, data files, instance parameters,
users, roles, sessions and locks. In the parameter list **Change value…** executes `ALTER SYSTEM SET … SCOPE=BOTH`, and
in the user list **Lock** and **Unlock** change the account state — always after confirmation and with the same
safeguards as the SQL Window. Parts you have no privileges for show a message instead of data.

**Tools › Instance Viewer** is an instance dashboard: database version and state, uptime, number of sessions, wait
classes (increase per second), the most expensive queries (V$SQL), and SGA and PGA, with automatic refresh.

![Instance Viewer](../img/instance-viewer.png)

## DBMS Scheduler

**Tools › DBMS Scheduler** shows the scheduler objects in a tree: windows and window groups, job classes, schedules,
programs, chains, jobs, file watchers and credentials, with an SQL preview (View SQL) of the selected object.

- **New job…** creates a job with an inline schedule (e.g. `FREQ=DAILY;BYHOUR=3`) or a named one, with a class, a
  comment and e-mail notifications. You change an existing job with **Edit…**, and delete it after confirmation.
- **Runs** shows the run history with reports (all, failed, custom conditions) and color rules.
- **Running** shows jobs in progress; **Stop** and **Stop (Force)** interrupt them.
