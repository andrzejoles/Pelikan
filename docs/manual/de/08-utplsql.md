# utPLSQL-Tests

Pelikan unterstützt utPLSQL — die Bibliothek für Unit-Tests in PL/SQL — direkt: Ausführen von Tests mit
Live-Ergebnissen, Codeabdeckung, Erzeugen von Testgerüsten und Navigation zwischen einem Paket und seinen Tests. Die
Befehle stehen im Menü **Werkzeuge › utPLSQL**.

## utPLSQL in der Datenbank installieren

**Werkzeuge › utPLSQL › utPLSQL: Version in der Datenbank** prüft, ob utPLSQL installiert ist und in welcher Version.

Fehlt es, lädt **utPLSQL: installieren oder aktualisieren …** das offizielle Release von GitHub herunter, prüft seine
Prüfsumme und führt die Installationsskripte in einer sichtbaren SQL*Plus-Konsole aus. Dieser Befehl funktioniert nur auf
Entwicklungs- und Testverbindungen und fragt immer nach einer Bestätigung. Der neue Eigentümer von utPLSQL erhält ein
zufälliges Passwort, das niemand kennt, und sein Konto wird sofort gesperrt. Auf gemeinsam genutzten Datenbanken
übernimmt die Installation in der Regel ein Administrator.

## Tests schreiben

- **utPLSQL: Testpaket generieren** — steht der Cursor in einem Paket (oder ist das Paket im Object Browser ausgewählt),
  öffnet es ein Program Window mit dem Gerüst eines Testpakets: eine Suite und je ein Test für jede Prozedur und
  Funktion, mit `ut.fail` zum Ausfüllen. Das Gerüst lässt sich sofort kompilieren und ausführen.
- Das Vorlagenfenster hat einen Ordner **utPLSQL** mit Vorlagen für Testpaket, Test, erwartete Ausnahme, Kontext,
  Erwartungen und Cursorvergleich.
- Der Codevorschlag kennt die Annotationen (nach `--%`) und die Matcher (nach `ut.expect(…).`).
- Beim Kompilieren der Spezifikation eines Testpakets warnt Pelikan vor unbekannten Annotationen, vor in `--%beforeall`,
  `--%aftereach` usw. genannten Prozeduren, die es in der Spezifikation nicht gibt, vor `--%test` ohne `--%suite` und
  vor nicht gepaarten `--%context`/`--%endcontext`.
- **utPLSQL: zu Test / getestetem Paket wechseln** (⌃⌘T) wechselt zwischen einem Paket und seinem Testpaket (nach dem
  Namen `test_name` oder nach Abhängigkeiten).

## Tests ausführen

| Befehl | Kurzbefehl (macOS) | Was ausgeführt wird |
|---|---|---|
| utPLSQL: alle Tests ausführen | ⇧⌘U | alle Tests des aktuellen Benutzers |
| utPLSQL: Test unter dem Cursor ausführen | ⌃⌘U | die Testprozedur unter dem Cursor oder das ganze Testpaket |
| utPLSQL: Tests aus Pfad ausführen … | — | Pfade `schema.paket.prozedur` oder `schema:suite.pfad`, mehrere durch Komma getrennt |
| utPLSQL: mit Optionen ausführen… | — | Pfade, Abdeckung, Abdeckungsschemata, ein- und ausgeschlossene Objekte |
| utPLSQL: fehlgeschlagene erneut ausführen | — | die Tests, die im letzten Lauf nicht bestanden haben |
| utPLSQL: unterbrechen | — | den laufenden Durchgang |

Im Profil PL/SQL Developer lauten die Kurzbefehle ⌃⇧U (alle), ⌃⌥U (unter dem Cursor) und ⌃⇧T (zum Test wechseln). Die
Tests des ausgewählten Pakets, der Prozedur oder des Benutzers starten Sie auch über **Werkzeuge › Objekt ›
utPLSQL-Tests ausführen**.

## Test-Explorer

**Ansicht › utPLSQL-Test-Explorer** zeigt den Baum der Suiten, Kontexte und Tests des aktuellen Benutzers mit dem Ergebnis
des letzten Laufs. Der Baum wird nach dem Kompilieren aktualisiert; ein Doppelklick auf einen Test öffnet seine
Annotation in der Spezifikation. Ausgewählte Tests führen Sie mit der Schaltfläche **Ausführen** oder **Mit Abdeckung
ausführen** aus.

## Ergebnisfenster

Die Ergebnisse erscheinen live: Fortschrittsbalken, Zähler und der Name des aktuellen Tests. Die Tests laufen in
separaten Sitzungen, sodass die Fenster von Pelikan verfügbar bleiben.

- Baum der Suiten, Kontexte und Tests mit Zeiten und Status: **Erfolg**, **Fehlschläge**, **Fehler**, **Deaktiviert**.
  **Anzeigen:** filtert nach Status, **Sortieren:** ändert die Reihenfolge (Ausführungsreihenfolge, Name, Zeit, Status).
- Testdetails: die Meldung der Erwartung, **Erwartet** und **Ist** nebeneinander mit hervorgehobenen Unterschieden (auch
  Cursorzeilen), **Fehlerstack** mit Sprung zur Zeile, die DBMS_OUTPUT-Ausgabe des Tests und **Testquelle öffnen**.
- Über das Testmenü führen Sie einen einzelnen Test erneut aus, mit **Erneut fehlgeschlagen** alle fehlgeschlagenen.
- **Verlauf** speichert die letzten 20 Läufe; **Änderungen** zeigt, welche Tests ihren Status gegenüber dem vorherigen
  Lauf geändert haben.

## Codeabdeckung

**utPLSQL: Tests mit Codeabdeckung** (oder **Mit Abdeckung ausführen**) erfasst die Abdeckung für das aktuelle Schema;
im Fenster **mit Optionen ausführen…** geben Sie andere Schemata sowie ein- und ausgeschlossene Objekte an.

- Im Program Window sind die Zeilen am Rand markiert: grün — abgedeckt, gelb — teilweise, rot — nicht abgedeckt.
- Die Statusleiste zeigt den Abdeckungsgrad des Objekts und des Schemas in Prozent.
- **Abdeckungsbericht** öffnet den HTML-Bericht von utPLSQL im Browser.

Die Abdeckung nutzt Profiler-Daten — vor dem ersten solchen Lauf in einer Sitzung erinnert Pelikan an die erforderlichen
Berechtigungen.

## Einen Test debuggen

**Debuggen › utPLSQL: Test unter dem Cursor debuggen** öffnet ein Test Window mit einem Aufruf `ut.run` für diesen Test,
setzt einen Haltepunkt in der Testprozedur und startet den Debugger (siehe Kapitel *Test Window, Debugger und
Profiler*).

## Ergebnisse für CI

- **utPLSQL: Ergebnisse exportieren …** führt Tests mit dem Reporter JUnit, Sonar, TeamCity oder TAP aus (oder mit einem
  Abdeckungsbericht Cobertura, Sonar, HTML) und speichert das Ergebnis in einer Datei.
- **utPLSQL: Skript für die Befehlszeile** erstellt ein SQL*Plus/SQLcl-Skript, das dieselben Tests mit JUnit-Ergebnis
  ausführt, sowie ein Shell-Skript. Die Skripte enthalten kein Passwort — Sie geben es in der CI aus Ihrem eigenen
  Secret-Speicher an.
