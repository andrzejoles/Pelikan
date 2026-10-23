# Test Window, Debugger und utPLSQL

## Test Window

Das Test Window führt einen PL/SQL-Block mit Bindevariablen aus, deren Werte Sie in die Tabelle unter dem Block
eintragen. Nach der Ausführung zeigt die Tabelle die Ausgabewerte, die Tabs zeigen DBMS_OUTPUT, Statistiken und das
Ausführungsprofil. Tests werden in `.tst`-Dateien gespeichert.

## Debugger

**Debuggen starten** führt den Test schrittweise aus: **Hineinspringen** (in ein Unterprogramm), **Überspringen**
(nächste Zeile), **Herausspringen** (Rückkehr aus dem Unterprogramm), Haltepunkte (auch bedingte), Anzeigen und Ändern
von Variablenwerten sowie Aufrufstapel. Der Debugger benötigt die Berechtigungen `DEBUG CONNECT SESSION` und
`DEBUG ANY PROCEDURE` (oder `DEBUG` auf dem Objekt).

## Profiler

Der Profiler (DBMS_PROFILER oder DBMS_HPROF) misst die Ausführungszeit jeder Zeile und jedes Unterprogramms, und die
Sitzungsstatistiken zeigen die Veränderung der Zähler während des Tests.

## utPLSQL

Der Test-Explorer zeigt die utPLSQL-Testpakete in der Datenbank. Tests können Sie für ein Paket, eine Suite oder das
ganze Schema ausführen; die Ergebnisse mit Laufzeit und Fehlermeldungen erscheinen im Baum, die Codeabdeckung im
Editor. Der Generator erstellt ein Gerüst für ein Testpaket zum ausgewählten Paket. Pelikan kann utPLSQL auch in einem
Schema installieren (nach Bestätigung).
