# Command Window

Command Window działa jak SQL*Plus: wykonuje skrypty i polecenia linia po linii. Obsługuje m.in. `SET`, `SHOW`,
`DEFINE`, `PROMPT`, `SPOOL`, `@` i `@@` (uruchomienie pliku), `DESC`, `EXEC`, `VARIABLE`, `PRINT`, `COLUMN`, `BREAK`,
`COMPUTE`, `WHENEVER SQLERROR` oraz polecenia SQLcl: `INFO`, `INFO+`, `DDL`, `LOAD`, `FORMAT`, `HISTORY`, `ALIAS`.

Polecenia zawierające hasła (`CONNECT`, `ALTER USER … IDENTIFIED BY`) nie trafiają do historii poleceń.

Pelikan dodaje też własne polecenia, np. `BEAUTIFY`, `EXPORT` i `RUNTESTSET`.
