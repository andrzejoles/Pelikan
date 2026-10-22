# PL/SQL Developer 17.0 — streszczenie funkcji (źródło do macierzy funkcji)

Źródła:
- **[UG]** PL/SQL Developer 17.0 User's Guide (Allround Automations, 11.09.2026, 322 s.) — plik `manual.pdf` z instalatora wersji
  próbnej https://www.allroundautomations.com/files/trial/plsqldev1703x64.msi (wypakowany tylko PDF dokumentacji; nie
  kopiujemy tekstu ani grafik, tylko streszczamy funkcje). Odwołania: „UG 7.2 s. 40” = rozdział 7.2, strona 40.
- **[NF17]** https://www.allroundautomations.com/products/pl-sql-developer/features/new-features-pl-sql-17-0/
- **[NFxx]** strony „New features” wcześniejszych wersji: `…/features/new-features-pl-sql-<wersja>/` (7-1, 8-0 … 16-0).

Zakres: wszystkie funkcje wersji 17 ze standardowej instalacji. Pominięte zgodnie z promptem §3.2: AI Assistant (rozdz. 16,
AI2SQL, GitHub Copilot CLI), wtyczki (37.6, Query Builder plug-ins 28.5), funkcje tylko Windows (MSI, rejestr, COM,
ODBC Importer — patrz decyzja w gap-analysis).

## 3. Logowanie (UG 3, s. 14)
- Okno logowania przy starcie (można anulować — praca bez połączenia, funkcje wymagające połączenia wyłączone).
- Kolejne połączenia przyciskiem Log on → trafiają na Connection List (rozdz. 19).
- Błędy logowania: brak klienta Oracle, wiele Oracle Home (wybór w Preferences → Oracle/Connection), Instant Client
  bez PATH/TNS_ADMIN/NLS_LANG (ustawiane też w params.ini / linii poleceń, 37.4).

## 4. Program Window — pisanie programów (UG 4, s. 15–18)
- Nowy program z szablonu (File → New → Program Window → Function/Procedure/Package/…): okno pytań o zmienne szablonu.
- Code Contents po lewej (drzewo struktury), Code Hierarchy nad edytorem (ścieżka od kursora: Statement ⟵ Sequence ⟵ Function).
- Wiele jednostek w jednym pliku: karty u góry okna (np. specyfikacja i ciało), menu kontekstowe „dodaj/usuń jednostkę”.
- Zapis do pliku zgodnego z SQL*Plus (`create or replace … /`), rozszerzenia: .fnc .prc .pck .spc .bdy .typ .tps .tpb .trg .jsp
  (konfigurowalne 23.29), nazwa pliku z nazwy jednostki (opcjonalnie z prefiksem właściciela 23.19).
- Wskaźniki na dole okna: niebieski = zmieniony nie zapisany, żółty = zmieniony nie skompilowany.
- Kompilacja (Execute): wszystkie jednostki pliku po kolei od pierwszej; przy błędzie stop i kursor w linii błędu; lista
  błędów pod edytorem (klik = przejście, dwuklik = opis błędu na stronie Oracle); **podpowiedzi (hints)** w liście
  błędów (porównanie z NULL, funkcja bez RETURN, nieużywany parametr, konwencje nazw — 23.19). Błąd samego CREATE
  (np. ORA-00900) w oknie komunikatu.
- Kompilacja bez zapisu pliku.
- Porównanie (menu „Compare to”): z plikiem na dysku, ze źródłem w bazie, z innym plikiem, z obiektem w innej bazie
  (połączenie do wyboru) — wbudowana przeglądarka różnic (26) lub zewnętrzna (23.23).
- Przycisk preferencji kompilatora na pasku stanu okna (23.3).

## 5. Test Window — testowanie (UG 5, s. 19–32)
- Test Script: blok PL/SQL + lista zmiennych (nazwa, typ, wartość) pod spodem; zmienne `:x`; przycisk „Scan source for
  variables”; preferencja automatycznego skanowania przed wykonaniem (23.21). Test z Object Browsera („Test”) tworzy skrypt
  ze zmiennymi parametrów i wyniku (BOOLEAN przez sys.diutil.bool_to_int/int_to_bool).
- Wykonanie: zmienne zaktualizowane, zmienione na żółtym tle; czas wykonania na dole; karty Statistics, Profiler, Trace,
  Output (DBMS_OUTPUT: rozmiar bufora, 0 = bez limitu, włącz/wyłącz), HTP Output (tylko gdy jest wynik), Results (gdy SELECT).
- Break (nie zawsze skuteczny — np. czekanie na blokadę). Po wykonaniu Commit/Rollback aktywne, jeśli zaczęto transakcję.
- Typy zmiennych: Integer, Float, String (≤4000, edytor wieloliniowy), Date, Long, Long Raw (import/eksport pliku),
  Cursor (wynik w SQL Window), CLOB/BLOB/BFile (lokatory z serwera), PL/SQL String (≤32000), Char, Substitution
  (podstawiana w tekście), Temporary CLOB/BLOB (dane od klienta).
- Zapis .tst (blok, zmienne z wartościami, obserwowane wyrażenia debugera); wczytanie do istniejącego okna (Load);
  zapis jako skrypt SQL*Plus (`variable`, `print`) — jednokierunkowy.
- Błędy wykonania: pytanie o pokazanie źródeł stosu błędu; okno z kartą na każdą jednostkę stosu, linie na czerwono.
- Ostrzeżenia ORA-04068 (stan pakietów odrzucony) i ORA-29549 (stan sesji Java) na pasku stanu.
- **Debuger (5.10)**: Start (z listą wyboru systemu DBMS_DEBUG / DBMS_DEBUG_JDWP i kreatorem JDWP), Run, Step into
  (także w wyzwalacz przy DML), Step over, Step out, Run to cursor, Run until exception. Źródło jednostki ładowane
  automatycznie. Po prawej (lub lewej/dole) stos wywołań (klik = ramka, zmienne ramki) i lista zmiennych: Local,
  Global Private (ciało pakietu), Global Public (specyfikacja), Input Values (zmienne skryptu na starcie); rekordy i
  obiekty rozwijane; Self w metodach; Old/New w wyzwalaczach wierszowych [NF17]. Podpowiedź z wartością po najechaniu
  na zmienną (½ s). Wartości tylko przy kompilacji z debug info (preferencja; „Add debug information” w Object Browserze).
- Punkty przerwania: klik na marginesie (Program Window i Test Window, nie w bloku skryptu); znacznik „nie zastosowany”
  dla nieskompilowanej jednostki; okno „Modify Breakpoints”: lista jednostek i punktów z włącz/wyłącz, warunek (wyrażenie
  SQL ze zmiennymi `:x`), komunikat do Output ([Timestamp], [Date], [Time], [Breakpoint], [Pass], [:Var]), „Don't Break”,
  licznik przejść (Pass Count); **error breakpoints** (kody błędów, zatrzymanie nawet przy obsłużonym wyjątku); zapis/odczyt
  punktów do pliku (dopasowanie linii po zmianach kodu).
- Wykonanie SQL w sesji debugowanej (tylko DBMS_DEBUG): wynik SELECT w SQL Window (pola jako tekst ≤1000 znaków).
- DBMS_DEBUG: DBMS_OUTPUT w trakcie, SQL w sesji, zmienne globalne innych pakietów, szybszy przy dużych opóźnieniach.
  DBMS_DEBUG_JDWP: daty z czasem, kolekcje typów złożonych, krokowanie Java; wymaga portu, ACL, zapory — kreator.
- Trace (5.11, DBMS_TRACE): poziomy Calls/Exceptions/SQL/Lines × All/Enabled/None; raport po wykonaniu, historia przebiegów,
  usuwanie przebiegu, kolumny raportu w preferencjach (23.6).
- Regression testing: Test Manager (24.16). Standard Tests (5.13): zapis testu dla funkcji/procedury (właściciel, nazwa,
  podobiekt) → w menu kontekstowym obiektu.

## 6. Optymalizacja (UG 6, s. 33–37)
- Explain Plan Window: SQL u góry, plan na dole; lista „Optimizer goal” (natychmiastowe przeliczenie); przyciski
  First/Previous/Next/Last operacji w kolejności wykonania; tworzenie PLAN_TABLE po pytaniu; kolumny planu w preferencjach
  (23.22); menu obiektu na kolumnie Object name; 11g+: plan w HTML, Text, XML.
- F5 na zaznaczonym SQL w Program Window → Explain Plan z zamianą zmiennych PL/SQL na zmienne wiązane.
- Statystyki automatyczne (6.2): karta Statistics w SQL i Test Window — wartość ostatniego wykonania i suma sesji
  (wymaga v$session, v$statname, v$sesstat — rola plustrace); zestaw statystyk w preferencjach (23.2); filtr, sortowanie,
  eksport CSV/TSV/XML/HTML/schowek.
- Profiler PL/SQL (6.3, DBMS_PROFILER): przycisk w Test Window, raport: czas całkowity/max/min/średni/liczba wystąpień
  na linię, wykres względny, przebiegi i jednostki do wyboru, linia na czerwono = kod zmieniony od profilu.
- SQL Trace (6.4): przycisk na wstążce Session, plik śladu na serwerze (tkprof).

## 7. SQL Window (UG 7, s. 38–54)
- Wynik zapytania w siatce pod edytorem; początkowo pobierana jedna strona (tyle wierszy, ile widać; preferencja 23.20),
  Next Page / Last Page, „(more…)” na pasku stanu.
- **Wiele poleceń → wszystkie wykonane, wyniki w osobnych kartach**; wybranie karty podświetla tekst polecenia.
  Polecenia SQL kończy `;` lub `/`, bloki PL/SQL `/` (jak w SQL*Plus). **Zaznaczony fragment → wykonuje się tylko on.**
- Break: przerywa wykonanie; podczas pobierania wierszy — zatrzymuje i pokazuje pobrane (dalej Next/Last Page).
  Refresh result set (ponowne wykonanie zapytania bieżącej karty).
