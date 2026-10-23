# Command Window

Command Window працює як SQL*Plus: виконує скрипти й команди рядок за рядком. Підтримує, зокрема, `SET`, `SHOW`,
`DEFINE`, `PROMPT`, `SPOOL`, `@` і `@@` (запуск файлу), `DESC`, `EXEC`, `VARIABLE`, `PRINT`, `COLUMN`, `BREAK`,
`COMPUTE`, `WHENEVER SQLERROR`, а також команди SQLcl: `INFO`, `INFO+`, `DDL`, `LOAD`, `FORMAT`, `HISTORY`, `ALIAS`.

Команди, що містять паролі (`CONNECT`, `ALTER USER … IDENTIFIED BY`), не потрапляють до історії команд.

Pelikan також додає власні команди, наприклад `BEAUTIFY`, `EXPORT` і `RUNTESTSET`.
