# Sicherheit und Datenschutz

Dieses Kapitel fasst an einer Stelle zusammen, wie Pelikan Passwörter, Daten und Datenbanken schützt — auch vor Fehlern
und vor KI-Agenten.

## Passwörter

- Datenbankpasswörter, SSH-Passwörter (Tunnel und Pro*C-Ziele) und Passwörter von SSH-Schlüsseln werden **ausschließlich
  im macOS-Schlüsselbund** gespeichert — im Anmeldeschlüsselbund, ohne iCloud-Synchronisierung, nur bei entsperrtem Mac
  verfügbar.
- Passwörter gelangen **nie** in die Dateien von Pelikan (Verbindungsdefinitionen, Einstellungen, Worksets, Exporte), in
  Protokolle, den Befehlsverlauf, Prozessargumente oder Umgebungsvariablen. Befehle mit Passwörtern (`CONNECT`, `ALTER
  USER … IDENTIFIED BY`, `CREATE DATABASE LINK`) werden nicht im Befehlsverlauf gespeichert.
- Ein nicht im Schlüsselbund gesichertes Passwort wird nur bis zum Beenden der Anwendung im Speicher gehalten.
- Die Option **Vor Verwendung eines gespeicherten Passworts Touch ID oder Mac-Passwort verlangen** (**Einstellungen ›
  Oracle › Verbindungspasswörter**) verlangt während der Laufzeit der Anwendung einmal pro Verbindung eine Bestätigung —
  auch wenn ein KI-Agent die Verbindung verwendet.
- Das SSH-Passwort gelangt über eine einmalige Pipe, auf die nur Ihr Konto zugreifen kann, zum Programm `ssh` und nicht
  über Argumente, die Umgebung oder eine Datei.
- Passwörter aus einem Oracle Wallet gelangen nie zu Pelikan — um die Anmeldung kümmert sich der Oracle-Client.
- Der Export von Verbindungsdefinitionen, der Export von Einstellungen, Definitionen von Jobs, Übertragungen und
  Benutzerwerkzeugen, utPLSQL-Skripte für CI und Startparameter enthalten keine Passwörter.

## Schutz der Datenbanken vor Fehlern

- Die **Umgebung der Verbindung** (Entwicklung, Test, Produktion) ist in der gesamten Oberfläche an der Farbe zu
  erkennen.
- Auf einer **Produktionsverbindung** erfordern Befehle, die Daten oder Objekte ändern, eine Bestätigung.
- Eine **schreibgeschützte** Verbindung blockiert vor dem Senden an die Datenbank alles außer Abfragen (auch `SELECT …
  FOR UPDATE` und PL/SQL-Blöcke). Der Startparameter `readonly=` ermöglicht es, ausgewählte Verbindungen für einen Start
  schreibgeschützt zu öffnen.
- Pelikan schreibt Transaktionen nicht selbst fest: AutoCommit ist standardmäßig deaktiviert, und das Schließen eines
  Fensters oder der Anwendung mit offener Transaktion endet mit einer Nachfrage.
- Die Installation von utPLSQL aus der Anwendung funktioniert nur auf Entwicklungs- und Testverbindungen.
- Werkzeuge, die Skripte erzeugen (Vergleiche, Korb, Refactoring, DDL von Duality Views, ORDS), öffnen sie zur Prüfung
  in einem SQL Window — sie führen sie nicht selbst aus.

## KI-Agenten

Die Regeln für Agenten beschreibt das Kapitel *KI-Agenten*. In Kürze:

- der Agent kennt Verbindungen nur mit Namen und Umgebung — er sieht keine Passwörter, Hosts, Ports, Dienste oder
  Benutzernamen;
- er hat eigene Datenbanksitzungen und sieht Ihre Transaktion nicht;
- er liest in schreibgeschützten Transaktionen, mit Limits;
- er nimmt Änderungen nur nach Ihrer Zustimmung in einem Fenster ohne Standardschaltfläche vor, und DML bleibt bis zu
  einer gesonderten Zustimmung zu COMMIT nicht festgeschrieben;
- er hat keinen Zugriff auf das Command Window, Systembefehle, den Debugger, Berichte der Oracle-Packs oder den
  Remote-Build;
- er kommuniziert mit Pelikan nur über einen Socket, auf den Ihr Konto zugreifen kann, mit einem Einmal-Token der
  Sitzung;
- die Daten, die der Agent liest, gelangen zum Anbieter des KI-Modells — für sensible Daten verwenden Sie einen eigenen
  Datenbankbenutzer des Agenten mit eingeschränkten Berechtigungen und das Maskieren von Spalten.

## Was Ihren Mac verlässt

Pelikan hat keine Telemetrie und keine Analysefunktionen. Netzwerkverbindungen baut es nur auf:

- zu den Datenbanken und SSH-Servern, die Sie konfigurieren;
- zu GitHub — einmal täglich, um nach Updates zu suchen (und sie herunterzuladen, wenn Sie zustimmen), sowie bei der
  Installation von utPLSQL aus der Anwendung (Download des offiziellen Release);
- im Browser, wenn Sie selbst die Oracle-Dokumentation (F1), eine Websuche oder ein Dokument mit einer http(s)-Adresse
  öffnen.

Die Programme der KI-Agenten (Claude Code, Codex, Grok, Antigravity) sind unabhängige Anwendungen der Anbieter und
verbinden sich mit deren Servern — sie senden dorthin, was der Agent in Pelikan liest.

## Daten auf dem Datenträger

Die Daten von Pelikan liegen im Verzeichnis `~/Library/Application Support/Pelikan`: Verbindungsdefinitionen (ohne
Passwörter), Einstellungen, Befehlsverlauf, Worksets und Snapshots zur Fensterwiederherstellung (sie können den Text
nicht gespeicherter Fenster enthalten), lokaler Dateiverlauf, Berichte, Körbe, Agentenprotokoll. Dateien mit
Fensterinhalten und dem Protokoll werden mit Zugriffsrechten nur für Ihr Konto gespeichert. Wenn Ihr Mac gemeinsam
genutzt wird, bedenken Sie, dass eine Person mit Zugriff auf Ihr macOS-Konto auch auf diese Daten zugreifen kann — sie
werden durch das Anmeldepasswort des Mac und die Festplattenverschlüsselung FileVault geschützt.

## Wovor Pelikan nicht schützt

- Schadsoftware, die unter Ihrem macOS-Konto läuft, kann Speicher und Dateien Ihrer Programme lesen — das ist Aufgabe
  des Systems (Gatekeeper, XProtect).
- Ein ohne strikten Modus gestartetes Agentenprogramm hat die Rechte Ihres Kontos.
- Festgeschriebene Änderungen (COMMIT) und DDL auf Tabellen lassen sich nicht rückgängig machen — Pelikan sagt das vor
  der Ausführung deutlich.
- In Abfragen aufgerufene Funktionen können Nebenwirkungen haben (z. B. autonome Transaktionen) — sie begrenzt nur das
  Berechtigungsmodell der Datenbank.
