# SQL*Plus-Konsole

## Wozu es dient

**SQL*Plus** ist das klassische Textwerkzeug von Oracle zum Ausführen von Skripten. Viele Teams rollen Änderungen in der
Datenbank mit SQL*Plus-Skripten aus — mit `SET`, `PROMPT`, `SPOOL` (Ausgabe in eine Datei schreiben) oder
`WHENEVER SQLERROR` (Abbruch bei einem Fehler). Das SQL Window versteht sie nicht, die **SQL*Plus-Konsole** in Pelikan
schon.

**Wann verwenden:** zum Ausführen fertiger Rollout-Skripte (`@install.sql`), für Skripte, die Ausgaben in eine Datei
schreiben, und wenn Sie sehen möchten, wie sich ein Skript in SQL*Plus beim Administrator verhält. Für gewöhnliche
Abfragen und das Durchsehen von Daten ist das SQL Window mit seinem Ergebnisraster bequemer (Kapitel 3).

Die SQL*Plus-Konsole arbeitet wie SQL*Plus: Sie führt Befehle zeilenweise und Skripte aus und zeigt Abfrageergebnisse als
Text in Spalten. Sie öffnen sie über **Datei › Neu › SQL*Plus-Konsole** oder über das Menü der Verbindung in der
Verbindungsliste.

Das Fenster hat zwei Tabs:

- **Dialog** — die Ausgabe und unten die **Befehlszeile**. Geben Sie einen SQL*Plus-Befehl, einen SQL-Befehl oder einen
  PL/SQL-Block ein (ein Block endet mit einem Schrägstrich `/` in einer eigenen Zeile) und drücken Sie ↩. Die
  Pfeiltasten blättern im Verlauf der eingegebenen Zeilen.
- **Editor** — ein Skript mit Syntaxhervorhebung. F8 (⌘↩) führt die Auswahl oder das ganze Skript aus; das Ergebnis
  erscheint im Tab „Dialog“. **Sitzung › Unterbrechen** (⌘.) hält das Skript an.

Die Statusleiste zeigt die aktuellen Einstellungen `ECHO`, `TERMOUT`, `FEEDBACK`, `VERIFY`, `AUTOPRINT`, `HEADING` und
`TIMING`; ein Doppelklick auf eine Anzeige schaltet die Einstellung um.

> **Übung: Ihr erstes SQL*Plus-Skript.**
> 1. Öffnen Sie **Datei › Neu › SQL*Plus-Konsole**.
>    *Ergebnis:* ein Fenster mit dem Buchstaben **C**, der Tab **Dialog** mit einer Befehlszeile unten.
> 2. Geben Sie in der Befehlszeile `DESCRIBE pel_employees` ein und drücken Sie ↩.
>    *Ergebnis:* eine Liste der Spalten der Tabelle mit ihren Typen und der Angabe, ob sie leer sein dürfen (NULL).
> 3. Wechseln Sie zum Tab **Editor** und geben Sie das Skript ein:
>
>    ```sql
>    SET SERVEROUTPUT ON
>    SET TIMING ON
>    PROMPT Mitarbeiter der Abteilung Informatyka:
>    EXECUTE pel_emp_api.print_department(20)
>    COLUMN last_name HEADING 'Nachname' FORMAT A15
>    SELECT last_name, salary FROM pel_employees WHERE dept_id = 20;
>    ```
>
> 4. Drücken Sie **F8**.
>    *Ergebnis:* Der Tab Dialog zeigt den PROMPT-Text, die Liste aus `print_department` (DBMS_OUTPUT), eine Texttabelle
>    mit der Überschrift „Nachname“ und die Ausführungszeit jedes Befehls (TIMING). Die Statusleiste zeigt TIMING an.
> 5. Geben Sie in der Befehlszeile `DIR` ein, um das aktuelle Verzeichnis der Konsole zu sehen (Sie ändern es mit
>    `CD verzeichnis`). Geben Sie dann `SPOOL mitarbeiter.txt`, `SELECT * FROM pel_departments;` und `SPOOL OFF` ein.
>    *Ergebnis:* Im aktuellen Verzeichnis liegt die Datei `mitarbeiter.txt` mit dem Abfrageergebnis.
>
> ⚠️ **Achtung.** Beginnen Sie ein Rollout-Skript mit `WHENEVER SQLERROR EXIT SQL.SQLCODE` — sonst laufen nach einem
> fehlgeschlagenen Befehl die nächsten weiter und die Datenbank bleibt „halb“ geändert. Lesen Sie ein fremdes Skript vor
> dem Ausführen und prüfen Sie, auf welcher Verbindung die Konsole ist.

## Unterstützte SQL*Plus-Befehle

