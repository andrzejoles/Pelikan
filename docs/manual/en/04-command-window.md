# SQL*Plus Console

The SQL*Plus Console works like SQL*Plus: it executes statements line by line and scripts, and shows query results as text
in columns. You open it with **File › New › SQL*Plus Console** or from the connection's menu in the connection list.

The window has two tabs:

- **Dialog** — output and the **command line** at the bottom. Type an SQL*Plus command, an SQL statement or a PL/SQL
  block (a block is ended by a slash `/` on a separate line) and press ↩. The arrow keys scroll through the history of
  entered lines.
- **Editor** — a script with syntax highlighting. F8 (⌘↩) executes the selection or the whole script; the result appears
  on the Dialog tab. **Session › Break** (⌘.) stops the script.

The status bar shows the current settings of `ECHO`, `TERMOUT`, `FEEDBACK`, `VERIFY`, `AUTOPRINT`, `HEADING` and
`TIMING`; double-clicking an indicator toggles the setting.

## Supported SQL*Plus commands

- Running scripts: `@file`, `@@file` (relative to the current script), `START`, `RUN`, `/`.
- Variables: `DEFINE`, `UNDEFINE`, `ACCEPT`, `VARIABLE` (NUMBER, VARCHAR2, CHAR, CLOB, BLOB, REFCURSOR, DATE, BOOLEAN),
  `PRINT`, `EXECUTE`. `&&name` remembers the value as in SQL*Plus.
- Output: `PROMPT`, `PAUSE`, `SPOOL file` (also `APPEND`, `OFF`, `OUT`), `COLUMN` (`FORMAT`, `HEADING`, `NEW_VALUE`),
  `BREAK` (`SKIP`, `DUP`/`NODUP`), `COMPUTE` (`SUM`, `AVG`, `COUNT`, `MIN`, `MAX`, `NUM` with `LABEL`), `CLEAR`.
- `SET`: among others `AUTOPRINT`, `COLSEP`, `CONCAT`, `DEFINE`, `ECHO`, `ESCAPE`, `FEEDBACK`, `HEADING`, `LONG`,
  `NUMWIDTH`, `PAGESIZE`, `SCAN`, `SERVEROUTPUT` (`SIZE UNLIMITED`), `TERMOUT`, `TIMING`, `VERIFY`, `EXECPAUSE`.
  Unsupported `SET` options in scripts are skipped without an error.
- `SHOW` (`ERRORS`, `USER`, `RELEASE`, `SQLCODE`, `CONNECTION`, `ALL`…), `DESCRIBE`, `WHENEVER SQLERROR`, `CONNECT`,
  `DISCONNECT`, `EXIT`/`QUIT`, `REMARK`, `HELP`.
- Command buffer: `LIST`, `APPEND`, `CHANGE`, `DEL`, `INPUT`, `SAVE`, `GET`, `STORE SET`.
- `HOST`, `!` and `$` — an operating system command. Pelikan always shows it for confirmation and executes it without
  Pelikan's environment variables, with a 120-second limit. The AI agent has no access to the SQL*Plus Console.

An unsupported command is skipped with a message, so scripts written for SQL*Plus run to the end. `COPY` is not
supported.

After `@`, `@@` and `START`, code completion shows script files from the current directory, and after `CONNECT user@` —
aliases from `tnsnames.ora`. Commands with passwords (`CONNECT`, `ALTER USER … IDENTIFIED BY`, `CREATE DATABASE LINK`)
do not go to the command history.

## SQLcl commands

- `INFO` and `INFO+` — a description of a table or program with columns, indexes and statistics.
- `DDL object [file]` — the object's DDL on screen or to a file.
- `LOAD table file.csv [NEW]` — loading a CSV into a table (with `NEW` — creates the table).
- `FORMAT BUFFER` / `FORMAT FILE` — code formatting.
- `HISTORY` (with times, `CLEAR`), `ALIAS`, `REPEAT`, `CTAS`.
- `SET SQLFORMAT csv | json | xml | html | insert | loader | fixed | delimited | ansiconsole | default` — the format of
  query results.

## Pelikan commands

- `BEAUTIFY file` — formats a file with Pelikan's formatter.
- `EDIT object`, `VIEW object`, `BROWSE object`, `PROPERTIES object` — open the object in the appropriate window.
- `QUERYDATA table`, `EDITDATA table` — table data in a SQL Window (with editing).
- `TEST program`, `RECOMPILE object`, `INFO object`.
- `CD directory`, `DIR` — the window's current directory for scripts and `SPOOL`.
- `ZIP`, `EXPORT TABLES …`, `EXPORT OBJECTS …` — exporting tables and objects as in the export tools.
- `RUNTESTSET file.pts` — runs a Test Manager test set.

## Step-by-step script execution

`SET EXECPAUSE ON` or **Session › Pause Execution** makes Pelikan ask before each statement of a script whether to
execute it, execute the rest of the script, or abort.
