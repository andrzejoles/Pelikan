# Command Window

La Command Window funciona como SQL*Plus: ejecuta scripts y comandos línea a línea. Admite, entre otros, `SET`, `SHOW`,
`DEFINE`, `PROMPT`, `SPOOL`, `@` y `@@` (ejecución de un archivo), `DESC`, `EXEC`, `VARIABLE`, `PRINT`, `COLUMN`,
`BREAK`, `COMPUTE`, `WHENEVER SQLERROR` y comandos de SQLcl: `INFO`, `INFO+`, `DDL`, `LOAD`, `FORMAT`, `HISTORY`,
`ALIAS`.

Los comandos que contienen contraseñas (`CONNECT`, `ALTER USER … IDENTIFIED BY`) no se guardan en el historial de
comandos.

Pelikan añade también comandos propios, p. ej., `BEAUTIFY`, `EXPORT` y `RUNTESTSET`.
