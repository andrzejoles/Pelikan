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
| Kodowanie pliku… | `file.encoding` |  |  | Brak | 0 | PC-ENC-001 |
| Zamknij okno | `file.close` | ⌘W | ⌘W | Pełny | 0 | PD-UI-004 |
| Zamknij wskazane okno | `file.closeWindow` |  |  | Pełny | 0 | PD-UI-004 |
| Zamknij pozostałe okna | `file.closeOthers` |  |  | Brak | 0 | PD-UI-004 |
| Zamknij okna z lewej | `file.closeLeft` |  |  | Brak | 0 | PD-UI-004 |
| Zamknij okna z prawej | `file.closeRight` |  |  | Brak | 0 | PD-UI-004 |
| Zamknij wszystkie okna | `file.closeAll` | ⌥⌘W | ⌥⌘W | Brak | 0 | PD-UI-004 |
| Drukuj… | `file.print` | ⌘P | ⌘P | Brak | 0 | PD-SQLW-016 |
| Eksportuj wynik… | `grid.export` |  |  | Brak | 0 | PD-GRID-013 |
| Eksport wyniku › Kolumna do plików… | `grid.columnToFiles` |  |  | Brak | 0 | PD-GRID-016 |
| Wklej jako nowe SQL Window | `file.pasteAsSQLWindow` |  |  | Brak | 0 | PD-SQLW-025 |
| Tylko do odczytu | `file.readOnly` |  |  | Brak | 0 | PD-FILE-003 |
| Otwórz z połączeniem… | `file.openWithConnection` |  |  | Brak | 0 | PD-FILE-004 |
| Wykonaj parametry startowe | `app.openStartupParameters` |  |  | Brak | 0 | PD-CLI-001 |
| Odzyskaj okna… | `file.restoreRecovery` |  |  | Brak | 0 | PD-FILE-001 |
| Notatnik › Eksportuj notatnik jako Markdown… | `notebook.exportMarkdown` |  |  | Brak | 0 | SD-NB-001 |
| Historia lokalna › Historia lokalna | `file.localHistory` |  |  | Brak | 0 | DG-HIST-001 |
| Historia lokalna › Wersje w historii lokalnej | `file.localHistoryList` |  |  | Odczyt | 0 | DG-HIST-001 |
| Historia lokalna › Zapisz wersję w historii | `file.localHistoryCheckpoint` |  |  | Brak | 0 | DG-HIST-001 |
| Historia lokalna › Porównaj z wersją | `file.localHistoryCompare` |  |  | Brak | 0 | DG-HIST-001 |
| Historia lokalna › Przywróć wersję | `file.localHistoryRestore` |  |  | Brak | 0 | DG-HIST-001 |
| Nowy › Nowy program z szablonu… | `file.newFromTemplate` |  |  | Pełny | 0 | PD-PROG-002 |
| Okno programu › Dodaj jednostkę… | `prog.addUnit` |  |  | Pełny | 0 | PD-PROG-001 |
| Okno programu › Usuń jednostkę | `prog.removeUnit` |  |  | Pełny | 0 | PD-PROG-001 |
| Przywróć | `prog.revert` |  |  | Pełny | 0 | PD-PROG-009 |
| Porównaj › Porównaj ze źródłem w bazie | `prog.compareWithDatabase` |  |  | Odczyt | 0 | PD-PROG-008 |
| Porównaj › Porównaj z plikiem… | `prog.compareWithFile` |  |  | Brak | 0 | PD-PROG-008 |
| Porównaj › Porównaj z obiektami w innej bazie… | `prog.compareWithConnection` |  |  | Odczyt | 0 | PD-PROG-008 |
| Nowy › Tabela… | `file.newTable` |  |  | Brak | 0 | PD-OED-001 |
| Nowy › Sekwencja… | `file.newSequence` |  |  | Brak | 0 | PD-OED-008 |
| Nowy › Synonim… | `file.newSynonym` |  |  | Brak | 0 | PD-OED-008 |
| Nowy › Indeks… | `file.newIndex` |  |  | Brak | 0 | PD-OED-010 |
| Nowy › Użytkownik… | `file.newUser` |  |  | Brak | 0 | PD-OED-009 |
| Nowy › Rola… | `file.newRole` |  |  | Brak | 0 | PD-OED-009 |
| Nowy › Domena… | `file.newDomain` |  |  | Brak | 0 | PD-OED-011 |
| Nowy › Asercja… | `file.newAssertion` |  |  | Brak | 0 | PD-OED-011 |
| Nowy › Widok… | `file.newView` |  |  | Brak | 0 | PD-OED-010 |
| Zapisz test jako skrypt SQL*Plus | `test.saveAsSQLPlus` |  |  | Pełny | 0 | PD-TEST-005 |
| Przeglądarka plików › Dodaj lokalizację… | `fb.addLocation` |  |  | Brak | 0 | PD-FB-001 |
| Przeglądarka plików › Usuń lokalizację | `fb.removeLocation` |  |  | Brak | 0 | PD-FB-001 |
| Przeglądarka plików › Otwórz jako… | `fb.open` |  |  | Brak | 0 | PD-FB-001 |
| Przeglądarka plików › Zmień nazwę… | `fb.rename` |  |  | Brak | 0 | PD-FB-001 |
| Przeglądarka plików › Nowy katalog… | `fb.newFolder` |  |  | Brak | 0 | PD-FB-001 |
| Przeglądarka plików › Nowy plik… | `fb.newFile` |  |  | Brak | 0 | PD-FB-001 |
| Przeglądarka plików › Przenieś do Kosza | `fb.trash` |  |  | Brak | 0 | PD-FB-001 |
| Przeglądarka plików › Pokaż w Finderze | `fb.showInFinder` |  |  | Brak | 0 | PD-FB-001 |
| Przeglądarka plików › Pokaż ukryte pliki | `fb.toggleHidden` |  |  | Brak | 0 | PD-FB-001 |
| Przeglądarka plików › Wyczyść historię filtra | `fb.clearFilterHistory` |  |  | Brak | 0 | PD-FB-002 |
| Workset › Nowy workset… | `workset.new` |  |  | Brak | 0 | PD-WSET-001 |
| Workset › Otwórz workset… | `workset.open` |  |  | Brak | 0 | PD-WSET-001 |
| Workset › Zapisz workset | `workset.save` |  |  | Brak | 0 | PD-WSET-001 |
| Workset › Przywróć workset | `workset.revert` |  |  | Brak | 0 | PD-WSET-001 |
| Workset › Zamknij workset | `workset.close` |  |  | Brak | 0 | PD-WSET-001 |
| Workset › Porównaj worksety… | `workset.compare` |  |  | Brak | 0 | PD-WSET-001 |
| Workset › Usuń workset… | `workset.delete` |  |  | Brak | 0 | PD-WSET-001 |
| Workset › Autozapis workseta | `workset.toggleAutosave` |  |  | Brak | 0 | PD-WSET-001 |

