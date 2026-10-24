# KI-Agenten

Mit Pelikan können Sie mit einem KI-Agenten arbeiten, der in einem in das Fenster eingebauten Terminal läuft — z. B.
Claude Code — und Ihre Fenster und die Datenbank ausschließlich über die Werkzeuge von Pelikan und nach Regeln sieht,
die Sie kontrollieren. Der Agent kann Code und Daten lesen, Pläne analysieren, Code in Fenstern schreiben und
formatieren, und Änderungen in der Datenbank nimmt er erst nach Ihrer Zustimmung vor.

## Unterstützte Programme

| Agent | Befehl | Wie er den MCP-Server von Pelikan erhält |
|---|---|---|
| Claude Code | `claude` | `--mcp-config` nur für diese Sitzung |
| Codex CLI | `codex` | `-c mcp_servers…` nur für diese Sitzung |
| Grok CLI | `grok` | Variable `GROK_CONFIG` nur für diese Sitzung |
| Antigravity | `agy` | einmalige Registrierung des Servers „pelikan“ — nur mit Ihrer Zustimmung |

Das Agentenprogramm installieren Sie selbst und melden sich darin mit Ihrem Konto beim Anbieter an. Pelikan sucht den
Befehl im `PATH` Ihrer Login-Shell. Die Liste der Programme ändern Sie unter **Einstellungen › Agenten** (**CLI
hinzufügen**, **Standard wiederherstellen**).

Der MCP-Server von Pelikan steht nur einer aus Pelikan gestarteten Sitzung zur Verfügung: Die Kommunikation läuft über
einen Unix-Socket, auf den nur Ihr Konto zugreifen kann (ohne Netzwerkports), und jede Sitzung hat ein eigenes
Einmal-Token, das dem Programm in der Umgebung übergeben und nach dem Ende der Sitzung ungültig wird. Antigravity
erlaubt es nicht, einen Server nur für eine Sitzung anzugeben, daher fragt Pelikan nach der Zustimmung zu einer
dauerhaften Registrierung; außerhalb von aus Pelikan gestarteten Sitzungen weist der registrierte Server jede Verbindung
ab.

## Einen Agenten starten

1. Wählen Sie **Werkzeuge › KI-Agent › Claude Code starten** (oder ein anderes Programm).
2. Es erscheint die **Berechtigungsmatrix der Sitzung**: eine Liste der Werkzeuge mit ihrer Zugriffsstufe. Sie können
   die Stufe ausgewählter Werkzeuge senken oder auf **Alles schreibgeschützt** klicken. Eine Stufe zu erhöhen ist nicht
   möglich. Klicken Sie auf **Ausführen**.
3. Rechts im Fenster öffnet sich der **Agentenbereich** mit dem Terminal des Programms. Sie arbeiten mit dem Agenten wie
   in einem gewöhnlichen Terminal.

Das Arbeitsverzeichnis des Agenten ist der Ordner der Datei des aktiven Fensters (z. B. eines Projekts), hat das Fenster
keine Datei, ein temporäres Sitzungsverzeichnis. Den Bereich blenden Sie über **Ansicht › Agentenbereich** ein und aus.

![Agentenbereich rechts im Hauptfenster](../img/panel-agenta.png)

Unter dem Terminal zeigt der Bereich die **Agent-Aktivität**: jeden Werkzeugaufruf mit Zeit, Status (läuft, genehmigt,
abgelehnt, Fehler), Parametern und Ergebnis sowie einen Zähler der Anfragen, die auf Zustimmung warten. Schaltflächen:
**Sitzung rückgängig machen …**, **Beenden** und **Protokoll**.

## Zugriffsstufen

Jeder Befehl von Pelikan hat eine Zugriffsstufe für Agenten:

- **Keine** — der Agent sieht diese Funktion nicht;
- **Lesen** — der Agent sieht den Zustand oder das Ergebnis und ändert nichts;
- **Mit Zustimmung** — der Agent meldet die Operation an, und Sie genehmigen sie nach Ansicht der Vorschau;
- **Vollständig** — der Agent führt die Operation ohne Rückfrage aus, aber nur eine, die sich rückgängig machen lässt
  (z. B. eine Textänderung in einem Fenster), und alles wird protokolliert.