- Historia poleceń okna: przyciski wstecz/dalej po prawej stronie.
- Karty: Statistics; druk okna (SQL + siatka, z ograniczeniem do zaznaczonych wierszy).
- Tytuł karty: komentarz `-- tab=Tytuł` przed poleceniem, zmienna `&Count` (liczba wierszy) [NF17].
- Siatka (7.2): Align (szerokość wg nagłówka/treści, wysokość wierszy, szablony wyrównania per zapytanie z kolejnością
  kolumn, auto-align); Hide Editor; Adjust Window width; NULL na jasnożółtym tle (kolor w preferencjach);
  `<Long>`, `<Long Raw>`, `<CLOB>`, `<BLOB>`, `<BFILE>` + przycisk komórki → Large Data Editor (27); przycisk także dla
  tekstu > 20 znaków; kalendarz dla DATE; TIMESTAMP wg NLS_TIMESTAMP_[TZ_]FORMAT; XML wykrywany w LDE; `<Cursor>` →
  nowe SQL Window z wynikiem kursora zagnieżdżonego; zaznaczanie wierszy/kolumn/bloków komórek, przenoszenie kolumn
  przeciąganiem, Select All; blokada przewijania kolumn i wierszy (Scroll lock); sortowanie lokalne klikiem nagłówka
  (rosnąco/malejąco/brak, sortowanie wtórne, bez rozróżniania wielkości liter — opcja „Sort case sensitive”, tylko
  pobrane wiersze); Single Record View (kolumna, wartość, typ, komentarz; Next/Previous Record); filtr kolumn
  (nazwy częściowo, typy, Mandatory, PK/UK/FK, historia filtrów; wklejanie wielu linii [NF17]).
- Eksport wyniku (zaznaczenie): CSV, TSV, HTML, XML, SQL (INSERT-y), także „do schowka jako…”; Column to files (kolumna
  → plik na wiersz, katalog i nazwa z wyrażeń); Copy, Copy with Header, Copy to Excel (xls/xlsx, „Copy all” — arkusz na
  wynik), Copy Header, Copy as Expression List (`empno in (7788, 7902)`); skróty dla Copy Header / Copy As Expression
  List [NF17]; kopiowanie siatki także jako HTML [NF17].
- Query By Example (7.3): pusty wiersz na kryteria; wyrażenia: wartość, wzorzec z %, `>`, `<`, `!=`/`<>`, `in (…)`,
  `between … and …`, `null`, `not null`; literały tekstowe bez cudzysłowów; preferencje (wielkość liter itd.).
- Linked Queries (7.4): menu tabel nadrzędnych i podrzędnych (z kluczy obcych) dla bieżącego wiersza → nowe SQL Window
  ze zmiennymi `:m_<kolumna>` odświeżane przy zmianie wiersza w oknie nadrzędnym (master/detail); Custom (własne
  zapytanie z `:m_…`); preferencja „Linked Query in New Window”, Ctrl odwraca.
- Zmienne (7.5): `&nazwa` (podstawienie tekstu, pytanie przed wykonaniem, wiele wystąpień), `:nazwa` (wiązana);
  typy, wartości domyślne, listy wyboru, zapytania list, pola wyboru — jak w raportach (12); przycisk `&` na pasku
  stanu wyłącza podstawianie (od 17 wyłącza też zmienne wiązane [NF17]).
- Edycja danych (7.6): siatka edytowalna gdy ROWID w zapytaniu lub `FOR UPDATE`; przy złączeniu edytowalne tylko kolumny
  tabeli z ROWID (od 17 tabela ustalana z ROWID [NF17]); kolumny z aliasem tylko do odczytu; Edit data, Insert record,
  Delete record (wiele zaznaczonych); czerwony tekst gdy wartość przekracza rozmiar/precyzję; przeliczanie kolumn
  wirtualnych; **Post changes** (zmiany w siatce nie trafiają do bazy, dopóki nie zatwierdzisz), wartości z wyzwalaczy
  i domyślne wracają do siatki; lista przy Post: pokaż SQL zmian w SQL/Command Window lub skopiuj; po Post — Commit/
  Rollback (bez AutoCommit). Edycja LOB w Large Data Editor.
- XMLTYPE (7.7): przez getclobval() i ROWID; View/Edit Data z Object Browsera robi to automatycznie.
- Compare records (7.8): podświetlanie identycznych/różnych pól względem bieżącego rekordu (kolumna/rekord, wielkość liter).
- Compare result sets (7.9): dwie karty naraz (Ctrl+klik), podświetlenie różnic, podział pionowy/poziomy.
- Pinning (7.10): przypięcie wyniku (Shift+klik karty) — nie znika przy kolejnym wykonaniu; „Pin All Result Sets”.
- Direct Query Export (7.11): eksport wyniku zapytania prosto do pliku (CSV, TSV, HTML, XML, Excel, SQL, schowek) bez
  wyświetlania; skrypty inicjalizacji/finalizacji eksportu SQL.
- Dyrektywy w komentarzach (7.12): `Tab=`, `Excel=`/`CSV=` (nazwa pliku z %zmiennymi%, %dbuser%, %dbname%, data/czas,
  `%&zmienna%`), `Records=All|Page|n`, `Totals=[tryb:]kolumny` (Sum/Count/Avg/Min/Max), `AltRowColor=`.
- Zapis .sql (tylko bieżące polecenie; „Save with history” — wszystkie, rozdzielone `/`), Load do istniejącego okna.
- Standard Queries (7.14): zapisane zapytania dla tabeli/widoku w menu kontekstowym (SQL, rozmiar okna, tryb siatki,
  zmienne `&`).

## 8. Command Window (UG 8, s. 55–60)
- Karta Dialog (linia poleceń jak SQL*Plus, strzałki lewo/prawo edycja, góra/dół historia linii) i karta Editor (plik
  skryptu z podświetlaniem SQL/PL/SQL/SQL*Plus); `edit` — edytor bufora; F8 wykonuje edytor i przełącza na Dialog.
- Pasek stanu: Echo, Termout, Feedback, Verify, Autoprint, Heading, Timing (dwuklik przełącza).
- Pause Execution / Execute Next Command — krokowanie skryptu; `SET EXECPAUSE`.
- Polecenia SQL*Plus: `/`, `?`, `@`, `@@` (z parametrami), ACCEPT, CLEAR [SCREEN|SQL], COLUMN (format, NEW_VALUE),
  CONNECT (EDITION, WORKSPACE), DEFINE, DESCRIBE, DISCONNECT, EDIT, EXECUTE, EXIT/QUIT [APPLICATION], GET, HOST, HELP,
  PAUSE, PRINT, PROMPT, RUN, REMARK, SET AUTOPRINT/COLSEP/CONCAT/DEFINE/ECHO/ESCAPE/FEEDBACK (ONLY, SQL_ID [NF17])/
  HEADING/LONG/NUMWIDTH/PAGESIZE/PROMPT ([user], [db], [connection], :bind)/SCAN/SERVEROUTPUT (SIZE UNLIMITED)/
  SPOOLDIRECTORY/TERMOUT/TIMING/VERIFY, SHOW ERRORS/RELEASE/SQLCODE/USER, SPOOL (APPEND, OFF, OUT, .zip), START,
  STORE SET, UNDEFINE, VARIABLE, WHENEVER OSERROR/SQLERROR (EXIT|CONTINUE [COMMIT|ROLLBACK]). Nieobsługiwane SET
  w skrypcie wsadowym bez błędu [NF17].
- Polecenia własne: BEAUTIFY (plik/obiekt, wzorce), BROWSE, CD, DIR, EDIT obiekt, EDITDATA, EXPORT (tabele 8.4 /
  obiekty 8.5), INFO, PROPERTIES, QUERYDATA, RECOMPILE, RUNTESTSET, SET BEAUTIFIERRULES, SET COLWIDTH, SET ENVVAR,
  SET EXECPAUSE, SHOW CONNECTION, SHOW ENVVAR, SQLPLUS, TEST, VIEW, ZIP.
- EXPORT TABLES: User, Tables, Method ("SQL Inserts" | "PL/SQL Developer"), Filename, Where, IncludeStorage,
  IncludePrivs, Wait; dla SQL Inserts: Zip, Create, Drop, Delete, DisableTriggers, DisableFKs, Commit=n; dla formatu
  własnego: Compress. EXPORT OBJECTS: User, Objects, Filename, IncludeStorage, IncludePrivs, SingleFile,
  FilePerObject, FilePerObject2.

## 9. Edytory obiektów nie-PL/SQL (UG 9, s. 61–82)
- New (File → New → typ) lub New na folderze Object Browsera; Edit / View; Rename osobno; **Duplicate** (edytor
  wypełniony bez właściciela i nazwy).
- Table Definition Editor (9.1): przyciski Apply, Refresh, Close, Help, Query (SQL Window z danymi), View SQL (DDL
  zmian lub pełny CREATE; edycja SQL i zastosowanie; zapis/schowek/Command Window). Karty: General (właściciel, nazwa,
  przestrzeń tabel, %Free/%Used/INITRANS/MAXTRANS, segmenty, klaster, tymczasowa z ON COMMIT, organizacja heap/index/
  external, komentarz, „Recreate table” — DROP+CREATE z ostrzeżeniem), Columns (dodaj/usuń/przesuń, typ z podpowiedzią,
  domyślna/wyrażenie kolumny wirtualnej, tabela obiektowa z typu, „Add foreign key columns” z prefiksem, identity —
  Never/Always/On default + parametry sekwencji, **domeny 23ai, adnotacje kolumn i tabeli** [NF17]), Keys (PK/UK/FK,
  kolumny z selektorem, tabela i kolumny odwołań, ON DELETE, deferrable/initially deferred), Checks (warunek, enable,
  deferrable), Indexes (właściciel, Normal/Unique/Bitmap, kolumny/funkcje/DESC, kompresja prefiksu, reverse, storage —
  zmiana wymaga przebudowy), Privileges (grantee × Select/Insert/Update/Delete/References/Alter/Index/Read, wartości
  puste/Yes/Grantable), Partitions (Range/Hash/List, kolumny, wartości, storage, subpartycje dla Range), Triggers (nowy
  z szablonu w Program Window, usuń, Enabled, edycja), External (sterownik, właściwości).