## Projekt

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Elementy projektu | `project.show` |  |  | Brak | 0 | PD-PROJ-001 |
| Nowy projekt… | `project.new` |  |  | Brak | 0 | PD-PROJ-001 |
| Otwórz projekt… | `project.open` |  |  | Brak | 0 | PD-PROJ-001 |
| Zamknij projekt | `project.close` |  |  | Brak | 0 | PD-PROJ-001 |
| Dodaj plik okna do projektu | `project.addActiveFile` |  |  | Brak | 0 | PD-PROJ-001 |
| Dodaj obiekt do projektu | `project.addSelectedObject` |  |  | Brak | 0 | PD-PROJ-001 |
| Buduj projekt | `project.build` |  |  | Brak | 0 | PD-PROJ-002 |
| Make projektu | `project.make` |  |  | Brak | 0 | PD-PROJ-002 |
| Zapisz pulpit projektu | `project.saveDesktop` |  |  | Brak | 0 | PD-PROJ-003 |
| Otwórz pulpit projektu | `project.openDesktop` |  |  | Brak | 0 | PD-PROJ-003 |
| Szukaj w projekcie… | `project.find` |  |  | Brak | 0 | PD-PROJ-003 |

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
| Wynik › Kopiuj | `grid.copy` |  |  | Brak | 0 | PD-GRID-015 |
| Wynik › Kopiuj z nagłówkiem | `grid.copyWithHeader` | ⌃⇧C †, ⇧⌘C | ⇧⌘C | Brak | 0 | PD-GRID-015 |
| Wynik › Kopiuj nagłówek | `grid.copyHeader` |  |  | Brak | 0 | PD-GRID-015 |
| Wynik › Kopiuj jako listę wyrażeń | `grid.copyExpressionList` |  |  | Brak | 0 | PD-GRID-015 |
| Wynik › Kopiuj jako… | `grid.copyAs` |  |  | Brak | 0 | PD-GRID-013 |
| Wynik › Kopiuj do Excela | `grid.copyToExcel` |  |  | Brak | 0 | PD-GRID-014 |
| Wynik › Large Data Editor… | `grid.largeData` | ⌥⌘L | ⌥⌘L | Brak | 0 | PD-GRID-003 |
| Wstaw snippet | `edit.insertSnippet` |  |  | Brak | 0 | SC-SNIP-001 |
| Wynik › Kalendarz… | `grid.chooseDate` |  |  | Brak | 0 | PD-GRID-005 |
| Wynik › Zaznacz blok komórek | `grid.selectBlock` |  |  | Brak | 0 | PD-GRID-007 |
| Wynik › Zaznacz kolumnę | `grid.selectColumn` |  |  | Brak | 0 | PD-GRID-007 |
| Wynik › Wielkie litery w komórkach | `grid.upperCase` |  |  | Brak | 0 | PD-GRID-026 |
| Wynik › Małe litery w komórkach | `grid.lowerCase` |  |  | Brak | 0 | PD-GRID-026 |
| Zakładki › Przełącz zakładkę | `edit.toggleBookmark` | ⌘F3 | ⌘F3 | Brak | 0 | PD-EDIT-011 |
| Zakładki › Przejdź do zakładki | `edit.gotoBookmark` |  |  | Brak | 0 | PD-EDIT-011 |
| Zakładki › Następna zakładka | `edit.nextBookmark` | ⌥⌘F3 | ⌥⌘F3 | Brak | 0 | PD-EDIT-011 |
| Zakładki › Poprzednia zakładka | `edit.previousBookmark` | ⌥⇧⌘F3 | ⌥⇧⌘F3 | Brak | 0 | PD-EDIT-011 |
| Zakładki › Nazwij zakładkę… | `edit.renameBookmark` |  |  | Brak | 0 | PD-EDIT-011 |
| Zakładki › Lista zakładek | `edit.bookmarkList` |  |  | Brak | 0 | PD-EDIT-011 |
| Zakładki › Usuń zakładki okna | `edit.clearBookmarks` |  |  | Brak | 0 | PD-EDIT-011 |
| Znaczniki kolorów › Oznacz kolorem | `edit.colorMark` |  |  | Brak | 0 | PD-EDIT-012 |
| Znaczniki kolorów › Usuń znaczniki kolorów | `edit.clearColorMarks` |  |  | Brak | 0 | PD-EDIT-012 |
| Wiele kursorów › Dodaj kursor powyżej | `edit.addCursorAbove` | ⌃⇧↑ † | ⌃⇧↑ | Brak | 0 | PD-EDIT-023 |
| Wiele kursorów › Dodaj kursor poniżej | `edit.addCursorBelow` | ⌃⇧↓ † | ⌃⇧↓ | Brak | 0 | PD-EDIT-023 |
| Wiele kursorów › Jeden kursor | `edit.singleCursor` |  |  | Brak | 0 | PD-EDIT-023 |
| Refaktoryzacja › Wydziel stałą lokalną… | `edit.extractLocalConstant` |  |  | Pełny | 0 | PD-CA-014 |
| Refaktoryzacja › Wydziel stałą globalną… | `edit.extractGlobalConstant` |  |  | Pełny | 0 | PD-CA-014 |
| Refaktoryzacja › Wydziel procedurę… | `edit.extractProcedure` |  |  | Pełny | 0 | PD-CA-014 |
| Refaktoryzacja › Zamień przypisanie na inicjalizację | `edit.replaceAssignmentWithInitialization` |  |  | Pełny | 0 | PD-CA-014 |
| Szukaj w edytorach i plikach… | `edit.searchBar` | ⌥⇧⌘F | ⌥⇧⌘F | Odczyt | 0 | PD-CA-015 |
| Szukaj w sieci | `edit.webSearch` |  |  | Brak | 0 | PD-EDIT-027 |
| Otwórz w zewnętrznym edytorze | `edit.openInExternalEditor` |  |  | Brak | 0 | PD-EDIT-028 |
| Analiza kodu › Analizuj kod | `edit.analyzeCode` |  |  | Odczyt | 0 | DG-INSP-001 |
| Analiza kodu › Analiza kodu w czasie pisania | `edit.toggleCodeAnalysis` |  |  | Brak | 0 | DG-RES-001 |
| Analiza kodu › Następny problem | `edit.nextProblem` |  | F2 | Brak | 0 | DG-RES-001 |
| Analiza kodu › Poprzedni problem | `edit.previousProblem` |  | ⇧F2 | Brak | 0 | DG-RES-001 |
| Analiza kodu › Lista problemów | `edit.showProblems` |  |  | Brak | 0 | DG-INSP-001 |
| Refaktoryzacja › Znajdź użycia | `edit.findUsages` |  | ⌥F7 | Brak | 0 | DG-USE-001 |
| Refaktoryzacja › Zmień nazwę… | `edit.refactorRename` |  | ⇧F6 | Za zgodą | 0 | DG-REF-001 |
| Wstaw szablon… | `edit.insertTemplate` |  |  | Pełny | 0 | PD-TPL-002 |
| Zawartość kodu › Zaznacz element | `codeContents.select` |  |  | Pełny | 0 | PD-CA-010 |
| Zawartość kodu › Kopiuj element | `codeContents.copy` |  |  | Odczyt | 0 | PD-CA-010 |
| Zawartość kodu › Wytnij element | `codeContents.cut` |  |  | Pełny | 0 | PD-CA-010 |
| Zawartość kodu › Testuj podprogram | `codeContents.test` |  |  | Pełny | 0 | PD-CA-010 |
| Nawigacja › Wstecz | `edit.navigateBack` | ⌃⌥← †, ⌃⌘← | ⌃⌘← | Pełny | 0 | PD-CA-013 |
| Nawigacja › Naprzód | `edit.navigateForward` | ⌃⌥→ †, ⌃⌘→ | ⌃⌘→ | Pełny | 0 | PD-CA-013 |
| Makra › Nagrywaj makro | `edit.macroRecord` | F11 | F11 | Brak | 0 | PD-EDIT-015 |
| Makra › Odtwórz makro | `edit.macroPlay` | F12 | F12 | Brak | 0 | PD-EDIT-015 |
| Makra › Odtwórz makro wielokrotnie… | `edit.macroRepeat` | ⇧F12 † | ⇧F12 | Brak | 0 | PD-EDIT-015 |
| Makra › Zapisz makro w bibliotece… | `edit.macroSave` |  |  | Brak | 0 | PD-EDIT-015 |
| Makra › Biblioteka makr… | `edit.macroLibrary` |  |  | Brak | 0 | PD-EDIT-015 |
| Kopiuj jako literał › Swift | `edit.specialCopy.swift` |  |  | Pełny | 0 | PD-EDIT-016 |
| Kopiuj jako literał › Java | `edit.specialCopy.java` |  |  | Pełny | 0 | PD-EDIT-016 |
| Kopiuj jako literał › C# | `edit.specialCopy.csharp` |  |  | Pełny | 0 | PD-EDIT-016 |
| Kopiuj jako literał › JavaScript | `edit.specialCopy.javascript` |  |  | Pełny | 0 | PD-EDIT-016 |
| Kopiuj jako literał › Python | `edit.specialCopy.python` |  |  | Pełny | 0 | PD-EDIT-016 |
| Kopiuj jako literał › C/C++ | `edit.specialCopy.c` |  |  | Pełny | 0 | PD-EDIT-016 |
| Kopiuj jako literał › PHP | `edit.specialCopy.php` |  |  | Pełny | 0 | PD-EDIT-016 |
| Kopiuj jako literał › Delphi | `edit.specialCopy.delphi` |  |  | Pełny | 0 | PD-EDIT-016 |
| Kopiuj jako literał › Visual Basic | `edit.specialCopy.vb` |  |  | Pełny | 0 | PD-EDIT-016 |
| Kopiuj jako literał › Wklej z języka programowania | `edit.pasteHostLanguage` |  |  | Pełny | 0 | PD-EDIT-016 |
| Wklej z historii schowka | `edit.pasteFromHistory` |  |  | Brak | 0 | PD-EDIT-024 |
| Wstaw zadanie To-Do | `edit.todoInsert` |  |  | Pełny | 0 | PD-TODO-001 |
| Zamknij lub otwórz zadanie To-Do | `edit.todoToggle` |  |  | Pełny | 0 | PD-TODO-001 |

