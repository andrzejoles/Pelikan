# Program Window und Codeeditor

## Program Window

Das Program Window dient zum Schreiben und Kompilieren von PL/SQL-Einheiten: Paketen, Prozeduren, Funktionen, Typen und
Triggern sowie Java-Quellen und MLE-Modulen (JavaScript). Sie öffnen es über **Datei › Neu › Program Window** (⇧⌘N) oder
mit **Bearbeiten** auf einem Objekt im Object Browser (der Code wird direkt aus der Datenbank geladen).

![Program Window: ein Paket mit Tabs für Spezifikation und Body, links der Codeinhalt](../img/okno-programu.png)

- Jede Einheit der Datei hat einen eigenen Tab (z. B. Spezifikation und Body eines Pakets). Die Schaltfläche **+** neben
  den Tabs oder **Datei › Program Window › Einheit hinzufügen…** fügt eine Einheit aus einer Vorlage hinzu (Prozedur,
  Funktion, Paket, Typ, Trigger, Java-Quelle, MLE-Modul), mit einem Formular für Namen und Parameter. **Einheit
  entfernen** entfernt den Tab aus dem Text (das Objekt in der Datenbank bleibt bestehen).
- **Bearbeiten** auf einem Paket oder Typ — auch auf seinem Body aus den Ordnern „Package Bodies“ und „Type Bodies“ —
  öffnet Spezifikation und Body in einem Fenster auf zwei Tabs (vom Body aus geöffnet: der Body-Tab ist aktiv). Ein
  Objekt ohne Body hat einen Tab.
- **F8** (⌘↩) kompiliert alle Einheiten nacheinander und hält bei der ersten mit einem Fehler an. Die Kompilierung läuft
  in einer separaten Sitzung im Hintergrund und blockiert daher keine SQL Windows.
- Fehler und Warnungen des Compilers erscheinen unter dem Editor. Ein Klick springt zur Zeile, ein Doppelklick öffnet
  die Fehlerbeschreibung in der Oracle-Dokumentation.
- Die Statusleiste zeigt, ob der Text geändert und nicht gespeichert und ob er nicht kompiliert ist.
- **Datei › Speichern** (⌘S) speichert eine SQL*Plus-kompatible Datei (mit abschließendem `/`), mit Namen und Endung
  entsprechend der Einheit (z. B. `.pck`, `.prc`, `.fnc`, `.typ`, `.trg`).

### Sicheres Arbeiten mit Code in der Datenbank

- **Sitzung › Probekompilierung** kompiliert die Einheiten unter einem temporären Namen und zeigt Fehler, ohne die
  Objekte in der Datenbank zu ersetzen.
- **Sitzung › Objektänderungen in der Datenbank prüfen** prüft, ob jemand anderes das Objekt seit dem Laden oder
  Kompilieren geändert hat (Pelikan prüft das auch regelmäßig und warnt in der Statusleiste). Die Unterschiede sehen Sie
  über **Datei › Vergleichen › Mit Quelle in der Datenbank vergleichen**, die Version aus der Datenbank laden Sie mit
  **Sitzung › Aus Datenbank neu laden**.
- **Datei › Wiederherstellen** verwirft die Änderungen und kehrt zum Text vom Zeitpunkt des Öffnens, Ladens oder
  Speicherns zurück.
- **Datei › Vergleichen › Mit Datei vergleichen …** und **Mit Objekten in einer anderen Datenbank vergleichen…** (z. B.
  mit einer Testdatenbank) öffnen die Vergleichsansicht.
- **Sitzung › Block im Test Window ausführen** führt den ausgewählten anonymen Block in einem neuen Test Window mit
  DBMS_OUTPUT aus.

### Compiler-Einstellungen

Unter **Einstellungen › Oracle › Compiler** legen Sie `PLSQL_WARNINGS`, `PLSQL_OPTIMIZE_LEVEL`, `PLSQL_CODE_TYPE`,
`PLSCOPE_SETTINGS` und `PLSQL_CCFLAGS` fest — Pelikan setzt sie in der Kompilierungssitzung vor jeder Kompilierung eines
Program Window. Im Abschnitt **Debugger** aktivieren Sie das automatische Hinzufügen von Debug-Informationen,
**Compiler-Hinweise** (zusätzliche Codeprüfungen nach der Kompilierung) und die Prüfung von **Namenskonventionen**
(Präfixe von Parametern, lokalen und globalen Variablen, Konstanten, Cursorn und Typen). Ein Kommentar `-- Ignore` am
Zeilenende unterdrückt den Hinweis für diese Zeile.

