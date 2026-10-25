# Skróty klawiszowe i komendy

Plik generowany z rejestru komend (`PELIKAN_WRITE_DOCS=1 swift test --filter shortcutsDoc`) — nie edytuj ręcznie.
Skróty profilu PL/SQL Developer oznaczone † są do weryfikacji ze wzorcem (docs/research/keys.md).
Poziom agenta: Brak / Odczyt / Za zgodą / Pełny (docs/SECURITY.md) — efektywny (D33): komendy spoza `agent.*` i spoza
listy komend aplikacji dla agenta mają Brak, komendy aplikacji przez `run_command` najwyżej Za zgodą.
Skróty z ⌘ w profilu PL/SQL Developer to odpowiedniki macOS dodane przez Pelikana. Działają wszystkie skróty
komendy, nie tylko ten pokazany w menu (D17).

Kolizje z macOS: ⌃F8 (fokus do menu statusu), ⌃F2/⌃F3 i inne skróty z Ustawienia systemowe › Klawiatura ›
Skróty klawiszowe › Klawiatura przechwytuje system — użyj odpowiednika z ⌘ albo wyłącz skrót systemowy.
Klawisze F1–F12 działają jako klawisze funkcyjne po włączeniu „Używaj klawiszy F1, F2 itd. jako standardowych
klawiszy funkcyjnych” albo z klawiszem fn.

## Plik

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Funkcja |
|---|---|---|---|---|---|
| Nowy › Okno SQL | `file.new.sql` | ⌘N | ⌘N | Za zgodą | PD-SQLW-002 |
| Nowy › Okno programu | `file.new.program` | ⇧⌘N | ⇧⌘N | Za zgodą | PD-PROG-001 |
| Nowy › Okno testu | `file.new.test` |  |  | Za zgodą | PD-TEST-001 |
| Nowy › Okno poleceń | `file.new.command` |  |  | Brak | PD-CMDW-001 |
| Nowy › Okno planu (Explain Plan) | `file.new.explainPlan` |  |  | Brak | PD-OPT-001 |
| Nowy › Okno raportu | `file.new.report` |  |  | Brak | PD-REP-002 |
| Nowy › Okno diagramu | `file.new.diagram` |  |  | Brak | PD-DIAG-001 |
| Nowy › Notatnik SQL | `file.new.notebook` |  |  | Brak | SD-NB-001 |
| Otwórz… | `file.open` | ⌘O | ⌘O | Brak | PD-SQLW-012 |
| Otwórz ponownie | `file.reopen` |  |  | Brak | PD-SQLW-012 |
| Zapisz | `file.save` | ⌘S | ⌘S | Brak | PD-SQLW-012 |
| Zapisz jako… | `file.saveAs` | ⇧⌘S | ⇧⌘S | Brak | PD-SQLW-012 |
| Kodowanie pliku… | `file.encoding` |  |  | Brak | PC-ENC-001 |
| Zamknij okno | `file.close` | ⌘W | ⌘W | Brak | PD-UI-004 |
| Zamknij wskazane okno | `file.closeWindow` |  |  | Brak | PD-UI-004 |
| Zamknij pozostałe okna | `file.closeOthers` |  |  | Brak | PD-UI-004 |
| Zamknij okna z lewej | `file.closeLeft` |  |  | Brak | PD-UI-004 |
| Zamknij okna z prawej | `file.closeRight` |  |  | Brak | PD-UI-004 |
| Zamknij wszystkie okna | `file.closeAll` | ⌥⌘W | ⌥⌘W | Brak | PD-UI-004 |
| Drukuj… | `file.print` | ⌘P | ⌘P | Brak | PD-SQLW-016 |
| Eksportuj wynik… | `grid.export` |  |  | Brak | PD-GRID-013 |
| Eksport wyniku › Kolumna do plików… | `grid.columnToFiles` |  |  | Brak | PD-GRID-016 |
| Wklej jako nowe SQL Window | `file.pasteAsSQLWindow` |  |  | Brak | PD-SQLW-025 |
| Tylko do odczytu | `file.readOnly` |  |  | Brak | PD-FILE-003 |
| Otwórz z połączeniem… | `file.openWithConnection` |  |  | Brak | PD-FILE-004 |
| Wykonaj parametry startowe | `app.openStartupParameters` |  |  | Brak | PD-CLI-001 |
| Odzyskaj okna… | `file.restoreRecovery` |  |  | Brak | PD-FILE-001 |
| Notatnik › Eksportuj notatnik jako Markdown… | `notebook.exportMarkdown` |  |  | Brak | SD-NB-001 |
| Historia lokalna › Historia lokalna | `file.localHistory` |  |  | Brak | DG-HIST-001 |
| Historia lokalna › Wersje w historii lokalnej | `file.localHistoryList` |  |  | Brak | DG-HIST-001 |
| Historia lokalna › Zapisz wersję w historii | `file.localHistoryCheckpoint` |  |  | Brak | DG-HIST-001 |
| Historia lokalna › Porównaj z wersją | `file.localHistoryCompare` |  |  | Brak | DG-HIST-001 |
| Historia lokalna › Przywróć wersję | `file.localHistoryRestore` |  |  | Brak | DG-HIST-001 |
| Nowy › Nowy program z szablonu… | `file.newFromTemplate` |  |  | Brak | PD-PROG-002 |
| Okno programu › Dodaj jednostkę… | `prog.addUnit` |  |  | Brak | PD-PROG-001 |
| Okno programu › Usuń jednostkę | `prog.removeUnit` |  |  | Brak | PD-PROG-001 |
| Przywróć | `prog.revert` |  |  | Brak | PD-PROG-009 |
| Porównaj › Porównaj ze źródłem w bazie | `prog.compareWithDatabase` |  |  | Brak | PD-PROG-008 |
| Porównaj › Porównaj z plikiem… | `prog.compareWithFile` |  |  | Brak | PD-PROG-008 |
| Porównaj › Porównaj z obiektami w innej bazie… | `prog.compareWithConnection` |  |  | Brak | PD-PROG-008 |
| Nowy › Tabela… | `file.newTable` |  |  | Brak | PD-OED-001 |
| Nowy › Sekwencja… | `file.newSequence` |  |  | Brak | PD-OED-008 |
| Nowy › Synonim… | `file.newSynonym` |  |  | Brak | PD-OED-008 |
| Nowy › Indeks… | `file.newIndex` |  |  | Brak | PD-OED-010 |
| Nowy › Użytkownik… | `file.newUser` |  |  | Brak | PD-OED-009 |
| Nowy › Rola… | `file.newRole` |  |  | Brak | PD-OED-009 |
| Nowy › Biblioteka… | `file.newLibrary` |  |  | Brak | PD-OED-008 |
| Nowy › Katalog… | `file.newDirectory` |  |  | Brak | PD-OED-008 |
| Nowy › Zadanie… | `file.newJob` |  |  | Brak | PD-OED-008 |
| Nowy › Kolejka… | `file.newQueue` |  |  | Brak | PD-OED-008 |
| Nowy › Profil… | `file.newProfile` |  |  | Brak | PD-OED-009 |
| Nowy › Łącze bazy danych… | `file.newDatabaseLink` |  |  | Brak | PD-OED-009 |
| Nowy › Widok (edytor)… | `file.newViewEditor` |  |  | Brak | PD-OED-010 |
| Nowy › Domena… | `file.newDomain` |  |  | Brak | PD-OED-011 |
| Nowy › Asercja… | `file.newAssertion` |  |  | Brak | PD-OED-011 |
| Nowy › Widok… | `file.newView` |  |  | Brak | PD-OED-010 |
| Zapisz test jako skrypt SQL*Plus | `test.saveAsSQLPlus` |  |  | Brak | PD-TEST-005 |
| Przeglądarka plików › Dodaj lokalizację… | `fb.addLocation` |  |  | Brak | PD-FB-001 |
| Przeglądarka plików › Usuń lokalizację | `fb.removeLocation` |  |  | Brak | PD-FB-001 |
| Przeglądarka plików › Otwórz jako… | `fb.open` |  |  | Brak | PD-FB-001 |
| Przeglądarka plików › Zmień nazwę… | `fb.rename` |  |  | Brak | PD-FB-001 |
| Przeglądarka plików › Nowy katalog… | `fb.newFolder` |  |  | Brak | PD-FB-001 |
| Przeglądarka plików › Nowy plik… | `fb.newFile` |  |  | Brak | PD-FB-001 |
| Przeglądarka plików › Przenieś do Kosza | `fb.trash` |  |  | Brak | PD-FB-001 |
| Przeglądarka plików › Pokaż w Finderze | `fb.showInFinder` |  |  | Brak | PD-FB-001 |
| Przeglądarka plików › Pokaż ukryte pliki | `fb.toggleHidden` |  |  | Brak | PD-FB-001 |
| Przeglądarka plików › Wyczyść historię filtra | `fb.clearFilterHistory` |  |  | Brak | PD-FB-002 |
| Workset › Nowy workset… | `workset.new` |  |  | Brak | PD-WSET-001 |
| Workset › Otwórz workset… | `workset.open` |  |  | Brak | PD-WSET-001 |
| Workset › Zapisz workset | `workset.save` |  |  | Brak | PD-WSET-001 |
| Workset › Przywróć workset | `workset.revert` |  |  | Brak | PD-WSET-001 |
| Workset › Zamknij workset | `workset.close` |  |  | Brak | PD-WSET-001 |
| Workset › Porównaj worksety… | `workset.compare` |  |  | Brak | PD-WSET-001 |
| Workset › Usuń workset… | `workset.delete` |  |  | Brak | PD-WSET-001 |
| Workset › Autozapis workseta | `workset.toggleAutosave` |  |  | Brak | PD-WSET-001 |