- Sequence (9.2): domyślne min 1, max bez limitu, start 1, krok 1, cache 20, cycle/order off.
- Synonym (9.3): właściciel, PUBLIC, obiekt docelowy z podpowiedzią.
- Library (9.4), Directory (9.5), Job (9.6 — DBMS_JOB.SUBMIT/CHANGE, edytor PL/SQL dla „What”), Queue (9.7) i Queue
  Table (9.8, Advanced Queuing: payload typ obiektowy lub RAW).
- User (9.9): General (hasło, domyślna i tymczasowa przestrzeń, profil, wygaśnięcie hasła, blokada), Object privileges,
  Role privileges, System privileges, Quotas (dalej w UG 9.9–9.12), Role (9.10), Profile (9.11), Database Link (9.12).
  User: Object privileges (bez ról), Role privileges (grantable, default — SET ROLE), System privileges (grantable),
  Quotas (B/KB/MB/unlimited). Role (9.10): bez identyfikacji / hasło / zewnętrzna + 3 karty uprawnień. Profile (9.11):
  limity zasobów i haseł (Default/Unlimited/wartość), karta Users. Database link (9.12): hasło i Authenticated By nie
  są odczytywane przy edycji.

## 10. DBMS Scheduler (UG 10, s. 83–91)
- Narzędzie (Tools → DBMS Scheduler lub Edit/View na obiekcie): drzewo po lewej — Windows, Window groups, Job classes
  (systemowe), Schedules, Programs, Chains, Jobs (z podfolderami właścicieli), File watchers, Credentials, Running
  jobs, Job runs; po prawej właściwości u góry i szczegóły na dole.
- Schedules: Calendar (repeat interval) lub Event (kolejka + warunek). Windows: harmonogram inline lub nazwany (pola
  kursywą, nadpisanie = inline), członkostwo w grupach. Window groups: okna członkowskie. Job classes: uprawnienia EXECUTE.
- Programs: akcja (procedura, program zewnętrzny, blok PL/SQL), argumenty, uprawnienia EXECUTE/ALTER. Chains: kroki
  (Program, Event schedule, Inline event) i reguły. Jobs: akcja inline lub program/łańcuch, harmonogram inline/nazwany/
  okno/grupa, file watcher, uprawnienia ALTER, karty szczegółów i logów przebiegów (100 wierszy, Fetch all).
- New / Apply / View SQL / Cancel / Drop (po potwierdzeniu).
- Job runs: raporty predefiniowane (All, Failed…), sortowanie, przenoszenie kolumn, kopiowanie CSV/TSV, Refresh;
  własne raporty (nazwa, lista pól, WHERE, ORDER BY na all_scheduler_job_run_details, warunki kolorowania wierszy).
- Running jobs: lista, Stop.

## 11. Diagramy (UG 11, s. 92–96)
- Diagram Window: przeciąganie obiektów z Object Browsera (wiele naraz); przesuwanie, zmiana rozmiaru, usuwanie z
  diagramu (nie z bazy); menu obiektu i akcja domyślna na dwuklik.
- Elementy obiektu: pokaż/ukryj (kolumny, klucze, indeksy, całe sekcje), „Set as default”, kolejność (jak utworzone/
  alfabetycznie/przeciąganie).
- Relacje: automatycznie z kluczy obcych (opcja dodania powiązanych tabel, „Add related tables”), ręczne (przeciągnięcie
  elementu na element), „Reference links” (zależności, np. pakiet → tabele); łamanie linii (Insert bend, Ctrl+klik),
  zakończenia (1:N, opcjonalne, strzałki), kolor/grubość/etykieta.
- Grupy (kolor, tytuł w rogu, przezroczystość, auto-rozmiar, obiekty w środku przesuwają się z grupą, Ctrl — bez nich,
  na wierzch/spód, styl domyślny), notatki tekstowe, wyrównanie do siatki 8 px (pojedynczo/wszystko).
- Zoom 10–200%; zapis .pdd (katalog w preferencjach); Update from DB (obiekt/wszystko); druk (widok, rozmiar strony
  auto/ręczny z przesuwaniem granic stron); eksport do obrazu (bmp/jpg/wmf/emf) i do schowka.

## 12. Raporty (UG 12, s. 97–112)
- Raporty standardowe w menu Reports (struktura katalogu Reports), np. Compilation errors (pytanie o typ, właściciela,
  nazwę). Wynik HTML w przeglądarce wewnętrznej; druk; zapis HTML/PDF; Copy as HTML; eksport CSV/TSV/XML/Excel;
  Edit report (gdy nie zablokowany).
- Report Window: jedno zapytanie SELECT (master/detail przez złączenie); Execute.
- **Zmienne raportu (12.3) — ta sama składnia w SQL Window (7.5)**: `&nazwa`, `&"Nazwa ze spacjami"`,
  `&<name="…" hint="…" type="none|string|integer|float|date" required="yes" default="wartość|select…"
  ifempty="…" uppercase="yes" lowercase="yes" readonly="yes" hidden="yes" list="a, b|select…" description="yes"
  restricted="yes" multiselect="yes" checkbox="wł, wył" prefix="…" suffix="…" lines="n" editor="plain|sql|xml">`.
  Listy zależne od innych zmiennych przez `:nazwa_zmiennej` (spacje → podkreślenia, ≤30 znaków; pusta wartość = pusta
  lista). `&&` = literał `&` w tekście (np. 'R&&D').
- Układ (12.4): siatka elementów (Report Title, Variables, tabele, Default Field/Header, pola po „Refresh Fieldlist”):
  wyświetlany, opis, styl (edytor CSS, biblioteka stylów), nagłówek, wyrównanie (Left/Right/Center/Default/None), format
  (liczby 9 0 G D E, literały; daty), Break / Break + Header / Master/Detail, Sum (poziom przerwania/raportu), Auto Update.
- Nagłówek strony z `&OSUser &DBUser &Database &Date &Time &Page` i HTML.
- Style Library (12.5): style nazwane i specjalne (Default Report Title, Variables, Tabular Tables, Form Tables, Field
  Style, Field Header); style zapisywane w pliku raportu.
- Opcje (12.6): Connect Parameters (użytkownik/hasło/baza, `*` = bieżąca, „Use this connection”), Security (Unlocked /
  Locked for other users / Locked for all users — plik .rep szyfrowany), układ (Form layout, marginesy, Page break, Only
  NBSP, Include SQL), tło (obraz/kolor).
- Menu Reports (12.7): katalog standardowy + lista katalogów użytkownika (scalane).

## 13. Wykresy (UG 13, s. 113–114)
- Graph Window z SQL Window lub Report Window: kreator (oś X: kolumna lub [Index]; oś Y; styl) albo styl/szablon
  predefiniowany; narzędzia Rotate, Move, Zoom, Depth, 3D, Edit (dane i wygląd), Save as template (wg nazw kolumn);
  druk, schowek; auto-odświeżanie przy zmianie wyniku SQL Window (Auto refresh / Refresh).

## 14. Projekty (UG 14, s. 115–118)
- Preferencja „Use Projects”; wstążka Project: New, Save (.prj), Add to Project, Project Items, Find, Build, Make.
- Opcje: General (połączenie projektu, „Halt after first error”, własna historia folderów i File Browser, własne reguły
  Beautifiera), Version Control (system i ścieżka), Items, Notes, To-Do items.
- Elementy: pliki (ścieżki względne do .prj), obiekty bazy (właściciel zapisywany tylko gdy inny), pliki zewnętrzne;
  programy domyślnie włączone do kompilacji; kolejność = kolejność kompilacji (przeciąganie); dwuklik otwiera
  w odpowiednim oknie/edytorze/aplikacji; menu obiektu jako podmenu; Find in Project; grupy elementów (karty, „All”).
- Build (wszystko włączone w grupie po kolei), Make (tylko zmienione od ostatniej kompilacji + niepoprawne obiekty,
  „Skipped”); pulpit projektu (.dsk) z otwartymi oknami (AutoSave Desktop).

## 15. Worksets (UG 15, s. 119–121)
- Zestaw okien (Program, SQL, Test, Command, Report, Diagram) z niezapisanymi zmianami, rozmiarami i pozycjami,
  zachowywany między uruchomieniami; New (Empty / Based on opened windows / Based on existing), nazwa w tytule
  aplikacji, lista Open, autozapis co 10 min (preferencja Backup) i przed wykonaniem okna; jeden naraz (parametr
  `workset="…"` dla wielu instancji); Apply (zapis plików, kompilacja obiektów, pytanie o nazwę dla nowych); Revert;
  Compare z plikiem / źródłem w bazie; Manage (filtr, Rename, Delete, katalog danych); projekt jako część zestawu;
  kontrola wersji widzi tylko zastosowane zmiany.

## 17. Kontrola wersji (UG 17, s. 144–145)
- Git i SVN: status pliku (untracked, unchanged, added, modified, conflict, locked) na pasku stanu okna, w File Browserze
  i w projekcie; operacje przez kliknięcie ikony statusu lub menu elementu — przez zewnętrzne GUI (np. Git Extensions);
  od 17: gałąź Git na pasku stanu [NF17].

## 18. To-Do Items (UG 18, s. 146–147)
- Komentarz `TODO:` o ustalonym formacie w źródle; edytor (tekst, priorytet, kategoria, właściciel, data utworzenia
  i zamknięcia; listy w preferencjach 23.25); Add/Edit/Close/Delete Item z menu; lista To-Do dla pliku (sortowanie,
  Goto, kopiuj/drukuj/eksport).

## 19. Connection List (UG 19, s. 148–153)
- Panel (domyślnie lewy górny): odśwież, rozwiń/zwiń, Define Connections. Foldery użytkownika (połączenia jawne i
  dopasowane regułami), folder Recent; kolor połączenia (szary = niejawne); pod połączeniem okna z jego sesjami;
  ikona klucza: hasło znane + sesje / hasło znane bez sesji / hasło nieznane.
