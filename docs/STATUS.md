# Stan Pelikana — Etap 8 (2026-10-24)

Macierz funkcji (`docs/FEATURES.md`): **434** wierszy — 325 ✅ z testem, 18 👁 sprawdzone zrzutem lub do zrzutu, 85 ⚠️ częściowo, 6 pominiętych decyzją. Żaden wiersz nie ma stanu „do zrobienia”.

## Jak sprawdzić

- `make test-unit` — testy bez bazy (pakiet, agent, SSH na lokalnym `sshd`, Pro*C); `make testdb && make test` — z bazą testową w kontenerze (Oracle Free 26ai + utPLSQL).
- `scripts/screenshots.sh` — zrzuty okien w tle (D113), `python3 scripts/l10n.py check --strict` — komplet tłumaczeń en/de/es/uk.
- CI: macOS (budowanie, testy jednostkowe, testy SSH, aplikacja) i Linux (warstwa bazy na Oracle Free z utPLSQL).

## Do potwierdzenia przez właściciela

Te funkcje są zaimplementowane, ale nie dało się ich sprawdzić w środowisku testowym:

- **Pro*C na AIX 6.1 / ksh88** — pipeline wdrożenia, skrypty, Stop i parsery `proc`/`xlc` przetestowane na lokalnym `sshd` z ksh93 (D54); próbki komunikatów z prawdziwego serwera warto podmienić w fixture'ach.
- **Microsoft Entra ID** (SD-AUTH-001) — wymaga konta Azure (D82).
- **ORDS** (SD-ORDS-001) — baza testowa nie ma ORDS (D82).
- **Kerberos, LDAP, Workspace Manager** (PD-CONN-013/014/009) — bez KDC, serwera LDAP i DBMS_WM w bazie testowej (D97).
- **Quick Look** (MAC-QL-001) — rozszerzenie zbudowane; przy podpisie własnym macOS może go nie załadować (D95).
- **Asercje 26ai** (PD-OED-011) — czekają na wersję bazy testowej, która je ma (D104).
- **Szkice wydań** na GitHubie — publikuje właściciel (`gh release edit vX.Y.Z --draft=false`).

## Ograniczenia (wiersze częściowe)

