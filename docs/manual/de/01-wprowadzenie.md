# Einführung

Pelikan ist eine native macOS-Umgebung für die Arbeit mit Oracle-Datenbanken: zum Schreiben und Ausführen von SQL, zum
Entwickeln und Testen von PL/SQL-Code, zum Durchsuchen von Datenbankobjekten, zum Debuggen, für utPLSQL-Tests und
Administrationswerkzeuge. Aufbau und Tastenkürzel entsprechen PL/SQL Developer, sodass Benutzer dieses Programms
vertraute Fenster wiederfinden: **SQL Window**, **Command Window**, **Program Window**, **Test Window** und
**Object Browser**.

## Erste Schritte

1. Installieren Sie Oracle Instant Client (Basic oder Basic Light) und geben Sie dessen Verzeichnis unter
   **Einstellungen › Oracle** an. Pelikan erkennt außerdem das neueste Verzeichnis `instantclient_*` im Ordner
   „Downloads“. Ohne Instant Client arbeitet der *Thin*-Treiber mit geringerem Funktionsumfang.
2. Legen Sie eine Verbindungsdefinition an: **Sitzung › Verbindungen › Neue Verbindung …** oder über die Schaltfläche in
   der Verbindungsliste.
3. Stellen Sie die Verbindung her und öffnen Sie ein **SQL Window** (⌘N). Geben Sie eine Abfrage ein und führen Sie sie
   aus (F8 oder ⌘↩).

## Hauptfenster

Links befindet sich ein Bereich mit Tabs: Object Browser, File Browser, Fensterliste, Templates, To-Do und Projekt. In
der Mitte liegen die Dokument-Tabs — jedes SQL-, Programm- oder Testfenster hat einen eigenen Tab. Die Statusleiste
zeigt die Verbindung des Fensters, den Transaktionsstatus, die Cursorposition, die Dateikodierung und den Git-Branch.

Jede Aktion lässt sich über das Menü, per Tastenkürzel oder über die **Befehlspalette** (⇧⌘P) aufrufen, die Befehle
nach Namen sucht.

## Sprachen

Die Oberfläche ist auf Polnisch, Englisch, Deutsch, Spanisch und Ukrainisch verfügbar. Die Sprache wählen Sie unter
**Einstellungen › Allgemein › Sprache der Benutzeroberfläche**; die Änderung wird nach einem Neustart wirksam.