- Menu połączenia: otwórz okno danego typu (SQL, Program, Test, Command, Reports…), New Instance, Show All Windows
  (minimalizuje inne), Close All Windows, Reconnect All Windows (przepięcie okien na inne połączenie), Connect, Connect
  as Main (też dwuklik; główne pogrubione), Disconnect, Set current schema (ALTER SESSION SET CURRENT_SCHEMA we wszystkich
  sesjach, wyświetlane `sys@chicago [scott]`), Remove (niejawne), Add to Folder.
- Menu folderu: Show All / Close All / Reconnect All Windows. Menu okna: aktywuj, zamknij, rozmiar, Reconnect, Rename,
  Short Text („P - employee.pck”), Execute.
- Define Connections: drzewo z New Connection / New Folder / Delete / Up / Down / Left (hierarchia), przeciąganie,
  eksport i import definicji. Folder: nazwa, obraz, reguły dopasowania (Username, Database, Connect as — wzorce * ?),
  Edition, Workspace; Alt = w korzeniu, Ctrl = kopia. Połączenie: nazwa (domyślnie user@db), obraz, Username, Database,
  Password (puste = pytanie przy pierwszym użyciu), Connect as, Identified externally; Properties: Edition (EBR),
  Workspace (DBMS_WM.GotoWorkspace), JDWP Debugger Port i karta sieciowa, **kolor wskaźnika** (nadpisuje reguły
  23.16), Connect on startup, **Read Only** (blokada zmian obiektów i danych; też parametr ReadOnly), karta
  Initialization (skrypt dla każdej sesji), karta Message (komunikat przy logowaniu), przycisk Test.

## 20. Połączenia, okna, sesje i transakcje (UG 20, s. 154–155)
- Multi-connection (każde okno inne połączenie, połączenie na pasku stanu w lewym dolnym rogu, zmiana kliknięciem),
  multi-session (osobne sesje dla okien Test/SQL/Command i osobna sesja kompilacji — DDL robi COMMIT), multi-threading
  (okna wykonują się równolegle).
- Połączenie główne (Main): domyślne dla nowych okien i Object Browsera; zmiana przez Log on, dwuklik w Connection List,
  Set Main Connection / Set Main Connection to <current>.
- Połączenie okna przypięte / nieprzypięte (nieprzypięte podąża za główną; jawna zmiana przypina; preferencja domyślna
  23.1); Disconnect okna.
- Session mode (23.2): Multi session (sesja na okno + sesja kompilacji), Dual session (wspólna sesja okien + sesja
  kompilacji, jedno okno naraz), Single session (wszystko w jednej, debuger wyłączony).
- Break (multi/dual), Kill na wstążce Session; kursor „wykonywanie” nad oknem w trakcie (bez edycji); Commit/Rollback
  odzwierciedlają transakcję okna na wierzchu.

## 21. Object Browser (UG 21, s. 156–165)
- Drzewo typów obiektów dla połączenia głównego; foldery obiektu (np. kolumny, klucze obce); Recent objects; cache
  słownika w pamięci, Refresh obiektu (Ctrl+Refresh = całość).
- Przeciągnięcie obiektu na obszar roboczy → edytor definicji (akcja w preferencjach 23.11); na edytor → menu: nazwa
  (z właścicielem gdy trzeba), właściwości, opis, inne teksty; folder → nazwy obiektów po przecinku (jedna linia/wiele —
  23.12). Wybór wielu obiektów (Ctrl/Shift) — menu z akcjami wspólnymi. Ctrl- / Ctrl+ — szerokość panelu do treści.
- Preferencje: widoczne foldery i kolejność, limit Recent, akcja dwukliku (rozwiń / edytor / właściwości).
- Filtrowanie: wybór użytkownika (<CURRENT USER>, <ALL USERS>, konkretny), filtr nazwany, pole filtra ad hoc
  (`DEPT`, `DEPT%`, wiele nazw po przecinku) i formularz: Name=, Source= (tekst w źródle PL/SQL), Status=valid|invalid,
  CreatedAfter=, CreatedBefore=, ModifiedAfter=, ModifiedBefore=.
- Menu obiektu: New (program z szablonu w Program Window, widok w SQL Window z szablonu, tabela/sekwencja/synonim w
  edytorach), Duplicate, Copy comma separated, Properties (okno niemodalne na wierzchu, zwijane), Describe (kolumny /
  parametry / elementy pakietu / metody i atrybuty typu; zaznaczanie, kopiowanie, eksport CSV/TSV/HTML/XML, druk,
  sortowanie, dwuklik wstawia do edytora), View (dla elementu tabeli — nawigacja do elementu), Edit (wyłączalne
  preferencją), Rename (tabele, widoki, sekwencje, synonimy, kolumny 9.2+), Drop, Browse (obiekty powiązane),
  Recompile (czerwony znacznik niepoprawnych), Add source to editor (Program/Test Window), Add debug information
  (z zaznaczeniem stanu), PL/SQL CCFlags (podgląd i zmiana flag kompilacji warunkowej z rekompilacją), Recompile
  referencing objects (Compile Invalid Objects), Compare (z obiektem w innej bazie/schemacie, z plikiem, z bieżącym
  oknem), Test, Query data, Edit data (z ROWID, od razu w trybie edycji; AutoExecute), Export data (Export Tables),
  Enable/Disable (wyzwalacze, więzy — wyszarzone gdy wyłączone), Run (DBMS_JOB), Enable/disable enqueue/dequeue
  (kolejki), Refresh (widok zmaterializowany), Add to folder, Recycle bin: Purge / Restore (pod starą lub nową nazwą).
  Od 17: Ctrl-C kopiuje zaznaczone [NF17]; foldery MLE Modules, Domains, Assertions, Annotations [NF17].
- Filtry (21.2): opis, użytkownik (scott@chicago), domyślny, WHERE i ORDER BY na all_objects (owner, object_name,
  object_type, status, created, last_ddl_time), zmienne `:browser_user`, `&browser_filter`.
- Foldery (21.3): kolejność, kolor (dziedziczony), widoczność, opis, warunek połączenia (wzorce `*@prd`), rodzic
  (hierarchia), Suppress owner, foldery użytkownika — zapytanie (WHERE/ORDER BY na all_objects) i/lub lista
  `OWNER.NAZWA`.

## 22. File Browser (UG 22, s. 166–169)
- Lokalizacje (File Browser Locations): ścieżka, podkatalogi tak/nie, filtr włączający i wykluczający (`*.sql; *.cmd`,
  domyślnie wykluczone pliki stanu i kopie `*.~*`), opis, kolor, lokalizacja nadrzędna; tworzenie/usuwanie/sortowanie.
- Drzewo; dwuklik otwiera do edycji; menu: Open, Open as (Program/SQL/Command Window), Open with, Open in Explorer
  (na Macu: Finder), Rename, Create file, Create subdirectory, Delete, Refresh, Sort (nazwa/data, kierunek), kontrola
  wersji, „Save window in <katalog>”, „Save window as <plik>”, Shell; ikona tylko do odczytu, status VCS; automatyczne
  odświeżanie przy zmianach zewnętrznych.
- Filtr: wzorzec nazwy i formularz Name=, Status=Writable|Readonly, VCS=…, MinSize=, MaxSize=, ModifiedAfter=,
  ModifiedBefore=; historia filtrów; Clear filter.

## 23. Preferencje (UG 23, s. 170–219)
Okno: kategorie Oracle / User Interface / Window Types / Tools / Files / Other; wybór zestawu preferencji; wyszukiwarka
preferencji; zielony znacznik = ustawione w bieżącym zestawie (klik = przywróć dziedziczoną), czarny = dziedziczone;
OK / Cancel / Apply (podgląd) / Import/Export do pliku.
- **Oracle – Connection (23.1)**: Session mode (Multi/Dual/Single); **Logoff with open transaction** (domyślnie COMMIT!,
  opcje Rollback / pytaj); Check connection (co 60 s; po utracie — wylogowanie), Check all sessions; Oracle Home / OCI
  Library (Windows — u nas: katalog Instant Client); zmienne środowiska Oracle (NLS_LANG, NLS_DATE_FORMAT…); Allow
  multiple connections; Pin window connections by default; Automatically close unused connections; Store recent history
  (z hasłem / bez).
- **Oracle – Options (23.2)**: Allow editing of database source; Ask to save edited database source; Allow compilation of
  read-only source files; Confirm Commit & Rollback; Use DBA views if available; Automatic statistics (+ wybór
  statystyk); Unicode enabled; Check client/server character set mismatch; Add column alias list for View DDL (Auto);
  Use FORCE option for View DDL (Only for Exports / Always / Never) [NF17]; timestamp format for scheduler objects;
  Always include owner prefix (DDL).
- **Oracle – Compiler (23.3)**: PLSQL_OPTIMIZE_LEVEL, PLSQL_CODE_TYPE (Interpreted/Native), PL/Scope identifiers/
  statements, domyślne flagi kompilacji warunkowej (Reset to default flags), PLSQL_WARNINGS (kategorie i numery:
  Disabled/Warning/Error, kolejność ma znaczenie), `-- Ignore` po linii tłumi ostrzeżenie/podpowiedź, wartości zmiennych
  podstawiania `&` w plikach programów.
- **Oracle – Debugger (23.4)**: wartości w dymku; pomijanie inicjalizacji specyfikacji i ciała pakietu; Step over SYS
  objects; domyślny system (DBMS_DEBUG / JDWP), port i karta sieciowa JDWP; Add debug information when compiling;
  listy NEVER/ALWAYS add debug info dla połączeń (`user@db` ze wzorcami) i NEVER dla obiektów.
- **Oracle – Output (23.5)**: DBMS_OUTPUT włączony, czyszczenie przed wykonaniem, rozmiar bufora (0 = bez limitu),
  zapis do pliku (zmienne %dbname% %dbuser% %date% …) z nagłówkiem.
- **Oracle – Trace (23.6)** i **Profiler (23.7)**: kolumny, jednostki czasu, pokaż 0 wystąpień, wykres czasu.
- **Oracle – Logon History (23.8)**: historia logowań (z hasłem lub bez; Ctrl+Enter przy logowaniu = bez zapisu hasła),
  rozmiar historii, sortowanie, Fixed Users z podmenu `>nazwa` (np. Development/Test/Production), Delete item/all.