| ID | Funkcja | Stan |
|---|---|---|
| PD-CONN-005 | Kolor połączenia i wskaźnik (pasek, okno, Window List, tło); reguły Connection Indicators user@db | ⚠️ częściowo (kolor i środowisko na liście; bez tła okna i reguł) |
| PD-CONN-009 | Edition (EBR) i Workspace (DBMS_WM) połączenia | ⚠️ test (Edition z definicji połączenia — test na bazie, CURRENT_EDITION_NAME; Workspace Manager przez DBMS_WM.GotoWorkspace po połączeniu — bez próby, baza testowa nie ma DBMS_WM, D97) |
| PD-CONN-013 | LDAP (directory naming) | ⚠️ częściowo (ldap.ora użytkownika dowiązany do katalogu Oracle Net Pelikana, NAMES.DIRECTORY_PATH z jego sqlnet.ora; bez próby z serwerem LDAP, D97) |
| PD-CONN-014 | Uwierzytelnianie zewnętrzne / Kerberos | ⚠️ test (uwierzytelnianie zewnętrzne — test przez magazyn haseł Oracle Wallet; Kerberos tym samym trybem, bez KDC w testach, D97) |
| PD-GRID-004 | Liczby z pełną precyzją Oracle; układ liczb (lewo/prawo/formatowane/z separatorem tysięcy) | ⚠️ częściowo (pełna precyzja; bez wyboru układu liczb) |
| PD-GRID-005 | Daty i znaczniki czasu wg formatu (NLS / własny), kalendarz przy edycji DATE | ⚠️ częściowo (formaty z preferencji; bez kalendarza) |
| PD-GRID-007 | Zaznaczanie wierszy, kolumn i bloków komórek; Select All; przenoszenie kolumn | ⚠️ częściowo (wiersze, przenoszenie kolumn; bez bloków komórek) |
| PD-GRID-010 | Single Record View (kolumna, wartość, typ, komentarz; poprzedni/następny rekord) | ⚠️ częściowo (bez komentarzy kolumn) |
| PD-GRID-012 | Align (szerokość wg nagłówka/treści, wysokość, szablony wyrównania z kolejnością, auto-align), Hide Editor, Adjust Window width | ⚠️ częściowo (szerokości wg nagłówka/treści/obu, szablon kolejności i szerokości per zapytanie stosowany automatycznie ✅ test; wysokość wierszy, Hide Editor, Adjust Window width — nie, D109) |
| PD-CMDW-004 | Polecenia SQL*Plus: /, ?, @, @@, ACCEPT, CLEAR, COLUMN (FORMAT, NEW_VALUE), CONNECT, DEFINE, DESCRIBE, DISCONNECT, EDIT, EXECUTE, EXIT/QUIT, GET, HELP, PAUSE, PRINT, PROMPT, RUN, REMARK, START, STORE SET, UNDEFINE, VARIABLE, WHENEVER | ⚠️ częściowo (bez GET/STORE/CHANGE/INPUT/COPY/BREAK/COMPUTE) |
| PD-PROG-001 | Program Window: wiele jednostek w pliku jako karty (specyfikacja/ciało), dodaj/usuń jednostkę | ⚠️ częściowo (karty jednostek jako nawigacja; bez dodaj/usuń jednostkę) |
| PD-PROG-002 | Nowy program z szablonu (funkcja, procedura, pakiet, typ, wyzwalacz, Java, MLE) z formularzem zmiennych | ⚠️ częściowo (z panelu Szablony: procedura, funkcja, pakiet, typ, wyzwalacz; bez Java i MLE) ✅ test |
| PD-PROG-008 | Porównanie: z plikiem, ze źródłem w bazie, z innym plikiem, z obiektem w innej bazie | ⚠️ częściowo (z plikiem, ze źródłem w bazie; z obiektem w innej bazie — Etap 6) ✅ test 👁 |
| PD-PROG-009 | Edycja źródła prosto z bazy (Edit), pytanie o zapis do pliku, Revert | ⚠️ częściowo (edycja z bazy; bez Revert) |
| PD-PROG-013 | Preferencje kompilatora: PLSQL_OPTIMIZE_LEVEL, CODE_TYPE, PL/Scope, flagi kompilacji warunkowej, PLSQL_WARNINGS, wartości `&` | ⚠️ częściowo (PLSQL_WARNINGS; bez pozostałych parametrów) |
| PD-PROG-014 | Moduły MLE (JavaScript) w Program Window: edycja, podświetlanie, kompilacja | ⚠️ test (moduł MLE w Program Window: źródło z nagłówkiem CREATE MLE MODULE i wersją, jednostka rozpoznawana, kompilacja i błędy JavaScript; podświetlanie składni JavaScript — nie, edytor używa leksera PL/SQL) |
| PD-PROG-015 | Podświetlanie poleceń transakcyjnych (COMMIT/ROLLBACK/SAVEPOINT) i par if/loop/case/blok | ⚠️ częściowo (pary if/loop/case/blok; bez wyróżniania COMMIT/ROLLBACK/SAVEPOINT) ✅ test |
| PD-EDIT-003 | Numery linii (interwał), status linii (zmieniona/nowa), podświetlenie bieżącej linii, margines pionowy, znaki specjalne | ⚠️ częściowo (numery i bieżąca linia; bez statusu zmienionych linii) |
| PD-EDIT-004 | Wcięcia None/Automatic/Smart, Backspace/Delete unindents, tabulacje, zawijanie, kursor za końcem linii | ⚠️ częściowo (auto-wcięcie, Tab/Shift+Tab; bez trybu Smart i zawijania) |
| PD-EDIT-013 | Zwijanie kodu (+/−, Fold All, podgląd zwiniętego), klawisze zwijania | ⚠️ częściowo (bloki, IF, LOOP, CASE; ▸/▾ w marginesie, ⌥⌘←/→, Zwiń/Rozwiń wszystko; bez podglądu zwiniętego) ✅ test 👁 |
| PD-EDIT-018 | Podświetlanie nawiasów, zmiennych, pasujących słów przy zaznaczeniu, kolumn INSERT ↔ VALUES, tabela.kolumna | ⚠️ częściowo (pary nawiasów i BEGIN/IF/LOOP/CASE ↔ END przy kursorze; bez zmiennych, pasujących słów, INSERT ↔ VALUES) ✅ test |
| PD-EDIT-020 | Duplicate line, Delete next word, First Character on Line | ⚠️ częściowo (Duplicate line; bez Delete next word) |
| PD-EDIT-025 | Menu obiektu bazy na nazwie w edytorze (jak w Object Browserze) | ⚠️ częściowo (menu na nazwie: dane, opis, edycja, DDL, właściwości, rekompilacja, porównanie, deklaracja; bez testu UI) |
| PD-CA-001 | Code Assistant po `obiekt.`: elementy pakietu, parametry (notacja nazwana), kolumny, NEXTVAL/CURRVAL, obiekty użytkownika | ⚠️ częściowo (elementy pakietu, kolumny, NEXTVAL/CURRVAL, obiekty schematu; bez parametrów w notacji nazwanej) ✅ test 👁 |
| PD-CA-002 | Code Assistant dla zmiennych: kursor, rekord, %ROWTYPE (bez niewidocznych), obiekt, kolekcja, `:new`/`:old`, Self | ⚠️ częściowo (kursor, rekord, %ROWTYPE, rekord pętli FOR, typ obiektowy, :new/:old; bez kolekcji i Self) ✅ test |
| PD-CA-003 | Kontekst: obiekty dostępne, kolumny tabel DML (bez aliasu), słowa kluczowe, identyfikatory jednostki i specyfikacji | ⚠️ częściowo (obiekty schematu, kolumny tabel instrukcji, słowa kluczowe, deklaracje w zasięgu i specyfikacji) ✅ test |
| PD-CA-005 | `@` — linki bazy | ⚠️ częściowo (lista z ALL_DB_LINKS; kontekst `@` ✅ test, bez testu listy — baza testowa nie ma linków) |
| PD-CA-006 | Wybór wielu elementów i „(all)” (kolumny, parametry, konstruktory, pola widoku inline), układ w liniach, wyrównanie `=>`, przecinek przed | ⚠️ częściowo (pozycja „(all)” dla kolumn i pól po kwalifikatorze, także pól widoku inline, oraz parametrów podprogramów lokalnych i z bazy — ALL_ARGUMENTS; w jednej linii albo po jednym w linii, przecinek na początku, wyrównanie `=>` ✅ test; bez konstruktorów typów obiektowych — D100) |
| PD-CA-010 | Code Contents: drzewo struktury, śledzenie kursora, hot track, sortowanie, menu (zaznacz, wytnij, test…) | ⚠️ częściowo (drzewo, śledzenie kursora, przejście; bez sortowania i menu) ✅ test 👁 |
| PD-CA-011 | Code Hierarchy nad edytorem (ścieżka od kursora, zaznaczanie, menu) | ⚠️ częściowo (ścieżka pod edytorem; bez menu zaznaczania) ✅ test 👁 |
| PD-CA-012 | Hyperlink navigation (Cmd/Ctrl+klik) do deklaracji: w źródle, w oknach, w nowym oknie; tabela → definicja / zapytanie | ⚠️ częściowo (deklaracje lokalne i obiekty bazy w nowym oknie, Cmd+klik; bez wariantów „w oknach”) ✅ test |
| PD-TEST-002 | Typy zmiennych: Integer, Float, String, Date, Long, Long Raw, Cursor, CLOB/BLOB/BFile, PL/SQL String, Char, Substitution, Temporary CLOB/BLOB, Boolean | ⚠️ częściowo (Integer, Float, String, PL/SQL String, Char, Date, Timestamp, Long, Long Raw, Cursor, CLOB/BLOB, Boolean; bez BFile, Substitution jako podstawienia, tymczasowych LOB jako osobnych) ✅ test |
| PD-TEST-003 | Wykonanie: zmienione wartości na żółto, czas, Break, Commit/Rollback, AutoCommit after execute | ⚠️ częściowo (zmienione na żółto, czas, DBMS_OUTPUT; Break/Commit/Rollback z menu sesji; bez AutoCommit after execute) ✅ test |
| PD-TEST-005 | Zapis .tst (blok, zmienne, obserwowane), Load, zapis jako skrypt SQL*Plus | ⚠️ częściowo (.tst w formacie Pelikana, wczytanie, skrypt SQL*Plus; bez zmiennych obserwowanych) ✅ test |
| PD-TEST-008 | Karty Results (SELECT), Output (DBMS_OUTPUT), HTP Output, niejawne wyniki 12c jako zmienne | ⚠️ częściowo (niejawne wyniki 12c w karcie Wyniki, Output — DBMS_OUTPUT; bez HTP Output) ✅ test |
| PD-DBG-004 | Zmienne automatycznie: Local, Global Private, Global Public, Input Values; rekordy, kolekcje, obiekty jako drzewo; Self; Old/New w wyzwalaczu | ⚠️ częściowo (lokalne, parametry, globalne prywatne i publiczne pakietu, rekordy %ROWTYPE i lokalne, kolekcje jako drzewo, rekordy pętli; bez Self i :old/:new) ✅ test |
| PD-DBG-005 | Wartość w dymku po najechaniu; Set Variable; Copy variable / Append to clipboard | ⚠️ częściowo (Ustaw wartość skalarnej zmiennej — SET_VALUE, Kopiuj wartość; bez dymka po najechaniu) ✅ test |
| PD-DBG-007 | Punkty przerwania na marginesie (Program i Test Window), znacznik nie zastosowanego, warunki, komunikaty, Don't Break, Pass Count, Logpoint | ⚠️ częściowo (punkty w marginesie okna testu i programu, w bloku testu — emulacja, Pass Count; bez warunków, komunikatów, logpointów i znacznika niezastosowanego) ✅ test |
| PD-DBG-008 | Error breakpoints (kody błędów), zapis/odczyt punktów, Enable/Disable All | ⚠️ częściowo (punkty na kodach błędów ORA-, włącz/wyłącz/usuń wszystkie, okno punktów; bez zapisu/odczytu do pliku) ✅ test |
| PD-DBG-011 | Add debug information (z Object Browsera i automatycznie przy kompilacji; listy NEVER/ALWAYS dla połączeń i obiektów) | ⚠️ częściowo (z Object Browsera i przy kompilacji okna programu — preferencja; bez list NEVER/ALWAYS) ✅ test |
| PD-OPT-004 | Statystyki automatyczne (V$SESSTAT): ostatnie i suma sesji, wybór statystyk, filtr, sortowanie, eksport | ⚠️ częściowo (statystyki wykonania okna testu — różnica V$MYSTAT, filtr; bez sumy sesji, wyboru statystyk i eksportu; okno SQL — PD-SQLW-008) ✅ test |
| PD-OPT-005 | Profiler PL/SQL (DBMS_PROFILER): raport na linię, przebiegi, jednostki, wykres, preferencje | ⚠️ częściowo (raport na linię z czasem, liczbą wykonań, udziałem i tekstem; bez historii przebiegów, wykresu i preferencji) ✅ test 👁 |
| PD-OPT-006 | Profiler hierarchiczny (DBMS_HPROF) | ⚠️ częściowo (funkcje z wywołaniami i czasami własnym/z wywołaniami; bez drzewa rodzic–dziecko w UI) ✅ test |
| PD-OB-002 | Foldery 23ai/26ai: MLE Modules, Domains, Annotations (+ użycie), Assertions | ⚠️ częściowo (MLE, domeny; bez adnotacji i asercji) |
| PD-OB-010 | Przeciąganie obiektu do edytora (menu: nazwa, właściwości, opis, SELECT/INSERT…) i na obszar roboczy (akcja z preferencji); folder → nazwy po przecinku | ⚠️ częściowo (przeciąganie nazwy; bez menu i akcji) |
| PD-OB-011 | Wybór wielu obiektów (akcje wspólne), Copy comma separated, Cmd+C | ⚠️ częściowo (Kopiuj nazwę; bez wielu obiektów) |
| PD-OB-016 | Rename (tabele, widoki, sekwencje, synonimy, kolumny, indeksy, więzy), Drop (z potwierdzeniem), Duplicate | ⚠️ częściowo (Drop; bez Rename i Duplicate) |
| PD-OB-019 | Enable/Disable wyzwalaczy i więzów; Run job (DBMS_JOB); kolejki enqueue/dequeue; Refresh MV; Test linku | ⚠️ test (włącz/wyłącz wyzwalacz, więz i wszystkie wyzwalacze tabeli, odświeżenie widoku zmaterializowanego — testy na bazie; test łącza i DBMS_JOB.RUN bez próby — baza testowa bez łączy i zadań DBMS_JOB; kolejki AQ — nie zrobione, D99) |
| PD-OB-022 | Compare obiektu (z bazą/schematem, plikiem, bieżącym oknem) | ⚠️ częściowo (obiekt z aktywnym oknem; ze schematem innej bazy — Etap 6) ✅ test |
| PD-OB-026 | Zapytania słownika odporne na wersję (19c, 21c, 23ai/26ai; starsze — brak kolumn/widoków), DBA views gdy dostępne | ⚠️ częściowo (DBA/ALL, foldery wg wersji; testowane na 26ai) |
| PD-OED-001 | Table Definition Editor: General (właściciel, przestrzeń, storage, klaster, temporary, organizacja heap/IOT/external, komentarz, Recreate table) | ⚠️ częściowo (nazwa, przestrzeń, temporary, IOT, komentarz; bez storage, klastra, external, Recreate) ✅ test 👁 |
| PD-OED-002 | Tabela — Columns (typ z podpowiedzią, domyślna, wirtualna, identity, DEFAULT ON NULL, niewidoczne, tabela obiektowa, Add foreign key columns) | ⚠️ częściowo (typ z podpowiedzią, domyślna, ON NULL, wirtualna, identity, NOT NULL, komentarz, zmiana nazwy/typu, usuwanie; bez niewidocznych i tabel obiektowych) ✅ test 👁 |
| PD-OED-004 | Tabela — Keys, Checks, Indexes (normal/unique/bitmap, funkcyjne, DESC, kompresja, reverse, niewidoczne, lokalne partycjonowane, storage) | ⚠️ częściowo (PK/UK/FK z ON DELETE, CHECK, indeksy zwykłe/unikalne/bitmap, funkcyjne, DESC, niewidoczne, przestrzeń; bez kompresji, reverse, partycji) ✅ test |
| PD-OED-006 | Tabela — Partitions (Range/Hash/List, subpartycje), Triggers (nowy, usuń, Enabled, edycja), External | ⚠️ test (partycjonowanie RANGE z INTERVAL, LIST, HASH przy tworzeniu tabeli, opis dla istniejącej; wyzwalacze tabeli z włączaniem i wyłączaniem; bez subpartycji, zmian partycji istniejącej tabeli i tabel zewnętrznych, D104) |
| PD-OED-008 | Edytory: Sequence, Synonym, Library, Directory, Job (DBMS_JOB), Queue, Queue Table | ⚠️ częściowo (sekwencja, synonim; bez Library, Directory, Job, Queue) ✅ test 👁 |
| PD-OED-009 | Edytory: User (uprawnienia obiektowe, role, systemowe, quoty), Role, Profile, Database link | ⚠️ częściowo (użytkownik: hasło maskowane, przestrzenie, profil, blokada, role, uprawnienia systemowe, limity; rola; bez uprawnień obiektowych, Profile, Database link) ✅ test |
| PD-OED-010 | Edytor widoku w SQL Window z szablonu; edytory widoku i indeksu (z SQL Developer for VS Code) | ⚠️ częściowo (widok z szablonu w oknie SQL, edytor indeksu; bez edytora widoku z SQL Developera) ✅ test |
| PD-OED-011 | Domena (File > New > Domain z szablonem; View/Edit/Drop/Properties) i Assertion (26ai) | ⚠️ test (domena: szablon CREATE DOMAIN w menu Nowy, DDL z DBMS_METADATA SQL_DOMAIN do edycji, usuwanie jak inne obiekty; asercje 26ai — nie, baza testowa 23.26 ich nie ma, D104) |
| PD-TOOL-001 | Find Database Objects: pełnotekstowo w źródłach/DDL (regex, całe słowa), kryteria, typy (MLE), w tle, Locate text, eksport, zapis kryteriów | ⚠️ częściowo (źródła, zapytania widoków, nazwy; regex, całe słowa, wielkość liter; w tle z przerwaniem; przejście do linii; kopiowanie wyników; bez DDL tabel i zapisu kryteriów) ✅ test 👁 |
| PD-DIAG-002 | Diagram: linie (łamanie, zakończenia, kolor, etykiety), grupy, notatki, siatka 8 px, zoom 10–200 % | ⚠️ częściowo (zakończenia linii, kolor, etykiety FK, grupy, notatki, siatka 8 px z dociąganiem, zoom 10–200 % ✅ test; punkty łamania zapisywane i rysowane, bez edycji myszą; okno bez zrzutu (D30)) |
| PD-QB-001 | Query Builder: tabele przeciągane, aliasy, złączenia z FK, pola, INTO, WHERE, ORDER BY, DISTINCT, synonimy, SQL, modyfikacja istniejącego SELECT, preferencje formatu | ⚠️ częściowo (tabele przeciągane, aliasy, złączenia z FK i ich rodzaj, pola z aliasem, sortowanie, GROUP BY, WHERE, HAVING, INTO, DISTINCT, synonimy prywatne i PUBLIC, preferencje formatu, odczyt prostego SELECT ✅ test; bez podzapytań; zrzut w tle: docs/screenshots/09-querybuilder-1.png) |
| PD-BEAU-001 | PL/SQL Beautifier: reguły (wcięcie, margines, tabulacje, puste linie, listy, wielkość liter, Special Case), podgląd | ⚠️ częściowo (wcięcie, tabulacje, margines, listy, przecinek, puste linie, wielkość liter, Special Case, podgląd; bez osobnych reguł DML/parametrów) ✅ test 👁 |
| PD-TPL-001 | Template Window (dokowalny, foldery, filtr) z szablonami domyślnymi (DML, pętle, typy, funkcje SQL, jednostki programów…) | ⚠️ częściowo (panel w pasku bocznym, foldery, filtr, szablony wbudowane; bez dokowania) ✅ test 👁 |
| PD-TPL-002 | Użycie szablonu (dwuklik, przeciągnięcie, menu edytora), formularz zmiennych, `$OSUSER $DBUSER $DATE $TIME`, `[#]`, wiele jednostek z `/` | ⚠️ częściowo (dwuklik i menu, formularz zmiennych z listami, $OSUSER $DBUSER $DATE $TIME, [#], wiele jednostek z /; bez przeciągania) ✅ test 👁 |
| PD-TPL-003 | Tworzenie i edycja szablonów i folderów | ⚠️ częściowo (zapis zaznaczenia jako szablon, usuwanie; edycja przez nadpisanie) ✅ test |
| PD-LDE-001 | Large Data Editor: Text, XML, JSON, HTML (podgląd), obraz, Hex; Parse/Format, Auto Format; Open/Save/Clear; Post, następny/poprzedni rekord | ⚠️ częściowo (bez podglądu HTML i Auto Format) |
| PD-DIFF-001 | Wewnętrzna przeglądarka różnic (dwie kolumny, mapa, następna/poprzednia, różnice w linii, ignoruj wielkość liter/białe znaki/komentarze, Swap, Reload) | ⚠️ częściowo (dwie kolumny, mapa, następna/poprzednia, różnice w linii, ignoruj wielkość liter/białe znaki/komentarze, Swap; bez Reload) ✅ test 👁 |
| PD-FILE-001 | Kopie zapasowe plików przy zapisie (`plik.~ext`) i odzyskiwanie po awarii (przy wykonaniu, co interwał, Open Recovery, przywracanie połączeń) | ⚠️ częściowo (kopia plik.~ext przy zapisie — opcja; migawka niezapisanych okien co interwał, nieczyste zamknięcie → pytanie o odzyskanie i Plik › Odzyskaj okna ✅ test; połączenie odtwarzane tylko dla okien z przypiętym połączeniem; bez migawki przy każdym wykonaniu — D91) |
| PD-FILE-003 | Okno/plik tylko do odczytu (menu Read Only) | ⚠️ częściowo (Plik › Tylko do odczytu: edytor nieedytowalny, komendy zaznaczenia i refaktoryzacji odmawiają ✅ test; narzędzia agenta zmieniające tekst okna nie sprawdzają trybu — D102) |
| PD-UI-002 | Window List (status niezapisany/nieskompilowany/transakcja, wskaźnik połączenia, przypięcie, auto-refresh; menu: Execute, Reconnect, Rename, Short Text, New, Sort; środkowy klik zamyka) | ⚠️ częściowo (stan okna i transakcji; bez menu Execute/Reconnect/Rename) |
| PD-UI-003 | Narzędzia dokowane/pływające (Object Browser, File Browser, Connection List, Window List, Templates, Bookmarks, Search, To-Do, Project, Clipboard), autoukrywanie | ⚠️ częściowo (narzędzia w kartach lewej kolumny — Object Browser, pliki, połączenia, okna, szablony, To-Do, projekt; zwijanie kolumny; okna narzędzi jako osobne okna; bez dokowania w dowolnym miejscu i autoukrywania, D112) |
| PD-PREF-001 | Okno preferencji: kategorie Oracle / UI / Window Types / Tools / Files / Other, wyszukiwarka, Apply | ⚠️ częściowo (karty bez wyszukiwarki i pełnych kategorii) |
| PD-PREF-005 | Czcionki edytora, siatek, przeglądarki (z kolorem i tłem) | ⚠️ test (czcionka i rozmiar edytora, rozmiar siatki wyników i Object Browsera; bez osobnego koloru i tła czcionek — kolory z motywu systemu, D112) |
| UT-RUN-003 | Menu Object Browsera: testy lub pokrycie dla pakietu, ciała, procedury, użytkownika | ⚠️ częściowo (pakiet, ciało, procedura, użytkownik, z pokryciem; bez osobnego okna opcji) ✅ test |
| UT-RES-001 | Okno wyników: drzewo suit/kontekstów/testów, czasy, statusy, filtr statusu, sortowanie | ⚠️ częściowo (drzewo suit/kontekstów/testów, czasy, statusy, filtr statusów; bez sortowania) ✅ test 👁 |
| UT-RES-002 | Szczegóły: oczekiwane vs otrzymane (porównanie), DBMS_OUTPUT testu, stos błędu z przejściem do linii | ⚠️ częściowo (komunikat oczekiwania z wartościami, miejsce wywołania i stos z przejściem do linii, DBMS_OUTPUT; bez porównania obok siebie) ✅ test |
| UT-COV-001 | Pokrycie kodu: okno opcji (schematy, include/exclude), raport HTML (ut_coverage_html_reporter) | ⚠️ częściowo (pokrycie schematu, raport HTML w przeglądarce; bez okna include/exclude) ✅ test |
| UT-COV-002 | Pokrycie na marginesie edytora (linie pokryte/niepokryte/częściowo), procent obiektu i schematu | ⚠️ częściowo (linie pokryte/niepokryte na marginesie okna programu; bez częściowo pokrytych i procentu w pasku) ✅ test |
| UT-CA-002 | Walidacja adnotacji przy kompilacji (nieznana adnotacja, brak `--%suite`, zła lista procedur) | ⚠️ częściowo (nieznane adnotacje jako ostrzeżenia kompilacji; bez sprawdzania list procedur) ✅ test |
| AI-PERM-001 | Poziomy Brak/Odczyt/Za zgodą/Pełny, efektywny = min(komenda, sesja, połączenie); macierz sesji przy starcie | ⚠️ częściowo (poziomy i minimum z komendy, sesji, ustawień, połączenia ✅ test; macierz przy starcie — panel) |
| SD-AUTH-001 | Uwierzytelnianie Entra ID (Oracle na Azure) | ⚠️ test (Entra ID interaktywnie i token OAuth2 z pliku przez Instant Client 23: parametry TOKEN_AUTH w deskryptorze/EZConnect, pola w edytorze połączenia; bez próby na Azure — brak konta, D82) |
| SD-ORDS-001 | ORDS: włączenie REST dla schematu i obiektów, lista modułów | ⚠️ test (wykrycie ORDS, moduły/szablony, obiekty AutoREST, skrypty ENABLE_SCHEMA/ENABLE_OBJECT do okna SQL; baza testowa bez ORDS — lista modułów niesprawdzona na żywym ORDS, D82) |
| DB-SSH-001 | Tunel SSH (hasło z Pęku kluczy, klucz, agent, jump host) przez systemowy ssh | ⚠️ częściowo (bez hasła SSH — D19) |
| MAC-QL-001 | Quick Look dla plików SQL/PL/SQL z podświetlaniem | ⚠️ test (rozszerzenie Quick Look w Contents/PlugIns: podgląd oparty na danych, HTML z kolorami składni z leksera — CodeHTML z testem, kodowania UTF-8/ISO-8859-2/Windows-1250, pliki .sql, pakiety, programy, .tst; działanie w Finderze niesprawdzone — podpis ad hoc, bez rejestracji w systemie, D95) |
| MAC-UI-001 | Natywne karty, pełny ekran, tryb ciemny/jasny, menu wg HIG | ⚠️ częściowo (pełny ekran, jasny/ciemny, menu wg HIG; karty własne) |

## Pominięte decyzją

| ID | Funkcja | Powód |
|---|---|---|
| PD-GRID-008 | Blokada przewijania kolumn i wierszy (Scroll lock) | pominięte (NSTableView nie zamraża kolumn ani wierszy; kolumna numerów wierszy i nagłówek zostają widoczne — D108) |
| PD-DBG-002 | Debuger DBMS_DEBUG_JDWP (wybór systemu, port, kreator konfiguracji JDWP); sprawdzenie dostępności na wersji bazy | pominięte (DBMS_DEBUG_JDWP wymaga własnej implementacji protokołu JDWP; debuger Pelikana na DBMS_DEBUG działa na 19c–26ai, D106) |
| PD-TOOL-010 | ODBC Importer | pominięte (ODBC na macOS bez sensu dla Oracle; zastępuje Text/Excel Importer i kreator importu — gap-analysis) |
| AI-E2E-001 | Testy E2E z prawdziwymi CLI (lokalnie, opcjonalnie) | pominięte (testy z prawdziwymi CLI używałyby kont dostawców właściciela — do ręcznego uruchomienia, D36) |
| SD-APEX-001 | APEXlang (eksport/import/porównanie aplikacji APEX) | pominięte (wymaga APEX; poza codzienną pracą z PL/SQL — D11) |
| SC-LB-001 | Liquibase (`lb`) | pominięte w pierwszej wersji (wymaga Javy i biblioteki Liquibase — D11) |
