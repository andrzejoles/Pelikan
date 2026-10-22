# Skróty klawiszowe i komendy

Plik generowany z rejestru komend (`PELIKAN_WRITE_DOCS=1 swift test --filter shortcutsDoc`) — nie edytuj ręcznie.
Skróty profilu PL/SQL Developer oznaczone † są do weryfikacji ze wzorcem (docs/research/keys.md).
Poziom agenta: Brak / Odczyt / Za zgodą / Pełny (docs/SECURITY.md). Etap > 0 = komenda zapowiedziana (wyszarzona).

## Plik

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Nowy › Okno SQL | `file.new.sql` | ⌘N † | ⌘N | Pełny | 0 | PD-SQLW-002 |
| Nowy › Okno programu | `file.new.program` | ⇧⌘N † | ⇧⌘N | Pełny | 0 | PD-PROG-001 |
| Nowy › Okno testu | `file.new.test` |  |  | Pełny | 0 | PD-TEST-001 |
| Nowy › Okno poleceń | `file.new.command` |  |  | Pełny | 0 | PD-CMDW-001 |
| Nowy › Okno planu (Explain Plan) | `file.new.explainPlan` |  |  | Pełny | 0 | PD-OPT-001 |
| Nowy › Okno raportu | `file.new.report` |  |  | Pełny | 0 | PD-REP-002 |
| Nowy › Okno diagramu | `file.new.diagram` |  |  | Pełny | 0 | PD-DIAG-001 |
| Nowy › Notatnik SQL | `file.new.notebook` |  |  | Pełny | 0 | SD-NB-001 |
| Otwórz… | `file.open` | ⌘O † | ⌘O | Brak | 1 | PD-SQLW-012 |
| Zapisz | `file.save` | ⌘S † | ⌘S | Pełny | 1 | PD-SQLW-012 |
| Zapisz jako… | `file.saveAs` | ⇧⌘S † | ⇧⌘S | Brak | 1 | PD-SQLW-012 |
| Zamknij okno | `file.close` | ⌘W † | ⌘W | Pełny | 0 | PD-UI-004 |
| Zamknij wszystkie okna | `file.closeAll` | ⌥⌘W † | ⌥⌘W | Brak | 0 | PD-UI-004 |
| Drukuj… | `file.print` | ⌘P † | ⌘P | Brak | 8 | PD-SQLW-016 |

## Edycja

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Znajdź i zamień… | `edit.find` | ⌃F, ⌘F † | ⌘F | Pełny | 1 | PD-EDIT-008 |
| Przejdź do linii… | `edit.gotoLine` | ⌃G, ⌘L † | ⌘L | Pełny | 1 | PD-EDIT-010 |
| Historia poleceń… | `edit.recallStatement` | ⌃E, ⇧⌘H † | ⇧⌘H | Odczyt | 1 | PD-EDIT-009 |
| Zaznaczenie › Komentarz linii | `edit.commentLine` | ⌃-, ⌘/ † | ⌘/ | Pełny | 1 | PD-EDIT-006 |
| Zaznaczenie › Powiel linię | `edit.duplicateLine` | ⇧⌘D † | ⇧⌘D | Pełny | 1 | PD-EDIT-020 |
| Zaznaczenie › Wielkie litery | `edit.uppercase` |  |  | Pełny | 1 | PD-EDIT-005 |
| Zaznaczenie › Małe litery | `edit.lowercase` |  |  | Pełny | 1 | PD-EDIT-005 |
| Formatuj kod (PL/SQL Beautifier) | `edit.beautify` | ⇧⌘F † | ⇧⌘F | Pełny | 2 | PD-BEAU-002 |
| Makra › Nagrywaj makro | `edit.macroRecord` | F11 | F11 | Brak | 6 | PD-EDIT-015 |
| Makra › Odtwórz makro | `edit.macroPlay` | F12 | F12 | Brak | 6 | PD-EDIT-015 |

## Sesja

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Zaloguj… | `session.logon` |  |  | Brak | 1 | PD-CONN-002 |
| Wyloguj | `session.logoff` |  |  | Brak | 1 | PD-CONN-018 |
| Wykonaj | `sql.execute` | F8, ⌘↩ † | ⌘↩, F8 | Brak | 1 | PD-SQLW-002 |
| Wykonaj (odwrotnie do AutoSelect) | `sql.executeAlternate` | ⌃F8, ⇧⌘↩ † | ⇧⌘↩, ⌃F8 | Brak | 1 | PD-SQLW-003 |
| Przerwij | `sql.break` | ⇧⎋ †, ⌘. † | ⌘. | Brak | 1 | PD-SQLW-005 |
| Zatwierdź (COMMIT) | `session.commit` | F10 †, ⌥⌘↩ † | ⌥⌘↩, F10 | Za zgodą | 1 | PD-SQLW-014 |
| Wycofaj (ROLLBACK) | `session.rollback` | ⇧F10 †, ⌥⌘⌫ † | ⌥⌘⌫, ⇧F10 | Za zgodą | 1 | PD-SQLW-014 |
| Zakończ sesję okna (Kill) | `session.kill` |  |  | Brak | 1 | PD-CONN-027 |
| Zmień hasło… | `session.setPassword` |  |  | Brak | 1 | PD-CONN-017 |
| SQL Trace | `session.sqlTrace` |  |  | Brak | 3 | PD-OPT-008 |

