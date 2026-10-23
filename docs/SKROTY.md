# Skróty klawiszowe i komendy

Plik generowany z rejestru komend (`PELIKAN_WRITE_DOCS=1 swift test --filter shortcutsDoc`) — nie edytuj ręcznie.
Skróty profilu PL/SQL Developer oznaczone † są do weryfikacji ze wzorcem (docs/research/keys.md).
Poziom agenta: Brak / Odczyt / Za zgodą / Pełny (docs/SECURITY.md). Etap > 0 = komenda zapowiedziana (wyszarzona).
Skróty z ⌘ w profilu PL/SQL Developer to odpowiedniki macOS dodane przez Pelikana. Działają wszystkie skróty
komendy, nie tylko ten pokazany w menu (D17).

Kolizje z macOS: ⌃F8 (fokus do menu statusu), ⌃F2/⌃F3 i inne skróty z Ustawienia systemowe › Klawiatura ›
Skróty klawiszowe › Klawiatura przechwytuje system — użyj odpowiednika z ⌘ albo wyłącz skrót systemowy.
Klawisze F1–F12 działają jako klawisze funkcyjne po włączeniu „Używaj klawiszy F1, F2 itd. jako standardowych
klawiszy funkcyjnych” albo z klawiszem fn.

## Plik

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Nowy › Okno SQL | `file.new.sql` | ⌘N | ⌘N | Pełny | 0 | PD-SQLW-002 |
| Nowy › Okno programu | `file.new.program` | ⇧⌘N | ⇧⌘N | Pełny | 0 | PD-PROG-001 |
| Nowy › Okno testu | `file.new.test` |  |  | Pełny | 0 | PD-TEST-001 |
| Nowy › Okno poleceń | `file.new.command` |  |  | Pełny | 0 | PD-CMDW-001 |
| Nowy › Okno planu (Explain Plan) | `file.new.explainPlan` |  |  | Pełny | 0 | PD-OPT-001 |
| Nowy › Okno raportu | `file.new.report` |  |  | Pełny | 0 | PD-REP-002 |
| Nowy › Okno diagramu | `file.new.diagram` |  |  | Pełny | 0 | PD-DIAG-001 |
| Nowy › Notatnik SQL | `file.new.notebook` |  |  | Pełny | 0 | SD-NB-001 |
| Otwórz… | `file.open` | ⌘O | ⌘O | Brak | 0 | PD-SQLW-012 |
| Otwórz ponownie | `file.reopen` |  |  | Brak | 0 | PD-SQLW-012 |
| Zapisz | `file.save` | ⌘S | ⌘S | Za zgodą | 0 | PD-SQLW-012 |
| Zapisz jako… | `file.saveAs` | ⇧⌘S | ⇧⌘S | Brak | 0 | PD-SQLW-012 |
| Zamknij okno | `file.close` | ⌘W | ⌘W | Pełny | 0 | PD-UI-004 |
| Zamknij wskazane okno | `file.closeWindow` |  |  | Pełny | 0 | PD-UI-004 |
| Zamknij pozostałe okna | `file.closeOthers` |  |  | Brak | 0 | PD-UI-004 |
| Zamknij okna z lewej | `file.closeLeft` |  |  | Brak | 0 | PD-UI-004 |
| Zamknij okna z prawej | `file.closeRight` |  |  | Brak | 0 | PD-UI-004 |
| Zamknij wszystkie okna | `file.closeAll` | ⌥⌘W | ⌥⌘W | Brak | 0 | PD-UI-004 |
| Drukuj… | `file.print` | ⌘P | ⌘P | Brak | 8 | PD-SQLW-016 |
| Eksportuj wynik… | `grid.export` |  |  | Brak | 0 | PD-GRID-013 |
| Nowy › Nowy program z szablonu… | `file.newFromTemplate` |  |  | Pełny | 0 | PD-PROG-002 |
| Porównaj › Porównaj ze źródłem w bazie | `prog.compareWithDatabase` |  |  | Odczyt | 0 | PD-PROG-008 |
| Porównaj › Porównaj z plikiem… | `prog.compareWithFile` |  |  | Brak | 0 | PD-PROG-008 |
| Nowy › Tabela… | `file.newTable` |  |  | Brak | 0 | PD-OED-001 |
| Nowy › Sekwencja… | `file.newSequence` |  |  | Brak | 0 | PD-OED-008 |
| Nowy › Synonim… | `file.newSynonym` |  |  | Brak | 0 | PD-OED-008 |
| Nowy › Indeks… | `file.newIndex` |  |  | Brak | 0 | PD-OED-010 |
| Nowy › Użytkownik… | `file.newUser` |  |  | Brak | 0 | PD-OED-009 |
| Nowy › Rola… | `file.newRole` |  |  | Brak | 0 | PD-OED-009 |
| Nowy › Widok… | `file.newView` |  |  | Brak | 0 | PD-OED-010 |
| Zapisz test jako skrypt SQL*Plus | `test.saveAsSQLPlus` |  |  | Pełny | 0 | PD-TEST-005 |

