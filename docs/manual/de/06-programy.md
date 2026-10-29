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
- Der Editor zeigt nur die Einheit des gewählten Tabs; der aktive Tab ist gedrückt und fett. Den Tab wechseln Sie per
  Klick, mit **Datei › Program Window › Einheit anzeigen…**, **Nächste Einheit** (⌥⌘], im Profil PL/SQL Developer
  auch ⌃⇟) und **Vorherige Einheit** (⌥⌘[, ⌃⇞) — der Cursor kehrt an seine letzte Stelle auf diesem Tab zurück. Jeder
  Sprung an eine Stelle in einer anderen Einheit (Kompilierfehler, Codeinhalt, Weitersuchen, Gehe zu Deklaration,
  Lesezeichen, Debugger, Zurück/Vor, Widerrufen) wechselt den Tab selbst. Pfeiltasten und ⌘A bleiben im Tab.
  Zeilennummern im Tab, die Fehlerliste und **Gehe zu Zeile** zählen Zeilen der Einheit wie Oracle (ALL_SOURCE,
  ALL_ERRORS) — Zeile 1 ist die Zeile `PACKAGE BODY …`. **Alle ersetzen** ersetzt im ganzen Fenster (allen Einheiten).
- Einheiten werden an den Köpfen `CREATE … PACKAGE`, `PACKAGE BODY`, `TYPE`, `PROCEDURE`, `FUNCTION`, `TRIGGER` am
  Zeilenanfang erkannt — die Datei braucht kein „/“ nach den Einheiten. Pelikan fügt beim Speichern kein „/“ hinzu,
  und Code aus der Datenbank sowie neue Einheiten kommen ohne „/“ (außer Sie aktivieren **Einstellungen › Oracle ›
  Einheiten im Programmfenster mit „/“ abschließen**). Eine Datei mit „/“ wird unverändert gespeichert.
- **F8** (⌘↩) kompiliert alle Einheiten nacheinander und hält bei der ersten mit einem Fehler an. Die Kompilierung läuft
  in einer separaten Sitzung im Hintergrund und blockiert daher keine SQL Windows.
- Fehler und Warnungen des Compilers erscheinen unter dem Editor. Ein Klick springt zur Zeile, ein Doppelklick öffnet
  die Fehlerbeschreibung in der Oracle-Dokumentation.
- Die Statusleiste zeigt, ob der Text geändert und nicht gespeichert und ob er nicht kompiliert ist.
- **Datei › Speichern** (⌘S) speichert den Fenstertext unverändert (ohne angehängtes `/`), mit Namen und Endung
  entsprechend der Einheit (z. B. `.prc`, `.fnc`, `.trg`).
- **Spezifikation und Body in getrennten Dateien.** Ein Fenster mit Spezifikation und Body eines Pakets wird in ein
  Dateipaar `name.pks` (Spezifikation) und `name.pkb` (Body) gespeichert, ein Typ in `name.tps` und `name.tpb`, ohne
  „/“. **Speichern unter …** (und das erste **Speichern** eines neuen Fensters) fragt nach dem Namen und legt beide
  Dateien im gewählten Ordner an; existiert die Body-Datei bereits, fragt es, ob sie ersetzt werden soll. Jede Datei
  behält ihre Kodierung und Zeilenenden, und **Speichern** schreibt nur die Datei, deren Einheit sich geändert hat.
  Eine Datei enthält den Text ihres Reiters (mit Kommentaren über `CREATE` und `GRANT`-Anweisungen nach der Einheit).
  Ein Paarfenster, aus dem Sie den Body entfernen oder dem Sie eine weitere Einheit hinzufügen, wird nicht in diese
  Dateien gespeichert — **Datei › Als eine Datei speichern …** speichert das ganze Fenster wie bisher in einer Datei
  (z. B. `.pck`).
- Das Öffnen von `name.pks` oder `name.pkb`, wenn die Paardatei daneben liegt, öffnet beide Einheiten in einem Fenster
  auf dem Reiter der geöffneten Datei; der Fenstertitel lautet `name.pks + .pkb`. Das funktioniert auch aus dem Finder,
  dem Dateibrowser, den zuletzt verwendeten Dateien, Projekten und Worksets. Dateien, die nicht Spezifikation und Body
  eines Pakets oder Typs sind, öffnen sich einzeln — auch eine `.pks`-Datei mit einem Kommentar nach dem `END` der
  Spezifikation (beim Speichern würde er in die Body-Datei wandern). Hat sich eine Paardatei seit dem Öffnen auf dem
  Datenträger geändert (anderes Programm, `git checkout`), fragt **Speichern** vor dem Überschreiben. Erweiterungen und das Öffnen des Paars stellen Sie unter
  **Einstellungen › Allgemein › Spezifikation und Body in getrennten Dateien** ein.

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

Derselbe Editor arbeitet in SQL-, Programm- und Testfenstern sowie in der SQL*Plus-Konsole. Er bearbeitet selbst Pakete mit Zehntausenden
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
- **Ansicht › Codeinhalt** zeigt den Strukturbaum: Spezifikation und Body des Pakets (Typs) getrennt, darin
  Unterprogramme mit Parametern und Rückgabetyp (vollständiger Kopf im Tooltip), Typen (Record, Tabelle, REF CURSOR,
  Subtyp), Cursor, Variablen, Konstanten, Exceptions, Pragmas und verschachtelte Unterprogramme. Private Elemente des
  Bodys (nicht in der Spezifikation deklariert) sind kursiv. Klick oder Enter setzt den Cursor auf das Element (auch
  auf einem anderen Tab), Pfeiltasten im Baum bewegen den Cursor, ohne den Baum zu verlassen. Das Feld über dem Baum
  filtert Namen. Der Baum verfolgt den Cursor und hat Sortierung und Menü (auswählen, kopieren, ausschneiden,
  Unterprogramm testen, alles auf-/zuklappen). Unter dem Editor zeigt die **Codehierarchie** den Pfad vom Cursor aus
  (Paket › Prozedur › Block); ein Klick auf eine Ebene wählt sie aus oder springt zu ihrem Namen.
  Den Bereich blenden Sie in jedem Fenster einzeln ein und aus — **Ansicht › Codeinhalt** oder die
  Seitenleisten-Taste am linken Ende der Fensterleiste; die Auswahl bleibt im Fenster (auch im Workset).
  **Einstellungen › Editor › Codeinhalt standardmäßig sichtbar** gilt für Fenster, in denen der Bereich nicht
  umgeschaltet wurde.
- **Kontrollstrukturen** im Codeinhalt: `IF` mit den Zweigen `ELSIF` und `ELSE`, Schleifen `LOOP`, `FOR` (Zähl-
  und Cursorschleifen, auch `FOR r IN (SELECT …) LOOP`) und `WHILE`, `FORALL`, die `CASE`-Anweisung mit ihren
  `WHEN`-Zweigen (ein `CASE … END`-Ausdruck in SQL oder in einer Zuweisung ist kein Knoten), der `EXCEPTION`-Abschnitt mit den Behandlungen `WHEN Ausnahme`, der Initialisierungsabschnitt
  des Package Body und die Zeitpunkte eines Compound Triggers. Ein Knoten zeigt das öffnende Schlüsselwort, das Label
  `<<name>>` und eine gekürzte Bedingung (z. B. „IF v_betrag > 0…“, „FOR r IN c_emp LOOP“); der vollständige Kopf
  steht im Tooltip. Strukturen sind standardmäßig eingeklappt; ein Klick setzt den Cursor auf das öffnende
  Schlüsselwort, und der Baum markiert die innerste Struktur mit dem Cursor. Der Namensfilter sucht auch in
  Bedingungen und Labels. Eine unvollständige Struktur (z. B. noch ohne `END IF` beim Tippen) endet am `END` des
  Blocks oder vor dem nächsten Unterprogramm, und `$IF … $END` (bedingte Kompilierung) ist keine `IF`-Anweisung. Die
  Verzweigungs-Taste neben dem Filter oder **Kontrollstrukturen anzeigen** im Menü des Bereichs blendet sie in allen
  Fenstern aus (z. B. in einem großen Package); `BEGIN … END`-Blöcke (auch mit `DECLARE`) bleiben immer sichtbar;
  dieselbe Einstellung: **Einstellungen › Editor › Kontrollstrukturen
  im Codeinhalt** (standardmäßig eingeschaltet).
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

Die Registerkarte **Einstellungen › Formatierer** hat die Gruppen **Layout**, **Listen und Kommas** (getrennt
SELECT-/INTO-/FROM-Listen, UPDATE … SET, GROUP BY und ORDER BY, Parameterdeklarationen, Aufrufparameter, INSERT-Listen,
Listen in Klammern — IN, Funktionsargumente — sowie Tabellenspalten, Record- und Typfelder: ein Element pro Zeile, in
einer Zeile, wenn es passt, oder bis zum Rand), **SQL-Klauseln und Bedingungen** (Klauselwörter rechts — der „Fluss“,
Standard — links oder in eigener Zeile; AND/OR am Zeilenanfang oder -ende; die Bedingung JOIN … ON; THEN in neuer Zeile;
CASE in eigenen Zeilen — sehr kurze mit einem WHEN-Zweig bis zu einer festgelegten Zeichenzahl in einer Zeile;
Unterabfragen und CTEs eingerückt mit `)` in eigener Zeile oder nach der Klammer; Position des Operators in langen
Ausdrücken), **AND-/OR-Bedingungen** (für jeden Ort getrennt — WHERE, HAVING, JOIN … ON, MERGE … ON, START WITH /
CONNECT BY, CASE … WHEN, IF / ELSIF, WHILE, EXIT / CONTINUE WHEN, Trigger-WHEN, CHECK, verschachtelte Klammern:
Umbruch — jeweils in eigener Zeile, nur wenn die Bedingung nicht passt, nicht umbrechen; Position von AND/OR;
Ausrichtung am Schlüsselwort — „Fluss“, unter der ersten Bedingung oder darunter eingerückt), **Spaltenausrichtung**
(Deklarationen, Parameter mit Modus und Typ, benannte Parameter `=>`, Zuweisungen `:=`, Aliasse in SELECT und FROM, `=`
in UPDATE … SET, Tabellenspalten und Recordfelder — Typ, DEFAULT, NOT NULL, Kommentare am Zeilenende), **Abstände** und
**Groß-/Kleinschreibung** — getrennt für Schlüsselwörter, Bezeichner, Datentypen, integrierte Funktionen und
Oracle-Pakete; Sonderschreibweisen akzeptieren auch Muster mit `%` oder `*` (z. B. `DBMS_%`). Rechts ist eine Vorschau
mit Syntaxfarben, Zeilennummern und einer senkrechten Linie am rechten Rand; der Umschalter darüber wählt das Beispiel:
**PL/SQL**, **Abfragen**, **DML** oder **DDL**. Durch die letzte Änderung geänderte Zeilen werden 5 s lang (oder bis zur
nächsten Änderung) hervorgehoben, ein roter Strich markiert entfernte Zeilen; eine Optionsänderung wechselt zum
Beispiel, in dem sie sichtbar ist, und scrollt dorthin, ein Klick auf eine Option zeigt ihr Beispiel. Ein Bereich ohne
Formatierung lässt sich auch mit den Kommentaren `-- @formatter:off` und `-- @formatter:on` markieren; bedingte
Kompilierung `$IF … $END` lässt der Formatierer unverändert.

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
- Eine geöffnete Datei wird nicht gesperrt — andere Programme (Agent, git, Editor) können sie ändern. Kehren Sie zum
  Fenster, zu einem Reiter des Paars oder zu Pelikan zurück und hat sich die Datei auf dem Datenträger geändert, fragt
  Pelikan, ob sie **neu geladen** werden soll; ein Fenster mit ungespeicherten Änderungen warnt vor deren Verlust
  (**Meine Änderungen behalten** behält den Fenstertext, und ein späteres **Speichern** warnt noch einmal vor dem
  Überschreiben). Eine bloße Änderung des Dateidatums (z. B. `touch`) löst keine Frage aus. Im Fenster eines
  `.pks`/`.pkb`-Paars wird nur die geänderte Datei neu geladen. Gelöschte oder verschobene Datei: **Im Fenster behalten**
  oder **Fenster schließen**. **Datei › Von der Festplatte neu laden** tut dies auf Wunsch. Unter **Einstellungen ›
  Allgemein › Dateien** schalten Sie die Erkennung ab oder das Neuladen ohne Rückfrage ein, wenn das Fenster keine
  Änderungen hat.
- **Datei › Mit Verbindung öffnen …** öffnet eine Datei mit sofort angehefteter Verbindung.
- **Bearbeiten › In externem Editor öffnen** übergibt den Text an das unter **Einstellungen › Werkzeuge** angegebene
  Programm (z. B. Visual Studio Code); nach der Rückkehr zu Pelikan werden die Änderungen geladen.
- **Bearbeiten › Im Web suchen** öffnet eine Suche nach dem ausgewählten Wort (Adressen der Suchmaschinen in den
  Einstellungen).
- Pelikan merkt sich den Zustand der Dateifenster (Cursor, Lesezeichen, Markierungen, eingeklappte Bereiche,
  Variablenwerte).
- Nach einem unerwarteten Beenden der Anwendung bietet Pelikan an, nicht gespeicherte Fenster wiederherzustellen
  (**Datei › Fenster wiederherstellen …**).
