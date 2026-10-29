# Prompt: natywne IDE dla Oracle PL/SQL na macOS (odpowiednik PL/SQL Developer 17) z utPLSQL i API dla agentów AI

> Prompt dla agenta programistycznego (Claude Code lub podobnego). Wklej całość jako pierwszą wiadomość w pustym katalogu projektu na Macu. Projekt jest prowadzony **w pełni autonomicznie**: nie czekaj na moje akceptacje, decyzje zapisuj w `docs/DECISIONS.md`, postęp pokazuj w raporcie HTML (sekcja 11).

---

## 0. Twoja rola i sposób pracy

Jesteś doświadczonym programistą macOS (Swift, AppKit) i Oracle (SQL, PL/SQL, słownik danych, OCI/protokół TNS). Budujesz dla mnie natywne IDE dla baz Oracle, które **wyglądem, układem i sposobem działania jak najwierniej odwzorowuje PL/SQL Developer 17** firmy Allround Automations, ale jest napisane od zera pod macOS na Apple Silicon. Dodatkowo ma wbudowane narzędzia do testów jednostkowych utPLSQL, wybrane funkcje z Oracle SQL Developer, DBeaver i DataGrip (tylko te dotyczące Oracle) oraz bezpieczne API dla agentów AI, wzorowane na moim projekcie **Bifold** (`github.com/andrzejoles/Bifold`).

Zasady pracy:

1. **Autonomia.** Pracujesz sam od analizy do wydania. Każde miejsce, w którym normalnie zapytałbyś mnie o zdanie, zastępujesz wpisem w `docs/DECISIONS.md` (data, decyzja, powód, alternatywy, jak zmienić później) i pracujesz dalej. Pierwszy wpis (D1) opisuje tę zasadę. Wyjątki, przy których się zatrzymujesz i opisujesz sprawę w raporcie jako **blokadę** (a w międzyczasie robisz inne zadania): sekcja 13.
2. **Najpierw analiza i plan, potem kod** (Etap 0). Bez pełnej inwentaryzacji funkcji wzorca nie zaczynaj implementacji.
3. **Etapy (sekcja 8).** Każdy kończy się aplikacją, której da się używać na co dzień, testami, aktualnym raportem i scalonym PR. Kolejny etap zaczynasz, gdy poprzedni spełnia kryteria odbioru, które sam sprawdziłeś testami i w działającej aplikacji (zrzuty ekranu).
4. **Gotowe, sprawdzone biblioteki zamiast własnych implementacji tam, gdzie to rozsądne** (protokół sieciowy Oracle, kryptografia, terminal, aktualizacje). Każdą zależność uzasadnij w `docs/DECISIONS.md` i wpisz do `docs/THIRD_PARTY.md` (wersja przypięta, licencja).
5. **Każda funkcja ma testy** (sekcja 9). Błąd znaleziony w trakcie: najpierw test, który go odtwarza, potem poprawka.
6. **Pamięć projektu w repozytorium.** Praca potrwa długo i przejdzie przez wiele sesji oraz kompresji kontekstu. Wszystko, co trzeba wiedzieć, żeby wznowić pracę w nowej sesji, ma być w `CLAUDE.md`, `docs/PLAN.md`, `docs/progress/status.json` i `docs/DECISIONS.md`. Na początku każdej sesji czytaj je, zanim cokolwiek zmienisz.
7. **Nie zgaduj faktów.** Zachowanie wzorca sprawdzaj w jego dokumentacji, API Oracle w dokumentacji Oracle, opcje CLI agentów w ich `--help`. Jeśli czegoś nie da się ustalić, zapisz założenie w `docs/DECISIONS.md` z oznaczeniem „do weryfikacji”.

---

## 1. Kontekst

- **Użytkownik:** ja, programista PL/SQL, na MacBooku Pro z Apple Silicon (M5 Pro), najnowszy macOS. Narzędzie do codziennej pracy z bazami Oracle (rozwój pakietów, zapytania, testy, analiza wydajności).
- **Wzorzec:** PL/SQL Developer 17.0 w wersji finalnej (Allround Automations). Uzupełnienia: Oracle SQL Developer (klasyczny desktopowy i obecny **SQL Developer for VS Code**, rozszerzenie VS Code), SQLcl, DBeaver, DataGrip, tylko w zakresie Oracle.
- **Nazwa:** `Pelikan`, bundle id `local.aoles.pelikan`, trzymana w jednym miejscu (`Config/Brand.xcconfig`, jak w Bifoldzie). Nie używaj w nazwie, ikonie ani materiałach znaków towarowych „PL/SQL Developer”, „Allround Automations” ani „Oracle” w sposób sugerujący produkt tych firm.
- **Autor** wszędzie (Info.plist, „O programie”, LICENSE, README): „Andrzej Oleś w kooperacji z Claude AI”.
- **Język interfejsu:** polski jako źródłowy, do tego en, de, es, uk (jak w Bifoldzie i CantatePresenter), wszystkie teksty w String Catalog (`Localizable.xcstrings`), kluczem jest polskie zdanie. Terminy techniczne Oracle (np. „Explain Plan”, nazwy typów obiektów) zostają tam, gdzie polski odpowiednik byłby mylący; zapisz słownik terminów w `docs/GLOSSARY.md`.
- **Prawo:** odtwarzasz układ i działanie na podstawie publicznej dokumentacji. Nie kopiuj grafik, ikon, tekstów pomocy ani kodu wzorców, nie dekompiluj ich binariów. Ikony z SF Symbols albo własne.

---

## 2. Źródła do analizy (Etap 0)

Przeczytaj i streść w `docs/research/` (z adresami URL przy każdej informacji):

