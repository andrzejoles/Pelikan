# utPLSQL-Tests

## Wozu es dient

Ein **Unit-Test** ist ein kleines Programm, das Ihren Code aufruft und prüft, ob das Ergebnis wie erwartet ist — z. B.
„nach einer Erhöhung um 10 % beträgt ein Gehalt von 9500 genau 10450“. Sie führen Tests nach jeder Änderung aus: Haben
Sie etwas kaputt gemacht, zeigt ein Test das sofort, bevor der Fehler die Benutzer erreicht. **utPLSQL** ist die
beliebteste Testbibliothek für PL/SQL: Tests werden als Pakete mit Annotationskommentaren (`--%suite`, `--%test`)
geschrieben, Prüfungen als Aufrufe von `ut.expect(…).to_equal(…)`. utPLSQL rollt von einem Test vorgenommene
Datenänderungen automatisch zurück, sodass Tests keine Daten verderben.

**Wann verwenden:** für jedes Paket mit Geschäftslogik. Eine gute Gewohnheit: zuerst ein Test, der den Fehler zeigt, dann
die Korrektur, nach der der Test besteht.

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

> **Übung: die Tests des Übungspakets ausführen.**
>
> Erfordert utPLSQL in der Datenbank (prüfen Sie **utPLSQL: Version in der Datenbank**) und das Paket `PEL_EMP_API_TEST`
> aus dem Skript in Kapitel 1.
>
> 1. Öffnen Sie im Object Browser **Bearbeiten** auf dem Paket **PEL_EMP_API_TEST** und sehen Sie sich die
>    Spezifikation an.
>    *Ergebnis:* Die Annotation `--%suite` benennt die Testsuite, jede `--%test` ist ein Test, und `--%throws(-20001)`
>    sagt, dass der Test mit diesem Fehler enden muss.
> 2. Setzen Sie den Cursor in die Spezifikation und drücken Sie **⌃⌘U** (Test unter dem Cursor ausführen).
>    *Ergebnis:* Das Ergebnisfenster öffnet sich mit einem Fortschrittsbalken; drei Tests grün — **Erfolg**.
> 3. Ändern Sie im Body des Tests den erwarteten Wert in `raise_salary_ten_percent` von `10450` auf `10000` und
>    kompilieren Sie (F8).
> 4. Führen Sie die Tests erneut aus (**⌃⌘U**).
>    *Ergebnis:* ein Test rot (**Fehlschläge**). In den Testdetails: **Erwartet** 10000, **Ist** 10450 — Sie sehen sofort,
>    was nicht stimmt.
> 5. Stellen Sie `10450` wieder her, kompilieren Sie und wählen Sie **Erneut fehlgeschlagen**.
>    *Ergebnis:* alles grün.
> 6. Prüfen Sie in einem SQL Window: `SELECT salary FROM pel_employees WHERE emp_id = 2;`.
>    *Ergebnis:* 9500 — utPLSQL hat die vom Test vorgenommene Erhöhung zurückgerollt.
>
> **Übung: ein Test für die neue Funktion.** Wenn Sie in Kapitel 6 die Funktion `department_name` hinzugefügt haben,
> ergänzen Sie das Testpaket um einen Test (Deklaration in der Spezifikation mit `--%test(…)` und Prozedur im Body) mit
> `ut.expect(pel_emp_api.department_name(2)).to_equal('Informatyka');` und führen Sie ihn aus.

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

**So lesen Sie die Abdeckung:** Rote Zeilen sind Code, den kein Test ausgeführt hat — ein Fehler darin wird nicht
entdeckt. 100 % Abdeckung heißt nicht, dass der Code fehlerfrei ist, aber eine niedrige Abdeckung heißt, dass die Tests
wenig prüfen. Führen Sie die Tests `PEL_EMP_API_TEST` mit Abdeckung aus und öffnen Sie den Body von `PEL_EMP_API`: Die
Prozeduren `hire` und `print_department` sind rot — sie haben keine Tests.

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
