# Command Window

The Command Window works like SQL*Plus: it executes scripts and commands line by line. It supports, among others, `SET`,
`SHOW`, `DEFINE`, `PROMPT`, `SPOOL`, `@` and `@@` (running a file), `DESC`, `EXEC`, `VARIABLE`, `PRINT`, `COLUMN`,
`BREAK`, `COMPUTE`, `WHENEVER SQLERROR` and SQLcl commands: `INFO`, `INFO+`, `DDL`, `LOAD`, `FORMAT`, `HISTORY`, `ALIAS`.

Commands containing passwords (`CONNECT`, `ALTER USER … IDENTIFIED BY`) are not added to the command history.

Pelikan also adds its own commands, e.g. `BEAUTIFY`, `EXPORT` and `RUNTESTSET`.