## Debugowanie

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Rozpocznij debugowanie | `debug.start` | F9 † | F9 | Brak | 3 | PD-DBG-001 |
| Kontynuuj | `debug.run` | ⌃R † | ⌃R | Brak | 3 | PD-DBG-001 |
| Wejdź | `debug.stepInto` | ⌃N † | ⌃N | Brak | 3 | PD-DBG-001 |
| Przejdź | `debug.stepOver` | ⌃O † | ⌃O | Brak | 3 | PD-DBG-001 |
| Wyjdź | `debug.stepOut` | ⌃T † | ⌃T | Brak | 3 | PD-DBG-001 |
| Wykonaj do kursora | `debug.runToCursor` |  |  | Brak | 3 | PD-DBG-001 |
| Wykonaj do wyjątku | `debug.runToException` |  |  | Brak | 3 | PD-DBG-001 |
| Punkt przerwania | `debug.toggleBreakpoint` | ⌃B † | ⌃B | Brak | 3 | PD-DBG-001 |
| Punkty przerwania… | `debug.breakpoints` |  |  | Brak | 3 | PD-DBG-001 |

## Narzędzia

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Explain Plan | `tools.explainPlan` | F5 | F5 | Odczyt | 6 | PD-OPT-002 |
| Query Builder… | `tools.queryBuilder` |  |  | Brak | 6 | PD-QB-001 |
| Znajdź obiekty bazy… | `tools.findObjects` |  |  | Odczyt | 2 | PD-TOOL-001 |
| Kompiluj niepoprawne obiekty… | `tools.compileInvalid` |  |  | Za zgodą | 2 | PD-TOOL-002 |
| Sesje | `tools.sessions` |  |  | Odczyt | 6 | PD-TOOL-015 |
| DBMS Scheduler | `tools.scheduler` |  |  | Odczyt | 6 | PD-SCHED-001 |
| Eksport tabel… | `tools.exportTables` |  |  | Brak | 6 | PD-TOOL-003 |
| Import tabel… | `tools.importTables` |  |  | Brak | 6 | PD-TOOL-006 |
| Eksport obiektów użytkownika… | `tools.exportUserObjects` |  |  | Brak | 6 | PD-TOOL-007 |
| Porównaj obiekty użytkowników… | `tools.compareUserObjects` |  |  | Odczyt | 6 | PD-TOOL-012 |
| Porównaj dane tabel… | `tools.compareTableData` |  |  | Odczyt | 6 | PD-TOOL-013 |
| Import tekstu… | `tools.textImporter` |  |  | Brak | 6 | PD-TOOL-008 |
| Import z Excela… | `tools.excelImporter` |  |  | Brak | 6 | PD-TOOL-009 |
| Generator danych… | `tools.dataGenerator` |  |  | Brak | 6 | PD-TOOL-011 |
| Monitor zdarzeń… | `tools.eventMonitor` |  |  | Brak | 6 | PD-TOOL-014 |
| Menedżer testów… | `tools.testManager` |  |  | Brak | 6 | PD-TOOL-018 |
| Test obciążenia… | `tools.loadTester` |  |  | Brak | 6 | PD-TOOL-019 |
| utPLSQL: uruchom wszystkie testy | `utplsql.runAll` |  |  | Za zgodą | 4 | UT-RUN-001 |
| utPLSQL: uruchom testy ze ścieżki… | `utplsql.runPath` |  |  | Za zgodą | 4 | UT-RUN-002 |
| utPLSQL: pokrycie kodu… | `utplsql.coverage` |  |  | Za zgodą | 4 | UT-COV-001 |

## Raporty

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Błędy kompilacji | `reports.compilationErrors` |  |  | Odczyt | 6 | PD-REP-001 |

## Widok

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Paleta komend… | `view.commandPalette` | ⇧⌘P † | ⇧⌘P | Brak | 0 | PD-UI-007 |
| Przeglądarka obiektów | `view.objectBrowser` |  |  | Brak | 2 | PD-OB-001 |
| Lista połączeń | `view.connectionList` |  |  | Brak | 1 | PD-CONN-003 |

## Okno

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Następne okno | `window.next` | ⌃⇥, ⇧⌘] † | ⇧⌘], ⌃⇥ | Pełny | 0 | PD-UI-004 |
| Poprzednie okno | `window.previous` | ⌃⇧⇥, ⇧⌘[ † | ⇧⌘[, ⌃⇧⇥ | Pełny | 0 | PD-UI-004 |

## Pomoc

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Pomoc kontekstowa (dokumentacja Oracle) | `help.context` | F1 | F1 | Brak | 2 | PD-EDIT-026 |