## Codeeditor

Derselbe Editor arbeitet in SQL-, Programm-, Test- und Befehlsfenstern. Er bearbeitet selbst Pakete mit Zehntausenden
von Zeilen ohne Verzögerung.

### Vorschläge und Navigation

- Der **Codevorschlag** erscheint von selbst nach einem Punkt (z. B. `paket.`, `alias.`, `sequenz.`) oder auf
  Anforderung: ⌥⎋ (im Profil PL/SQL Developer ⌃Leertaste). Er schlägt Schemaobjekte vor, Spalten (auch über
  Tabellenaliase), Paketelemente, Parameter in benannter Notation, Record-Felder und `%ROWTYPE`, Collection-Methoden,
  `:new`/`:old`, Datenbank-Links nach `@` sowie utPLSQL-Annotationen und -Assertions. Der Eintrag **(alle)** fügt alle
  Spalten oder Parameter auf einmal ein. **Bearbeiten › Codevorschläge aktualisieren** aktualisiert den
  Dictionary-Cache.
- Wenn Sie mit der Maus auf eine Variable zeigen, wird ihre Deklaration angezeigt.
- **⌘+Klick** auf einen Namen oder **Bearbeiten › Zur Deklaration springen** (⌃⌘J) springt zur Deklaration — in
  derselben Quelle, in einem anderen offenen Fenster oder in einem Objekt aus der Datenbank (in einem neuen Fenster).
  **Bearbeiten › Navigation › Zurück** (⌃⌘←) und **Vorwärts** (⌃⌘→) kehren nach Sprüngen zurück.
- **Ansicht › Codeinhalt** zeigt den Strukturbaum der Einheit mit Cursorverfolgung, Sortierung und Menü (auswählen,
  kopieren, ausschneiden, Unterprogramm testen). Unter dem Editor zeigt die **Codehierarchie** den Pfad vom Cursor aus
  (Paket › Prozedur › Block); ein Klick auf eine Ebene wählt sie aus oder springt zu ihrem Namen.
- Das Kontextmenü auf dem Namen eines Datenbankobjekts im Editor bietet dieselben Aktionen wie der Object Browser.
- **F1** öffnet die Oracle-Dokumentation zum Wort unter dem Cursor.

### Schreiben und Auswählen