## Projekt

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Funkcja |
|---|---|---|---|---|---|
| Elementy projektu | `project.show` |  |  | Brak | PD-PROJ-001 |
| Nowy projekt… | `project.new` |  |  | Brak | PD-PROJ-001 |
| Otwórz projekt… | `project.open` |  |  | Brak | PD-PROJ-001 |
| Zamknij projekt | `project.close` |  |  | Brak | PD-PROJ-001 |
| Dodaj plik okna do projektu | `project.addActiveFile` |  |  | Brak | PD-PROJ-001 |
| Dodaj obiekt do projektu | `project.addSelectedObject` |  |  | Brak | PD-PROJ-001 |
| Buduj projekt | `project.build` |  |  | Brak | PD-PROJ-002 |
| Make projektu | `project.make` |  |  | Brak | PD-PROJ-002 |
| Zapisz pulpit projektu | `project.saveDesktop` |  |  | Brak | PD-PROJ-003 |
| Otwórz pulpit projektu | `project.openDesktop` |  |  | Brak | PD-PROJ-003 |
| Szukaj w projekcie… | `project.find` |  |  | Brak | PD-PROJ-003 |

## Edycja

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Funkcja |
|---|---|---|---|---|---|
| Znajdź i zamień… | `edit.find` | ⌃F, ⌘F | ⌘F | Brak | PD-EDIT-008 |
| Znajdź następne | `edit.findNext` | F3 †, ⌘G | ⌘G, F3 | Za zgodą | PD-EDIT-008 |
| Znajdź poprzednie | `edit.findPrevious` | ⇧F3 †, ⇧⌘G | ⇧⌘G, ⇧F3 | Za zgodą | PD-EDIT-008 |
| Przejdź do linii… | `edit.gotoLine` | ⌃G, ⌘L | ⌘L | Za zgodą | PD-EDIT-010 |
| Formatuj kod PL/SQL | `edit.beautify` | ⇧⌘F | ⇧⌘F | Za zgodą | PD-BEAU-002 |
| Podpowiedź kodu | `edit.codeAssistant` | ⌃Spacja † | ⌥⎋, ⌃Spacja | Brak | PD-CA-001 |
| Odśwież podpowiedzi kodu | `edit.refreshCodeAssistant` |  |  | Brak | PD-CA-009 |
| Zwiń blok | `edit.fold` | ⌥⌘← | ⌥⌘← | Brak | PD-EDIT-013 |
| Rozwiń blok | `edit.unfold` | ⌥⌘→ | ⌥⌘→ | Brak | PD-EDIT-013 |
| Zwiń wszystko | `edit.foldAll` | ⌥⇧⌘← | ⌥⇧⌘← | Brak | PD-EDIT-013 |
| Rozwiń wszystko | `edit.unfoldAll` | ⌥⇧⌘→ | ⌥⇧⌘→ | Brak | PD-EDIT-013 |
| Przejdź do deklaracji | `edit.gotoDeclaration` | ⌃⌥D †, ⌃⌘J | ⌃⌘J | Brak | PD-CA-012 |
| Historia poleceń… | `edit.recallStatement` | ⌃E, ⇧⌘H | ⇧⌘H | Brak | PD-EDIT-009 |
| Zaznaczenie › Komentarz linii | `edit.commentLine` | ⌃-, ⌘/ | ⌘/ | Za zgodą | PD-EDIT-006 |
| Zaznaczenie › Powiel linię | `edit.duplicateLine` | ⇧⌘D | ⇧⌘D | Za zgodą | PD-EDIT-020 |
| Zaznaczenie › Usuń następne słowo | `edit.deleteNextWord` | ⌃⌦ † | ⌃⌥⌦ | Brak | PD-EDIT-020 |
| Zaznaczenie › Pierwszy znak w linii | `edit.firstCharacterOnLine` | ⌥↖ † | ⌃⌥← | Brak | PD-EDIT-020 |
| Zaznaczenie › Wielkie litery | `edit.uppercase` | ⌥⌘U | ⌥⌘U | Za zgodą | PD-EDIT-005 |
| Zaznaczenie › Małe litery | `edit.lowercase` | ⌥⇧⌘U | ⌥⇧⌘U | Za zgodą | PD-EDIT-005 |
| Zaznaczenie › Zwiększ wcięcie | `edit.indent` | ⌘] | ⌘] | Za zgodą | PD-EDIT-005 |
| Zaznaczenie › Zmniejsz wcięcie | `edit.outdent` | ⌘[ | ⌘[ | Za zgodą | PD-EDIT-005 |
| Zaznaczenie › Usuń końcowe spacje | `edit.removeTrailingSpaces` |  |  | Za zgodą | PD-EDIT-005 |
| Wynik › Kopiuj | `grid.copy` |  |  | Brak | PD-GRID-015 |
| Wynik › Kopiuj z nagłówkiem | `grid.copyWithHeader` | ⌃⇧C †, ⇧⌘C | ⇧⌘C | Brak | PD-GRID-015 |
| Wynik › Kopiuj nagłówek | `grid.copyHeader` |  |  | Brak | PD-GRID-015 |
| Wynik › Kopiuj jako listę wyrażeń | `grid.copyExpressionList` |  |  | Brak | PD-GRID-015 |
| Wynik › Kopiuj jako… | `grid.copyAs` |  |  | Brak | PD-GRID-013 |
| Wynik › Kopiuj do Excela | `grid.copyToExcel` |  |  | Brak | PD-GRID-014 |
| Wynik › Large Data Editor… | `grid.largeData` | ⌥⌘L | ⌥⌘L | Brak | PD-GRID-003 |
| Wstaw snippet | `edit.insertSnippet` |  |  | Brak | SC-SNIP-001 |
| Wynik › Kalendarz… | `grid.chooseDate` |  |  | Brak | PD-GRID-005 |
| Wynik › Zaznacz blok komórek | `grid.selectBlock` |  |  | Brak | PD-GRID-007 |
| Wynik › Zaznacz kolumnę | `grid.selectColumn` |  |  | Brak | PD-GRID-007 |
| Wynik › Wielkie litery w komórkach | `grid.upperCase` |  |  | Brak | PD-GRID-026 |
| Wynik › Małe litery w komórkach | `grid.lowerCase` |  |  | Brak | PD-GRID-026 |
| Zakładki › Przełącz zakładkę | `edit.toggleBookmark` | ⌘F3 | ⌘F3 | Brak | PD-EDIT-011 |
| Zakładki › Przejdź do zakładki | `edit.gotoBookmark` |  |  | Brak | PD-EDIT-011 |
| Zakładki › Następna zakładka | `edit.nextBookmark` | ⌥⌘F3 | ⌥⌘F3 | Brak | PD-EDIT-011 |
| Zakładki › Poprzednia zakładka | `edit.previousBookmark` | ⌥⇧⌘F3 | ⌥⇧⌘F3 | Brak | PD-EDIT-011 |
| Zakładki › Nazwij zakładkę… | `edit.renameBookmark` |  |  | Brak | PD-EDIT-011 |
| Zakładki › Lista zakładek | `edit.bookmarkList` |  |  | Brak | PD-EDIT-011 |
| Zakładki › Usuń zakładki okna | `edit.clearBookmarks` |  |  | Brak | PD-EDIT-011 |
| Znaczniki kolorów › Oznacz kolorem | `edit.colorMark` |  |  | Brak | PD-EDIT-012 |
| Znaczniki kolorów › Usuń znaczniki kolorów | `edit.clearColorMarks` |  |  | Brak | PD-EDIT-012 |
| Wiele kursorów › Dodaj kursor powyżej | `edit.addCursorAbove` | ⌃⇧↑ † | ⌃⇧↑ | Brak | PD-EDIT-023 |
| Wiele kursorów › Dodaj kursor poniżej | `edit.addCursorBelow` | ⌃⇧↓ † | ⌃⇧↓ | Brak | PD-EDIT-023 |
| Wiele kursorów › Jeden kursor | `edit.singleCursor` |  |  | Brak | PD-EDIT-023 |
| Refaktoryzacja › Wydziel stałą lokalną… | `edit.extractLocalConstant` |  |  | Brak | PD-CA-014 |
| Refaktoryzacja › Wydziel stałą globalną… | `edit.extractGlobalConstant` |  |  | Brak | PD-CA-014 |
| Refaktoryzacja › Wydziel procedurę… | `edit.extractProcedure` |  |  | Brak | PD-CA-014 |
| Refaktoryzacja › Zamień przypisanie na inicjalizację | `edit.replaceAssignmentWithInitialization` |  |  | Brak | PD-CA-014 |
| Szukaj w edytorach i plikach… | `edit.searchBar` | ⌥⇧⌘F | ⌥⇧⌘F | Brak | PD-CA-015 |
| Szukaj w sieci | `edit.webSearch` |  |  | Brak | PD-EDIT-027 |
| Otwórz w zewnętrznym edytorze | `edit.openInExternalEditor` |  |  | Brak | PD-EDIT-028 |
| Analiza kodu › Analizuj kod | `edit.analyzeCode` |  |  | Brak | DG-INSP-001 |
| Analiza kodu › Analiza kodu w czasie pisania | `edit.toggleCodeAnalysis` |  |  | Brak | DG-RES-001 |
| Analiza kodu › Następny problem | `edit.nextProblem` |  | F2 | Brak | DG-RES-001 |
| Analiza kodu › Poprzedni problem | `edit.previousProblem` |  | ⇧F2 | Brak | DG-RES-001 |
| Analiza kodu › Lista problemów | `edit.showProblems` |  |  | Brak | DG-INSP-001 |
| Refaktoryzacja › Znajdź użycia | `edit.findUsages` |  | ⌥F7 | Brak | DG-USE-001 |
| Refaktoryzacja › Zmień nazwę… | `edit.refactorRename` |  | ⇧F6 | Brak | DG-REF-001 |
| Wstaw szablon… | `edit.insertTemplate` |  |  | Brak | PD-TPL-002 |
| Zawartość kodu › Zaznacz element | `codeContents.select` |  |  | Brak | PD-CA-010 |
| Zawartość kodu › Kopiuj element | `codeContents.copy` |  |  | Brak | PD-CA-010 |
| Zawartość kodu › Wytnij element | `codeContents.cut` |  |  | Brak | PD-CA-010 |
| Zawartość kodu › Testuj podprogram | `codeContents.test` |  |  | Brak | PD-CA-010 |
| Zawartość kodu › Zaznacz poziom hierarchii kodu | `codeHierarchy.select` |  |  | Brak | PD-CA-011 |
| Zawartość kodu › Przejdź do poziomu hierarchii kodu | `codeHierarchy.goto` |  |  | Brak | PD-CA-011 |
| Nawigacja › Wstecz | `edit.navigateBack` | ⌃⌥← †, ⌃⌘← | ⌃⌘← | Za zgodą | PD-CA-013 |
| Nawigacja › Naprzód | `edit.navigateForward` | ⌃⌥→ †, ⌃⌘→ | ⌃⌘→ | Za zgodą | PD-CA-013 |
| Makra › Nagrywaj makro | `edit.macroRecord` | F11 | F11 | Brak | PD-EDIT-015 |
| Makra › Odtwórz makro | `edit.macroPlay` | F12 | F12 | Brak | PD-EDIT-015 |
| Makra › Odtwórz makro wielokrotnie… | `edit.macroRepeat` | ⇧F12 † | ⇧F12 | Brak | PD-EDIT-015 |
| Makra › Zapisz makro w bibliotece… | `edit.macroSave` |  |  | Brak | PD-EDIT-015 |
| Makra › Biblioteka makr… | `edit.macroLibrary` |  |  | Brak | PD-EDIT-015 |
| Kopiuj jako literał › Swift | `edit.specialCopy.swift` |  |  | Brak | PD-EDIT-016 |
| Kopiuj jako literał › Java | `edit.specialCopy.java` |  |  | Brak | PD-EDIT-016 |
| Kopiuj jako literał › C# | `edit.specialCopy.csharp` |  |  | Brak | PD-EDIT-016 |
| Kopiuj jako literał › JavaScript | `edit.specialCopy.javascript` |  |  | Brak | PD-EDIT-016 |
| Kopiuj jako literał › Python | `edit.specialCopy.python` |  |  | Brak | PD-EDIT-016 |
| Kopiuj jako literał › C/C++ | `edit.specialCopy.c` |  |  | Brak | PD-EDIT-016 |
| Kopiuj jako literał › PHP | `edit.specialCopy.php` |  |  | Brak | PD-EDIT-016 |
| Kopiuj jako literał › Delphi | `edit.specialCopy.delphi` |  |  | Brak | PD-EDIT-016 |
| Kopiuj jako literał › Visual Basic | `edit.specialCopy.vb` |  |  | Brak | PD-EDIT-016 |
| Kopiuj jako literał › Wklej z języka programowania | `edit.pasteHostLanguage` |  |  | Brak | PD-EDIT-016 |
| Wklej z historii schowka | `edit.pasteFromHistory` |  |  | Brak | PD-EDIT-024 |
| Wstaw zadanie To-Do | `edit.todoInsert` |  |  | Brak | PD-TODO-001 |
| Zamknij lub otwórz zadanie To-Do | `edit.todoToggle` |  |  | Brak | PD-TODO-001 |

## Sesja

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Funkcja |
|---|---|---|---|---|---|
| Zakończ sesję okna (Kill) | `session.kill` |  |  | Brak | PD-CONN-027 |
| Zmień hasło… | `session.setPassword` |  |  | Brak | PD-CONN-017 |
| SQL Trace | `session.sqlTrace` |  |  | Brak | PD-OPT-008 |
| Wykonaj | `sql.execute` | F8, ⌘↩ | ⌘↩, F8 | Brak | PD-SQLW-002 |
| Wykonaj (odwrotnie do AutoSelect) | `sql.executeAlternate` | ⌃F8, ⇧⌘↩ | ⇧⌘↩, ⌃F8 | Brak | PD-SQLW-003 |
| Przerwij | `sql.break` | ⇧⎋ †, ⌘. | ⌘. | Brak | PD-SQLW-005 |
| Wstrzymaj wykonanie | `cmd.pause` |  |  | Brak | PD-CMDW-003 |
| Wykonaj linię poleceń | `cmd.executeLine` |  |  | Brak | PD-CMDW-001 |
| Zatwierdź (COMMIT) | `session.commit` | F10 †, ⌥⌘↩ | ⌥⌘↩, F10 | Brak | PD-SQLW-014 |
| Wycofaj (ROLLBACK) | `session.rollback` | ⇧F10 †, ⌥⌘⌫ | ⌥⌘⌫, ⇧F10 | Brak | PD-SQLW-014 |
| Historia okna › Poprzednie polecenie okna | `sql.historyBack` | ⌥⌘↑ | ⌥⌘↑ | Za zgodą | PD-SQLW-007 |
| Historia okna › Następne polecenie okna | `sql.historyForward` | ⌥⌘↓ | ⌥⌘↓ | Za zgodą | PD-SQLW-007 |
| Podstawianie zmiennych | `sql.toggleSubstitution` |  |  | Brak | PD-VAR-005 |
| Wynik › Następna strona | `grid.nextPage` | ⌘⇟ | ⌘⇟ | Brak | PD-SQLW-004 |
| Wynik › Ostatnia strona (pobierz wszystkie) | `grid.lastPage` | ⇧⌘⇟ | ⇧⌘⇟ | Brak | PD-SQLW-004 |
| Wynik › Wykres… | `grid.graph` |  |  | Brak | PD-GRAPH-001 |
| Wynik › Edytuj dane | `grid.edit` | ⌥⌘E | ⌥⌘E | Brak | PD-GRID-017 |
| Wynik › Wstaw rekord | `grid.insertRecord` | ⌥⌘I | ⌥⌘I | Brak | PD-GRID-017 |
| Wynik › Usuń rekord | `grid.deleteRecord` | ⇧⌘⌫ | ⇧⌘⌫ | Brak | PD-GRID-017 |
| Wynik › Zatwierdź zmiany (Post) | `grid.post` | ⌥⌘S | ⌥⌘S | Brak | PD-GRID-017 |
| Wynik › Anuluj zmiany | `grid.cancelChanges` |  |  | Brak | PD-GRID-017 |
| Wynik › Kopiuj SQL zmian | `grid.copyChangesSQL` |  |  | Brak | PD-GRID-020 |
| Wynik › Zapisz jako zapytanie standardowe… | `grid.saveAsStandardQuery` |  |  | Brak | PD-SQLW-013 |
| Wynik › Zapytania powiązane… | `grid.linkedQueries` |  |  | Brak | PD-SQLW-019 |
| Wynik › Porównaj rekordy | `grid.compareRecords` |  |  | Brak | PD-SQLW-020 |
| Wynik › Porównaj wyniki | `grid.compareResults` |  |  | Brak | PD-SQLW-021 |
| Wynik › Filtruj według wartości komórki | `grid.filterByValue` |  |  | Brak | DB-GRID-001 |
| Wynik › Filtr wyrażeniem… | `grid.filterExpression` |  |  | Brak | DB-GRID-001 |
| Wynik › Wyczyść filtr | `grid.clearFilter` |  |  | Brak | DB-GRID-001 |
| Wynik › Grupuj według kolumny | `grid.groupBy` |  |  | Brak | DB-GRID-001 |
| Wynik › Generuj SQL z wierszy… | `grid.generateSQL` |  |  | Brak | DB-GRID-002 |
| Wynik › Rekord z komentarzami kolumn | `grid.recordView` |  |  | Brak | PD-GRID-010 |
| Wynik › Otwórz kursor zagnieżdżony | `grid.openCursor` |  |  | Brak | PD-GRID-006 |
| Wynik › Filtr kolumn… | `grid.columnFilter` |  |  | Brak | PD-GRID-011 |
| Wynik › Pokaż wszystkie kolumny | `grid.clearColumnFilter` |  |  | Brak | PD-GRID-011 |
| Wynik › Wyrównaj kolumny | `grid.align` |  |  | Brak | PD-GRID-012 |
| Wynik › Ukryj edytor | `sql.toggleEditor` |  |  | Brak | PD-GRID-012 |
| Wynik › Wysokość wierszy… | `grid.rowHeight` |  |  | Brak | PD-GRID-012 |
| Wynik › Zapisz wyrównanie dla zapytania | `grid.saveAlignTemplate` |  |  | Brak | PD-GRID-012 |
| Wynik › Usuń wyrównanie zapytania | `grid.removeAlignTemplate` |  |  | Brak | PD-GRID-012 |
| Wynik › Informacje o kolumnie | `grid.columnInfo` |  |  | Brak | PD-GRID-022 |
| Wynik › Lista wartości… | `grid.valueList` |  |  | Brak | PD-GRID-022 |
| Wynik › Sumy kolumny… | `grid.totals` |  |  | Brak | PD-GRID-024 |
| Wynik › Wyłącz sumy | `grid.clearTotals` |  |  | Brak | PD-GRID-024 |
| Wynik › Odśwież wynik | `sql.refreshResult` | ⇧⌘R | ⇧⌘R | Brak | PD-SQLW-006 |
| Wynik › Automatyczne odświeżanie… | `sql.autoRefresh` |  |  | Brak | PD-SQLW-006 |
| Wynik › Przypnij wynik | `sql.pinResult` |  |  | Brak | PD-SQLW-017 |
| Wynik › Przypnij wszystkie wyniki | `sql.pinAllResults` |  |  | Brak | PD-SQLW-017 |
| Wynik › Wyczyść karty wyników | `sql.clearResults` |  |  | Brak | PD-SQLW-017 |
| Wynik › Eksportuj zapytanie do pliku… | `sql.exportQuery` |  |  | Brak | PD-SQLW-018 |
| Wynik › Query By Example… | `grid.queryByExample` | ⇧⌘E | ⇧⌘E | Brak | PD-SQLW-022 |
| Wynik › Wyczyść Query By Example | `grid.clearQueryByExample` |  |  | Brak | PD-SQLW-022 |
| Wczytaj ponownie z bazy | `prog.reloadFromDatabase` |  |  | Brak | PD-PROG-011 |
| Kompilacja próbna | `prog.safeCompile` |  |  | Brak | PD-PROG-010 |
| Sprawdź zmiany obiektów w bazie | `prog.checkChanges` |  |  | Brak | PD-PROG-011 |
| Uruchom blok w oknie testu | `prog.runBlock` |  |  | Brak | PD-PROG-016 |
| Notatnik › Wykonaj wszystkie komórki | `notebook.runAll` |  |  | Brak | SD-NB-001 |
| Notatnik › Wykonaj komórkę | `notebook.runCell` |  |  | Brak | SD-NB-001 |
| Konsola połączenia | `session.console` |  |  | Brak | DG-CONS-001 |
| Wynik › Następna zmiana oczekująca | `grid.nextPendingChange` |  |  | Brak | DG-GRID-001 |
| Wynik › Poprzednia zmiana oczekująca | `grid.previousPendingChange` |  |  | Brak | DG-GRID-001 |
| Wynik › Cofnij zmiany wierszy | `grid.revertRowChanges` |  |  | Brak | DG-GRID-001 |
| Zaloguj… | `session.logon` | ⇧⌘L | ⇧⌘L | Brak | PD-CONN-002 |
| Wyloguj połączenie główne | `session.logoff` |  |  | Brak | PD-CONN-018 |
| Połączenia › Eksportuj definicje połączeń… | `connection.export` |  |  | Brak | PD-CONN-010 |
| Połączenia › Importuj definicje połączeń… | `connection.import` |  |  | Brak | PD-CONN-010 |
| Połączenia › Nowe połączenie… | `connection.new` |  |  | Brak | PD-CONN-004 |
| Połączenia › Edytuj połączenie… | `connection.edit` |  |  | Brak | PD-CONN-004 |
| Połączenia › Usuń połączenie | `connection.delete` |  |  | Brak | PD-CONN-004 |
| Połączenia › Połącz jako główne | `connection.connectAsMain` |  |  | Brak | PD-CONN-018 |
| Połączenia › Połącz | `connection.connect` |  |  | Brak | PD-CONN-022 |
| Połączenia › Nowe okno na połączeniu | `connection.openWindow` |  |  | Brak | PD-CONN-022 |
| Połączenia › Pokaż okna połączenia | `connection.showWindows` |  |  | Brak | PD-CONN-022 |
| Połączenia › Zamknij okna połączenia | `connection.closeWindows` |  |  | Brak | PD-CONN-022 |
| Połączenia › Połącz ponownie okna połączenia | `connection.reconnectWindows` |  |  | Brak | PD-CONN-022 |
| Połączenia › Ustaw bieżący schemat… | `connection.setCurrentSchema` |  |  | Brak | PD-CONN-022 |
| Połączenia › Rozłącz | `connection.disconnect` |  |  | Brak | PD-CONN-022 |
| Połączenie okna… | `session.windowConnection` |  |  | Brak | PD-CONN-019 |
| Połączenia › Nowy folder… | `connection.newFolder` |  |  | Brak | PD-CONN-003 |

## Debugowanie

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Funkcja |
|---|---|---|---|---|---|
| Przebiegi profilera | `test.profilerRuns` |  |  | Brak | PD-OPT-005 |
| Otwórz przebieg profilera… | `test.profilerOpenRun` |  |  | Brak | PD-OPT-005 |
| Zapisz punkty przerwania… | `debug.saveBreakpoints` |  |  | Brak | PD-DBG-008 |
| Wczytaj punkty przerwania… | `debug.loadBreakpoints` |  |  | Brak | PD-DBG-008 |
| Zapisz jako test standardowy… | `test.saveAsStandard` |  |  | Brak | PD-TEST-009 |
| Ślad DBMS_TRACE przy wykonaniu | `test.trace` |  |  | Brak | PD-OPT-007 |
| Historia przebiegów DBMS_TRACE | `test.traceRuns` |  |  | Brak | PD-OPT-007 |
| Uprawnienia debugera… | `debug.grantPrivileges` |  |  | Brak | PD-DBG-013 |
| Profiler przy wykonaniu | `test.profiler` |  |  | Brak | PD-OPT-005 |
| utPLSQL: debuguj test pod kursorem | `utplsql.debugTest` |  |  | Brak | UT-RUN-007 |
| Rozpocznij debugowanie | `debug.start` | F9 † | F9 | Brak | PD-DBG-001 |
| Kontynuuj | `debug.run` | ⌃R † | ⌃R | Brak | PD-DBG-001 |
| Wejdź | `debug.stepInto` | ⌃N † | ⌃N | Brak | PD-DBG-001 |
| Przejdź | `debug.stepOver` | ⌃O † | ⌃O | Brak | PD-DBG-001 |
| Wyjdź | `debug.stepOut` | ⌃T † | ⌃T | Brak | PD-DBG-001 |
| Wykonaj do wyjątku | `debug.runToException` |  |  | Brak | PD-DBG-001 |
| Wykonaj do kursora | `debug.runToCursor` |  |  | Brak | PD-DBG-001 |
| Zatrzymaj debugowanie | `debug.stop` | ⇧F9 † | ⇧F9 | Brak | PD-DBG-001 |
| Punkty przerwania… | `debug.breakpoints` |  |  | Brak | PD-DBG-008 |
| Punkt przerwania | `debug.toggleBreakpoint` | ⌃B † | ⌃B | Brak | PD-DBG-007 |

## Narzędzia

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Funkcja |
|---|---|---|---|---|---|
| Obiekt › Zapytanie standardowe | `ob.standardQuery` |  |  | Brak | PD-SQLW-013 |
| Obiekt › Generuj kod… | `ob.generateCode` |  |  | Brak | SD-GEN-001 |
| Autotrace | `tools.autotrace` |  |  | Brak | SD-PLAN-002 |
| Plan › Porównaj z poprzednim planem | `plan.compare` |  |  | Brak | SD-PLAN-003 |
| DBA › Zmień parametr instancji | `dba.alterParameter` |  |  | Brak | SD-DBA-001 |
| DBA › Zablokuj / odblokuj konto | `dba.lockUser` |  |  | Brak | SD-DBA-001 |
| Instance Viewer | `tools.instanceViewer` |  |  | Brak | SD-DBA-004 |
| Dokumentacja schematu… | `tools.schemaDoc` |  |  | Brak | SD-DOC-001 |
| Wydajność (pakiety Oracle) › Raport AWR | `tools.awrReport` |  |  | Brak | SD-DBA-002 |
| Wydajność (pakiety Oracle) › Raport ASH | `tools.ashReport` |  |  | Brak | SD-DBA-002 |
| Wydajność (pakiety Oracle) › Raport ADDM | `tools.addmReport` |  |  | Brak | SD-DBA-002 |
| Wydajność (pakiety Oracle) › Raport SQL Monitor | `tools.sqlMonitorReport` |  |  | Brak | SD-MON-001 |
| Wydajność (pakiety Oracle) › SQL Monitor | `tools.sqlMonitor` |  |  | Brak | SD-MON-001 |
| Wydajność (pakiety Oracle) › SQL Tuning Advisor | `tools.sqlTuningAdvisor` |  |  | Brak | SD-DBA-003 |
| Obiekt › Kopiuj nazwy po przecinku | `ob.copyNames` |  |  | Brak | PD-OB-011 |
| Obiekt › Rekompiluj zaznaczone | `ob.recompileSelected` |  |  | Brak | PD-OB-011 |
| Obiekt › DDL zaznaczonych | `ob.ddlSelected` |  |  | Brak | PD-OB-011 |
| Obiekt › Usuń zaznaczone… | `ob.dropSelected` |  |  | Brak | PD-OB-011 |
| Eksportuj statystyki… | `stats.export` |  |  | Brak | PD-OPT-004 |
| Obiekt › Zmień nazwę… | `ob.rename` |  |  | Brak | PD-OB-016 |
| Obiekt › Zmień nazwę elementu… | `ob.renameChild` |  |  | Brak | PD-OB-016 |
| Obiekt › Duplikuj… | `ob.duplicate` |  |  | Brak | PD-OB-016 |
| Obiekt › Wstaw obiekt do edytora | `ob.dropText` |  |  | Brak | PD-OB-010 |
| Obiekt › Upuść obiekt na obszar okien | `ob.dropOnWorkspace` |  |  | Brak | PD-OB-010 |
| Object Browser › Filtr nazwany… | `ob.applyFilter` |  |  | Brak | PD-OB-007 |
| Obiekt › Dodaj do folderu… | `ob.addToFolder` |  |  | Brak | PD-OB-008 |
| Obiekt › Włącz | `ob.enable` |  |  | Brak | PD-OB-019 |
| Obiekt › Wyłącz | `ob.disable` |  |  | Brak | PD-OB-019 |
| Obiekt › Odśwież widok zmaterializowany | `ob.refreshMV` |  |  | Brak | PD-OB-019 |
| Obiekt › Testuj łącze | `ob.testLink` |  |  | Brak | PD-OB-019 |
| Obiekt › Uruchom zadanie | `ob.runJob` |  |  | Brak | PD-OB-019 |
| Obiekt › Uruchom kolejkę | `ob.startQueue` |  |  | Brak | PD-OB-019 |
| Obiekt › Zatrzymaj kolejkę | `ob.stopQueue` |  |  | Brak | PD-OB-019 |
| Kosz | `ob.recycleBin` |  |  | Brak | PD-OB-021 |
| Kosz › Przywróć z kosza… | `ob.restoreFromRecycleBin` |  |  | Brak | PD-OB-021 |
| Kosz › Opróżnij kosz… | `ob.purgeRecycleBin` |  |  | Brak | PD-OB-021 |
| Obiekt › Flagi kompilacji warunkowej… | `ob.ccflags` |  |  | Brak | PD-OB-020 |
| Obiekt › Dodaj źródło do edytora | `ob.addSourceToEditor` |  |  | Brak | PD-OB-023 |
| Preferencje › Eksportuj preferencje… | `prefs.export` |  |  | Brak | PD-PREF-003 |
| Preferencje › Importuj preferencje… | `prefs.import` |  |  | Brak | PD-PREF-003 |
| Preferencje › Zestawy preferencji… | `prefs.sets` |  |  | Brak | PD-PREF-002 |
| Dokumenty… | `tools.documents` |  |  | Brak | PD-DOC-002 |
| Zdalny build Pro*C › Cele SSH… | `ssh.manager` |  |  | Brak | PC-CONN-002 |
| Zdalny build Pro*C › Testuj cel SSH | `ssh.test` |  |  | Brak | PC-CONN-003 |
| Zdalny build Pro*C › Eksportuj cele SSH… | `ssh.export` |  |  | Brak | PC-CONN-001 |
| Zdalny build Pro*C › Wdróż na cel… | `proc.deploy` |  |  | Brak | PC-DEPLOY-001 |
| Zdalny build Pro*C › Wycofaj binarkę… | `proc.rollback` |  |  | Brak | PC-DEPLOY-003 |
| Zdalny build Pro*C › Historia wdrożeń | `proc.history` |  |  | Brak | PC-DEPLOY-004 |
| Zdalny build Pro*C › Konsola wdrożenia | `proc.console` |  |  | Brak | PC-CONS-001 |
| Zdalny build Pro*C › Zatrzymaj wdrożenie | `proc.stop` |  |  | Brak | PC-CONS-002 |
| Zdalny build Pro*C › Zdejmij blokadę celu… | `proc.releaseLock` |  |  | Brak | PC-DEPLOY-002 |
| Zdalny build Pro*C › Stan git i wdrożeń | `proc.gitStatus` |  |  | Brak | PC-GIT-001 |
| Zdalny build Pro*C › Importuj cele SSH… | `ssh.import` |  |  | Brak | PC-CONN-001 |
| Database Diff… | `tools.databaseDiff` |  |  | Brak | SD-DIFF-001 |
| Koszyk wdrożenia… | `tools.cart` |  |  | Brak | SD-DIFF-001 |
| Koszyk › Dodaj obiekt do koszyka | `cart.add` |  |  | Brak | SD-DIFF-001 |
| Koszyk › Skrypt wdrożenia koszyka | `cart.script` |  |  | Brak | SD-DIFF-001 |
| Kopiowanie schematu… | `tools.schemaCopy` |  |  | Brak | SD-COPY-001 |
| Kreator importu danych… | `tools.importWizard` |  |  | Brak | SD-IMP-001 |
| Diagram › Diagram ER ze schematu… | `diagram.fromSchema` |  |  | Brak | DB-DIAG-001 |
| Przenoszenie danych… | `tools.dataTransfer` |  |  | Brak | DB-XFER-001 |
| Wykonaj zapisane przeniesienie danych | `transfer.run` |  |  | Brak | DB-XFER-001 |
| Zadania lokalne… | `tools.localTasks` |  |  | Brak | DB-TASK-001 |
| Uruchom zadanie lokalne | `localTasks.runNow` |  |  | Brak | DB-TASK-001 |
| Widoki dualności JSON | `tools.dualityViews` |  |  | Brak | SD-DV-001 |
| Nowy widok dualności… | `tools.dualityViewDDL` |  |  | Brak | SD-DV-001 |
| Moduły i środowiska MLE | `tools.mleModules` |  |  | Brak | SD-MLE-001 |
| Importuj moduł JavaScript… | `tools.importMLEModule` |  |  | Brak | SD-MLE-001 |
| Debuguj moduł MLE po wykonaniu… | `tools.debugMLE` |  |  | Brak | SD-MLE-001 |
| REST (ORDS) › Moduły REST (ORDS) | `tools.ordsModules` |  |  | Brak | SD-ORDS-001 |
| REST (ORDS) › Włącz REST dla schematu… | `tools.ordsEnableSchema` |  |  | Brak | SD-ORDS-001 |
| REST (ORDS) › Włącz REST dla obiektu… | `tools.ordsEnableObject` |  |  | Brak | SD-ORDS-001 |
| Test Manager | `tools.testManager` |  |  | Brak | PD-TOOL-018 |
| Test Manager › Uruchom zestaw testów | `testManager.run` |  |  | Brak | PD-TOOL-018 |
| Monitor zdarzeń… | `tools.eventMonitor` |  |  | Brak | PD-TOOL-014 |
| Test obciążenia… | `tools.loadTester` |  |  | Brak | PD-TOOL-019 |
| Obiekt › Pokaż dane | `ob.queryData` |  |  | Brak | PD-OB-017 |
| Obiekt › Edytuj dane | `ob.editData` |  |  | Brak | PD-OB-017 |
| Obiekt › DDL | `ob.ddl` |  |  | Brak | PD-OB-015 |
| Obiekt › Opis | `ob.describe` |  |  | Brak | PD-OB-013 |
| Obiekt › Właściwości | `ob.properties` |  |  | Brak | PD-OB-012 |
| Obiekt › Edytuj | `ob.edit` |  |  | Brak | PD-OB-014 |
| Obiekt › Rekompiluj | `ob.recompile` |  |  | Brak | PD-OB-009 |
| Obiekt › Dodaj informację debugowania | `ob.addDebugInfo` |  |  | Brak | PD-DBG-011 |
| Obiekt › Usuń obiekt… | `ob.drop` |  |  | Brak | PD-OB-016 |
| Obiekt › Kopiuj nazwę | `ob.copyName` |  |  | Brak | PD-OB-011 |
| Obiekt › Odśwież Object Browser | `ob.refresh` |  |  | Brak | PD-OB-004 |
| Zapisz kryteria wyszukiwania | `tools.saveObjectSearch` |  |  | Brak | PD-TOOL-001 |
| Usuń zapisane kryteria wyszukiwania | `tools.deleteObjectSearch` |  |  | Brak | PD-TOOL-001 |
| Znajdź obiekty bazy… | `tools.findObjects` | ⌃⇧O †, ⇧⌘O | ⇧⌘O | Brak | PD-TOOL-001 |
| Kompiluj niepoprawne obiekty… | `tools.compileInvalid` |  |  | Brak | PD-TOOL-002 |
| Szablony › Zapisz zaznaczenie jako szablon… | `templates.save` |  |  | Brak | PD-TPL-003 |
| Szablony › Usuń szablon | `templates.delete` |  |  | Brak | PD-TPL-003 |
| Szablony › Edytuj szablon… | `templates.edit` |  |  | Brak | PD-TPL-003 |
| Szablony › Nowy folder szablonów… | `templates.newFolder` |  |  | Brak | PD-TPL-003 |
| Szablony › Zmień nazwę folderu szablonów… | `templates.renameFolder` |  |  | Brak | PD-TPL-003 |
| Szablony › Usuń folder szablonów | `templates.deleteFolder` |  |  | Brak | PD-TPL-003 |
| Obiekt › Porównaj z aktywnym oknem | `ob.compare` |  |  | Brak | PD-OB-022 |
| Obiekt › Porównaj z obiektem w innej bazie… | `ob.compareWithConnection` |  |  | Brak | PD-OB-022 |
| Porównaj pliki… | `tools.compareFiles` |  |  | Brak | PD-DIFF-001 |
| Porównaj teksty | `tools.compareTexts` |  |  | Brak | PD-DIFF-001 |
| Obiekt › Edytor widoku | `ob.viewEditor` |  |  | Brak | PD-OED-010 |
| Obiekt › Testuj | `ob.test` |  |  | Brak | PD-TEST-004 |
| Obiekt › Test standardowy… | `ob.standardTest` |  |  | Brak | PD-TEST-009 |
| Obiekt › Edytuj definicję tabeli | `ob.editTable` |  |  | Brak | PD-OED-002 |
| utPLSQL › utPLSQL: uruchom wszystkie testy | `utplsql.runAll` | ⌃⇧U †, ⇧⌘U | ⇧⌘U | Brak | UT-RUN-001 |
| utPLSQL › utPLSQL: uruchom testy ze ścieżki… | `utplsql.runPath` |  |  | Brak | UT-RUN-002 |
| utPLSQL › utPLSQL: uruchom z opcjami… | `utplsql.runWithOptions` |  |  | Brak | UT-RUN-003 |
| utPLSQL › utPLSQL: testy z pokryciem kodu | `utplsql.coverage` |  |  | Brak | UT-COV-001 |
| utPLSQL › utPLSQL: uruchom test pod kursorem | `utplsql.runEditor` | ⌃⌥U †, ⌃⌘U | ⌃⌘U | Brak | UT-RUN-004 |
| utPLSQL › utPLSQL: uruchom ponownie nieudane | `utplsql.rerunFailed` |  |  | Brak | UT-RUN-006 |
| utPLSQL › utPLSQL: przerwij | `utplsql.cancel` |  |  | Brak | UT-RUN-006 |
| utPLSQL › utPLSQL: wersja w bazie | `utplsql.version` |  |  | Brak | UT-INS-001 |
| utPLSQL › utPLSQL: instaluj lub aktualizuj… | `utplsql.install` |  |  | Brak | UT-INS-002 |
| utPLSQL › utPLSQL: generuj pakiet testowy | `utplsql.generateTest` |  |  | Brak | UT-GEN-001 |
| utPLSQL › utPLSQL: przejdź do testu / testowanego pakietu | `utplsql.toggleTest` | ⌃⇧T †, ⌃⌘T | ⌃⌘T | Brak | UT-NAV-001 |
| utPLSQL › utPLSQL: eksport wyników… | `utplsql.export` |  |  | Brak | UT-CI-001 |
| utPLSQL › utPLSQL: skrypt dla wiersza poleceń | `utplsql.cliScript` |  |  | Brak | UT-CI-001 |
| Obiekt › Uruchom testy utPLSQL | `ob.utplsqlRun` |  |  | Brak | UT-RUN-003 |
| Git › Stan Git pliku | `vcs.status` |  |  | Brak | PD-VCS-001 |
| Git › Porównaj z HEAD | `vcs.diff` |  |  | Brak | PD-VCS-001 |
| Git › Dodaj do zatwierdzenia (git add) | `vcs.add` |  |  | Brak | PD-VCS-001 |
| Git › Zatwierdź (git commit)… | `vcs.commit` |  |  | Brak | PD-VCS-001 |
| Git › Historia Git pliku | `vcs.log` |  |  | Brak | PD-VCS-001 |
| Explain Plan | `tools.explainPlan` | F5 | F5 | Brak | PD-OPT-002 |
| Plan › Zapisz plan jako… | `plan.export` |  |  | Brak | PD-OPT-003 |
| Sesje | `tools.sessions` |  |  | Brak | PD-TOOL-015 |
| Eksport obiektów użytkownika… | `tools.exportUserObjects` |  |  | Brak | PD-TOOL-007 |
| Porównaj obiekty użytkowników… | `tools.compareUserObjects` |  |  | Brak | PD-TOOL-012 |
| Sesje › Zabij sesję | `sessions.kill` |  |  | Brak | PD-TOOL-015 |
| DBMS Scheduler | `tools.scheduler` |  |  | Brak | PD-SCHED-001 |
| Diagram › Dodaj do diagramu | `diagram.addObject` |  |  | Brak | PD-DIAG-001 |
| Diagram › Dodaj powiązane tabele | `diagram.addRelated` |  |  | Brak | PD-DIAG-001 |
| Diagram › Dodaj zależności | `diagram.addReferences` |  |  | Brak | PD-DIAG-001 |
| Diagram › Pokaż lub ukryj kolumny | `diagram.showColumns` |  |  | Brak | PD-DIAG-001 |
| Diagram › Dodaj notatkę | `diagram.addNote` |  |  | Brak | PD-DIAG-002 |
| Diagram › Grupuj zaznaczone | `diagram.addGroup` |  |  | Brak | PD-DIAG-002 |
| Diagram › Usuń z diagramu | `diagram.delete` |  |  | Brak | PD-DIAG-002 |
| Diagram › Powiększenie diagramu | `diagram.zoom` |  |  | Brak | PD-DIAG-002 |
| Diagram › Siatka diagramu | `diagram.toggleGrid` |  |  | Brak | PD-DIAG-002 |
| Diagram › Aktualizuj z bazy | `diagram.updateFromDB` |  |  | Brak | PD-DIAG-003 |
| Diagram › Eksportuj diagram jako obraz… | `diagram.export` |  |  | Brak | PD-DIAG-003 |
| Diagram › Kopiuj diagram jako obraz | `diagram.copyImage` |  |  | Brak | PD-DIAG-003 |
| Diagram › Drukuj diagram… | `diagram.print` |  |  | Brak | PD-DIAG-003 |
| Query Builder… | `tools.queryBuilder` |  |  | Brak | PD-QB-001 |
| Eksport tabel… | `tools.exportTables` |  |  | Brak | PD-TOOL-003 |
| Import tabel… | `tools.importTables` |  |  | Brak | PD-TOOL-006 |
| Import tekstu… | `tools.textImporter` |  |  | Brak | PD-TOOL-008 |
| Import z Excela… | `tools.excelImporter` |  |  | Brak | PD-TOOL-009 |
| Generator danych… | `tools.dataGenerator` |  |  | Brak | PD-TOOL-011 |
| Porównaj dane tabel… | `tools.compareTableData` |  |  | Brak | PD-TOOL-013 |
| Narzędzia użytkownika… | `tools.configureTools` |  |  | Brak | PD-TOOL-017 |

## Raporty

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Funkcja |
|---|---|---|---|---|---|
| Raporty predefiniowane… | `reports.predefined` |  |  | Brak | SD-REP-001 |
| Wykonaj raport predefiniowany | `reports.predefined.run` |  |  | Brak | SD-REP-001 |
| Otwórz raport w oknie SQL | `reports.predefined.worksheet` |  |  | Brak | SD-REP-001 |
| Błędy kompilacji | `reports.compilationErrors` |  |  | Brak | PD-REP-001 |
| Niepoprawne obiekty | `reports.invalidObjects` |  |  | Brak | PD-REP-001 |
| Ostatnio zmienione obiekty | `reports.recentChanges` |  |  | Brak | PD-REP-001 |
| Rozmiary tabel | `reports.tableSizes` |  |  | Brak | PD-REP-001 |
| Kolumny tabel | `reports.tableColumns` |  |  | Brak | PD-REP-001 |
| Uprawnienia użytkownika | `reports.privileges` |  |  | Brak | PD-REP-001 |
| Sesje | `reports.sessions` |  |  | Brak | PD-REP-001 |
| Raport › Wykonaj raport | `report.execute` |  |  | Brak | PD-REP-002 |
| Raport › Zapisz raport jako HTML… | `report.saveHTML` |  |  | Brak | PD-REP-001 |
| Raport › Eksportuj dane raportu… | `report.export` |  |  | Brak | PD-REP-001 |
| Raport › Drukuj raport… | `report.print` |  |  | Brak | PD-REP-001 |
| Raport › Zablokuj definicję raportu | `report.lock` |  |  | Brak | PD-REP-004 |
| Raport › Odblokuj definicję raportu | `report.unlock` |  |  | Brak | PD-REP-004 |
| Raport › Dodaj raport do menu Raporty | `report.addToMenu` |  |  | Brak | PD-REP-004 |

## Widok

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Funkcja |
|---|---|---|---|---|---|
| Panel wartości | `grid.valuePanel` | ⌥⌘V | ⌥⌘V | Brak | DB-PANEL-001 |
| Snippety | `view.snippets` |  |  | Brak | SC-SNIP-001 |
| Panel DBA | `view.dba` |  |  | Brak | SD-DBA-001 |
| Zadania w tle | `view.taskMonitor` |  |  | Brak | SD-MON-002 |
| Siatka › Układ liczb w siatce | `grid.numberLayout` |  |  | Brak | PD-GRID-004 |
| Siatka › Auto Format w Large Data Editor | `grid.largeDataAutoFormat` |  |  | Brak | PD-LDE-001 |
| Siatka › Większa czcionka siatki | `grid.fontLarger` |  |  | Brak | PD-GRID-025 |
| Siatka › Mniejsza czcionka siatki | `grid.fontSmaller` |  |  | Brak | PD-GRID-025 |
| Siatka › Domyślna czcionka siatki | `grid.fontReset` |  |  | Brak | PD-GRID-025 |
| Siatka › Numer wiersza w kopiowaniu i eksporcie | `grid.toggleRowNumbers` |  |  | Brak | PD-GRID-027 |
| Podziel edytor | `view.splitEditor` |  |  | Brak | PD-EDIT-014 |
| Powiększ czcionkę edytora | `view.zoomIn` | ⌃= †, ⌘= | ⌘= | Brak | PD-EDIT-021 |
| Pomniejsz czcionkę edytora | `view.zoomOut` | ⌃⇧- †, ⌘- | ⌘- | Brak | PD-EDIT-021 |
| Domyślny rozmiar czcionki edytora | `view.zoomReset` | ⌃0 †, ⌘0 | ⌘0 | Brak | PD-EDIT-021 |
| Dostosuj pasek narzędzi… | `view.customizeToolbar` |  |  | Brak | PD-UI-006 |
| Dodaj do paska szybkiego dostępu | `view.addToQuickAccess` |  |  | Brak | PD-UI-006 |
| Usuń z paska szybkiego dostępu | `view.removeFromQuickAccess` |  |  | Brak | PD-UI-006 |
| Podgląd przestrzenny | `grid.spatialPreview` |  |  | Brak | SD-DATA-001 |
| Zawijaj wiersze | `view.wordWrap` |  |  | Brak | PD-EDIT-004 |
| Okno szablonów | `view.templateWindow` |  |  | Brak | PD-TPL-001 |
| Znaki specjalne | `view.specialCharacters` |  |  | Brak | PD-EDIT-003 |
| Status linii | `view.lineStatus` |  |  | Brak | PD-EDIT-003 |
| Eksplorator testów utPLSQL | `utplsql.explorer` |  |  | Brak | UT-EXP-001 |
| Historia schowka | `view.clipboardHistory` |  |  | Brak | PD-EDIT-024 |
| Zadania To-Do | `view.todoItems` |  |  | Brak | PD-TODO-001 |
| Przeglądarka plików | `view.fileBrowser` |  |  | Brak | PD-FB-001 |
| Zapisz układ okna | `view.saveLayout` |  |  | Brak | PD-WSET-002 |
| Przywróć układ okna | `view.restoreLayout` |  |  | Brak | PD-WSET-002 |
| Autozapis układu okna | `view.autosaveLayout` |  |  | Brak | PD-WSET-002 |
| Paleta komend… | `view.commandPalette` | ⇧⌘P | ⇧⌘P | Brak | PD-UI-007 |
| Zawartość kodu | `view.codeContents` |  |  | Brak | PD-CA-010 |
| Przeglądarka obiektów | `view.objectBrowser` |  |  | Brak | PD-OB-001 |

## Okno

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Funkcja |
|---|---|---|---|---|---|
| Wykonaj okno | `window.execute` |  |  | Brak | PD-UI-002 |
| Połącz ponownie okno | `window.reconnect` |  |  | Brak | PD-UI-002 |
| Zmień nazwę okna… | `window.rename` |  |  | Brak | PD-UI-002 |
| Krótkie nazwy na liście okien | `window.listShortTitles` |  |  | Brak | PD-UI-002 |
| Sortuj listę okien… | `window.listSort` |  |  | Brak | PD-UI-002 |
| Następne okno | `window.next` | ⌃⇥, ⇧⌘] | ⇧⌘], ⌃⇥ | Za zgodą | PD-UI-004 |
| Poprzednie okno | `window.previous` | ⌃⇧⇥, ⇧⌘[ | ⇧⌘[, ⌃⇧⇥ | Za zgodą | PD-UI-004 |

## Pomoc

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Funkcja |
|---|---|---|---|---|---|
| Połączenia (agent) | `agent.connections` |  |  | Odczyt | AI-TOOL-001 |
| Stan okien (agent) | `agent.state` |  |  | Odczyt | AI-TOOL-001 |
| Treść edytora (agent) | `agent.editor` |  |  | Odczyt | AI-TOOL-001 |
| Nowe okno z tekstem (agent) | `agent.openEditor` |  |  | Pełny | AI-TOOL-002 |
| Wstaw tekst (agent) | `agent.insertText` |  |  | Pełny | AI-TOOL-002 |
| Zamień zakres linii (agent) | `agent.replaceRange` |  |  | Pełny | AI-TOOL-002 |
| Przejdź do linii (agent) | `agent.navigate` |  |  | Pełny | AI-TOOL-002 |
| Formatuj kod (agent) | `agent.format` |  |  | Pełny | AI-TOOL-002 |
| Szukaj obiektów (agent) | `agent.searchObjects` |  |  | Odczyt | AI-TOOL-001 |
| Opis obiektu (agent) | `agent.describe` |  |  | Odczyt | AI-TOOL-001 |
| Źródło programu (agent) | `agent.source` |  |  | Odczyt | AI-TOOL-001 |
| DDL obiektu (agent) | `agent.ddl` |  |  | Odczyt | AI-TOOL-001 |
| Zależności obiektu (agent) | `agent.dependencies` |  |  | Odczyt | AI-TOOL-001 |
| Użycia obiektu (agent) | `agent.findUsages` |  |  | Odczyt | AI-TOOL-001 |
| Zapytanie (agent) | `agent.query` |  |  | Odczyt | AI-SEC-006 |
| Plan wykonania (agent) | `agent.explain` |  |  | Odczyt | AI-TOOL-001 |
| Błędy kompilacji (agent) | `agent.compileErrors` |  |  | Odczyt | AI-TOOL-001 |
| DBMS_OUTPUT sesji agenta | `agent.dbmsOutput` |  |  | Odczyt | AI-TOOL-001 |
| Testy utPLSQL (agent) | `agent.listTests` |  |  | Odczyt | AI-TOOL-001 |
| Wyniki testów (agent) | `agent.testResults` |  |  | Odczyt | AI-TOOL-001 |
| Pokrycie kodu (agent) | `agent.coverage` |  |  | Odczyt | AI-TOOL-001 |
| Sesje bazy (agent) | `agent.sessions` |  |  | Odczyt | AI-TOOL-001 |
| Otwórz obiekt (agent) | `agent.openObject` |  |  | Pełny | AI-TOOL-002 |
| Wykonaj polecenie (agent) | `agent.execute` |  |  | Za zgodą | AI-TOOL-003 |
| Wykonaj skrypt (agent) | `agent.executeScript` |  |  | Za zgodą | AI-TOOL-003 |
| Utwórz pakiet testowy (agent) | `agent.createTestPackage` |  |  | Za zgodą | AI-TOOL-003 |
| Kompiluj (agent) | `agent.compile` |  |  | Za zgodą | AI-TOOL-003 |
| COMMIT zmian agenta | `agent.commit` |  |  | Za zgodą | AI-SEC-007 |
| ROLLBACK zmian agenta | `agent.rollback` |  |  | Za zgodą | AI-SEC-007 |
| Uruchom testy utPLSQL (agent) | `agent.runTests` |  |  | Za zgodą | AI-TOOL-003 |
| Generuj i kompiluj szkielet testu (agent) | `agent.generateTest` |  |  | Za zgodą | AI-TOOL-003 |
| Instaluj utPLSQL (agent) | `agent.installUtplsql` |  |  | Za zgodą | AI-TOOL-003 |
| Pomoc kontekstowa (dokumentacja Oracle) | `help.context` | F1 | F1 | Brak | PD-EDIT-026 |
| Instrukcja Pelikana | `help.manual` | ⇧⌘/ | ⇧⌘/ | Brak | PL-INFRA-010 |
| Dokumentacja Oracle… | `help.oracleManuals` |  |  | Brak | PD-DOC-001 |