## Sesja

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Zakończ sesję okna (Kill) | `session.kill` |  |  | Brak | 0 | PD-CONN-027 |
| Zmień hasło… | `session.setPassword` |  |  | Brak | 1 | PD-CONN-017 |
| SQL Trace | `session.sqlTrace` |  |  | Brak | 0 | PD-OPT-008 |
| Wykonaj | `sql.execute` | F8, ⌘↩ | ⌘↩, F8 | Brak | 0 | PD-SQLW-002 |
| Wykonaj (odwrotnie do AutoSelect) | `sql.executeAlternate` | ⌃F8, ⇧⌘↩ | ⇧⌘↩, ⌃F8 | Brak | 0 | PD-SQLW-003 |
| Przerwij | `sql.break` | ⇧⎋ †, ⌘. | ⌘. | Brak | 0 | PD-SQLW-005 |
| Wstrzymaj wykonanie | `cmd.pause` |  |  | Brak | 0 | PD-CMDW-003 |
| Wykonaj linię poleceń | `cmd.executeLine` |  |  | Brak | 0 | PD-CMDW-001 |
| Zatwierdź (COMMIT) | `session.commit` | F10 †, ⌥⌘↩ | ⌥⌘↩, F10 | Za zgodą | 0 | PD-SQLW-014 |
| Wycofaj (ROLLBACK) | `session.rollback` | ⇧F10 †, ⌥⌘⌫ | ⌥⌘⌫, ⇧F10 | Za zgodą | 0 | PD-SQLW-014 |
| Historia okna › Poprzednie polecenie okna | `sql.historyBack` | ⌥⌘↑ | ⌥⌘↑ | Pełny | 0 | PD-SQLW-007 |
| Historia okna › Następne polecenie okna | `sql.historyForward` | ⌥⌘↓ | ⌥⌘↓ | Pełny | 0 | PD-SQLW-007 |
| Podstawianie zmiennych | `sql.toggleSubstitution` |  |  | Brak | 0 | PD-VAR-005 |
| Wynik › Następna strona | `grid.nextPage` | ⌘⇟ | ⌘⇟ | Brak | 0 | PD-SQLW-004 |
| Wynik › Ostatnia strona (pobierz wszystkie) | `grid.lastPage` | ⇧⌘⇟ | ⇧⌘⇟ | Brak | 0 | PD-SQLW-004 |
| Wynik › Wykres… | `grid.graph` |  |  | Brak | 0 | PD-GRAPH-001 |
| Wynik › Edytuj dane | `grid.edit` | ⌥⌘E | ⌥⌘E | Brak | 0 | PD-GRID-017 |
| Wynik › Wstaw rekord | `grid.insertRecord` | ⌥⌘I | ⌥⌘I | Brak | 0 | PD-GRID-017 |
| Wynik › Usuń rekord | `grid.deleteRecord` | ⇧⌘⌫ | ⇧⌘⌫ | Brak | 0 | PD-GRID-017 |
| Wynik › Zatwierdź zmiany (Post) | `grid.post` | ⌥⌘S | ⌥⌘S | Za zgodą | 0 | PD-GRID-017 |
| Wynik › Anuluj zmiany | `grid.cancelChanges` |  |  | Brak | 0 | PD-GRID-017 |
| Wynik › Kopiuj SQL zmian | `grid.copyChangesSQL` |  |  | Odczyt | 0 | PD-GRID-020 |
| Wynik › Zapisz jako zapytanie standardowe… | `grid.saveAsStandardQuery` |  |  | Brak | 0 | PD-SQLW-013 |
| Wynik › Zapytania powiązane… | `grid.linkedQueries` |  |  | Brak | 0 | PD-SQLW-019 |
| Wynik › Porównaj rekordy | `grid.compareRecords` |  |  | Brak | 0 | PD-SQLW-020 |
| Wynik › Porównaj wyniki | `grid.compareResults` |  |  | Brak | 0 | PD-SQLW-021 |
| Wynik › Filtruj według wartości komórki | `grid.filterByValue` |  |  | Brak | 0 | DB-GRID-001 |
| Wynik › Filtr wyrażeniem… | `grid.filterExpression` |  |  | Brak | 0 | DB-GRID-001 |
| Wynik › Wyczyść filtr | `grid.clearFilter` |  |  | Brak | 0 | DB-GRID-001 |
| Wynik › Grupuj według kolumny | `grid.groupBy` |  |  | Brak | 0 | DB-GRID-001 |
| Wynik › Generuj SQL z wierszy… | `grid.generateSQL` |  |  | Brak | 0 | DB-GRID-002 |
| Wynik › Rekord z komentarzami kolumn | `grid.recordView` |  |  | Brak | 0 | PD-GRID-010 |
| Wynik › Otwórz kursor zagnieżdżony | `grid.openCursor` |  |  | Brak | 0 | PD-GRID-006 |
| Wynik › Filtr kolumn… | `grid.columnFilter` |  |  | Brak | 0 | PD-GRID-011 |
| Wynik › Pokaż wszystkie kolumny | `grid.clearColumnFilter` |  |  | Brak | 0 | PD-GRID-011 |
| Wynik › Wyrównaj kolumny | `grid.align` |  |  | Brak | 0 | PD-GRID-012 |
| Wynik › Zapisz wyrównanie dla zapytania | `grid.saveAlignTemplate` |  |  | Brak | 0 | PD-GRID-012 |
| Wynik › Usuń wyrównanie zapytania | `grid.removeAlignTemplate` |  |  | Brak | 0 | PD-GRID-012 |
| Wynik › Informacje o kolumnie | `grid.columnInfo` |  |  | Brak | 0 | PD-GRID-022 |
| Wynik › Lista wartości… | `grid.valueList` |  |  | Brak | 0 | PD-GRID-022 |
| Wynik › Sumy kolumny… | `grid.totals` |  |  | Brak | 0 | PD-GRID-024 |
| Wynik › Wyłącz sumy | `grid.clearTotals` |  |  | Brak | 0 | PD-GRID-024 |
| Wynik › Odśwież wynik | `sql.refreshResult` | ⇧⌘R | ⇧⌘R | Brak | 0 | PD-SQLW-006 |
| Wynik › Automatyczne odświeżanie… | `sql.autoRefresh` |  |  | Brak | 0 | PD-SQLW-006 |
| Wynik › Przypnij wynik | `sql.pinResult` |  |  | Brak | 0 | PD-SQLW-017 |
| Wynik › Przypnij wszystkie wyniki | `sql.pinAllResults` |  |  | Brak | 0 | PD-SQLW-017 |
| Wynik › Wyczyść karty wyników | `sql.clearResults` |  |  | Brak | 0 | PD-SQLW-017 |
| Wynik › Eksportuj zapytanie do pliku… | `sql.exportQuery` |  |  | Brak | 0 | PD-SQLW-018 |
| Wynik › Query By Example… | `grid.queryByExample` | ⇧⌘E | ⇧⌘E | Brak | 0 | PD-SQLW-022 |
| Wynik › Wyczyść Query By Example | `grid.clearQueryByExample` |  |  | Brak | 0 | PD-SQLW-022 |
| Wczytaj ponownie z bazy | `prog.reloadFromDatabase` |  |  | Brak | 0 | PD-PROG-011 |
| Kompilacja próbna | `prog.safeCompile` |  |  | Brak | 0 | PD-PROG-010 |
| Sprawdź zmiany obiektów w bazie | `prog.checkChanges` |  |  | Odczyt | 0 | PD-PROG-011 |
| Uruchom blok w oknie testu | `prog.runBlock` |  |  | Brak | 0 | PD-PROG-016 |
| Notatnik › Wykonaj wszystkie komórki | `notebook.runAll` |  |  | Brak | 0 | SD-NB-001 |
| Notatnik › Wykonaj komórkę | `notebook.runCell` |  |  | Brak | 0 | SD-NB-001 |
| Konsola połączenia | `session.console` |  |  | Brak | 0 | DG-CONS-001 |
| Wynik › Następna zmiana oczekująca | `grid.nextPendingChange` |  |  | Brak | 0 | DG-GRID-001 |
| Wynik › Poprzednia zmiana oczekująca | `grid.previousPendingChange` |  |  | Brak | 0 | DG-GRID-001 |
| Wynik › Cofnij zmiany wierszy | `grid.revertRowChanges` |  |  | Brak | 0 | DG-GRID-001 |
| Zaloguj… | `session.logon` | ⇧⌘L | ⇧⌘L | Brak | 0 | PD-CONN-002 |
| Wyloguj połączenie główne | `session.logoff` |  |  | Brak | 0 | PD-CONN-018 |
| Połączenia › Eksportuj definicje połączeń… | `connection.export` |  |  | Brak | 0 | PD-CONN-010 |
| Połączenia › Importuj definicje połączeń… | `connection.import` |  |  | Brak | 0 | PD-CONN-010 |
| Połączenia › Nowe połączenie… | `connection.new` |  |  | Brak | 0 | PD-CONN-004 |
| Połączenia › Edytuj połączenie… | `connection.edit` |  |  | Brak | 0 | PD-CONN-004 |
| Połączenia › Usuń połączenie | `connection.delete` |  |  | Brak | 0 | PD-CONN-004 |
| Połączenia › Połącz jako główne | `connection.connectAsMain` |  |  | Brak | 0 | PD-CONN-018 |
| Połączenia › Połącz | `connection.connect` |  |  | Brak | 0 | PD-CONN-022 |
| Połączenia › Nowe okno na połączeniu | `connection.openWindow` |  |  | Brak | 0 | PD-CONN-022 |
| Połączenia › Pokaż okna połączenia | `connection.showWindows` |  |  | Brak | 0 | PD-CONN-022 |
| Połączenia › Zamknij okna połączenia | `connection.closeWindows` |  |  | Brak | 0 | PD-CONN-022 |
| Połączenia › Połącz ponownie okna połączenia | `connection.reconnectWindows` |  |  | Brak | 0 | PD-CONN-022 |
| Połączenia › Ustaw bieżący schemat… | `connection.setCurrentSchema` |  |  | Brak | 0 | PD-CONN-022 |
| Połączenia › Rozłącz | `connection.disconnect` |  |  | Brak | 0 | PD-CONN-022 |
| Połączenie okna… | `session.windowConnection` |  |  | Brak | 0 | PD-CONN-019 |
| Połączenia › Nowy folder… | `connection.newFolder` |  |  | Brak | 0 | PD-CONN-003 |

