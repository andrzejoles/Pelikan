# SQL Window

Das SQL Window dient zum Ausführen von Abfragen und Skripten. Das Abfrageergebnis erscheint im Raster unter dem Editor,
Meldungen auf dem Tab *Output* und die Ausgabe von DBMS_OUTPUT auf einem eigenen Tab.

## Ausführen

- **F8 / ⌘↩** — führt die Auswahl oder die Anweisung unter dem Cursor aus (je nach Einstellung von *AutoSelect*).
- **⌃F8 / ⇧⌘↩** — führt entgegengesetzt zu *AutoSelect* aus (z. B. alle Anweisungen des Fensters statt der Anweisung
  unter dem Cursor).
- **Unterbrechen** (⌘.) — bricht eine lange laufende Abfrage ab.
- Substitutionsvariablen `&` und `&&` sowie Bindevariablen `:nazwa` erkennt Pelikan selbst und fragt nach ihren Werten.
  Außerdem erkennt es JasperReports-Berichtsparameter `$P{…}`, `$P!{…}` und `$X{…}`.

## Ergebnisraster

Das Raster lädt Zeilen portionsweise und holt beim Scrollen weitere nach. Ein Klick auf einen Spaltenkopf sortiert, und
der Filter arbeitet lokal auf den geladenen Zeilen. Zellen lassen sich bearbeiten, wenn die Abfrage `ROWID` abruft oder
aus einer einzelnen Tabelle mit Schlüssel stammt — die Änderungen übernehmen Sie mit einer Schaltfläche und bestätigen
sie durch Festschreiben der Transaktion. Große Werte (CLOB, BLOB, XML, JSON) öffnet der **Large Data Editor**.

Das Ergebnis können Sie nach CSV, TSV, HTML, XML, XLSX, in INSERT-Befehle oder in die Zwischenablage exportieren. Der
**Wertebereich** (⌥⌘V) zeigt die aktuelle Zelle als Text, JSON, XML, HTML, Bild oder Hex.

## Transaktionen

Die Statusleiste zeigt eine offene Transaktion an. **Commit** (F10, ⌥⌘↩) und **Rollback** finden Sie im Menü „Sitzung“
und in der Symbolleiste. Im Modus *Multi session* hat jedes Fenster eine eigene Sitzung, im Modus *Dual session* teilen
sich die Fenster eine Sitzung.

## Explain Plan und Autotrace

**Explain Plan** (F5) zeigt den Ausführungsplan der Anweisung unter dem Cursor als Baum mit Kosten, Zeilenzahl und
Prädikaten. Pläne lassen sich vergleichen, und **Autotrace** führt die Anweisung aus und zeigt den tatsächlichen Plan
mit Statistiken.
