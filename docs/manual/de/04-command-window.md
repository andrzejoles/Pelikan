# Command Window

Das Command Window arbeitet wie SQL*Plus: Es führt Skripte und Befehle Zeile für Zeile aus. Es unterstützt u. a. `SET`,
`SHOW`, `DEFINE`, `PROMPT`, `SPOOL`, `@` und `@@` (Ausführen einer Datei), `DESC`, `EXEC`, `VARIABLE`, `PRINT`,
`COLUMN`, `BREAK`, `COMPUTE`, `WHENEVER SQLERROR` sowie die SQLcl-Befehle `INFO`, `INFO+`, `DDL`, `LOAD`, `FORMAT`,
`HISTORY`, `ALIAS`.

Befehle mit Passwörtern (`CONNECT`, `ALTER USER … IDENTIFIED BY`) werden nicht in den Befehlsverlauf aufgenommen.

Pelikan fügt außerdem eigene Befehle hinzu, z. B. `BEAUTIFY`, `EXPORT` und `RUNTESTSET`.