## Debugowanie

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Zapisz jako test standardowy… | `test.saveAsStandard` |  |  | Brak | 0 | PD-TEST-009 |
| Ślad DBMS_TRACE przy wykonaniu | `test.trace` |  |  | Brak | 0 | PD-OPT-007 |
| Historia przebiegów DBMS_TRACE | `test.traceRuns` |  |  | Brak | 0 | PD-OPT-007 |
| Uprawnienia debugera… | `debug.grantPrivileges` |  |  | Brak | 0 | PD-DBG-013 |
| Profiler przy wykonaniu | `test.profiler` |  |  | Pełny | 0 | PD-OPT-005 |
| utPLSQL: debuguj test pod kursorem | `utplsql.debugTest` |  |  | Brak | 0 | UT-RUN-007 |
| Rozpocznij debugowanie | `debug.start` | F9 † | F9 | Brak | 0 | PD-DBG-001 |
| Kontynuuj | `debug.run` | ⌃R † | ⌃R | Brak | 0 | PD-DBG-001 |
| Wejdź | `debug.stepInto` | ⌃N † | ⌃N | Brak | 0 | PD-DBG-001 |
| Przejdź | `debug.stepOver` | ⌃O † | ⌃O | Brak | 0 | PD-DBG-001 |
| Wyjdź | `debug.stepOut` | ⌃T † | ⌃T | Brak | 0 | PD-DBG-001 |
| Wykonaj do wyjątku | `debug.runToException` |  |  | Brak | 0 | PD-DBG-001 |
| Wykonaj do kursora | `debug.runToCursor` |  |  | Brak | 0 | PD-DBG-001 |
| Zatrzymaj debugowanie | `debug.stop` | ⇧F9 † | ⇧F9 | Brak | 0 | PD-DBG-001 |
| Punkty przerwania… | `debug.breakpoints` |  |  | Brak | 0 | PD-DBG-008 |
| Punkt przerwania | `debug.toggleBreakpoint` | ⌃B † | ⌃B | Brak | 0 | PD-DBG-007 |