1. **PL/SQL Developer** (allroundautomations.com):
   - pełna dokumentacja użytkownika (User's Guide, PDF/HTML) wersji 17.0 (finalnej),
   - nowości wersji 17.0: https://www.allroundautomations.com/products/pl-sql-developer/features/new-features-pl-sql-17-0/ (m.in. przebudowany debuger: automatyczne zmienne lokalne i globalne, rekordy i obiekty jako rozwijane elementy, `:old`/`:new` w wyzwalaczach wierszowych; obsługa `DBMS_DEBUG` i `DBMS_DEBUG_JDWP`; moduły MLE (Oracle 23ai/26ai) w oknie programu i Object Browserze; domeny 23ai w Object Browserze i edytorze tabel). Przejdź całą stronę, nie tylko te punkty,
   - strony „New features” **wszystkich wcześniejszych** wersji (z tej samej sekcji witryny, od najstarszych do 16.x), bo opis wielu funkcji jest tylko w notach wersji, w których je dodano,
   - forum producenta (forums.allroundautomations.com) tylko jako źródło pomocnicze (zachowanie w szczegółach),
   - domyślne skróty klawiszowe, menu i ustawienia (Preferences) wzorca.
2. **utPLSQL:** dokumentacja utPLSQL v3 (utplsql.org: adnotacje, `ut.run`, `ut_runner`, reportery, pokrycie kodu), oficjalna wtyczka **`github.com/utPLSQL/utPLSQL-PLSQL-Developer`** (README, kod C#, wydania; Apache 2.0) i dodatkowo **`utPLSQL-SQLDeveloper`** (generowanie testów, uruchamianie, raport na żywo, pokrycie).
3. **Oracle SQL Developer i SQLcl** (docs.oracle.com, notatki wydań): funkcje, których PL/SQL Developer nie ma. Osobno i dokładnie **SQL Developer for VS Code** (obecna, rozwijana wersja SQL Developera jako rozszerzenie VS Code): dokumentacja i noty **wszystkich** wydań (https://docs.oracle.com/en/database/oracle/sql-developer-vscode/, od 24.x do najnowszego) oraz opis w Visual Studio Marketplace (`Oracle.sql-developer`). Według not wydań m.in.: SQL Notebook z wykresami, diagramy, generowanie kodu przez przeciąganie obiektów, zarządzanie importem danych, edytory tabel, widoków i indeksów, uwierzytelnianie Kerberos i Entra ID, obsługa APEXlang. Ustal pełną listę i zaznacz, czym różni się od klasycznego SQL Developera.
4. **DBeaver i DataGrip:** funkcje dla Oracle, których nie mają PL/SQL Developer ani SQL Developer.
5. **Bifold** (`github.com/andrzejoles/Bifold`, publiczne): `docs/PROMPT.md`, `docs/ARCHITECTURE.md` (sekcje 4, 7, 8: rejestr komend, uprawnienia, przepływ wywołania agenta), `docs/SECURITY.md`, `docs/DECISIONS.md` (D17–D23: most MCP, token, konfiguracja MCP na sesję dla każdego CLI), `docs/WYDANIA.md`, `scripts/version.sh`, `scripts/release.sh`, `scripts/signing.sh`, `Makefile`, `CLAUDE.md`. Przenieś sprawdzone rozwiązania, nie wymyślaj ich od nowa.

**Wynik Etapu 0:** `docs/FEATURES.md`, czyli macierz funkcji. Każdy wiersz: identyfikator (np. `PD-SQLW-012`, `SD-…`, `DB-…`, `DG-…`, `UT-…`, `AI-…`), funkcja, źródło (URL), okno lub menu wzorca, etap, priorytet, poziom dostępu agenta (sekcja 7.4), stan (do zrobienia / w toku / ✅ test / 👁 sprawdzone ręcznie / ⚠️ bez weryfikacji, z powodem). Z tej macierzy liczony jest postęp w raporcie.

---

## 3. Zakres funkcji

### 3.1 PL/SQL Developer: wszystkie funkcje wbudowane

Odwzoruj **wszystkie funkcje wersji 17**, które są częścią standardowej instalacji. Lista poniżej to punkt wyjścia; pełna lista powstaje w Etapie 0.

- **Połączenia:** lista połączeń z folderami i kolorami (kolor okna/paska wg połączenia, np. produkcja na czerwono), wiele połączeń naraz, osobne połączenie dla każdego okna, połączenie główne, TNS (`tnsnames.ora`, `sqlnet.ora`, `TNS_ADMIN`), EZConnect, LDAP, wallet (mTLS, Autonomous Database), uwierzytelnianie systemu (Kerberos, jeśli wybrany sterownik je obsługuje), role SYSDBA/SYSOPER, proxy user, zmiana wygasłego hasła, NLS sesji.
- **Okna:** SQL Window (siatka wyników z dociąganiem, wiele wyników, edycja i Query By Example, eksport, zapytania powiązane, zmienne podstawiania i bind), Program Window (specyfikacja i ciało w kartach, kompilacja, lista błędów, przejście do błędu), Test Window (blok PL/SQL ze zmiennymi, `DBMS_OUTPUT`, statystyki, debuger, profiler), Command Window (zgodność z SQL*Plus: `SET`, `SPOOL`, `@`/`@@`, `DEFINE`, `PROMPT`, `PAUSE`, edytor skryptu), Explain Plan Window, Report Window, Diagram Window, Query Builder, okna opisu obiektów i edytory tabel, widoków, sekwencji, użytkowników, ról, synonimów, typów, jobów itd.
- **Object Browser:** foldery wg typów (także moduły MLE i domeny 23ai/26ai), własne foldery i filtry, menu kontekstowe (Wyświetl, Edytuj, Usuń, Właściwości, Kompiluj, Szablony, Zapytanie, Opis, DDL), obiekty niepoprawne, przeciąganie nazw i szablonów do edytora.
- **Edytor:** podświetlanie składni, Code Assistant (podpowiedzi kolumn, parametrów, pakietów, aliasów), Code Contents i hierarchia, nawigacja hiperłączem do deklaracji, zwijanie, zakładki, makra (nagrywanie i odtwarzanie), szablony, PL/SQL Beautifier z regułami, refaktoryzacja (zmiana nazwy, wydzielanie), znajdź i zamień z regex, porównanie, wiele kursorów, jeśli jest we wzorcu.
- **Debuger:** punkty przerwania (warunkowe), krokowanie, zmienne lokalne i globalne, rekordy, kolekcje i obiekty jako drzewo, `:old`/`:new` w wyzwalaczach, stos wywołań, obserwowane wyrażenia, wyjątki; oba mechanizmy `DBMS_DEBUG` i `DBMS_DEBUG_JDWP` (jak w wersji 17). Na każdej wersji bazy sprawdź, który jest dostępny.
- **Narzędzia:** Session Browser (z zapytaniami definiowanymi przez użytkownika), Compare User Objects, Compare Table Data, Export User Objects, Export/Import Tables (SQL Inserts, format własny, `expdp`/`impdp` przez `DBMS_DATAPUMP`), Text Importer, Data Generator, Event Monitor (`DBMS_ALERT`, `DBMS_PIPE`, `DBMS_OUTPUT`), DBMS Scheduler, Find Database Objects, Recompile Invalid Objects, profiler PL/SQL i profiler hierarchiczny, statystyki sesji, raporty, historia poleceń (Recall Statement), projekty, układy okien (desktops), lista okien, wyszukiwarka komend.
- **Transakcje:** domyślnie bez auto-commita, przyciski Commit/Rollback, ostrzeżenie o niezatwierdzonej transakcji przy zamykaniu okna i aplikacji, tryb wielu sesji jak we wzorcu.
- **Ustawienia:** odpowiedniki Preferences wzorca, z profilami eksportowanymi do pliku.

### 3.2 Wyłączone

- **Wtyczki i dodatki instalowane osobno** (pluginy z katalogu PlugIns, dodatki do pobrania). Sam mechanizm wtyczek też pomiń (decyzja w `docs/DECISIONS.md`), ale architektura (rejestr komend, sekcja 4) nie może utrudniać dodania go później.
- **Wszystkie funkcje AI wzorców:** AI Assistant z PL/SQL Developer (w tym obsługa GitHub Copilot CLI z wersji 17), Select AI i asystenci z SQL Developer, serwer MCP SQLcl i funkcje AI z SQL Developer for VS Code, AI Assistant z DataGrip, AI z DBeaver. Zamiast nich jest wbudowana obsługa agentów jak w Bifoldzie (sekcja 7).
- Wszystko, co dotyczy baz innych niż Oracle (migracje z innych baz, sterowniki innych baz).
- Funkcje Windows bez sensu na macOS (rejestr Windows, COM, ODBC Importer, chyba że w Etapie 0 uzasadnisz, że ODBC na macOS ma sens).

### 3.3 Dodatki z SQL Developer / SQLcl, DBeaver i DataGrip (tylko Oracle)

W Etapie 0 zrób porównanie i zapisz w `docs/research/gap-analysis.md`, czego nie ma w PL/SQL Developer. Kandydaci do sprawdzenia (bierz te, które faktycznie występują we wzorcach i których brakuje w PL/SQL Developer):

- **SQL Developer for VS Code:** SQL Notebook (komórki SQL i Markdown, wyniki i wykresy zapisywane w pliku), diagramy, generowanie kodu przez przeciąganie obiektów do edytora, kreator importu danych, uwierzytelnianie Entra ID (dla Oracle na Azure), APEXlang (jeśli w Etapie 0 uznasz to za przydatne bez instalowania APEX), wszystko inne z not wydań, czego brak w PL/SQL Developer.
- **SQL Developer / SQLcl:** Real-Time SQL Monitoring, panel DBA (przestrzenie tabel, użytkownicy, parametry, sesje, blokady), raporty AWR/ASH/ADDM, SQL Tuning Advisor, porównanie planów, Autotrace ze statystykami, Instance Viewer, Database Diff i Cart (pakiet zmian do wdrożenia), Data Pump i kopiowanie bazy w kreatorach, generowanie dokumentacji schematu, podgląd i edycja JSON/XML/przestrzennych, polecenia SQLcl (`INFO`, `DDL`, `LOAD`, `FORMAT`, `SET SQLFORMAT`, `HISTORY`, Liquibase `lb`), snippets, ORDS (REST) dla schematu.
- **DBeaver:** tunel SSH do bazy (ważne na Macu), diagramy ER z bazy, panel wartości (JSON, XML, obraz z BLOB, hex), filtrowanie i grupowanie wyników w siatce, przenoszenie danych między tabelami i schematami, porównanie wyników, wykresy z wyników, zaplanowane zadania.
- **DataGrip:** rozwiązywanie nazw w czasie pisania (podkreślanie nieznanych obiektów i kolumn), inspekcje kodu (nieużywane zmienne, nieosiągalny kod, niejawne konwersje), Find Usages, refaktoryzacja z podglądem, lokalna historia plików i obiektów, edycja danych ze zmianami oczekującymi i podglądem SQL przed zapisem, przypinanie wyników, konsole zapytań na połączenie, cache metadanych z odświeżaniem w tle, uruchamianie z parametrami.

**Licencje Oracle:** AWR, ASH, ADDM, SQL Monitoring i Tuning Advisor wymagają Diagnostics/Tuning Pack. Przed pierwszym użyciem na danym połączeniu pokaż ostrzeżenie licencyjne i zapamiętaj zgodę na połączeniu (`CONTROL_MANAGEMENT_PACK_ACCESS`). Agent AI nigdy nie uruchamia tych funkcji.

### 3.4 Optymalizacja pod macOS

- Natywny AppKit: okna, karty (natywne karty macOS albo karty dokumentów jak we wzorcu; wybór uzasadnij), pełny ekran, tryb ciemny i jasny, menu wg Apple HIG, a jednocześnie układ paneli i okien jak we wzorcu (lista okien, Object Browser po lewej, paski narzędzi).
- **Dwa profile klawiatury:** zgodny z PL/SQL Developer (F-klawisze i Ctrl jak we wzorcu, z zamiennikami dla klawiatury MacBooka: brak Insert, Home/End przez fn) oraz profil macOS (Cmd). Konfigurowalne skróty.
- Hasła w Pęku kluczy, odblokowanie zapisanych haseł Touch ID (opcja), pliki `.sql`, `.pks`, `.pkb`, `.pck`, `.tst` otwierane z Findera, Quick Look dla tych plików, usługi macOS, przeciąganie plików.
- Wydajność: arm64, Swift concurrency, nic blokującego na wątku głównym, siatka wyników płynna przy milionach wierszy (dociąganie stronami, przewijanie bez zacięć), podświetlanie i Code Assistant bez opóźnień w pakiecie z 50 000 linii.

---

## 4. Stos technologiczny i architektura

### 4.1 Stos (do potwierdzenia w ADR w Etapie 0)

| Obszar | Wybór / do rozstrzygnięcia |
|---|---|
| Język | Swift 6, ścisła współbieżność |
| Interfejs | AppKit dla okna głównego, edytora, siatki i drzew; SwiftUI dla ustawień i prostych okien |
| Platforma | najnowszy macOS, tylko arm64 |
| Projekt | Xcode + SPM, projekt generowany XcodeGen (`project.yml`, jak w Bifoldzie). Logika w pakietach SPM testowalnych bez interfejsu |
| **Dostęp do Oracle** | **Dwa sterowniki, wybierane w ustawieniach każdego połączenia** (decyzja właściciela): (a) **domyślny i priorytetowy: ODPI-C + Oracle Instant Client dla macOS ARM64** (tryb „thick”: pełne OCI, starsze bazy, Kerberos, wszystkie typy); (b) **alternatywny: OracleNIO** (`lovetodream/oracle-nio`, sterownik „thin” w czystym Swifcie na SwiftNIO, bez Instant Client; sprawdź dojrzałość, wydania i obsługiwane funkcje). Oba za wspólnym protokołem `DatabaseSession` (4.2 p. 2), żadne okno ani narzędzie nie zależy od konkretnego sterownika. Najpierw pełna implementacja Instant Client, potem thin. W ADR macierz możliwości obu: wersje baz (cel: 19c, 21c, 23ai/26ai; 12.2 i starsze wg możliwości), `DBMS_DEBUG`/JDWP, LOB, typy obiektowe i kolekcje, REF CURSOR, `DBMS_OUTPUT`, przerwanie zapytania (break), wallet/mTLS, Kerberos, proxy user, zmiana hasła, wydajność pobierania. Funkcja niedostępna w wybranym sterowniku jest w interfejsie wyszarzona z wyjaśnieniem i podpowiedzią „przełącz na Instant Client”. Instant Client: wykrywanie (ścieżka konfigurowalna, domyślnie lokalizacja z Homebrew/pobrania), ekran pomocy przy braku, a dołączanie go do pakietu tylko wtedy, gdy licencja Oracle na to wyraźnie pozwala (ustal i zapisz w ADR) |
| Parser SQL/PL/SQL | ADR: własny tolerancyjny lekser i parser zstępujący z przyrostowym leksowaniem (zalecane dla edytora), gramatyka `PlSqlParser` z `antlr/grammars-v4` jako źródło wiedzy i korpusu testów |
| Edytor | ADR: TextKit 2 (własny widok albo np. STTextView) vs własny renderer. Wymagania: duże pliki, zwijanie, wiele kursorów, marginesy z punktami przerwania i pokryciem testami |
| Siatka wyników | ADR: `NSTableView` vs własny widok; miliony wierszy, setki kolumn, edycja w miejscu, zaznaczanie bloków |
| Terminal (panele agentów) | SwiftTerm |
| Aktualizacje | Sparkle 2 (jak Bifold), kanał `releases/latest/download/appcast.xml` |
| Agenci AI | serwer MCP w aplikacji + most stdio↔gniazdo Unix (jak Bifold D17) |
| Testy | Swift Testing, XCUITest dla interfejsu |

### 4.2 Zasady, których nie wolno łamać

1. **Rejestr komend** (jak Bifold): każda czynność to komenda z identyfikatorem, nazwą, skrótem, parametrami, funkcją wykonującą, **poziomem dostępu agenta** i opisem skutków (podgląd przed wykonaniem). Menu, paski narzędzi, skróty, wyszukiwarka komend i API agenta wywołują te same komendy. Plik `docs/SKROTY.md` generowany z rejestru.
2. **Warstwa bazy danych za protokołem** (`DatabaseSession`, `MetadataProvider`, `Debugger`, `TestRunner`), bez AppKit, budowana i testowana także na Linuksie (CI z bazą Oracle w kontenerze, sekcja 9).
3. **Stan aplikacji jako model:** okna, połączenia, sesje, transakcje, zawartość edytorów i zaznaczenie w jednym modelu, z którego czytają interfejs i API agenta.
4. **Długie operacje poza wątkiem głównym, zawsze z przerwaniem** (Break, jak we wzorcu): zapytania, kompilacja, eksport, porównania, testy.
5. **Metadane z cache** odświeżanego w tle; edytor i Code Assistant nie czekają na sieć.
6. **Bezpieczeństwo danych:** hasła tylko w Pęku kluczy (nigdy w plikach, logach, argumentach procesów, zmiennych środowiskowych ani w raporcie), połączenia oznaczone środowiskiem (dev/test/prod) z ostrzeżeniami przy zmianach na prod.

---

## 5. Kluczowe zachowania do wiernego odwzorowania

Opisz w `docs/research/behaviour.md` i pokryj testami: dzielenie skryptu na polecenia (`;`, `/`, bloki PL/SQL, `CREATE OR REPLACE` z ciałem), który fragment wykonuje się przy zaznaczeniu i bez niego, zmienne `&` i `:bind` (okno pytania o wartości), zachowanie siatki (dociąganie, „pobierz wszystkie”, edycja z `ROWID`/kluczem, blokada `FOR UPDATE`), kompilacja z ostrzeżeniami `PLSQL_WARNINGS`, `DBMS_OUTPUT` (bufor, limit), Code Assistant (kiedy się otwiera, co podpowiada), domyślne ustawienia NLS i formaty dat w siatce, zachowanie przy utracie połączenia (ponowne połączenie, informacja o utraconej transakcji).

---

## 6. utPLSQL: testy jednostkowe

### 6.1 Co ma oficjalna wtyczka (minimum)

Na podstawie `utPLSQL-PLSQL-Developer`: przyciski uruchomienia wszystkich testów bieżącego użytkownika, testów ze wskazanej ścieżki (`schemat.pakiet.procedura`, `:ścieżka.suity`) i pokrycia kodu; menu kontekstowe w Object Browserze (testy lub pokrycie dla pakietu, procedury, użytkownika); okno wyników z drzewem suit, czasami, błędami, filtrem statusu (od wersji 1.1.0) i raportem pokrycia. Sprawdź w kodzie wtyczki, jak wywołuje utPLSQL (reportery, odczyt wyników), i odwzoruj to działanie natywnie.

### 6.2 Rozszerzenia (wbudowane, nie jako wtyczka)

- **Eksplorator testów:** drzewo suit, kontekstów i testów z bazy (`ut_runner.get_suites_info`), odświeżane po kompilacji, z ostatnim wynikiem przy każdym elemencie.
- **Uruchamianie:** z eksploratora, z edytora (test lub suita pod kursorem, cały pakiet), ponowne uruchomienie nieudanych, uruchomienie z debugerem, przerwanie. Wyniki na żywo przez `ut_realtime_reporter` (postęp, licznik, aktualny test).
- **Wyniki:** oczekiwane i otrzymane z porównaniem, `DBMS_OUTPUT` testu, stos błędu z przejściem do linii w kodzie, historia uruchomień i porównanie dwóch uruchomień.
- **Pokrycie kodu:** zaznaczenie pokrytych i niepokrytych linii na marginesie edytora, procent dla obiektu i schematu, raport HTML (`ut_coverage_html_reporter`), eksport Cobertura/Sonar; ostrzeżenie, że pokrycie wymaga uprawnień i zbiera dane profilera.
- **Pisanie testów:** generowanie szkieletu pakietu testowego ze specyfikacji testowanego pakietu (po jednym teście na procedurę/funkcję, z adnotacjami `--%suite`, `--%test`, `--%beforeall` itd.), szablony, Code Assistant dla adnotacji `--%` i dla matcherów (`ut.expect(...).to_equal(...)` itd.), sprawdzanie poprawności adnotacji przy kompilacji, przejście między pakietem a jego testem.
- **Instalacja i wersja:** wykrycie utPLSQL i jego wersji w bazie (`ut_runner.version`), instalacja lub aktualizacja z oficjalnego wydania tylko na połączeniach oznaczonych jako dev/test i tylko po potwierdzeniu przeze mnie w aplikacji.
- **CI:** eksport wyników w formatach JUnit, Sonar, TeamCity i skrypt do uruchamiania tych samych testów z wiersza poleceń.

Weryfikuj API z dokumentacją aktualnej wersji utPLSQL; w testach integracyjnych instaluj utPLSQL w bazie testowej (sekcja 9).

---

## 7. Integracja z agentami AI (jak w Bifoldzie)

Przenieś model z Bifolda (`docs/PROMPT.md` sekcja 5, `docs/ARCHITECTURE.md` sekcje 7–8, `docs/SECURITY.md`, `docs/DECISIONS.md` D17–D23) i dostosuj go do bazy danych.

### 7.1 Agenci i panel agenta

- Oficjalne CLI jako osobne procesy: **Claude Code** (`claude`), **Codex CLI** (`codex`), **Grok CLI** (`grok`), **Antigravity** (`agy`), z listą konfigurowalną, żeby dało się dodać kolejne. Aplikacja nigdy nie widzi tokenów ani subskrypcji dostawców i nie wywołuje ich API bezpośrednio.
- Serwer MCP podawany **tylko dla jednej sesji** (Bifold D21: `--mcp-config … --strict-mcp-config`, `-c mcp_servers.…`, `GROK_CONFIG`, a dla `agy` trwała rejestracja za zgodą). Opcje sprawdź ponownie w `--help` aktualnych wersji.
- Panel agenta: terminal SwiftTerm z natywnym interfejsem CLI wewnątrz okna aplikacji + panel aktywności (każde wywołanie narzędzia: parametry, wynik, czas, decyzja) + oczekujące prośby o zgodę. Katalog roboczy agenta to folder projektu (jak „Projects” we wzorcu) albo katalog tymczasowy sesji.
- Przy starcie krótka instrukcja o dostępnych narzędziach (np. `--append-system-prompt`).

### 7.2 Bezpieczeństwo kanału (obowiązkowe, jak w Bifoldzie)

Most `pelikan-mcp` (stdio ↔ gniazdo Unix `0600` w katalogu `0700`, **żadnych portów TCP**), token sesji 256 bit tylko w środowisku procesu CLI, porównanie w stałym czasie, weryfikacja UID (`getpeereid`) i drzewa procesów (`LOCAL_PEERPID`), unieważnienie po zamknięciu sesji, tryb ścisły (CLI bez własnej powłoki i edycji plików, np. `--tools ""` + `--allowedTools mcp__pelikan__*`, `--sandbox read-only`), wyraźne ostrzeżenie, gdy danego CLI nie da się ograniczyć, limit wywołań na minutę.

### 7.3 Zasady specyficzne dla bazy danych

1. **Agent widzi połączenia tylko pod aliasem** i ze znacznikiem środowiska (dev/test/prod). Nigdy: hasła, wallet, host, port, nazwa usługi, użytkownik systemu operacyjnego.
2. **Agent ma własną sesję bazy na danym połączeniu** (nie moją), z nazwą `MODULE`/`ACTION` pozwalającą ją rozpoznać w Session Browserze. Moja niezatwierdzona transakcja nigdy nie jest widoczna ani dotykana przez agenta.
3. **Klasyfikacja poleceń parserem** (zapytanie, DML, DDL, PL/SQL, kontrola transakcji, `ALTER SESSION/SYSTEM`) przed wykonaniem. Polecenie nierozpoznane = najwyższa kategoria ryzyka.
4. **Odczyt** = tylko `SELECT`/`WITH` w transakcji `READ ONLY`, z limitem wierszy, czasu i rozmiaru wyniku. Opisz w `docs/SECURITY.md`, że funkcje wywoływane w zapytaniu mogą mieć skutki uboczne (transakcje autonomiczne), więc twardą granicą są uprawnienia użytkownika bazy. W ustawieniach połączenia pozwól wskazać **osobnego użytkownika bazy dla agenta** (np. proxy user z samymi grantami odczytu) i zalecaj to dla prod.
5. **Zmiany** (DML, DDL, kompilacja, `EXECUTE` bloku): podgląd przed zgodą: pełny tekst polecenia, obiekty, na które wpływa (zależności z `ALL_DEPENDENCIES`), plan wykonania i szacunek liczby wierszy dla DML. DML po wykonaniu zostaje **niezatwierdzone** do mojej osobnej zgody na COMMIT (podgląd liczby zmienionych wierszy), domyślnie ROLLBACK przy zamknięciu sesji agenta.
6. **Przed każdą zmianą kodu obiektu** (DDL na pakiecie, procedurze, widoku, wyzwalaczu, typie) zapisz poprzednią wersję DDL do lokalnej historii, żeby „Cofnij sesję agenta” mogło przywrócić kod (z wykrywaniem konfliktu, gdy obiekt zmienił się później). Zmian danych po COMMIT i DDL na tabelach nie da się cofnąć: okno zgody mówi to wprost.
7. **Dane z bazy są niezaufane** (wyniki zapytań, kod źródłowy, komentarze, nazwy obiektów): oznaczone w odpowiedzi (`untrusted_content`). Uprawnienia egzekwuje aplikacja, nigdy treść promptu ani dane.
8. **Na połączeniach prod** domyślnie tylko metadane i odczyt; zmiany wyłączone (włączam ręcznie dla konkretnego połączenia). Opcjonalne maskowanie wskazanych kolumn (np. PESEL, e-mail) w wynikach dla agenta.
9. Agent nie ma dostępu do terminala, Command Window ani poleceń systemu operacyjnego (`HOST`, `!`).

### 7.4 Poziomy dostępu

Jak w Bifoldzie: **Brak** (narzędzie niewidoczne), **Odczyt**, **Za zgodą** (podgląd na sucho + okno zatwierdzania bez przycisku domyślnego, „Zatwierdź” aktywne po 0,8 s, Esc odrzuca, jak Bifold D23), **Pełny** (bez pytania, z dziennikiem i cofaniem, tylko tam, gdzie da się cofnąć). Zasada najmniejszego poziomu: efektywny poziom = min(poziom komendy, ustawienie sesji, poziom połączenia/środowiska). Macierz uprawnień na sesję, edytowalna przy starcie agenta.

### 7.5 Narzędzia MCP (propozycja, dopracuj w ARCHITECTURE.md)

Odczyt: `list_connections`, `get_state` (okna, aktywne połączenie, otwarte obiekty), `get_editor` (treść, zaznaczenie, kursor, błędy kompilacji), `search_objects`, `describe_object`, `get_source`, `get_ddl`, `get_dependencies`, `find_usages`, `run_query`, `explain_plan`, `get_compile_errors`, `get_dbms_output`, `list_tests`, `get_test_results`, `get_coverage`, `session_list`.
Pełny (zmiany tylko w aplikacji, cofalne): `open_object`, `open_editor`, `insert_text`, `replace_range` (zmienia tekst w edytorze, bez kompilacji), `format_code`, `navigate_to`.
Za zgodą: `compile`, `execute_statement`, `execute_script`, `commit`, `rollback`, `create_test_package`, `run_tests` (na dev może być Pełny), `generate_test_skeleton` (zapis do bazy), `install_utplsql` (tylko dev/test), `run_command` (dowolna komenda z rejestru, najwyżej „Za zgodą”, jak Bifold D20).
Brak: wszystko, co dotyka haseł, połączeń, Command Window, `HOST`, AWR/ASH/Tuning Pack, eksportu danych do plików poza projektem.

### 7.6 Dziennik i cofanie

Dziennik każdego wywołania (JSONL w katalogu danych aplikacji): czas, agent, narzędzie, parametry (bez danych wrażliwych), decyzja, wynik, czas wykonania. Przeglądarka dziennika w aplikacji. „Cofnij sesję agenta”: zmiany w edytorach, przywrócenie kodu obiektów z historii, ROLLBACK niezatwierdzonych zmian, z podglądem i wykrywaniem konfliktów.

---

## 8. Etapy

Każdy etap: lista zadań w `docs/PLAN.md`, kryteria odbioru, testy, zrzuty ekranu, PR(y) scalone, aktualny raport, szkic wydania na GitHubie (sekcja 10). Kolejność możesz zmienić, jeśli Etap 0 wykaże lepszą (uzasadnij w DECISIONS).

| Etap | Zakres | Kryteria odbioru (przykłady) |
|---|---|---|
| **0. Analiza i fundament** | Źródła z sekcji 2, `docs/FEATURES.md`, `gap-analysis.md`, `behaviour.md`, ADR (macierz możliwości obu sterowników, parser, edytor, siatka), `ARCHITECTURE.md`, `SECURITY.md`, `PLAN.md`, repozytorium na GitHubie, CI, baza testowa w kontenerze z utPLSQL, szkielet aplikacji (okno, rejestr komend, menu), generator raportu postępów | Raport HTML działa i pokazuje macierz funkcji; CI zielone; `make test` łączy się z bazą testową |
| **1. Połączenia, SQL Window, Command Window** | Sterownik Instant Client (ODPI-C), potem sterownik thin (OracleNIO) i wybór sterownika w połączeniu, menedżer połączeń (Pęk kluczy, TNS, EZConnect, wallet, tunel SSH), sesje i transakcje, edytor z podświetlaniem, dzielenie skryptów, siatka wyników z dociąganiem i edycją, zmienne `&`/`:bind`, `DBMS_OUTPUT`, eksport wyników, Command Window (podstawowe polecenia SQL*Plus), historia poleceń, przerwanie zapytania, profil klawiatury | Codzienna praca z zapytaniami tylko z klawiatury; 1 mln wierszy przewijany płynnie; brak blokad UI przy długim zapytaniu |
| **2. Object Browser i Program Window** | Object Browser (wszystkie typy, filtry, foldery, MLE, domeny), okna opisu i edytory obiektów, Program Window z kompilacją i błędami, Code Assistant, Code Contents, nawigacja, szablony, Beautifier, wyszukiwanie obiektów, rekompilacja niepoprawnych | Edycja i kompilacja pakietu 50 000 linii bez opóźnień w pisaniu |
| **3. Test Window, debuger, profiler** | Test Window, debuger (`DBMS_DEBUG` i `DBMS_DEBUG_JDWP`, funkcje wersji 17), profiler i profiler hierarchiczny, statystyki | Krokowanie przez pakiet z wyzwalaczem, podgląd rekordu i kolekcji, test integracyjny debugera na bazie testowej |
| **4. utPLSQL** | Sekcja 6 w całości | Wygenerowany szkielet testu kompiluje się, testy uruchamiają się z eksploratora i edytora, pokrycie widać na marginesie |
| **5. Agenci AI** | Sekcja 7 w całości | Każdy z czterech agentów czyta stan i obiekty; operacje „Za zgodą” czekają na decyzję; testy: połączenie bez tokenu, z błędnym tokenem i spoza drzewa procesów odrzucone; narzędzia „Brak” niewidoczne; agent nie widzi danych logowania; DML agenta nie jest zatwierdzane bez zgody; cofnięcie sesji przywraca kod obiektów |
| **6. Narzędzia** | Explain Plan, Session Browser, porównania obiektów i danych, eksport/import, Text Importer, Data Generator, Event Monitor, Scheduler, raporty, Query Builder, diagramy, projekty, układy okien, makra | Każde narzędzie z macierzy ma test lub zrzut ekranu |
| **7. Dodatki z SQL Developer, DBeaver, DataGrip** | Wybrane w `gap-analysis.md` | Jak wyżej |
| **8. Dopracowanie i wydanie** | Audyt zgodności z macierzą (każdy wiersz z oceną), wydajność, dostępność (VoiceOver), tłumaczenia, instrukcja użytkownika w aplikacji, instalatory DMG i PKG, Sparkle, `docs/STATUS.md` z listą ograniczeń | Macierz bez wierszy „do zrobienia” albo z uzasadnieniem pominięcia |

---

## 9. Testy i środowisko testowe

- **Baza testowa:** Oracle Database Free (23ai/26ai) w kontenerze na Apple Silicon (obraz arm64, np. `gvenzl/oracle-free` albo oficjalny z container-registry.oracle.com; środowisko kontenerów: Colima, OrbStack lub Docker Desktop, wybór w ADR, instalacja przez Homebrew). Skrypt `scripts/testdb.sh up|down|reset|seed` tworzy schematy testowe, przykładowe pakiety (także z błędami kompilacji, wyzwalaczami, typami obiektowymi, kolekcjami, LOB-ami, modułami MLE, domenami) i instaluje utPLSQL. Starszych wersji (19c i wcześniejszych) nie ma na arm64: zapisz to w ograniczeniach, a zgodność z nimi zapewnij zapytaniami słownika danych odpornymi na brak kolumn i widoków.
- **Testy nigdy nie łączą się z bazami spoza środowiska testowego** i nie czytają prawdziwych danych aplikacji (katalog danych wstrzykiwany, jak `CANTATE_DATA_DIR` / `Workspace(persists: false)`).
- **Rodzaje testów:** jednostkowe (lekser, parser, dzielenie skryptów, klasyfikacja poleceń, formatowanie, Beautifier, zmienne podstawiania, polityka uprawnień agenta, generator szkieletów testów), integracyjne z bazą (metadane, kompilacja, siatka, debuger, utPLSQL, transakcje, przerwanie, utrata połączenia), bezpieczeństwa (most MCP, tokeny, drzewo procesów, brak haseł w logach i odpowiedziach agenta), interfejsu (XCUITest, zrzuty ekranu każdego okna do raportu), wydajności w konfiguracji Release (siatka, edytor, otwieranie dużego pakietu, Object Browser ze 100 000 obiektów), E2E z prawdziwymi CLI agentów (opcjonalne, uruchamiane lokalnie, jak `AgentE2ETests` w Bifoldzie).
- **Oba sterowniki w testach:** testy integracyjne warstwy bazy są sparametryzowane sterownikiem i przechodzą na obu (poza funkcjami, których thin nie obsługuje; te mają test sprawdzający czytelny komunikat zamiast awarii). W CI na Linuksie Instant Client dla Linuksa.
- **Korpus PL/SQL:** przykłady z dokumentacji Oracle, testy gramatyki `grammars-v4` i własne przypadki brzegowe; parser nie może się wywrócić na żadnym pliku (fuzzing).
- `make test`, `make test-integration`, `make test-release` (interfejs — zrzuty w tle `scripts/screenshots.sh`, D113, D196). Przed każdym PR uruchamiasz wszystkie, które da się uruchomić lokalnie.

---

## 10. Git, GitHub, CI, wersje i wydania (jak w Bifoldzie)

- **Repozytorium:** `github.com/andrzejoles/Pelikan` na moim koncie (użyj zalogowanego `gh`), publiczne, licencja MIT (jak Bifold; wymagają tego automatyczne aktualizacje z GitHub Releases). Przed każdym commitem sprawdź, że nic nie zawiera haseł, kluczy, adresów baz, ścieżek domowych ani danych z `~/Library`.
- **Praca ciągła:** commit po każdym logicznym kroku (konwencjonalne prefiksy po angielsku z identyfikatorem z macierzy, np. `feat(sqlwin): fetch rows in pages (PD-SQLW-004)`), push gałęzi po każdym commicie. Gałąź na zadanie lub podetap (`etap-1/siatka-wynikow`).
- **PR:** co najmniej jeden na podetap, mały i spójny; opis: co zrobione, identyfikatory z macierzy, jak przetestowano, zrzuty ekranu. Przed scaleniem krytycznie przejrzyj własny diff (albo użyj `/code-review`, jeśli jest dostępne), popraw znalezione błędy.
- **Scalanie samodzielne:** gdy CI jest zielone, scal PR zwykłym **„Merge pull request”** (`gh pr merge --merge --delete-branch`), **nigdy squash ani rebase**, bo wersja liczy się ze scalonych PR. Czerwone CI naprawiasz, nie omijasz (bez wyłączania testów, bez pustych commitów). Nigdy nie wypychaj bezpośrednio na `main` i nie przepisuj jego historii.
- **Wersja:** `scripts/version.sh` jak w Bifoldzie/CantatePresenter: `(1 + PR/10).(PR mod 10).(commity od ostatniego scalonego PR)`, numer kompilacji = liczba commitów; nigdzie nie wpisuj wersji ręcznie. CI z `fetch-depth: 0`.
- **CI (GitHub Actions):** zadanie macOS (najnowszy Xcode runnera): budowanie, testy jednostkowe, budowanie `.app` i weryfikacja podpisu; zadanie Linux z bazą Oracle Free jako kontener usługi: testy warstwy bazy danych i utPLSQL (dlatego warstwa bazy jest bez AppKit). Status CI widoczny w raporcie.
- **Podpis i wydania:** jak Bifold: stały podpis własnym certyfikatem (`scripts/signing.sh`), bez notaryzacji i bez konta Apple Developer (nie proponuj zakupu); instalatory DMG i PKG (`make installer`); Sparkle z kluczem EdDSA w Pęku kluczy; `scripts/release.sh` tworzy na koniec każdego etapu **szkic** wydania (publikuję go ja).

---

## 11. Raport postępów w HTML (na bieżąco)

Chcę otworzyć raport w przeglądarce i po odświeżeniu widzieć aktualny stan.

- **Źródło danych:** `docs/progress/status.json` (aktualizowany przez Ciebie) + historia gita + wyniki testów + macierz `docs/FEATURES.md`. **Generator:** `scripts/progress.py` (Python 3, sama biblioteka standardowa) tworzy jeden samodzielny plik `docs/progress/index.html` (CSS i obrazy osadzone lub względne, **bez zasobów z internetu**), commitowany razem ze zmianami.
- **Stała lokalizacja:** generator kopiuje raport także do `~/Pelikan-raport/index.html` (z katalogiem `img/`), niezależnie od gałęzi i worktree. W pierwszej wiadomości podaj mi ten adres (`file:///Users/…/Pelikan-raport/index.html`). Strona odświeża się sama co 30 s (`<meta http-equiv="refresh">`), a ręczne odświeżenie zawsze pokazuje najnowszy stan. Jeśli pracujesz w chmurze (nie na moim Macu), publikuj ten sam raport jako stronę, którą mogę otworzyć (np. artefakt claude.ai pod stałym adresem albo GitHub Pages z `main`), i podaj mi adres.
- **Kiedy aktualizować:** po każdym zakończonym zadaniu, przy każdym commicie, przy każdej blokadzie i co najmniej co 30 minut pracy (pole „ostatni sygnał” pokazuje, że praca trwa).
- **Zawartość:**
  1. Nagłówek: wersja (z `scripts/version.sh`), data i godzina aktualizacji, ostatni sygnał, bieżący etap i zadanie, stan CI na `main`.
  2. Postęp ogólny i na etap (paski), liczony z macierzy funkcji; osobno pokrycie funkcji PL/SQL Developer, dodatków (SD/DB/DG), utPLSQL i agentów AI.
  3. Macierz funkcji z filtrem (etap, stan, źródło) i wyszukiwarką; legenda ✅ 👁 ⚠️ jak w `docs/STATUS.md` Bifolda.
  4. Oś czasu: ostatnie commity i PR (z linkami do GitHuba), scalenia, szkice wydań.
  5. Testy: liczba wszystkich, zielonych, czerwonych, pominiętych w każdej kategorii (jednostkowe, integracyjne, UI, wydajność), wyniki pomiarów wydajności z celami.
  6. Zrzuty ekranu najnowszych okien (miniatury z powiększeniem), z porównaniem do opisu wzorca.
  7. Decyzje (ostatnie wpisy z `docs/DECISIONS.md`), **blokady i pytania do mnie** (wyraźnie wyróżnione), znane ograniczenia, następne kroki.
- Tryb jasny i ciemny, czytelny na telefonie, po polsku. Raport nie może zawierać haseł, adresów baz, nazw użytkowników baz ani danych z bazy (repozytorium jest publiczne).

---

## 12. Dokumentacja projektu

Prowadź na bieżąco: `CLAUDE.md` (zasady, polecenia, pułapki, jak w Bifoldzie), `README.md`, `docs/PLAN.md`, `docs/FEATURES.md`, `docs/ARCHITECTURE.md`, `docs/SECURITY.md` (model zagrożeń API agentów i dostępu do baz: co chroni, przed czym nie chroni), `docs/DECISIONS.md`, `docs/THIRD_PARTY.md`, `docs/SKROTY.md` (z rejestru), `docs/STATUS.md`, `docs/WYDANIA.md`, `docs/GLOSSARY.md`, `CHANGELOG.md`, instrukcję użytkownika dostępną w aplikacji (po polsku, z tłumaczeniami).

---

## 13. Granice autonomii (zatrzymaj się, opisz blokadę w raporcie, rób inne zadania)

- Łączenie się z jakąkolwiek bazą poza lokalną bazą testową w kontenerze. Moje bazy podłączę sam; nie proś o hasła w czacie.
- Zakupy, płatne konta i usługi (w tym Apple Developer, płatne licencje Oracle).
- Zmiana widoczności repozytorium, usuwanie repozytoriów, gałęzi `main`, wydań i tagów, publikacja wydania (tylko szkice).
- Trwała zmiana globalnej konfiguracji CLI agentów, systemu lub Pęku kluczy poza tym, co opisano wyżej (wyjątek: jednorazowe `agy mcp add` jak w Bifoldzie, tylko po mojej zgodzie w aplikacji).
- Zależność z licencją, która zabrania dystrybucji, albo wymagająca osobnej instalacji przez użytkownika bez uzasadnienia w ADR (wyjątek uzgodniony: Instant Client, patrz 4.1).
- Sytuacja, w której wymaganie z tego dokumentu jest sprzeczne z bezpieczeństwem danych.

---

## 14. Pierwsze kroki

1. Przeczytaj cały dokument i repozytorium Bifolda (sekcja 2.5).
2. Utwórz repozytorium na GitHubie, szkielet projektu, `CLAUDE.md`, `docs/DECISIONS.md` (D1: praca autonomiczna), generator raportu i pierwszą wersję raportu. Podaj mi adres raportu.
3. Postaw bazę testową z utPLSQL i zielone CI.
4. Wykonaj analizę z sekcji 2 i macierz funkcji, potem ADR-y i plan Etapu 1.
5. Realizuj etapy po kolei, aktualizując raport, commitując, otwierając i scalając PR-y, aż do Etapu 8.