- **Oracle – Hints (23.9)**: włącz/wyłącz poszczególne podpowiedzi kompilatora (właściwości); konwencje nazw (typ
  elementu, prefiks, znaki pierwsze/kolejne, sufiks, opis „Parameter 'X' must start with 'p_'”, alternatywy „or”);
  `-- Ignore`.
- **UI – Options (23.10)**: Autosave username/desktop/layout; zapis plików przy utracie fokusu; karta startowa;
  układ per konfiguracja monitorów; przeglądarka HTML; Oracle Manuals „stay on top”; **Oracle Error Help URL**
  (`https://docs.oracle.com/en/error-help/db/%1/`); karty wielowierszowe; Use projects; okna komunikatów przy
  kursorze; wskaźnik transakcji i ikony statusu w Window List; widok szczegółów w oknach plików; preselekcja bieżącego
  użytkownika w listach obiektów; liczba ostatnich plików; limit wyników wyszukiwania w plikach; DSA Dialogs („nie
  pokazuj więcej” — edycja listy).
- **UI – Object Browser (23.11)**: limit Recent; akcja dwukliku i przeciągania (domyślna + per typ); domyślny wybór
  użytkownika (current/all/ostatni); WHERE dla listy użytkowników (all_users); pokazuj typy danych; Smooth Refresh;
  Confirm Recompile; zawsze pokazuj publiczne linki.
- **UI – Editor (23.12)**: wcięcia (None/Automatic/Smart — słowa bloków w pliku SmartIndent), krok, Backspace/Delete
  unindents; Smart tab, rozmiar tabulacji, Smart fill, znak tabulacji, zawijanie, kursor za końcem linii, margines
  pionowy, znaki specjalne; podświetlanie składni (styl i kolor słów kluczowych, komentarzy, tekstów, liczb, symboli;
  wielkość liter słów kluczowych przy pisaniu Upper/Lower/Init Caps; własne słowa kluczowe); **AutoReplace**
  (`wo=when others then`, także odwołanie do szablonu `wh=Loops\While loop.tpl`); schowek (styl czcionki, elementy po
  przecinku w jednej linii, historia schowka: liczba, dni, min/max rozmiar); ligatury [NF17]; zwijanie kodu (włączone,
  domyślnie wł.); numery linii (interwał, czcionka); status linii (żółty = zmieniona, zielony = nowa); podświetlenie
  bieżącej linii; zmienna szerokość znaków; poziomy pasek wg widocznego tekstu; podświetlanie nawiasów; kolory
  podświetleń i trafień wyszukiwania; oznaczanie identyfikatorów > 30 znaków (także dla 12.2+); hiperłącza do okna
  tylko do odczytu.
- **UI – Fonts (23.13)**: czcionki przeglądarki, edytora, siatek (z tłem; styl przy kopiowaniu), czcionka dialogów.
- **UI – Code Assistant (23.14)**: automatycznie / tylko klawiszem; opóźnienie (ms); filtr podelementów Contains /
  Starts with; styl wstawiania (Smart / Init Caps / Lower / Upper) i oryginalna wielkość liter ze słownika; opisuj
  użytkowników (obiekty po `user.` — wybrane typy); opisuj kontekst (obiekty dostępne — ładowane raz po zalogowaniu,
  funkcja „Refresh Code Assistant”); kolumny z tabeli bieżącego DML; minimalna liczba znaków; funkcje standardowe;
  deklaracje zmiennych i typów w dymku; wyrównanie `=>` przy wielu parametrach; maks. elementów w jednej linii;
  przecinek przed elementem.
- **UI – Key Configuration (23.15)**: lista funkcji, przypisanie klawisza, Esc czyści, filtr.
- **UI – Appearance (23.16)**: język; gradient tła; format i wyrównanie tytułu aplikacji [NF17]; tytuły okien MDI;
  karty okien w SDI; nazwa bazy w tytułach [NF17]; **Connection Indicators** (reguły `user@database` z * ?, kolor →
  wskaźnik na pasku narzędzi lewy/prawy, na oknie i w Window List, tło aplikacji; `{edition}`/`{workspace}`; pierwsza
  pasująca reguła wygrywa); połączenie okna w tytule aplikacji; przewijanie okna przy wyborze; animacje dokowania;
  autouzupełnianie list; sortowanie Connection List; rozmiar ikon; kolorowe ikony; motyw Light/Dark/Auto + styl;
  reset pasków i dokowania; wstążka / klasyczne menu.
- **UI – NLS Options (23.17)**: format daty (własny / systemowy / Oracle NLS_DATE_FORMAT), czasu (własny / systemowy),
  liczb (własne separatory / systemowe / Oracle NLS_NUMERIC_CHARACTERS).
- **Window Types – General (23.18)**: zapis stanu okna (.pfi: pozycja, rozmiar, zakładki, znaczniki kolorów, zmienne
  podstawiania); powiadomienie dźwiękiem o końcu długiego zapytania (próg, plik dźwięku).
- **Window Types – Program Window (23.19)**: kompilacja w trakcie wykonywania; **Safe compilation** (najpierw próbna
  kompilacja obiektu tymczasowego); **Check database object changes** (co n s; różnice i odświeżenie); kompilacja w tle
  (osobna sesja, tylko Multi session); zapis przed kompilacją; prefiks właściciela w nazwie pliku; końcowy `/`; ignoruj
  nierozpoznany PL/SQL; Code Contents i Code Hierarchy (pokaż, hot track); podświetlanie zmiennych; podświetlanie par
  słów if/loop/case/blok/transakcja; podpowiedzi kompilatora po kompilacji; kolory błędu i hot tracku.
- **Window Types – SQL Window (23.20)**: AutoCommit SQL; AutoCommit posted records; Refresh posted records;
  AutoExecute queries (Query/Edit Data); **AutoSelect statement** (wykonuje polecenie pod kursorem; bez tego —
  klawisz „Execute current statement”) — wartość domyślna do weryfikacji; pytanie o zapis nowych okien; linked query
  w nowym oknie; daty przez TO_CHAR na serwerze; LF↔CR/LF; **CLOB/BLOB pobierane na żądanie**; informacje słownika w
  siatce (typ, NOT NULL, komentarz na pasku stanu; lista wartości z CHECK IN (…); lista z FK do tabel < 1000 wierszy);
  numery linii w edytorze; numer wiersza w kopiowaniu/eksporcie; minimalna liczba linii edytora; kolory NULL (osobno
  dla kolumn obowiązkowych), naprzemiennych wierszy, porównania; **Records per page** (automatycznie wg wysokości /
  stała liczba / wszystkie); maksymalny rozmiar wyniku (MB, potem pytanie); układ liczb (lewo / prawo / formatowane wg
  precyzji / z separatorem tysięcy); QBE: bez wielkości liter, automatyczne „zawiera”, ignorowanie czasu w datach.
- **Window Types – Test Window (23.21)**: AutoCommit after execute; automatyczne skanowanie zmiennych (dodaje jako
  String, wyłącza nieużywane).
- **Plan Window (23.22)**: kolumny PLAN_TABLE i kolejność.
- **Tools – Difference Viewer (23.23)**: domyślne opcje (wielkość liter, białe znaki, komentarze, różnice w linii),
  kolory wewnętrznej przeglądarki, zewnętrzne narzędzie z dyrektywami `<IgnoreCase=on|off>` itd.
- **Tools – Data Generator (23.24)**, **To-Do List (23.25)** (listy priorytetów, kategorii, właścicieli; akcja dwukliku),
  **Recall Statement (23.26)** (liczba poleceń w historii, katalog).
- **Files – Version Control (23.27)**: Git / SVN (narzędzie wiersza poleceń + GUI).
- **Files – Directories (23.28)**: katalogi startowe dla programów, testów, skryptów SQL, raportów, plików poleceń,
  makr, szablonów, wtyczek, projektów, worksetów, standardowych zapytań i testów, plików Excel.
- **Files – Extensions (23.29)**: domyślne i dodatkowe rozszerzenia per typ (wzorce), rejestracja typów plików.
- **Files – Format (23.30)**: końce linii CR/LF vs LF (także per katalog), kodowanie (UTF-8 / ANSI / auto, BOM), CSV
  ze smart quotes, Excel: z SQL na osobnym arkuszu, z formatowaniem, z naprzemiennymi kolorami [NF17], XLS/XLSX/pytaj.
- **Files – Backup (23.31)**: kopia przed zapisem (`plik.~pck`), filtr „Backup files”; odzyskiwanie po awarii: zapis
  otwartych plików przy wykonaniu i co interwał.
- **Files – HTML/XML (23.32)**: kodowanie znaków, nagłówek.
- **Other – Printing (23.33)**: okno druku, numery linii, zawijanie, czarno-białe, tło, SQL w wydruku SQL Window,
  linie siatki, odwrócony nagłówek, nagłówek (typ i nazwa pliku, data) i stopka (numer strony).
- **Other – Updates & News (23.34)** (u nas: Sparkle).
- **Zestawy preferencji (23.35)**: osobiste (domyślny dla użytkownika systemu + zestawy dla połączeń ze wzorcami) i
  domyślne administratora (globalny + per połączenie); pierwszeństwo: osobisty połączenia > osobisty użytkownika >
  domyślny połączenia > domyślny globalny; pliki w katalogu preferencji (PREFPATH).

## 24. Narzędzia (UG 24, s. 220–261)
- **Find Database Objects (24.2)**: pełnotekstowe szukanie w DDL/źródłach (wielkość liter, całe słowa, regex; puste =
  wszystkie obiekty spełniające resztę), kryteria obiektu (filtr przeglądarki, właściciel z %, nazwa z %, status,
  utworzone/zmienione po/przed), typy obiektów (także MLE [NF17]); wyszukiwanie w tle; wynik z menu obiektu, „Locate
  text” (dwuklik — Program Window na pierwszym trafieniu); eksport wyników; zapis/odczyt kryteriów do pliku.
- **Compile Invalid Objects (24.3)**: lista niepoprawnych obiektów użytkownika, błędy wybranego, Compile w kolejności
  zależności, ikony wyniku, Refresh, menu obiektu (także MLE [NF17]).