## Narzędzia

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Obiekt › Zapytanie standardowe | `ob.standardQuery` |  |  | Brak | 0 | PD-SQLW-013 |
| Obiekt › Generuj kod… | `ob.generateCode` |  |  | Brak | 0 | SD-GEN-001 |
| Autotrace | `tools.autotrace` |  |  | Brak | 0 | SD-PLAN-002 |
| Plan › Porównaj z poprzednim planem | `plan.compare` |  |  | Brak | 0 | SD-PLAN-003 |
| DBA › Zmień parametr instancji | `dba.alterParameter` |  |  | Brak | 0 | SD-DBA-001 |
| DBA › Zablokuj / odblokuj konto | `dba.lockUser` |  |  | Brak | 0 | SD-DBA-001 |
| Instance Viewer | `tools.instanceViewer` |  |  | Brak | 0 | SD-DBA-004 |
| Dokumentacja schematu… | `tools.schemaDoc` |  |  | Brak | 0 | SD-DOC-001 |
| Wydajność (pakiety Oracle) › Raport AWR | `tools.awrReport` |  |  | Brak | 0 | SD-DBA-002 |
| Wydajność (pakiety Oracle) › Raport ASH | `tools.ashReport` |  |  | Brak | 0 | SD-DBA-002 |
| Wydajność (pakiety Oracle) › Raport ADDM | `tools.addmReport` |  |  | Brak | 0 | SD-DBA-002 |
| Wydajność (pakiety Oracle) › Raport SQL Monitor | `tools.sqlMonitorReport` |  |  | Brak | 0 | SD-MON-001 |
| Wydajność (pakiety Oracle) › SQL Monitor | `tools.sqlMonitor` |  |  | Brak | 0 | SD-MON-001 |
| Wydajność (pakiety Oracle) › SQL Tuning Advisor | `tools.sqlTuningAdvisor` |  |  | Brak | 0 | SD-DBA-003 |
| Obiekt › Zmień nazwę… | `ob.rename` |  |  | Za zgodą | 0 | PD-OB-016 |
| Obiekt › Zmień nazwę elementu… | `ob.renameChild` |  |  | Za zgodą | 0 | PD-OB-016 |
| Obiekt › Duplikuj… | `ob.duplicate` |  |  | Za zgodą | 0 | PD-OB-016 |
| Obiekt › Wstaw obiekt do edytora | `ob.dropText` |  |  | Brak | 0 | PD-OB-010 |
| Obiekt › Upuść obiekt na obszar okien | `ob.dropOnWorkspace` |  |  | Brak | 0 | PD-OB-010 |
| Object Browser › Filtr nazwany… | `ob.applyFilter` |  |  | Brak | 0 | PD-OB-007 |
| Obiekt › Dodaj do folderu… | `ob.addToFolder` |  |  | Brak | 0 | PD-OB-008 |
| Obiekt › Włącz | `ob.enable` |  |  | Brak | 0 | PD-OB-019 |
| Obiekt › Wyłącz | `ob.disable` |  |  | Brak | 0 | PD-OB-019 |
| Obiekt › Odśwież widok zmaterializowany | `ob.refreshMV` |  |  | Brak | 0 | PD-OB-019 |
| Obiekt › Testuj łącze | `ob.testLink` |  |  | Odczyt | 0 | PD-OB-019 |
| Obiekt › Uruchom zadanie | `ob.runJob` |  |  | Brak | 0 | PD-OB-019 |
| Obiekt › Uruchom kolejkę | `ob.startQueue` |  |  | Brak | 0 | PD-OB-019 |
| Obiekt › Zatrzymaj kolejkę | `ob.stopQueue` |  |  | Brak | 0 | PD-OB-019 |
| Kosz | `ob.recycleBin` |  |  | Odczyt | 0 | PD-OB-021 |
| Kosz › Przywróć z kosza… | `ob.restoreFromRecycleBin` |  |  | Brak | 0 | PD-OB-021 |
| Kosz › Opróżnij kosz… | `ob.purgeRecycleBin` |  |  | Brak | 0 | PD-OB-021 |
| Obiekt › Flagi kompilacji warunkowej… | `ob.ccflags` |  |  | Odczyt | 0 | PD-OB-020 |
| Obiekt › Dodaj źródło do edytora | `ob.addSourceToEditor` |  |  | Brak | 0 | PD-OB-023 |
| Preferencje › Eksportuj preferencje… | `prefs.export` |  |  | Brak | 0 | PD-PREF-003 |
| Preferencje › Importuj preferencje… | `prefs.import` |  |  | Brak | 0 | PD-PREF-003 |
| Preferencje › Zestawy preferencji… | `prefs.sets` |  |  | Brak | 0 | PD-PREF-002 |
| Dokumenty… | `tools.documents` |  |  | Brak | 0 | PD-DOC-002 |
| Zdalny build Pro*C › Cele SSH… | `ssh.manager` |  |  | Brak | 0 | PC-CONN-002 |
| Zdalny build Pro*C › Testuj cel SSH | `ssh.test` |  |  | Brak | 0 | PC-CONN-003 |
| Zdalny build Pro*C › Eksportuj cele SSH… | `ssh.export` |  |  | Brak | 0 | PC-CONN-001 |
| Zdalny build Pro*C › Wdróż na cel… | `proc.deploy` |  |  | Brak | 0 | PC-DEPLOY-001 |
| Zdalny build Pro*C › Wycofaj binarkę… | `proc.rollback` |  |  | Brak | 0 | PC-DEPLOY-003 |
| Zdalny build Pro*C › Historia wdrożeń | `proc.history` |  |  | Brak | 0 | PC-DEPLOY-004 |
| Zdalny build Pro*C › Konsola wdrożenia | `proc.console` |  |  | Brak | 0 | PC-CONS-001 |
| Zdalny build Pro*C › Zatrzymaj wdrożenie | `proc.stop` |  |  | Brak | 0 | PC-CONS-002 |
| Zdalny build Pro*C › Zdejmij blokadę celu… | `proc.releaseLock` |  |  | Brak | 0 | PC-DEPLOY-002 |
| Zdalny build Pro*C › Stan git i wdrożeń | `proc.gitStatus` |  |  | Brak | 0 | PC-GIT-001 |
| Zdalny build Pro*C › Importuj cele SSH… | `ssh.import` |  |  | Brak | 0 | PC-CONN-001 |
| Database Diff… | `tools.databaseDiff` |  |  | Brak | 0 | SD-DIFF-001 |
| Koszyk wdrożenia… | `tools.cart` |  |  | Brak | 0 | SD-DIFF-001 |
| Koszyk › Dodaj obiekt do koszyka | `cart.add` |  |  | Brak | 0 | SD-DIFF-001 |
| Koszyk › Skrypt wdrożenia koszyka | `cart.script` |  |  | Brak | 0 | SD-DIFF-001 |
| Kopiowanie schematu… | `tools.schemaCopy` |  |  | Brak | 0 | SD-COPY-001 |
| Kreator importu danych… | `tools.importWizard` |  |  | Brak | 0 | SD-IMP-001 |
| Diagram › Diagram ER ze schematu… | `diagram.fromSchema` |  |  | Brak | 0 | DB-DIAG-001 |
| Przenoszenie danych… | `tools.dataTransfer` |  |  | Brak | 0 | DB-XFER-001 |
| Wykonaj zapisane przeniesienie danych | `transfer.run` |  |  | Brak | 0 | DB-XFER-001 |
| Zadania lokalne… | `tools.localTasks` |  |  | Brak | 0 | DB-TASK-001 |
| Uruchom zadanie lokalne | `localTasks.runNow` |  |  | Brak | 0 | DB-TASK-001 |
| Widoki dualności JSON | `tools.dualityViews` |  |  | Brak | 0 | SD-DV-001 |
| Nowy widok dualności… | `tools.dualityViewDDL` |  |  | Brak | 0 | SD-DV-001 |
| Moduły i środowiska MLE | `tools.mleModules` |  |  | Brak | 0 | SD-MLE-001 |
| Importuj moduł JavaScript… | `tools.importMLEModule` |  |  | Brak | 0 | SD-MLE-001 |
| Debuguj moduł MLE po wykonaniu… | `tools.debugMLE` |  |  | Brak | 0 | SD-MLE-001 |
| REST (ORDS) › Moduły REST (ORDS) | `tools.ordsModules` |  |  | Brak | 0 | SD-ORDS-001 |
| REST (ORDS) › Włącz REST dla schematu… | `tools.ordsEnableSchema` |  |  | Brak | 0 | SD-ORDS-001 |
| REST (ORDS) › Włącz REST dla obiektu… | `tools.ordsEnableObject` |  |  | Brak | 0 | SD-ORDS-001 |
| Test Manager | `tools.testManager` |  |  | Brak | 0 | PD-TOOL-018 |
| Test Manager › Uruchom zestaw testów | `testManager.run` |  |  | Brak | 0 | PD-TOOL-018 |
| Monitor zdarzeń… | `tools.eventMonitor` |  |  | Brak | 0 | PD-TOOL-014 |
| Test obciążenia… | `tools.loadTester` |  |  | Brak | 0 | PD-TOOL-019 |
| Obiekt › Pokaż dane | `ob.queryData` |  |  | Brak | 0 | PD-OB-017 |
| Obiekt › Edytuj dane | `ob.editData` |  |  | Brak | 0 | PD-OB-017 |
| Obiekt › DDL | `ob.ddl` |  |  | Odczyt | 0 | PD-OB-015 |
| Obiekt › Opis | `ob.describe` |  |  | Odczyt | 0 | PD-OB-013 |
| Obiekt › Właściwości | `ob.properties` |  |  | Odczyt | 0 | PD-OB-012 |
| Obiekt › Edytuj | `ob.edit` |  |  | Brak | 0 | PD-OB-014 |
| Obiekt › Rekompiluj | `ob.recompile` |  |  | Za zgodą | 0 | PD-OB-009 |
| Obiekt › Dodaj informację debugowania | `ob.addDebugInfo` |  |  | Za zgodą | 0 | PD-DBG-011 |
| Obiekt › Usuń obiekt… | `ob.drop` |  |  | Za zgodą | 0 | PD-OB-016 |
| Obiekt › Kopiuj nazwę | `ob.copyName` |  |  | Brak | 0 | PD-OB-011 |
| Obiekt › Odśwież Object Browser | `ob.refresh` |  |  | Pełny | 0 | PD-OB-004 |
| Zapisz kryteria wyszukiwania | `tools.saveObjectSearch` |  |  | Brak | 0 | PD-TOOL-001 |
| Usuń zapisane kryteria wyszukiwania | `tools.deleteObjectSearch` |  |  | Brak | 0 | PD-TOOL-001 |
| Znajdź obiekty bazy… | `tools.findObjects` | ⌃⇧O †, ⇧⌘O | ⇧⌘O | Odczyt | 0 | PD-TOOL-001 |
| Kompiluj niepoprawne obiekty… | `tools.compileInvalid` |  |  | Za zgodą | 0 | PD-TOOL-002 |
| Szablony › Zapisz zaznaczenie jako szablon… | `templates.save` |  |  | Pełny | 0 | PD-TPL-003 |
| Szablony › Usuń szablon | `templates.delete` |  |  | Za zgodą | 0 | PD-TPL-003 |
| Obiekt › Porównaj z aktywnym oknem | `ob.compare` |  |  | Odczyt | 0 | PD-OB-022 |
| Obiekt › Porównaj z obiektem w innej bazie… | `ob.compareWithConnection` |  |  | Odczyt | 0 | PD-OB-022 |
| Porównaj pliki… | `tools.compareFiles` |  |  | Brak | 0 | PD-DIFF-001 |
| Porównaj teksty | `tools.compareTexts` |  |  | Odczyt | 0 | PD-DIFF-001 |
| Obiekt › Testuj | `ob.test` |  |  | Pełny | 0 | PD-TEST-004 |
| Obiekt › Test standardowy… | `ob.standardTest` |  |  | Odczyt | 0 | PD-TEST-009 |
| Obiekt › Edytuj definicję tabeli | `ob.editTable` |  |  | Odczyt | 0 | PD-OED-002 |
| utPLSQL › utPLSQL: uruchom wszystkie testy | `utplsql.runAll` | ⌃⇧U †, ⇧⌘U | ⇧⌘U | Za zgodą | 0 | UT-RUN-001 |
| utPLSQL › utPLSQL: uruchom testy ze ścieżki… | `utplsql.runPath` |  |  | Za zgodą | 0 | UT-RUN-002 |
| utPLSQL › utPLSQL: uruchom z opcjami… | `utplsql.runWithOptions` |  |  | Za zgodą | 0 | UT-RUN-003 |
| utPLSQL › utPLSQL: testy z pokryciem kodu | `utplsql.coverage` |  |  | Za zgodą | 0 | UT-COV-001 |
| utPLSQL › utPLSQL: uruchom test pod kursorem | `utplsql.runEditor` | ⌃⌥U †, ⌃⌘U | ⌃⌘U | Za zgodą | 0 | UT-RUN-004 |
| utPLSQL › utPLSQL: uruchom ponownie nieudane | `utplsql.rerunFailed` |  |  | Za zgodą | 0 | UT-RUN-006 |
| utPLSQL › utPLSQL: przerwij | `utplsql.cancel` |  |  | Pełny | 0 | UT-RUN-006 |
| utPLSQL › utPLSQL: wersja w bazie | `utplsql.version` |  |  | Odczyt | 0 | UT-INS-001 |
| utPLSQL › utPLSQL: instaluj lub aktualizuj… | `utplsql.install` |  |  | Za zgodą | 0 | UT-INS-002 |
| utPLSQL › utPLSQL: generuj pakiet testowy | `utplsql.generateTest` |  |  | Pełny | 0 | UT-GEN-001 |
| utPLSQL › utPLSQL: przejdź do testu / testowanego pakietu | `utplsql.toggleTest` | ⌃⇧T †, ⌃⌘T | ⌃⌘T | Pełny | 0 | UT-NAV-001 |
| utPLSQL › utPLSQL: eksport wyników… | `utplsql.export` |  |  | Za zgodą | 0 | UT-CI-001 |
| utPLSQL › utPLSQL: skrypt dla wiersza poleceń | `utplsql.cliScript` |  |  | Pełny | 0 | UT-CI-001 |
| Obiekt › Uruchom testy utPLSQL | `ob.utplsqlRun` |  |  | Za zgodą | 0 | UT-RUN-003 |
| Git › Stan Git pliku | `vcs.status` |  |  | Brak | 0 | PD-VCS-001 |
| Git › Porównaj z HEAD | `vcs.diff` |  |  | Brak | 0 | PD-VCS-001 |
| Git › Dodaj do zatwierdzenia (git add) | `vcs.add` |  |  | Brak | 0 | PD-VCS-001 |
| Git › Zatwierdź (git commit)… | `vcs.commit` |  |  | Brak | 0 | PD-VCS-001 |
| Git › Historia Git pliku | `vcs.log` |  |  | Brak | 0 | PD-VCS-001 |
| Explain Plan | `tools.explainPlan` | F5 | F5 | Brak | 0 | PD-OPT-002 |
| Plan › Zapisz plan jako… | `plan.export` |  |  | Brak | 0 | PD-OPT-003 |
| Sesje | `tools.sessions` |  |  | Brak | 0 | PD-TOOL-015 |
| Eksport obiektów użytkownika… | `tools.exportUserObjects` |  |  | Brak | 0 | PD-TOOL-007 |
| Porównaj obiekty użytkowników… | `tools.compareUserObjects` |  |  | Brak | 0 | PD-TOOL-012 |
| Sesje › Zabij sesję | `sessions.kill` |  |  | Brak | 0 | PD-TOOL-015 |
| DBMS Scheduler | `tools.scheduler` |  |  | Brak | 0 | PD-SCHED-001 |
| Diagram › Dodaj do diagramu | `diagram.addObject` |  |  | Brak | 0 | PD-DIAG-001 |
| Diagram › Dodaj powiązane tabele | `diagram.addRelated` |  |  | Brak | 0 | PD-DIAG-001 |
| Diagram › Dodaj zależności | `diagram.addReferences` |  |  | Brak | 0 | PD-DIAG-001 |
| Diagram › Pokaż lub ukryj kolumny | `diagram.showColumns` |  |  | Brak | 0 | PD-DIAG-001 |
| Diagram › Dodaj notatkę | `diagram.addNote` |  |  | Brak | 0 | PD-DIAG-002 |
| Diagram › Grupuj zaznaczone | `diagram.addGroup` |  |  | Brak | 0 | PD-DIAG-002 |
| Diagram › Usuń z diagramu | `diagram.delete` |  |  | Brak | 0 | PD-DIAG-002 |
| Diagram › Powiększenie diagramu | `diagram.zoom` |  |  | Brak | 0 | PD-DIAG-002 |
| Diagram › Siatka diagramu | `diagram.toggleGrid` |  |  | Brak | 0 | PD-DIAG-002 |
| Diagram › Aktualizuj z bazy | `diagram.updateFromDB` |  |  | Brak | 0 | PD-DIAG-003 |
| Diagram › Eksportuj diagram jako obraz… | `diagram.export` |  |  | Brak | 0 | PD-DIAG-003 |
| Diagram › Kopiuj diagram jako obraz | `diagram.copyImage` |  |  | Brak | 0 | PD-DIAG-003 |
| Diagram › Drukuj diagram… | `diagram.print` |  |  | Brak | 0 | PD-DIAG-003 |
| Query Builder… | `tools.queryBuilder` |  |  | Brak | 0 | PD-QB-001 |
| Eksport tabel… | `tools.exportTables` |  |  | Brak | 0 | PD-TOOL-003 |
| Import tabel… | `tools.importTables` |  |  | Brak | 0 | PD-TOOL-006 |
| Import tekstu… | `tools.textImporter` |  |  | Brak | 0 | PD-TOOL-008 |
| Import z Excela… | `tools.excelImporter` |  |  | Brak | 0 | PD-TOOL-009 |
| Generator danych… | `tools.dataGenerator` |  |  | Brak | 0 | PD-TOOL-011 |
| Porównaj dane tabel… | `tools.compareTableData` |  |  | Brak | 0 | PD-TOOL-013 |
| Narzędzia użytkownika… | `tools.configureTools` |  |  | Brak | 0 | PD-TOOL-017 |