- Skripte ausführen: `@datei`, `@@datei` (relativ zum aktuellen Skript), `START`, `RUN`, `/`.
- Variablen: `DEFINE`, `UNDEFINE`, `ACCEPT`, `VARIABLE` (NUMBER, VARCHAR2, CHAR, CLOB, BLOB, REFCURSOR, DATE, BOOLEAN),
  `PRINT`, `EXECUTE`. `&&name` merkt sich den Wert wie in SQL*Plus.
- Ausgabe: `PROMPT`, `PAUSE`, `SPOOL datei` (auch `APPEND`, `OFF`, `OUT`), `COLUMN` (`FORMAT`, `HEADING`, `NEW_VALUE`),
  `BREAK` (`SKIP`, `DUP`/`NODUP`), `COMPUTE` (`SUM`, `AVG`, `COUNT`, `MIN`, `MAX`, `NUM` mit `LABEL`), `CLEAR`.
- `SET`: u. a. `AUTOPRINT`, `COLSEP`, `CONCAT`, `DEFINE`, `ECHO`, `ESCAPE`, `FEEDBACK`, `HEADING`, `LONG`, `NUMWIDTH`,
  `PAGESIZE`, `SCAN`, `SERVEROUTPUT` (`SIZE UNLIMITED`), `TERMOUT`, `TIMING`, `VERIFY`, `EXECPAUSE`. Nicht unterstützte
  `SET`-Optionen werden in Skripten ohne Fehler übergangen.
- `SHOW` (`ERRORS`, `USER`, `RELEASE`, `SQLCODE`, `CONNECTION`, `ALL` …), `DESCRIBE`, `WHENEVER SQLERROR`, `CONNECT`,
  `DISCONNECT`, `EXIT`/`QUIT`, `REMARK`, `HELP`.
- Befehlspuffer: `LIST`, `APPEND`, `CHANGE`, `DEL`, `INPUT`, `SAVE`, `GET`, `STORE SET`.
- `HOST`, `!` und `$` — ein Betriebssystembefehl. Pelikan zeigt ihn immer zur Bestätigung an und führt ihn ohne die
  Umgebungsvariablen von Pelikan und mit einem Limit von 120 Sekunden aus. Der KI-Agent hat keinen Zugriff auf die
  SQL*Plus-Konsole.

Ein nicht unterstützter Befehl wird mit einem Hinweis übergangen, sodass für SQL*Plus geschriebene Skripte bis zum Ende
laufen. `COPY` wird nicht unterstützt.

Nach `@`, `@@` und `START` zeigt der Codevorschlag Skriptdateien aus dem aktuellen Verzeichnis, nach `CONNECT benutzer@`
die Aliase aus `tnsnames.ora`. Befehle mit Passwörtern (`CONNECT`, `ALTER USER … IDENTIFIED BY`, `CREATE DATABASE LINK`)
gelangen nicht in den Befehlsverlauf.

## SQLcl-Befehle

- `INFO` und `INFO+` — Beschreibung einer Tabelle oder eines Programms mit Spalten, Indizes und Statistiken.
- `DDL objekt [datei]` — die DDL des Objekts auf dem Bildschirm oder in eine Datei.
- `LOAD tabelle datei.csv [NEW]` — Laden einer CSV-Datei in eine Tabelle (mit `NEW` — legt die Tabelle an).
- `FORMAT BUFFER` / `FORMAT FILE` — Codeformatierung.
- `HISTORY` (mit Zeiten, `CLEAR`), `ALIAS`, `REPEAT`, `CTAS`.
- `SET SQLFORMAT csv | json | xml | html | insert | loader | fixed | delimited | ansiconsole | default` — das Format der
  Abfrageergebnisse.

## Pelikan-Befehle

- `BEAUTIFY datei` — formatiert eine Datei mit dem Formatierer von Pelikan.
- `EDIT objekt`, `VIEW objekt`, `BROWSE objekt`, `PROPERTIES objekt` — öffnen das Objekt im passenden Fenster.
- `QUERYDATA tabelle`, `EDITDATA tabelle` — Tabellendaten im SQL Window (mit Bearbeitungsmöglichkeit).
- `TEST programm`, `RECOMPILE objekt`, `INFO objekt`.
- `CD verzeichnis`, `DIR` — das aktuelle Verzeichnis des Fensters für Skripte und `SPOOL`.
- `ZIP`, `EXPORT TABLES …`, `EXPORT OBJECTS …` — Export von Tabellen und Objekten wie in den Exportwerkzeugen.
- `RUNTESTSET datei.pts` — führt ein Test-Set des Test Managers aus.

## Schrittweise Skriptausführung

`SET EXECPAUSE ON` oder **Sitzung › Ausführung anhalten** bewirkt, dass Pelikan vor jedem Befehl des Skripts fragt, ob
er ausgeführt, der Rest des Skripts ausgeführt oder abgebrochen werden soll. So führen Sie ein unbekanntes Skript sicher zum
ersten Mal aus: Sie sehen jeden Befehl, bevor er die Datenbank erreicht.