| Aktion | Kurzbefehl (macOS) | Menü |
|---|---|---|
| Zeilenkommentar | ⌘/ | Bearbeiten › Auswahl |
| Zeile duplizieren | ⇧⌘D | Bearbeiten › Auswahl |
| Groß- / Kleinbuchstaben | ⌥⌘U / ⌥⇧⌘U | Bearbeiten › Auswahl |
| Einrückung erhöhen / verringern | ⌘] / ⌘[ | Bearbeiten › Auswahl |
| PL/SQL-Code formatieren | ⇧⌘F | Bearbeiten |
| Suchen und Ersetzen | ⌘F | Bearbeiten |
| Weitersuchen / Rückwärts suchen | ⌘G / ⇧⌘G | Bearbeiten |
| Gehe zu Zeile | ⌘L | Bearbeiten |
| Block einklappen / ausklappen | ⌥⌘← / ⌥⌘→ | Bearbeiten |
| Alle einklappen / ausklappen | ⌥⇧⌘← / ⌥⇧⌘→ | Bearbeiten |
| Lesezeichen umschalten | ⌘F3 | Bearbeiten › Lesezeichen |
| Cursor darüber / darunter hinzufügen | ⌃⇧↑ / ⌃⇧↓ | Bearbeiten › Mehrere Cursor |
| Schrift vergrößern / verkleinern | ⌘= / ⌘− | Ansicht |

- **Code einklappen**: Der Pfeil im Rand neben den Zeilennummern klappt einen Block ein und aus (eingeklappter Block —
  Pfeil in Akzentfarbe, im Text „⋯“ mit dem eingeklappten Code im Tooltip).
- **Mehrere Cursor**: ⌥+Klick fügt einen Cursor hinzu, Esc lässt einen übrig. **Spaltenauswahl**: mit ⌥ ziehen — Tippen,
  Rückschritt und Einsetzen wirken in allen Zeilen gleichzeitig.
- **Suchen und Ersetzen** unterstützt reguläre Ausdrücke (mit `$1`), ganze Wörter, Groß-/Kleinschreibung, Beibehaltung
  der Schreibweise und die Suche nur im Code, in Kommentaren oder in Literalen.
- **Lesezeichen** 0–9 (im Profil PL/SQL Developer setzt ⌃K n, ⌃Q n springt), Lesezeichennamen und eine Liste der
  Lesezeichen aller Fenster. **Farbmarkierungen** heben Textstellen in einer von sechs Farben hervor.
- Der Editor hebt Klammerpaare und `BEGIN`/`IF`/`LOOP`/`CASE` ↔ `END` hervor, Vorkommen des Namens unter dem Cursor, die
  zur Position in `VALUES` passende `INSERT`-Spalte sowie die Befehle `COMMIT`, `ROLLBACK` und `SAVEPOINT`.
- **AutoReplace** (Einstellungen › Editor) ersetzt beim Tippen Abkürzungen durch Text; `|` im Ersatztext bestimmt die
  Cursorposition.
- **Ansicht › Editor teilen** zeigt zwei Ansichten desselben Texts. **Ansicht** bietet außerdem **Zeilen umbrechen**,
  **Sonderzeichen** und **Zeilenstatus** (Markierungen der seit dem Öffnen oder Speichern geänderten und neuen Zeilen).

### Formatieren

**Bearbeiten › PL/SQL-Code formatieren** (⇧⌘F) formatiert die Auswahl oder die ganze Quelle nach den Regeln unter
**Einstellungen › Formatierer** (Einrückungen, Listen, Kommas, Leerzeilen, Schreibweise von Schlüsselwörtern und
Bezeichnern, Sonderschreibweisen). Der Formatierer kann automatisch nach dem Öffnen einer Quelle aus der Datenbank, vor
dem Kompilieren und vor dem Speichern laufen. Ein Abschnitt zwischen den Kommentaren `-- NoFormat Start` und `--
NoFormat End` bleibt unverändert. Das Formatieren ändert nie die Bedeutung des Codes.

Die Registerkarte **Einstellungen › Formatierer** hat die Gruppen **Layout**, **Listen und Kommas**, **SQL-Klauseln und
Bedingungen** (Klauselwörter links, rechts oder in eigener Zeile; AND/OR am Zeilenanfang oder -ende; die Bedingung JOIN
… ON; THEN in neuer Zeile; mehrzeiliges CASE), **Spaltenausrichtung** (Deklarationen, Parameter mit Modus und Typ,
benannte Parameter `=>`, Zuweisungen `:=`, Aliasse in SELECT und FROM, `=` in UPDATE … SET, Kommentare am Zeilenende),
**Abstände** und **Groß-/Kleinschreibung** — getrennt für Schlüsselwörter, Bezeichner, Datentypen, integrierte
Funktionen und Oracle-Pakete. Rechts ist eine Vorschau: ein Beispielpaket, an dem jede Option sichtbar ist, mit
hervorgehobenen Zeilen der letzten Änderung, darüber ein Beispiel der Option unter dem Zeiger oder der zuletzt
geänderten — **Jetzt** und **Nach Änderung dieser Option**. Ein Bereich ohne Formatierung lässt sich auch mit den
Kommentaren `-- @formatter:off` und `-- @formatter:on` markieren.

### Vorlagen, Snippets und Makros

- **Templates** (Tab **Templates** in der linken Spalte oder **Ansicht › Vorlagenfenster**) fügen fertige Fragmente ein:
  DML-Befehle, Schleifen, Typen, SQL-Funktionen, Programmeinheiten und utPLSQL-Vorlagen. Ein Doppelklick oder Ziehen in
  den Editor fügt eine Vorlage ein; die Vorlagenvariablen füllen Sie in einem Formular aus (`$OSUSER`, `$DBUSER`,
  `$DATE`, `$TIME` werden selbst ersetzt). Eigene Vorlagen legen Sie über **Werkzeuge › Templates › Auswahl als Vorlage
  speichern …** an.
- **Ansicht › Snippets** ist eine Bibliothek kurzer Fragmente zum Ziehen (eingebaute und eigene).
- **Makros**: F11 startet und beendet die Aufnahme, F12 spielt ab, ⇧F12 spielt mehrfach ab. Ein Makro speichern Sie mit
  einem Kurzbefehl in der Bibliothek (**Bearbeiten › Makros › Makro in Bibliothek speichern …**).
- **Bearbeiten › Als Literal kopieren** kopiert das ausgewählte SQL als String-Literal einer Programmiersprache (Swift,
  Java, C#, JavaScript, Python, C/C++, PHP, Delphi, Visual Basic); **Aus Programmiersprache einsetzen** macht das
  Umgekehrte.
- Der **Zwischenablageverlauf** (**Ansicht › Zwischenablageverlauf**) hält die zuletzt kopierten Texte im Speicher.

### Codeanalyse und Refactoring

![Analyse beim Tippen: unbekannte Tabelle und Spalte unterstrichen; Editor in zwei Ansichten geteilt](../img/analiza-kodu.png)

- Beim Tippen unterstreicht Pelikan unbekannte Tabellen, Views, Spalten und Aliase (gemäß dem Dictionary der Verbindung
  des Fensters) sowie Probleme: unbenutzte Variablen und Parameter, Code nach `RETURN`/`RAISE`, `UPDATE`/`DELETE` ohne
  `WHERE`, implizite Konvertierungen. F2 und ⇧F2 springen zum nächsten und vorherigen Problem, **Bearbeiten ›
  Codeanalyse › Problemliste** zeigt alle. Die Analyse schalten Sie unter **Bearbeiten › Codeanalyse › Codeanalyse beim
  Tippen** ab.
- **Bearbeiten › Refactoring › Verwendungen suchen** (⌥F7) sucht Verwendungen eines Objekts oder einer Spalte: abhängige
  Objekte, Zeilen ihres Codes, PL/Scope, offene Fenster und Projektdateien.
- **Bearbeiten › Refactoring › Umbenennen …** (⇧F6) benennt eine Variable oder einen Parameter in ihrem
  Gültigkeitsbereich um oder ein Objekt bzw. eine Spalte in den Fenstern und Projektdateien. Vor dem Anwenden sehen Sie
  eine Vorschau der Unterschiede; eine Änderung in der Datenbank (DDL) landet in einem neuen Fenster und wird nicht
  ausgeführt.
- **Lokale Konstante extrahieren …**, **Globale Konstante extrahieren …**, **Prozedur extrahieren …** und **Zuweisung
  durch Initialisierung ersetzen** im selben Untermenü formen den ausgewählten Code um; jede Änderung machen Sie mit ⌘Z
  rückgängig.

### To-Do-Aufgaben

Kommentare `TODO` und `DONE` (mit Verantwortlichem, Priorität und Kategorie) werden im Fenster **Ansicht › To-Do-Aufgaben**
gesammelt. **Bearbeiten › To-Do-Aufgabe einfügen** fügt einen Kommentar ein, **To-Do-Aufgabe schließen oder öffnen**
ändert seinen Status.

## Dateien

- Pelikan öffnet aus dem Finder und per Ziehen die Dateien `.sql`, `.pck`, `.pks`, `.pkb`, `.spc`, `.bdy`, `.prc`,
  `.fnc`, `.trg`, `.typ`, `.tps`, Tests `.tst` und Notizbücher `.sqlnb`. Weitere Programm- und Testendungen tragen Sie
  unter **Einstellungen › Allgemein** ein. Das Ziehen eines Verzeichnisses öffnet alle seine Skripte.
- Dateien behalten ihre Kodierung (UTF-8, ISO-8859-2, Windows-1250) und Zeilenenden. Ein Zeichen, das sich in der
  Kodierung der Datei nicht speichern lässt, blockiert das Speichern mit genauer Angabe von Zeile und Spalte — die
  Kodierung ändern Sie nur bewusst über **Datei › Dateikodierung …**.
- **Datei › Schreibgeschützt** sperrt das Fenster für die Bearbeitung.
- **Datei › Mit Verbindung öffnen …** öffnet eine Datei mit sofort angehefteter Verbindung.
- **Bearbeiten › In externem Editor öffnen** übergibt den Text an das unter **Einstellungen › Werkzeuge** angegebene
  Programm (z. B. Visual Studio Code); nach der Rückkehr zu Pelikan werden die Änderungen geladen.
- **Bearbeiten › Im Web suchen** öffnet eine Suche nach dem ausgewählten Wort (Adressen der Suchmaschinen in den
  Einstellungen).
- Pelikan merkt sich den Zustand der Dateifenster (Cursor, Lesezeichen, Markierungen, eingeklappte Bereiche,
  Variablenwerte).
- Nach einem unerwarteten Beenden der Anwendung bietet Pelikan an, nicht gespeicherte Fenster wiederherzustellen
  (**Datei › Fenster wiederherstellen …**).