## Raporty

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Raporty predefiniowane… | `reports.predefined` |  |  | Brak | 0 | SD-REP-001 |
| Wykonaj raport predefiniowany | `reports.predefined.run` |  |  | Brak | 0 | SD-REP-001 |
| Otwórz raport w oknie SQL | `reports.predefined.worksheet` |  |  | Brak | 0 | SD-REP-001 |
| Błędy kompilacji | `reports.compilationErrors` |  |  | Brak | 0 | PD-REP-001 |
| Niepoprawne obiekty | `reports.invalidObjects` |  |  | Brak | 0 | PD-REP-001 |
| Ostatnio zmienione obiekty | `reports.recentChanges` |  |  | Brak | 0 | PD-REP-001 |
| Rozmiary tabel | `reports.tableSizes` |  |  | Brak | 0 | PD-REP-001 |
| Kolumny tabel | `reports.tableColumns` |  |  | Brak | 0 | PD-REP-001 |
| Uprawnienia użytkownika | `reports.privileges` |  |  | Brak | 0 | PD-REP-001 |
| Sesje | `reports.sessions` |  |  | Brak | 0 | PD-REP-001 |
| Raport › Wykonaj raport | `report.execute` |  |  | Brak | 0 | PD-REP-002 |
| Raport › Zapisz raport jako HTML… | `report.saveHTML` |  |  | Brak | 0 | PD-REP-001 |
| Raport › Eksportuj dane raportu… | `report.export` |  |  | Brak | 0 | PD-REP-001 |
| Raport › Drukuj raport… | `report.print` |  |  | Brak | 0 | PD-REP-001 |
| Raport › Zablokuj definicję raportu | `report.lock` |  |  | Brak | 0 | PD-REP-004 |
| Raport › Odblokuj definicję raportu | `report.unlock` |  |  | Brak | 0 | PD-REP-004 |
| Raport › Dodaj raport do menu Raporty | `report.addToMenu` |  |  | Brak | 0 | PD-REP-004 |