Es gilt die niedrigste der Stufen: die des Befehls, der Sitzungsmatrix und der Verbindung. Auf einer
**schreibgeschützten** Verbindung oder einer ohne Zustimmung zu Änderungen (Tab **KI-Agent** der Verbindungsdefinition)
hat der Agent höchstens **Lesen**. Auf Produktionsverbindungen ist die Zustimmung zu Änderungen standardmäßig
deaktiviert.

Die Werkzeuge des Agenten im Überblick:

- **Lesen**: Liste der Verbindungen (nur Aliase), Zustand der Fenster und Inhalt des Editors, Suchen und Beschreiben von
  Objekten, Quelltexte, DDL, Abhängigkeiten und Verwendungen, Abfragen, Ausführungsplan, Kompilierungsfehler,
  DBMS_OUTPUT, utPLSQL-Tests und ihre Ergebnisse, Abdeckung, Liste der Sitzungen;
- **Vollständig** (rückgängig machbar): Öffnen eines Objekts oder eines neuen Fensters, Einfügen und Ersetzen von Text,
  Formatieren, Sprung zu einer Zeile;
- **Mit Zustimmung**: Kompilieren, Ausführen eines Befehls und eines Skripts, COMMIT, ROLLBACK, Anlegen und Generieren
  eines Testpakets, Ausführen von utPLSQL-Tests, Installieren von utPLSQL.

Der Agent hat **keinen** Zugriff auf das Command Window und den Befehl HOST, auf die System-Shell über Pelikan, den
Debugger, das Fenster „Sitzungen“ (außer dem Lesen der Sitzungsliste) und das Beenden von Sitzungen, auf SQL Trace,
AWR/ASH/ADDM-Berichte, SQL Monitor und SQL Tuning Advisor, den Pro*C-Remote-Build, Benutzerwerkzeuge und auch nicht auf
Passwörter, Hosts, Ports und Benutzernamen der Verbindungen.

## Zustimmungsfenster

Wenn der Agent die Datenbank ändern möchte, zeigt Pelikan das Fenster **Zustimmung zur Agentenoperation** mit einer
vollständigen Vorschau: die Befehle, die betroffenen Objekte (mit Tabellen, Triggern und abhängigen Objekten), die
geschätzte Zeilenzahl, den Ausführungsplan und die Argumente. Lässt sich eine Änderung nicht rückgängig machen (COMMIT,
DDL auf einer Tabelle), sagt das Fenster dies mit einer roten Warnung deutlich.

![Fenster zur Zustimmung zu einer Agentenoperation](../img/zgoda-agenta.png)

Das Fenster ist so gestaltet, dass nichts versehentlich genehmigt wird:

- es gibt keine Standardschaltfläche — ↩ (z. B. beim Tippen im Terminal des Agenten gedrückt) genehmigt nichts;
- **Zulassen** wird erst nach 0,8 Sekunden aktiv;
- Esc lehnt die Anfrage ab (**Ablehnen**);
- weitere Anfragen warten in einer Warteschlange, bis Sie die aktuelle bearbeitet haben.

## Transaktionen und Rückgängigmachen

- Der Agent hat **eigene Datenbanksitzungen** — er sieht Ihre nicht festgeschriebene Transaktion nicht und kann sie
  nicht festschreiben. In V$SESSION haben seine Sitzungen MODULE „Pelikan agent“ und als ACTION den Namen des Werkzeugs.
- Abfragen des Agenten laufen in einer schreibgeschützten Transaktion mit Limits für Zeilenzahl, Zeit und Ergebnisgröße
  (**Einstellungen › Agenten › Agentenabfragen**; standardmäßig 500 Zeilen, 30 s und 1 MB) und einem Limit der Aufrufe
  pro Minute. Eine Abfrage muss ein einzelner SELECT/WITH-Befehl sein, ohne `FOR UPDATE` und ohne in der WITH-Klausel
  definierte Funktionen.