## Edycja

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Znajdź i zamień… | `edit.find` | ⌃F, ⌘F | ⌘F | Brak | 0 | PD-EDIT-008 |
| Znajdź następne | `edit.findNext` | F3 †, ⌘G | ⌘G, F3 | Pełny | 0 | PD-EDIT-008 |
| Znajdź poprzednie | `edit.findPrevious` | ⇧F3 †, ⇧⌘G | ⇧⌘G, ⇧F3 | Pełny | 0 | PD-EDIT-008 |
| Przejdź do linii… | `edit.gotoLine` | ⌃G, ⌘L | ⌘L | Pełny | 0 | PD-EDIT-010 |
| Formatuj kod PL/SQL | `edit.beautify` | ⇧⌘F | ⇧⌘F | Pełny | 0 | PD-BEAU-002 |
| Podpowiedź kodu | `edit.codeAssistant` | ⌃Spacja † | ⌥⎋, ⌃Spacja | Odczyt | 0 | PD-CA-001 |
| Odśwież podpowiedzi kodu | `edit.refreshCodeAssistant` |  |  | Pełny | 0 | PD-CA-009 |
| Zwiń blok | `edit.fold` | ⌥⌘← | ⌥⌘← | Brak | 0 | PD-EDIT-013 |
| Rozwiń blok | `edit.unfold` | ⌥⌘→ | ⌥⌘→ | Brak | 0 | PD-EDIT-013 |
| Zwiń wszystko | `edit.foldAll` | ⌥⇧⌘← | ⌥⇧⌘← | Brak | 0 | PD-EDIT-013 |
| Rozwiń wszystko | `edit.unfoldAll` | ⌥⇧⌘→ | ⌥⇧⌘→ | Brak | 0 | PD-EDIT-013 |
| Przejdź do deklaracji | `edit.gotoDeclaration` | ⌃⌥D †, ⌃⌘J | ⌃⌘J | Pełny | 0 | PD-CA-012 |
| Historia poleceń… | `edit.recallStatement` | ⌃E, ⇧⌘H | ⇧⌘H | Brak | 0 | PD-EDIT-009 |
| Zaznaczenie › Komentarz linii | `edit.commentLine` | ⌃-, ⌘/ | ⌘/ | Pełny | 0 | PD-EDIT-006 |
| Zaznaczenie › Powiel linię | `edit.duplicateLine` | ⇧⌘D | ⇧⌘D | Pełny | 0 | PD-EDIT-020 |
| Zaznaczenie › Wielkie litery | `edit.uppercase` | ⌥⌘U | ⌥⌘U | Pełny | 0 | PD-EDIT-005 |
| Zaznaczenie › Małe litery | `edit.lowercase` | ⌥⇧⌘U | ⌥⇧⌘U | Pełny | 0 | PD-EDIT-005 |
| Zaznaczenie › Zwiększ wcięcie | `edit.indent` | ⌘] | ⌘] | Pełny | 0 | PD-EDIT-005 |
| Zaznaczenie › Zmniejsz wcięcie | `edit.outdent` | ⌘[ | ⌘[ | Pełny | 0 | PD-EDIT-005 |
| Zaznaczenie › Usuń końcowe spacje | `edit.removeTrailingSpaces` |  |  | Pełny | 0 | PD-EDIT-005 |
| Makra › Nagrywaj makro | `edit.macroRecord` | F11 | F11 | Brak | 6 | PD-EDIT-015 |
| Makra › Odtwórz makro | `edit.macroPlay` | F12 | F12 | Brak | 6 | PD-EDIT-015 |
| Wynik › Kopiuj | `grid.copy` |  |  | Brak | 0 | PD-GRID-015 |
| Wynik › Kopiuj z nagłówkiem | `grid.copyWithHeader` | ⌃⇧C †, ⇧⌘C | ⇧⌘C | Brak | 0 | PD-GRID-015 |
| Wynik › Kopiuj nagłówek | `grid.copyHeader` |  |  | Brak | 0 | PD-GRID-015 |
| Wynik › Kopiuj jako listę wyrażeń | `grid.copyExpressionList` |  |  | Brak | 0 | PD-GRID-015 |
| Wynik › Kopiuj jako… | `grid.copyAs` |  |  | Brak | 0 | PD-GRID-013 |
| Wynik › Kopiuj do Excela | `grid.copyToExcel` |  |  | Brak | 0 | PD-GRID-014 |
| Wynik › Large Data Editor… | `grid.largeData` | ⌥⌘L | ⌥⌘L | Brak | 0 | PD-GRID-003 |
| Wstaw szablon… | `edit.insertTemplate` |  |  | Pełny | 0 | PD-TPL-002 |
| Nawigacja › Wstecz | `edit.navigateBack` | ⌃⌥← †, ⌃⌘← | ⌃⌘← | Pełny | 0 | PD-CA-013 |
| Nawigacja › Naprzód | `edit.navigateForward` | ⌃⌥→ †, ⌃⌘→ | ⌃⌘→ | Pełny | 0 | PD-CA-013 |

## Sesja

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Zakończ sesję okna (Kill) | `session.kill` |  |  | Brak | 1 | PD-CONN-027 |
| Zmień hasło… | `session.setPassword` |  |  | Brak | 1 | PD-CONN-017 |
| SQL Trace | `session.sqlTrace` |  |  | Brak | 3 | PD-OPT-008 |
| Wykonaj | `sql.execute` | F8, ⌘↩ | ⌘↩, F8 | Brak | 0 | PD-SQLW-002 |
| Wykonaj (odwrotnie do AutoSelect) | `sql.executeAlternate` | ⌃F8, ⇧⌘↩ | ⇧⌘↩, ⌃F8 | Brak | 0 | PD-SQLW-003 |
| Przerwij | `sql.break` | ⇧⎋ †, ⌘. | ⌘. | Brak | 0 | PD-SQLW-005 |
| Wykonaj linię poleceń | `cmd.executeLine` |  |  | Brak | 0 | PD-CMDW-001 |
| Zatwierdź (COMMIT) | `session.commit` | F10 †, ⌥⌘↩ | ⌥⌘↩, F10 | Za zgodą | 0 | PD-SQLW-014 |
| Wycofaj (ROLLBACK) | `session.rollback` | ⇧F10 †, ⌥⌘⌫ | ⌥⌘⌫, ⇧F10 | Za zgodą | 0 | PD-SQLW-014 |
| Historia okna › Poprzednie polecenie okna | `sql.historyBack` | ⌥⌘↑ | ⌥⌘↑ | Pełny | 0 | PD-SQLW-007 |
| Historia okna › Następne polecenie okna | `sql.historyForward` | ⌥⌘↓ | ⌥⌘↓ | Pełny | 0 | PD-SQLW-007 |
| Podstawianie zmiennych | `sql.toggleSubstitution` |  |  | Brak | 0 | PD-VAR-005 |
| Wynik › Następna strona | `grid.nextPage` | ⌘⇟ | ⌘⇟ | Brak | 0 | PD-SQLW-004 |
| Wynik › Ostatnia strona (pobierz wszystkie) | `grid.lastPage` | ⇧⌘⇟ | ⇧⌘⇟ | Brak | 0 | PD-SQLW-004 |
| Wynik › Edytuj dane | `grid.edit` | ⌥⌘E | ⌥⌘E | Brak | 0 | PD-GRID-017 |
| Wynik › Wstaw rekord | `grid.insertRecord` | ⌥⌘I | ⌥⌘I | Brak | 0 | PD-GRID-017 |
| Wynik › Usuń rekord | `grid.deleteRecord` | ⇧⌘⌫ | ⇧⌘⌫ | Brak | 0 | PD-GRID-017 |
| Wynik › Zatwierdź zmiany (Post) | `grid.post` | ⌥⌘S | ⌥⌘S | Za zgodą | 0 | PD-GRID-017 |
| Wynik › Anuluj zmiany | `grid.cancelChanges` |  |  | Brak | 0 | PD-GRID-017 |
| Wynik › Kopiuj SQL zmian | `grid.copyChangesSQL` |  |  | Odczyt | 0 | PD-GRID-020 |
| Zaloguj… | `session.logon` | ⇧⌘L | ⇧⌘L | Brak | 0 | PD-CONN-002 |
| Wyloguj połączenie główne | `session.logoff` |  |  | Brak | 0 | PD-CONN-018 |
| Połączenia › Nowe połączenie… | `connection.new` |  |  | Brak | 0 | PD-CONN-004 |
| Połączenia › Edytuj połączenie… | `connection.edit` |  |  | Brak | 0 | PD-CONN-004 |
| Połączenia › Usuń połączenie | `connection.delete` |  |  | Brak | 0 | PD-CONN-004 |
| Połączenia › Połącz jako główne | `connection.connectAsMain` |  |  | Brak | 0 | PD-CONN-018 |
| Połączenia › Połącz | `connection.connect` |  |  | Brak | 0 | PD-CONN-022 |
| Połączenia › Rozłącz | `connection.disconnect` |  |  | Brak | 0 | PD-CONN-022 |
| Połączenie okna… | `session.windowConnection` |  |  | Brak | 0 | PD-CONN-019 |
| Połączenia › Nowy folder… | `connection.newFolder` |  |  | Brak | 0 | PD-CONN-003 |

## Debugowanie

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Rozpocznij debugowanie | `debug.start` | F9 † | F9 | Brak | 0 | PD-DBG-001 |
| Kontynuuj | `debug.run` | ⌃R † | ⌃R | Brak | 0 | PD-DBG-001 |
| Wejdź | `debug.stepInto` | ⌃N † | ⌃N | Brak | 0 | PD-DBG-001 |
| Przejdź | `debug.stepOver` | ⌃O † | ⌃O | Brak | 0 | PD-DBG-001 |
| Wyjdź | `debug.stepOut` | ⌃T † | ⌃T | Brak | 0 | PD-DBG-001 |
| Wykonaj do wyjątku | `debug.runToException` |  |  | Brak | 0 | PD-DBG-001 |
| Wykonaj do kursora | `debug.runToCursor` |  |  | Brak | 0 | PD-DBG-001 |
| Zatrzymaj debugowanie | `debug.stop` | ⇧F9 † | ⇧F9 | Brak | 0 | PD-DBG-001 |
| Punkt przerwania | `debug.toggleBreakpoint` | ⌃B † | ⌃B | Brak | 0 | PD-DBG-007 |

## Narzędzia

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Obiekt › Pokaż dane | `ob.queryData` |  |  | Brak | 0 | PD-OB-017 |
| Obiekt › Edytuj dane | `ob.editData` |  |  | Brak | 0 | PD-OB-017 |
| Obiekt › DDL | `ob.ddl` |  |  | Odczyt | 0 | PD-OB-015 |
| Obiekt › Opis | `ob.describe` |  |  | Odczyt | 0 | PD-OB-013 |
| Obiekt › Właściwości | `ob.properties` |  |  | Odczyt | 0 | PD-OB-012 |
| Obiekt › Edytuj | `ob.edit` |  |  | Brak | 0 | PD-OB-014 |
| Obiekt › Rekompiluj | `ob.recompile` |  |  | Za zgodą | 0 | PD-OB-009 |
| Obiekt › Usuń obiekt… | `ob.drop` |  |  | Za zgodą | 0 | PD-OB-016 |
| Obiekt › Kopiuj nazwę | `ob.copyName` |  |  | Brak | 0 | PD-OB-011 |
| Obiekt › Odśwież Object Browser | `ob.refresh` |  |  | Pełny | 0 | PD-OB-004 |
| Znajdź obiekty bazy… | `tools.findObjects` | ⌃⇧O †, ⇧⌘O | ⇧⌘O | Odczyt | 0 | PD-TOOL-001 |
| Kompiluj niepoprawne obiekty… | `tools.compileInvalid` |  |  | Za zgodą | 0 | PD-TOOL-002 |
| Szablony › Zapisz zaznaczenie jako szablon… | `templates.save` |  |  | Pełny | 0 | PD-TPL-003 |
| Szablony › Usuń szablon | `templates.delete` |  |  | Za zgodą | 0 | PD-TPL-003 |
| Obiekt › Porównaj z aktywnym oknem | `ob.compare` |  |  | Odczyt | 0 | PD-OB-022 |
| Porównaj pliki… | `tools.compareFiles` |  |  | Brak | 0 | PD-DIFF-001 |
| Porównaj teksty | `tools.compareTexts` |  |  | Odczyt | 0 | PD-DIFF-001 |
| Obiekt › Testuj | `ob.test` |  |  | Pełny | 0 | PD-TEST-004 |
| Obiekt › Edytuj definicję tabeli | `ob.editTable` |  |  | Odczyt | 0 | PD-OED-002 |
| Explain Plan | `tools.explainPlan` | F5 | F5 | Odczyt | 6 | PD-OPT-002 |
| Query Builder… | `tools.queryBuilder` |  |  | Brak | 6 | PD-QB-001 |
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
| Paleta komend… | `view.commandPalette` | ⇧⌘P | ⇧⌘P | Brak | 0 | PD-UI-007 |
| Zawartość kodu | `view.codeContents` |  |  | Brak | 0 | PD-CA-010 |
| Przeglądarka obiektów | `view.objectBrowser` |  |  | Brak | 2 | PD-OB-001 |

## Okno

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Następne okno | `window.next` | ⌃⇥, ⇧⌘] | ⇧⌘], ⌃⇥ | Pełny | 0 | PD-UI-004 |
| Poprzednie okno | `window.previous` | ⌃⇧⇥, ⇧⌘[ | ⇧⌘[, ⌃⇧⇥ | Pełny | 0 | PD-UI-004 |

## Pomoc

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Pomoc kontekstowa (dokumentacja Oracle) | `help.context` | F1 | F1 | Brak | 2 | PD-EDIT-026 |