- **Export Tables (24.4)**: wybór użytkownika i tabel, kolejność wg kluczy obcych; metody: Oracle Export (exp —
  u nas zastąpione Data Pump przez DBMS_DATAPUMP, prompt §3.1), **SQL Inserts** (Drop / Create (z więzami, indeksami,
  grantami) / Truncate / Delete, wyłącz wyzwalacze, wyłącz FK, storage, uprawnienia, Commit every, Batch w blokach
  PL/SQL, WHERE dla wszystkich tabel, Zip, skrypty inicjalizacji/finalizacji), **format własny** (skompresowany,
  WHERE, storage, uprawnienia; opcje odłożone do importu); „Copy as Command” (składnia EXPORT z Command Window).
- **Import Tables (24.5)**: Oracle Import (imp → Data Pump), SQL Inserts (wewnętrzny Command Window lub SQL*Plus),
  format własny (wybór tabel z pliku; Drop/Create/Truncate/Delete, wyzwalacze, FK, Commit every).
- **Export User Objects (24.6)**: siatka obiektów użytkownika (zaznaczenie lub wszystkie), plik wyjściowy zgodny z
  SQL*Plus, View w Command Window, uprawnienia, storage, prefiks właściciela, Single file / File per object / File per
  object ze specyfikacją i ciałem razem; skrypty inicjalizacji/finalizacji; „Copy as Command” (MLE [NF17]).
- **Text Importer (24.7)**: pierwsze 100 linii (dowolny rozmiar pliku, strumieniowo), wklejanie ze schowka,
  automatyczne wykrycie formatu, definicja (liczba pól, koniec na końcu linii, nazwy w nagłówku, pomijanie pustych,
  znak cudzysłowu, znak komentarza, zakres linii; pole: start względny/bezwzględny/znak, koniec długość/znak),
  podświetlenie pola w danych, filtr SQL z `:pole`, Create table (edytor tabeli z kolumnami), mapowanie na tabelę
  (Delete / Truncate, Commit every, Overwrite / Ignore Duplicates wg PK, skrypty przed/po), typ pola (String/Number/
  Date), funkcja SQL z `#` (Create SQL → TO_DATE), zapis/odczyt definicji (zapamiętana dla pliku), Import / Import to
  Script.
- **Excel Importer (24.8)** [NF17]: plik .xlsx (bez ODBC) lub wklejenie z Excela, arkusz, linia nagłówka, pierwsza
  i ostatnia linia danych, mapowanie jak w Text Importer, funkcje SQL `upper(#)`, Ctrl+Import = przykładowy INSERT,
  zapis definicji.
