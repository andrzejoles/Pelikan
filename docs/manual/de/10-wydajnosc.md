# Ausführungsplan, Sitzungen und Administration

## Ausführungsplan (Explain Plan)

Setzen Sie den Cursor auf einen Befehl (oder wählen Sie ihn aus) und drücken Sie F5 (**Werkzeuge › Explain Plan**).
Pelikan öffnet ein Planfenster mit dem Plan aus PLAN_TABLE. In PL/SQL-Code werden Variablen durch Bindevariablen ersetzt
und `INTO` wird übergangen, sodass Sie den Plan einer Abfrage aus einer Prozedur ohne Umschreiben erhalten. Ein leeres
Planfenster öffnen Sie über **Datei › Neu › Explain Plan Window**; eine fehlende PLAN_TABLE kann Pelikan anlegen.

![Planfenster — Ansicht „Diagramm“](../img/plan-diagram.png)

- **Plan aktualisieren** berechnet den Plan für den Text im Editor des Planfensters neu, **Optimizer-Ziel** (*Wie in der Sitzung*,
  ALL_ROWS oder FIRST_ROWS_n) fügt einen Hint hinzu.
- Ansichten: **Baum** (Operationen mit Kosten, Zeilenzahl, Bytes, Zeit, Ausführungsreihenfolge sowie Zugriffs- und
  Filterprädikaten), **Diagramm** (ein Knoten je Operation mit Kosten, Kardinalität und Schrittnummer), **Flame Graph**
  (Kosten der Operationen im Verhältnis zum Elternknoten) und **Text** (DBMS_XPLAN).
- Die Navigationsschaltflächen gehen die Operationen in Ausführungsreihenfolge durch: erster, vorheriger, nächster und
  letzter Schritt.
- **Vergleichen** stellt den Plan dem vorherigen Plan des Fensters oder dem Plan in einem zweiten Planfenster gegenüber:
  Es ordnet die Operationen einander zu und zeigt Unterschiede bei Kosten, Kardinalität, Reihenfolge und Prädikaten.
- **Speichern** speichert den Plan als Text, HTML oder XML (DBMS_XPLAN).

Der Plan wird in einer separaten Werkzeugsitzung berechnet und beeinflusst daher die Transaktion des Fensters nicht.

## Autotrace

**Werkzeuge › Autotrace** (oder die Schaltfläche **Autotrace** im Planfenster) führt den Befehl mit Messung aus und
zeigt den tatsächlichen Plan: Starts, geschätzte (E-Rows) und tatsächliche (A-Rows) Zeilenzahlen mit Hervorhebung großer
Abweichungen, Zeiten, Puffer und Lesevorgänge sowie die Änderung der Sitzungsstatistiken vor und nach der Ausführung.
DML-Befehle werden nach der Messung zurückgerollt. Autotrace erfordert kein Tuning Pack.

Nach Variablen im Befehl fragt Autotrace wie das SQL-Fenster: Bindevariablen (`:name`) erhalten Werte aus dem Fenster
**Variablen** (im Fenster gespeichert), Substitutionsvariablen (`&name`) nur bei eingeschalteter Substitution des
Fensters; bei ausgeschalteter bleibt `&` ohne Nachfrage im Text.

## Oracle Diagnostics und Tuning Pack

Das Menü **Werkzeuge › Performance (Oracle-Packs)** enthält Werkzeuge, die kostenpflichtige Oracle-Packs nutzen:

| Befehl | Pack | Was er tut |
|---|---|---|
| AWR-Bericht | Diagnostics | HTML-Bericht aus AWR-Snapshots |
| ASH-Bericht | Diagnostics | HTML-Bericht der aktiven Sitzungen der letzten Minuten |
| ADDM-Bericht | Diagnostics | ADDM-Empfehlungen |
| SQL Monitor | Tuning | Liste der überwachten Abfragen (V$SQL_MONITOR) mit Bericht für die ausgewählte |
| SQL-Monitor-Bericht | Tuning | HTML-Bericht einer überwachten Abfrage |
| SQL Tuning Advisor | Tuning | Empfehlungen für den Befehl unter dem Cursor; die Advisor-Aufgabe wird anschließend gelöscht |