## Widok

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Panel wartości | `grid.valuePanel` | ⌥⌘V | ⌥⌘V | Brak | 0 | DB-PANEL-001 |
| Snippety | `view.snippets` |  |  | Brak | 0 | SC-SNIP-001 |
| Panel DBA | `view.dba` |  |  | Brak | 0 | SD-DBA-001 |
| Zadania w tle | `view.taskMonitor` |  |  | Brak | 0 | SD-MON-002 |
| Siatka › Układ liczb w siatce | `grid.numberLayout` |  |  | Brak | 0 | PD-GRID-004 |
| Siatka › Auto Format w Large Data Editor | `grid.largeDataAutoFormat` |  |  | Brak | 0 | PD-LDE-001 |
| Siatka › Większa czcionka siatki | `grid.fontLarger` |  |  | Brak | 0 | PD-GRID-025 |
| Siatka › Mniejsza czcionka siatki | `grid.fontSmaller` |  |  | Brak | 0 | PD-GRID-025 |
| Siatka › Domyślna czcionka siatki | `grid.fontReset` |  |  | Brak | 0 | PD-GRID-025 |
| Siatka › Numer wiersza w kopiowaniu i eksporcie | `grid.toggleRowNumbers` |  |  | Brak | 0 | PD-GRID-027 |
| Podziel edytor | `view.splitEditor` |  |  | Brak | 0 | PD-EDIT-014 |
| Powiększ czcionkę edytora | `view.zoomIn` | ⌃= †, ⌘= | ⌘= | Brak | 0 | PD-EDIT-021 |
| Pomniejsz czcionkę edytora | `view.zoomOut` | ⌃⇧- †, ⌘- | ⌘- | Brak | 0 | PD-EDIT-021 |
| Domyślny rozmiar czcionki edytora | `view.zoomReset` | ⌃0 †, ⌘0 | ⌘0 | Brak | 0 | PD-EDIT-021 |
| Dostosuj pasek narzędzi… | `view.customizeToolbar` |  |  | Brak | 0 | PD-UI-006 |
| Dodaj do paska szybkiego dostępu | `view.addToQuickAccess` |  |  | Brak | 0 | PD-UI-006 |
| Usuń z paska szybkiego dostępu | `view.removeFromQuickAccess` |  |  | Brak | 0 | PD-UI-006 |
| Podgląd przestrzenny | `grid.spatialPreview` |  |  | Brak | 0 | SD-DATA-001 |
| Zawijaj wiersze | `view.wordWrap` |  |  | Brak | 0 | PD-EDIT-004 |
| Okno szablonów | `view.templateWindow` |  |  | Brak | 0 | PD-TPL-001 |
| Znaki specjalne | `view.specialCharacters` |  |  | Brak | 0 | PD-EDIT-003 |
| Status linii | `view.lineStatus` |  |  | Brak | 0 | PD-EDIT-003 |
| Eksplorator testów utPLSQL | `utplsql.explorer` |  |  | Odczyt | 0 | UT-EXP-001 |
| Historia schowka | `view.clipboardHistory` |  |  | Brak | 0 | PD-EDIT-024 |
| Zadania To-Do | `view.todoItems` |  |  | Odczyt | 0 | PD-TODO-001 |
| Przeglądarka plików | `view.fileBrowser` |  |  | Brak | 0 | PD-FB-001 |
| Zapisz układ okna | `view.saveLayout` |  |  | Brak | 0 | PD-WSET-002 |
| Przywróć układ okna | `view.restoreLayout` |  |  | Brak | 0 | PD-WSET-002 |
| Autozapis układu okna | `view.autosaveLayout` |  |  | Brak | 0 | PD-WSET-002 |
| Paleta komend… | `view.commandPalette` | ⇧⌘P | ⇧⌘P | Brak | 0 | PD-UI-007 |
| Zawartość kodu | `view.codeContents` |  |  | Brak | 0 | PD-CA-010 |
| Przeglądarka obiektów | `view.objectBrowser` |  |  | Brak | 2 | PD-OB-001 |