- ODBC Importer (24.9) — tylko Windows (decyzja w gap-analysis: pominięte, zastąpione importem CSV/Excel/JSON).
- **Data Generator (24.10)**: definicja: tabele (z Object Browsera), liczba rekordów (liczba lub zakres 10..100),
  pola (nazwa, typ, rozmiar, definicja danych), tabela nadrzędna (rekordy podrzędne na rekord nadrzędny); składnia:
  `[Aaa00]` (zbiory a A @ # * 0 1 9, powtórzenia `(n)` i `(min..max)`, literały w apostrofach), funkcje Signal, Random,
  Sequence (WithinParent), List('x'(waga),…), List(select … :pole), SQL(wyrażenie z :pole), Text(styl, max, słowa/linia,
  linie/akapit), File(ścieżki z wzorcami), Uppercase/LowerCase/InitCaps, zbiory Firstname, Lastname, Company, Address1/2,
  ZIP, City, State, Country, Email, zbiory użytkownika z plików CSV; opcje: format daty, Commit every, opóźnienie,
  własne zbiory znaków, skrypt inicjalizacji; Start a test run (siatka), Create data as SQL, Create data in DB.
- **Compare User Objects (24.11)**: wybór obiektów źródła, sesja docelowa, opcje (storage, schemat docelowy, ignoruj
  wielkość liter / białe znaki / komentarze w PL/SQL poza literałami), wynik: lista różnych obiektów w kolejności
  zależności + SQL wyrównujący (dla zaznaczonych lub wszystkich), Show Differences (przeglądarka różnic), Apply SQL /
  Save SQL / Copy SQL; ignorowane: storage, więzy z nazwami systemowymi, właściwości wymagające odtworzenia tabeli,
  dane, wartości sekwencji (MLE [NF17]).
- **Compare Table Data (24.12)**: tabele źródła, sesja docelowa, akcje (Insert/Update/Delete), Commit every, tryb
  Generate script / Update database, schemat docelowy, właściciel w SQL; wynik: liczby zmian lub skrypt do przejrzenia
  (per tabela), zapis/kopiowanie/zastosowanie zaznaczonych.
- **Event Monitor (24.13)**: DBMS_ALERT (wiele nazw po dwukropku; wartość komunikatu) i DBMS_PIPE (jedna nazwa;
  wszystkie elementy komunikatu); Start; dziennik z czasem.
- **Sessions (24.14)**: lista sesji instancji (sortowanie), filtry sesji (zapytania z kolumnami i kolejnością), menu:
  Kill (normal/immediate), Enable/Disable SQL Trace (DBMS_SYSTEM), Refresh, Copy, Print, Export (CSV/TSV/HTML/XML),
  własne akcje; Auto refresh (okres); karty szczegółów (np. SQL, blokady, statystyki) z Single Record View; formatowanie
  SQL Beautifierem; **Define Session Queries**: Filters (podpis, minimalna wersja bazy, zapytanie), Details (podpis,
  wersja, zapytanie z `:sid` i dowolną kolumną v$session, wskazówka `/* concatenate */`), Actions (podpis, wersja,
  SQL/PL/SQL z `:sid`, `:serial#`; DBMS_OUTPUT po akcji).
- **User Defined Tools (24.15)**: typ External (program, parametry, katalog) lub Session (skrypt SQL dla sesji okna
  ze zmiennymi `&`); zmienne #file #path #dir #object #otype #oowner #oname #connect #username #password #database
  #wconnect … #line #column #line0 #column0 (u nas: bez haseł w argumentach — §4.2); opcje Save Window, Editor Text
  Only, Wait for Tool (odśwież okno), Run Minimized/Hidden, Active Connection, Browser Object, Window Types; Ctrl+Execute
  = podgląd poleceń.
- **Test Manager (24.16)**: Test Set (.ts) — lista skryptów testowych (przeciąganie z File/Object Browsera, dodawanie
  plików, New, duplikat z Ctrl), definicja: plik, opis, New Session, Enabled, wymagana wydajność (s), zmienne (wejście,
  oczekiwane wyjście, `null`, `LIKE 'RES%'`, `IN (…)`, Global — przekazywane między skryptami, `dbms_output` jako
  zmienna); Notes; Run (każdy skrypt w Test Window; nieudane na czerwono na górze), log wejść/wyjść i DBMS_OUTPUT,
  Debug (dwuklik), eksport wyników; `RunTestSet plik.ts log` w Command Window i z linii poleceń (wynik Success / Failed /
  Error / Slow / Skipped).
- **Load Tester (24.17)**: kroki w hierarchii (Name, Enabled, Repeat count / for each parent record, Repeat time,
  Delay before/after z losowością; dla SELECT: liczba rekordów, rekordy na fetch, Fetch LOBs), SQL kroku, zmienne kroku
  (String/Integer/Float/Date z value, Parent/Previous variable, Parent field, Sequence within run/session/parent,
  Random string/integer/float/date/datetime, Select … z list/select/file), opcje (wątki = sesje, połączenia, skrypty
  inicjalizacji/finalizacji), Run / Break, wyniki na żywo: tekst (log + statystyki min/śr/max), wykres słupkowy (średnia
  wszystkich / ostatnich 5 / ostatnia), wykres liniowy (zoom kółkiem, 2D/3D, kopiowanie), zapis do Excela.

## 25. Edytor (UG 25, s. 262–281) — wspólny dla wszystkich okien
- Funkcje zaznaczenia (25.1): Indent/Unindent (Tab/Shift+Tab przy zaznaczeniu), Remove Trailing Blanks (poza
  wieloliniowymi literałami), Lowercase/Uppercase (z pominięciem literałów), Comment/Uncomment (`/* */`; linia —
  Ctrl+minus), Apply Syntax Case, Sort (rosnąco, ponownie malejąco), Color mark.
- Zaznaczenie kolumnowe (25.2): Alt+przeciąganie; kopiuj/wklej/wytnij/usuń/wielkość liter/wcięcia/komentarz; pisanie
  powtarza tekst w każdej linii (wiele kursorów w kolumnie).
- Find & Replace (25.3, Ctrl+F): Search, Search Next, Search All (podświetla, liczba na pasku stanu), Replace, Replace
  All; opcje: wielkość liter, całe słowa, regex (menu elementów składni), **Preserve case on replace**; **Search in**:
  komentarze / literały / pozostały kod; zakres Global / Selection / From cursor; kierunek; wyciszenie [NF17]; zawijanie.
- **Code Assistant (25.4)**: po `pakiet.` (procedury, funkcje, typy, zmienne, stałe, wyjątki), funkcja/procedura
  (parametry w notacji nazwanej `p =>`), tabela/widok (kolumny), sekwencja (NEXTVAL, CURRVAL), użytkownik (jego
  obiekty), zmienna kursora (pola SELECT), rekord (pola), `%ROWTYPE` (kolumny bez niewidocznych [NF17]), typ obiektowy
  (atrybuty konstruktora), zmienna/kolumna obiektowa (atrybuty i metody), kolekcja (FIRST, NEXT, LIMIT…), `:new`/`:old`
  (kolumny tabeli wyzwalacza), `Self`, `@` (linki bazy; w Command Window na początku linii — listing katalogu);
  kontekst: obiekty dostępne, kolumny w DML, słowa kluczowe wg typu edytora, identyfikatory PL/SQL bieżącej jednostki
  (od 17 także ze specyfikacji przy edycji ciała [NF17]); zapytania słownika w pliku CANames.sql (u nas: wbudowane,
  odporne na wersję); filtrowanie w trakcie pisania, Enter wstawia, strzałki, sortowanie, Esc; pozycja „(all)” dla list
  kolumn/parametrów, wybór wielu (Ctrl/Shift), układ w jednej/wielu liniach.
- **Recall Statement (25.5, Ctrl+E)**: globalny bufor wykonanych poleceń (SQL Window, Command Window, Report Window;
  bez poleceń z hasłami), lista: czas, użytkownik, tekst; wstawienie (wiele naraz), sortowanie, filtr natychmiastowy
  [NF17]; menu: wszyscy/bieżący użytkownik, Find, Copy, Delete, View, Expand/Collapse, Export CSV; limit 200 (preferencja).
- **Special Copy (25.6)**: formaty `.copy` (`<line_1>`, `<line_*>`, `<line_N>`, `#define znak = zamiennik`,
  `#define compress`) dla języków (Delphi, C++, Java, VB…). **Paste from host language (25.7)**: odwrotność.
- F1 — pomoc kontekstowa w podręcznikach Oracle (25.8, rozdz. 36); menu obiektu bazy na nazwie w edytorze (25.9, jak
  w Object Browserze); Explain Plan z zaznaczenia (25.10).
- **Makra (25.11)**: F11 nagrywanie/stop (tylko klawiatura), F12 odtwarzanie, Repeat Play (liczba powtórzeń, 0 = do
  końca pliku), Macro Library (opis, obraz, podpowiedź, w menu tak/nie, karta Keys z edycją klawiszy, skrót per makro).
- Go to line (25.12, Ctrl+G): od początku / od kursora / od początku polecenia SQL (numer linii ze stosu błędów).
- **Zakładki (25.13)**: Ctrl+K n ustawia (0–9), Ctrl+Q n przechodzi, ikona na marginesie, lista zakładek (drzewo okien
  i edytorów, nazwy zakładek, usuwanie, dokowanie — jako menu u góry/dołu).
- **Color marks (25.14)**: tło zaznaczenia w wybranym kolorze, usuwanie.
- **Code Contents (25.15)**: drzewo struktury jednostki (Program Window), śledzi kursor, hot track, klik = deklaracja,
  menu (zaznacz, wytnij, kopiuj, wklej w miejsce, zamień na komentarz, rozwiń wszystko, utwórz test dla publicznej
  jednostki), sortowanie alfabetyczne (tylko główne elementy), pokaż/ukryj.
- **Code Hierarchy (25.16)**: ścieżka struktury od kursora nad edytorem; hot track; klik zaznacza; menu (zaznacz,
  wytnij, kopiuj, wklej, usuń, komentarz/odkomentuj); podpowiedź z pierwszą linią kodu [NF17].
- **Zwijanie (25.17)**: +/− na marginesie, Fold All / Unfold All, podgląd zwiniętego po najechaniu.
- **Split editing (25.18)**: przeciągnięcie dzielnika — dwa widoki tego samego źródła.
- **Hyperlink navigation (25.19)**: Ctrl+klik na identyfikatorze (podkreślenie) → deklaracja w tym źródle, w innych
  jednostkach okna, w innych otwartych oknach, w nowym oknie (specyfikacja; prawy klik — ciało); tabela/widok:
  Ctrl+lewy = definicja, Ctrl+prawy = SQL Window z zapytaniem [NF17]; preferencja okna tylko do odczytu.
- **Navigate back/forward (25.20)**: historia skoków (Code Contents, Find, błędy kompilacji, początek/koniec, hiperłącza,
  nowe okna).
- **Refaktoryzacja (25.21)**: Rename item (deklaracja i użycia), Extract procedure (parametry z używanych zmiennych),
  Extract local constant, Extract global constant (w pakiecie), Replace assignment with initialization; cofanie Undo.
- **Search Bar (25.22)**: dokowany pasek: wszystkie edytory / bieżący / katalogi (lokalizacje File Browsera, własne
  zestawy kryteriów plików), wielkość liter, całe słowa, regex; podświetlenia, następne/poprzednie, ukryj; lista wyników
  (pliki, okna, edytory, linie), dokowalna.
- **Web Search (25.23)**: konfigurowalne wyszukiwania (opis, URL z %s, przeglądarka zewnętrzna/wewnętrzna, ponowne
  użycie okna). Od 17: „Open in VS Code” w menu edytora [NF17] (u nas: „Otwórz w…” z wyborem edytora).

## 26. Difference Viewer (UG 26, s. 282)
- Dwie kolumny z numerami linii, mapa różnic na prawym marginesie (klik, przewijanie), następna/poprzednia różnica,
  kolory: dodane zielone, usunięte czerwone, zmienione żółte, różnice w linii podkreślone; widok poziomy/pionowy, Swap,
  opcje (wielkość liter, białe znaki, komentarze, różnice w linii).

## 27. Large Data Editor (UG 27, s. 283–289)
- Dla LONG, LONG RAW, CLOB, BLOB, BFILE (i VARCHAR2): automatyczne rozpoznanie formatu, karty Text, RTF, XML, JSON,
  HTML (podgląd tylko do odczytu + edycja jako Text), Image (bmp, jpg, gif, tiff…; skalowanie podglądu, format i rozmiar;
  wklejanie zmienia format na BMP), Hex (8 kolumn słów 16-bit + tekst, edycja obu, inne układy kolumn), External
  (rozszerzenie i program, plik tymczasowy, wykrycie zapisu i import zmian, zapamiętanie skojarzenia tabela/kolumna →
  program, „Execute automatically next time”, Ctrl — wyłączenie automatu, lista zarejestrowanych typów plików).
- Pasek: Open, Save, Print, Cut, Copy, Paste, Clear (NULL), Parse/Format (XML, JSON, HTML [NF17]), Auto Format
  [NF17], Post changes, Next/Previous record; OK przenosi zmiany do siatki/zmiennej.

## 28. Query Builder (UG 28, s. 290–295)
- Nowe zapytanie w miejscu kursora lub modyfikacja istniejącego (prawy klik na SELECT — zaznacza całe polecenie).
- Lewy panel: Object Browser (tabele, widoki); obszar roboczy z tabelami (alias w oknie właściwości; dodanie tabeli
  proponuje złączenie po kluczu obcym, wizualizacja złączenia); dolne panele: Fields (+ lista INTO ze zmiennych PL/SQL
  kodu), Where (edytor tekstowy, przeciąganie kolumn, „Foreign keys” dodaje warunek), Order by (przeciąganie,
  ASC/DESC przyciskiem); karta SQL; DISTINCT; aliasy pól; synonimy (Add Table); New/Open/Save definicji, Parse,
  Preferences; OK wstawia SQL.
- Preferencje: wielkość liter słów kluczowych i elementów, wyrównanie słów kluczowych (lewo/prawo), przecinek
  przed/po, AND przed/po, prefiks właściciela, słowa kluczowe w osobnych liniach, element na linię, prawy margines,
  okno właściwości tabeli zawsze, części SQL na jednej stronie.

## 29. PL/SQL Beautifier (UG 29, s. 296–298)
- Opcje: plik reguł (domyślne), automatyczne formatowanie per typ okna: After Creating (szablon / przeciągnięty DML),
  After Loading (z pliku), Before Compiling, Before Saving.
- Reguły (edytor z podglądem na żywo, Save / Save as / Open / domyślne): Indent, Right margin, tabulacje (znak, rozmiar),
  Empty Lines (usuń i wstaw wg reguł / scal / zachowaj), Item Lists, Syntax Case (słowa kluczowe i identyfikatory,
  Special Case z wzorcami `DBA_%`), dalsze karty (DML, parametry, …).
- Użycie: przycisk lub klawisz — całe źródło albo zaznaczony kompletny fragment; błąd składni = komunikat bez zmian;
  komunikat o zakończeniu [NF17]; dyrektywy `-- NoFormat Start` / `-- NoFormat End`.

## 30. PL/SQL Clipboard (UG 30, s. 299)
- Historia kopiowanego kodu (dokowalna): lista z podglądem z podświetlaniem i czasem, dwuklik/przeciągnięcie wkleja,
  Copy to Clipboard, Paste in Editor, Delete, filtr; „Paste from PL/SQL Clipboard” w menu edytora; limity w 23.12.

## 31. Szablony (UG 31, s. 300–304)
- Template Window (dokowalny, drzewo katalogu .tpl), foldery: Constants, Default (domyślna treść okien SQL/Test/Command/
  Explain i nowego widoku), DML Statements, Loops, Package elements, PLSQL Types, Program Units (szablony nowych
  jednostek), SQL Functions, Type elements, Variables; folder [Filtered] (filtr z * ?).
- Użycie: dwuklik (formularz zmiennych), przeciągnięcie na pozycję (wcięcie), menu Templates w edytorze; Modify,
  New Template, New Folder.
- Składnia: literały, zmienne użytkownika jak w 12.3 (`&Name`, `&"…"`, `&<name=… list=… restricted=… default=…
  checkbox=…>`), wiele jednostek rozdzielonych `/`, zmienne systemowe `$OSUSER`, `$DBUSER`, `$DATE`, `$TIME`
  (`$$` = literał), pozycja kursora `[#]`, ikony z plików .bmp obok.

## 32. Window List (UG 32, s. 305–306)
- Lista otwartych okien: tytuł, status (niebieski = niezapisany, żółty = nieskompilowany, zielony = otwarta transakcja),
  wskaźnik połączenia, przypięcie, auto-odświeżanie; klik aktywuje; Shift+klik / środkowy przycisk zamyka; menu:
  aktywuj, zamknij, rozmiar, Execute, Reconnect, Rename, Short Text, New (Program/SQL/Test/Command/Explain Plan/Diagram/
  obiekt), Sort (typ/nazwa, malejąco — trwałe do ręcznego przesunięcia).

## 33–35. Narzędzia dokowane, wstążki, interfejs dokumentów (UG 33–35, s. 307–312)
- Dokowalne / pływające: Object Browser, File Browser, Connection List, Window List, Template List, Bookmark List,
  Search Bar, Search Results, To-Do Items, Project Items, PL/SQL Clipboard; dokowanie z każdej strony, karty w jednym
  obszarze, maksymalizacja obszaru, przypinanie (autoukrywanie), zamykanie (przywracanie z menu View).
- Wstążki (File, Project, Edit, Session, Debug, Tools, Reports, Configure, View, Help) + Quick Access Toolbar albo
  klasyczne menu z paskiem (jak w 11.0); własne paski narzędzi (przeciąganie komend, nazwa, styl, separatory).
- MDI (wiele okien naraz) i SDI (jedno okno na obszarze, karty okien; zamykanie kart po lewej/prawej [NF17],
  „Same for all Windows” przy zamykaniu wielu zmienionych [NF17], karty wielowierszowe [NF17]); Ctrl+Tab /
  Ctrl+Shift+Tab między oknami.

## 36. Oracle Manuals (UG 36, s. 313–315)
- Konfiguracja katalogu z podręcznikami PDF/HTML, budowa indeksu słów kluczowych, wybór książek (domyślnie SQL
  Reference, PL/SQL Reference, PL/SQL Packages and Types Reference, Database Reference), wyszukiwanie słów i tematów,
  podgląd stron, karty wyników; F1 w edytorze. U nas: wyszukiwanie w dokumentacji Oracle online/offline (decyzja w
  gap-analysis).

## 37. Dostosowanie (UG 37, s. 316–322)
- Save Layout (okno główne, narzędzia dokowane, Code Contents, rozmiary okien poszczególnych typów).
- Dokumenty w menu Tools → Documents (opis z `&`, separator `-`, program, parametry, podpowiedź, obraz).
- Parametry wiersza poleceń / params.ini: UserID, Edition, Workspace, NoLogon, OracleHome, DontAdjustPath, NoSplash,
  NoPlugIns, Library, AppDataPath, PrefPath, DefaultPrefPath, CommandFile, ViewObject, EditObject, Registry,
  SessionMode, NoSCWarning, HexEdit, Project, NoConnectionList, InstantClient, tns_admin, nls_lang, env:zmienna,
  NoCrashRecovery, NoLoadDesktop, InstanceName, ReadOnly (lista baz/wzorców), workset= (rozdz. 15). U nas: argumenty
  i schemat URL `pelikan://`, bez haseł w argumentach (§4.2 p. 6).
- Słowa kluczowe do podświetlania w pliku default.kwf (sekcje [PLSQL], [SQL], [COMMAND]).
- Wtyczki (37.6) — pominięte (§3.2).

## Domyślne skróty klawiszowe wymienione w UG 17
F1 pomoc kontekstowa · F5 Explain Plan (z zaznaczenia) · F8 Execute (także w Command Window i AI Dialog) · F11 nagrywanie
makra · F12 odtwarzanie makra · Ctrl+E Recall Statement · Ctrl+F Find & Replace · Ctrl+G Go to line · Ctrl+K n / Ctrl+Q n
zakładki · Ctrl+minus komentarz linii · Ctrl+Tab / Ctrl+Shift+Tab okna · Ctrl-/Ctrl+ szerokość Object Browsera · Ctrl+C
kopiowanie z drzew [NF17] · Tab/Shift+Tab wcięcie zaznaczenia · Alt+przeciąganie zaznaczenie kolumnowe · Ctrl+klik
hiperłącze. Pozostałe domyślne skróty (Commit, Rollback, Break, Execute current statement, debuger…) — do ustalenia
z listy Key Configuration wzorca (docs/research/keys.md, „do weryfikacji”).

## Funkcje opisane tylko w notach wersji (NF7.1–NF16), uzupełniające podręcznik
- [NF8] powiadomienie o końcu długiego zapytania; „Clear Tab Results”; czas wykonania na pasku stanu; wklejenie tekstu
  na pusty obszar tworzy SQL Window; Auto Refresh okna ponownie używa wartości zmiennych `&`.
- [NF9] połączenie na okno (selektor w lewym dolnym rogu); XLSX bez limitu wierszy; edycja komentarzy w edytorze
  tekstu; klawisz otwierający Large Data Editor z siatki; Ctrl+Del = usuń następne słowo; makra z Find/Bookmark.
- [NF10] przypinanie połączeń okien; EBR (edition w nawiasach klamrowych `{R2}` w opisie połączenia), Workspace Manager;
  `connect … edition=R2 workspace=W12` w Command Window; **Session > Set Password** (zmiana hasła w bazie i w definicji
  połączenia; także po `ALTER USER … IDENTIFIED BY`); powiadomienia e-mail zadań, łańcuchy, harmonogramy zdarzeń,
  BySetpos w DBMS Scheduler; DDL przy przeciąganiu obiektów harmonogramu; synchronizacja preferencji między instancjami;
  przeciągnięcie katalogu otwiera wszystkie pliki; niewidoczne indeksy 11g.
- [NF11] kolumny wyniku z sumami trwałe po ponownym wykonaniu; rozszerzone łańcuchy 12c (> 4000 B); identity i
  DEFAULT ON NULL; indeksy domenowe; zmiana nazwy więzów/indeksów przez ALTER … RENAME; podświetlanie kolumn przy
  wpisywaniu wartości INSERT/UPDATE; zmienne debugera sortowane; wskaźnik nowego wyjścia DBMS_OUTPUT; **SQL Monitor**
  na karcie sesji (11.2+); zmienne raportu `lines`, `editor`, `lowercase`; sortowanie Connection List; Export/Import
  wybranych sekcji preferencji; pełny ekran z dostępnymi narzędziami; „New Instance”.
- [NF12] wstążka + Quick Access Toolbar; SDI z kartami; kolor ikony per typ okna; status transakcji na pasku stanu okna;
  **wartości złożone w debugerze** (typy, rekordy, kursory), error breakpoints, zapis/odczyt punktów, nadawanie
  uprawnień DEBUG z interfejsu; Code Assistant: kolumny DML bez aliasu, podrekordy, `<All>` dla konstruktorów, synonimy;
  kolor NULL dla kolumn obowiązkowych; Copy as expression list; rozpoznawanie formatów LOB i edytor zewnętrzny;
  przejście do komórki z błędem po INSERT/UPDATE; Standard Tests; **niejawne wyniki 12c w Test Window**; zapis
  DBMS_OUTPUT do pliku; `-- Ignore`; podprogramy lokalne w Code Contents; Kill immediate; Set current schema;
  **połączenie przez proxy user**; Compare w Object Browserze.
- [NF13] Load Tester; pisanie w zaznaczeniu kolumnowym; **Ctrl +/− rozmiar czcionki** edytora i siatek; Go to line od
  początku polecenia; podświetlanie odpowiadających wartości w liście kolumn INSERT, wystąpień `tabela.kolumna`
  i pól w SELECT; klawisze zwijania, **Duplicate line**, First Character on Line; filtr Code Assistant Contains/Starts
  with; regex: `\t`, `$1`, osobna historia; filtr kolumn wyniku; Compare to… (inny plik) w SQL Window; edycja kolumn
  niewidocznych; zachowany podział okna; PL/Scope; klawisze refaktoryzacji; końcowy `/`; DBMS_OUTPUT po bloku w Program
  Window; **Set Logpoint** (punkt tylko logujący) z menu marginesu; dźwięk po długim kroku debugera; CD, DIR, ENVVAR;
  automatyczne formatowanie widoku; Beautifier w Session Window; kolumny niewidoczne 12.1; Add related tables; Test
  linku bazy; synonim w Query/Edit data; kolor wskaźnika w definicji połączenia, Connect on startup, ostrzeżenie o
  duplikacie definicji; **„Read Only” okna/pliku**; otwieranie pliku z wyborem połączenia; „Open Recovery” (ręczny
  wybór zestawu odzyskiwania) i przywracanie połączeń po awarii.
- [NF14] wbudowane Git/SVN; worksets; wewnętrzna przeglądarka różnic (z ignorowaniem komentarzy, różnice w linii);
  **podświetlanie poleceń transakcyjnych** w Program Window; Test/Describe z Code Contents dla właściwego przeciążenia;
  „Copy variable” w debugerze; „Refresh Code Assistant”; podświetlanie pasujących słów przy zaznaczeniu; zaznaczenie
  trafia do pola Find; wiele wyników naraz i ich porównanie; CLOB/BLOB na żądanie; WITH_PLSQL; EXPORT TABLES/OBJECTS
  w Command Window; CONNECT z listą baz po `@`; wszystkie przeciążenia w Object Browserze; filtr wielu nazw; Row
  Archival; Session Actions; klawisze Search Bar; zmienne `&` w listach odwołujące się do innych zmiennych.
- [NF15] motywy jasne/ciemne; połączenia tylko do odczytu; Repeat play makra; przecinek przed elementem; Comment/
  Uncomment Line (Ctrl+−); **długość zaznaczenia na pasku stanu** (`linia:kolumna [długość]`); zakładki z nazwami i
  pozycją, lista jako menu; przypinanie wyników; SQL zmian siatki; auto-odświeżanie wykresów; Column to files; JSON w
  LDE; sortowanie/filtr statystyk; Credentials i File Watchers w Scheduler; ostrzeżenie o zmianie źródła w bazie przy
  otwieraniu workseta / odzyskiwaniu; Compare User Objects: `set sqlblanklines on`, `set define off`, status wyzwalaczy,
  pomijanie sekwencji identity / logów MV; SDI: pozycja kart (góra/dół/lewo/prawo), środkowy klik zamyka; pętle 21c w
  Code Contents i Beautifierze; podkreślanie całego słowa przy błędzie w SQL/Command Window; przycisk „Reload Window”
  w przeglądarce różnic przy powiadomieniu o zmianach.
- [NF16] podręczniki PDF Oracle (F1); **zmienne wiązane w SQL Window** z tą samą składnią opcji co `&`; filtr szablonów;
  kolorowe/szare ikony; pomoc błędów Oracle Help Center; Preserve case; Pin All Result Sets; eksport SQL w trybie Batch;
  AutoReplace także po symbolach; przycisk zamknięcia na kartach Program Window; (all) w polach widoku inline; AutoSave
  Layout osobno od Desktop; Temporary CLOB/BLOB w generowanym teście; okno z błędem Oracle wysuwane na wierzch.