- **DML des Agenten bleibt nicht festgeschrieben**, bis Sie einem COMMIT gesondert zustimmen. Das Schließen der
  Agentensitzung rollt nicht festgeschriebene Änderungen zurück (ROLLBACK). DDL des Agenten wird abgewiesen, wenn der
  Agent nicht festgeschriebene DML hat (DDL würde sie implizit festschreiben).
- Vor einer Änderung am Code eines Objekts (Paket, Prozedur, View …) speichert Pelikan die vorherige Version.
  **Werkzeuge › KI-Agent › Agentensitzung rückgängig machen …** (oder **Sitzung rückgängig machen …** im Bereich) stellt
  den Code der Objekte vom Stand vor der Sitzung wieder her, löscht vom Agenten angelegte Objekte, macht Textänderungen
  in Fenstern rückgängig und schließt vom Agenten geöffnete Fenster. Ein später von jemand anderem geändertes Objekt ist
  ein Konflikt — es wird übersprungen, es sei denn, Sie wählen **Erzwungen rückgängig machen**. Festgeschriebene
  Änderungen (COMMIT) und DDL auf Tabellen lassen sich nicht rückgängig machen.
- **Werkzeuge › KI-Agent › Agentensitzung beenden** beendet das Agentenprogramm, macht das Token ungültig, rollt die
  nicht festgeschriebenen Änderungen des Agenten zurück und schließt seine Datenbanksitzungen.

## Verbindungseinstellungen für den Agenten

Tab **KI-Agent** in der Verbindungsdefinition:

- **Agent sieht diese Verbindung (nur Alias und Umgebung)** — deaktivieren, um die Verbindung vor dem Agenten zu
  verbergen.
- **Agent darf Daten und Objekte ändern (mit Zustimmung)** — für die Produktionsumgebung standardmäßig deaktiviert.
- **Eigener Datenbankbenutzer für den Agenten** — der Agent verbindet sich über den Proxy `haupt[agent]` als Benutzer
  mit eingeschränkten Berechtigungen (z. B. nur SELECT). Ein Administrator muss `ALTER USER agent GRANT CONNECT THROUGH
  haupt` erteilen; ein zweites Passwort ist nicht nötig. Für die Produktion empfohlen.
- **Für den Agenten maskierte Spalten** — Spaltennamen (z. B. `PESEL, EMAIL`) oder `SCHEMA.TABELLE.SPALTE`. Die Werte
  werden in Ergebnissen maskiert, und Abfragen, die sich auf diese Spalten beziehen, werden abgewiesen.

Denken Sie daran: Alles, was der Agent liest (Code, Abfrageergebnisse), gelangt zum Anbieter des KI-Modells. Das
Maskieren arbeitet nach dem Spaltennamen und ist eine Erleichterung, keine Sicherheitsgrenze — eine Spalte lässt sich z.
B. über eine View mit anderem Namen lesen. Die eigentliche Grenze sind die Berechtigungen des Datenbankbenutzers, den
der Agent verwendet. In Abfragen aufgerufene Funktionen können Nebenwirkungen haben (z. B. autonome Transaktionen) —
auch davor schützen nur Berechtigungen.

## Strikter Modus

**Einstellungen › Agenten › Strikter Modus** (standardmäßig aktiviert) startet das Agentenprogramm ohne eigene Shell und
ohne Dateibearbeitung — nur mit den Werkzeugen von Pelikan, sofern das Programm das zulässt. Lässt es das nicht zu,
zeigt der Agentenbereich eine Warnung. Ein Agentenprogramm im vollen Modus läuft mit den Rechten Ihres macOS-Kontos —
Pelikan warnt, schränkt es aber nicht ein.

## Agentenprotokoll

Jeder Werkzeugaufruf — auch ein abgelehnter — landet im Protokoll (JSONL-Dateien im Datenverzeichnis von Pelikan, ohne
Token und Passwörter). **Werkzeuge › KI-Agent › Agentenprotokoll …** (oder **Protokoll** im Bereich) öffnet die
Protokollansicht mit Zeit, Werkzeug, Entscheidung, Argumenten und Ergebnis.