**Wichtig — Lizenzen.** Verwenden Sie diese Funktionen nur, wenn die Datenbank für das entsprechende Pack lizenziert ist
(das Tuning Pack setzt auch das Diagnostics Pack voraus). Bei der ersten Verwendung fragt Pelikan, welche Lizenz die
Datenbank hat, und merkt sich die Antwort in der Verbindungsdefinition (Tab **Erweitert** ›
**Diagnostics/Tuning-Pack-Lizenz**). Ohne angegebene Lizenz oder wenn der Datenbankparameter
`CONTROL_MANAGEMENT_PACK_ACCESS` den Wert `NONE` hat (oder `DIAGNOSTIC` für Funktionen des Tuning Pack), startet die
Funktion nicht. KI-Agenten haben keinen Zugriff auf diese Werkzeuge. Die Berichte speichern Sie als HTML.

## Datenbanksitzungen

**Werkzeuge › Sitzungen** zeigt die Sitzungen der Datenbank (V$SESSION):

- **Filter** wählt die Abfrage der Liste (z. B. *Benutzersitzungen*); **Aktualisieren alle** n Sekunden schaltet die
  automatische Aktualisierung ein.
- Detail-Tabs der ausgewählten Sitzung: **Aktuelles SQL**, **Offene Cursor**, **Sperren**, **Statistiken**, **Warten**.
- **Sitzung beenden** und **Sofort beenden** beenden die Sitzung (`ALTER SYSTEM KILL SESSION`) nach Bestätigung.
- **Aktionen** — u. a. das Aktivieren von SQL Trace für die Sitzung (DBMS_MONITOR).
- **Abfragen …** ermöglicht eigene Filter (WHERE-Bedingung), Detail-Tabs (mit `:sid`, `:serial#`) und Aktionen.

Die Sitzungen von Pelikan haben in der Spalte MODULE den Wert „Pelikan“, die Sitzungen von KI-Agenten „Pelikan agent“.

## DBA-Bereich und Instance Viewer

**Ansicht › DBA-Bereich** sammelt administrative Informationen: Tablespaces mit Belegung, Datendateien, Instanzparameter,
Benutzer, Rollen, Sitzungen und Sperren. In der Parameterliste führt **Wert ändern …** `ALTER SYSTEM SET … SCOPE=BOTH`
aus, in der Benutzerliste ändern **Sperren** und **Entsperren** den Kontostatus — immer nach Bestätigung und mit
denselben Schutzmechanismen wie das SQL Window. Bereiche, für die Ihnen die Berechtigungen fehlen, zeigen eine Meldung
statt der Daten.

**Werkzeuge › Instance Viewer** ist ein Dashboard der Instanz: Version und Zustand der Datenbank, Laufzeit, Anzahl der
Sitzungen, Warteklassen (Zuwachs pro Sekunde), die teuersten Abfragen (V$SQL) sowie SGA und PGA, mit automatischer
Aktualisierung.

![Instance Viewer](../img/instance-viewer.png)

## DBMS Scheduler

**Werkzeuge › DBMS Scheduler** zeigt die Objekte des Schedulers in einem Baum: Fenster und Fenstergruppen, Job-Klassen,
Zeitpläne, Programme, Ketten, Jobs, File Watcher und Anmeldedaten, mit einer SQL-Vorschau (View SQL) des ausgewählten
Objekts.

- **Neuer Job …** legt einen Job mit eingebettetem (z. B. `FREQ=DAILY;BYHOUR=3`) oder benanntem Zeitplan an, mit Klasse,
  Kommentar und E-Mail-Benachrichtigungen. Einen vorhandenen Job ändern Sie mit **Bearbeiten …**, löschen ihn nach
  Bestätigung.
- **Läufe** zeigt die Ausführungshistorie mit Berichten (alle, fehlgeschlagene, eigene Bedingungen) und Farbregeln.
- **Laufend** zeigt die laufenden Jobs; **Anhalten** und **Anhalten (Force)** unterbrechen sie.