## Okno

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Wykonaj okno | `window.execute` |  |  | Brak | 0 | PD-UI-002 |
| Połącz ponownie okno | `window.reconnect` |  |  | Brak | 0 | PD-UI-002 |
| Zmień nazwę okna… | `window.rename` |  |  | Brak | 0 | PD-UI-002 |
| Krótkie nazwy na liście okien | `window.listShortTitles` |  |  | Brak | 0 | PD-UI-002 |
| Sortuj listę okien… | `window.listSort` |  |  | Brak | 0 | PD-UI-002 |
| Następne okno | `window.next` | ⌃⇥, ⇧⌘] | ⇧⌘], ⌃⇥ | Pełny | 0 | PD-UI-004 |
| Poprzednie okno | `window.previous` | ⌃⇧⇥, ⇧⌘[ | ⇧⌘[, ⌃⇧⇥ | Pełny | 0 | PD-UI-004 |

## Pomoc

| Komenda | Identyfikator | PL/SQL Developer | macOS | Agent | Etap | Funkcja |
|---|---|---|---|---|---|---|
| Połączenia (agent) | `agent.connections` |  |  | Odczyt | 0 | AI-TOOL-001 |
| Stan okien (agent) | `agent.state` |  |  | Odczyt | 0 | AI-TOOL-001 |
| Treść edytora (agent) | `agent.editor` |  |  | Odczyt | 0 | AI-TOOL-001 |
| Nowe okno z tekstem (agent) | `agent.openEditor` |  |  | Pełny | 0 | AI-TOOL-002 |
| Wstaw tekst (agent) | `agent.insertText` |  |  | Pełny | 0 | AI-TOOL-002 |
| Zamień zakres linii (agent) | `agent.replaceRange` |  |  | Pełny | 0 | AI-TOOL-002 |
| Przejdź do linii (agent) | `agent.navigate` |  |  | Pełny | 0 | AI-TOOL-002 |
| Formatuj kod (agent) | `agent.format` |  |  | Pełny | 0 | AI-TOOL-002 |
| Szukaj obiektów (agent) | `agent.searchObjects` |  |  | Odczyt | 0 | AI-TOOL-001 |
| Opis obiektu (agent) | `agent.describe` |  |  | Odczyt | 0 | AI-TOOL-001 |
| Źródło programu (agent) | `agent.source` |  |  | Odczyt | 0 | AI-TOOL-001 |
| DDL obiektu (agent) | `agent.ddl` |  |  | Odczyt | 0 | AI-TOOL-001 |
| Zależności obiektu (agent) | `agent.dependencies` |  |  | Odczyt | 0 | AI-TOOL-001 |
| Użycia obiektu (agent) | `agent.findUsages` |  |  | Odczyt | 0 | AI-TOOL-001 |
| Zapytanie (agent) | `agent.query` |  |  | Odczyt | 0 | AI-SEC-006 |
| Plan wykonania (agent) | `agent.explain` |  |  | Odczyt | 0 | AI-TOOL-001 |
| Błędy kompilacji (agent) | `agent.compileErrors` |  |  | Odczyt | 0 | AI-TOOL-001 |
| DBMS_OUTPUT sesji agenta | `agent.dbmsOutput` |  |  | Odczyt | 0 | AI-TOOL-001 |
| Testy utPLSQL (agent) | `agent.listTests` |  |  | Odczyt | 0 | AI-TOOL-001 |
| Wyniki testów (agent) | `agent.testResults` |  |  | Odczyt | 0 | AI-TOOL-001 |
| Pokrycie kodu (agent) | `agent.coverage` |  |  | Odczyt | 0 | AI-TOOL-001 |
| Sesje bazy (agent) | `agent.sessions` |  |  | Odczyt | 0 | AI-TOOL-001 |
| Otwórz obiekt (agent) | `agent.openObject` |  |  | Pełny | 0 | AI-TOOL-002 |
| Wykonaj polecenie (agent) | `agent.execute` |  |  | Za zgodą | 0 | AI-TOOL-003 |
| Wykonaj skrypt (agent) | `agent.executeScript` |  |  | Za zgodą | 0 | AI-TOOL-003 |
| Utwórz pakiet testowy (agent) | `agent.createTestPackage` |  |  | Za zgodą | 0 | AI-TOOL-003 |
| Kompiluj (agent) | `agent.compile` |  |  | Za zgodą | 0 | AI-TOOL-003 |
| COMMIT zmian agenta | `agent.commit` |  |  | Za zgodą | 0 | AI-SEC-007 |
| ROLLBACK zmian agenta | `agent.rollback` |  |  | Za zgodą | 0 | AI-SEC-007 |
| Uruchom testy utPLSQL (agent) | `agent.runTests` |  |  | Za zgodą | 0 | AI-TOOL-003 |
| Generuj i kompiluj szkielet testu (agent) | `agent.generateTest` |  |  | Za zgodą | 0 | AI-TOOL-003 |
| Instaluj utPLSQL (agent) | `agent.installUtplsql` |  |  | Za zgodą | 0 | AI-TOOL-003 |
| Pomoc kontekstowa (dokumentacja Oracle) | `help.context` | F1 | F1 | Brak | 0 | PD-EDIT-026 |
| Instrukcja Pelikana | `help.manual` | ⇧⌘/ | ⇧⌘/ | Brak | 0 | PL-INFRA-010 |
| Dokumentacja Oracle… | `help.oracleManuals` |  |  | Brak | 0 | PD-DOC-001 |

