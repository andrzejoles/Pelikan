# Analiza luk: czego nie ma w PL/SQL Developer 17, a jest w SQL Developer, SQLcl, DBeaver i DataGrip (tylko Oracle)

Wynik trafia do macierzy (`docs/FEATURES.md`, prefiksy SD-, SC-, DB-, DG-) z etapem 7, chyba że funkcja jest potrzebna
wcześniej (np. tunel SSH w Etapie 1). Funkcje AI wszystkich narzędzi są wyłączone (PROMPT §3.2) — zastępuje je
integracja agentów (Etap 5). Oznaczenie „do weryfikacji” = opis z dokumentacji ogólnej, szczegóły do sprawdzenia przed
implementacją.

Źródła:
- SQL Developer for VS Code: https://docs.oracle.com/en/database/oracle/sql-developer-vscode/ (wydania 23.4–26.3,
  strony „Changes in Release …”, przewodnik 26.3 `sqdnx/`), Marketplace `Oracle.sql-developer`.
- SQL Developer (klasyczny, desktopowy): https://docs.oracle.com/en/database/oracle/sql-developer/ (User's Guide).
- SQLcl: https://docs.oracle.com/en/database/oracle/sql-developer-command-line/ (User's Guide, polecenia).
- DBeaver: https://dbeaver.com/docs/dbeaver/ (wiki/dokumentacja Community i PRO).
- DataGrip: https://www.jetbrains.com/help/datagrip/

## 1. SQL Developer for VS Code — wydania i funkcje

| Wydanie | Nowe funkcje (wg „Changes in Release”) |
|---|---|
| 23.4 | pierwsze wydanie: połączenia, przeglądarka obiektów, SQL Worksheet, edycja i kompilacja PL/SQL, eksport danych |
| 24.1 | wiele sesji w SQL Worksheet; sortowanie i wyszukiwanie w SQL History; widok diagramu planu wykonania; filtry schematów i typów obiektów |
| 24.2 | widoki dualności JSON-relacyjnej (JSON-Relational Duality Views) |
| 24.3 | debugowanie obiektów PL/SQL; monitor zadań w czasie rzeczywistym (Task Monitor) |
| 24.4 | raporty predefiniowane; Real Time SQL Monitoring |
| 25.1 | foldery połączeń |
| 25.2 | serwer MCP SQLcl (AI — wyłączone); SQL Notebook |
| 25.3 | wykresy w SQL Notebook; diagramy (ER/obiekty); generowanie kodu przez przeciąganie; AI Enrichment (wyłączone) |
| 25.4 | generowanie kodu przez przeciąganie (rozszerzenie); zarządzanie importem danych; uwierzytelnianie Entra ID; edytor tabel |
| 26.1 | Kerberos; import danych (rozszerzenie); edytory widoków i indeksów; APEXlang |
| 26.2 | obiekty DBA: Scheduler Jobs (dashboard, tworzenie/edycja), DBA Users (tworzenie/edycja, klonowanie, blokada, odblokowanie, wygaszenie hasła), DBA Roles; raporty wydajności ASH i AWR; połączenia OCI DBTools; licencjonowanie pakietów (Diagnostics/Tuning) na połączeniu; filtrowanie folderów obiektów; eksport AI Enrichment (wyłączone); porównanie plików APEXlang z aplikacją APEX |
| 26.3 | Kerberos (uzupełnienie) |

Szczegóły ważne dla Pelikana:
- **SQL Notebook** (`.sqlnb`, format YAML): komórki kodu (SQL, PL/SQL, skrypty) i Markdown, Run All, Clear All Outputs,
  podłączenie do połączenia, widok pojedynczego rekordu, eksport, **renderowanie wyniku jako wykres**, opcje komórki.
- **Explain Plan**: widok tekstowy (poziom szczegółów), **diagram** (kardynalność na strzałkach, operacja, kolejność,
  koszt CPU predykatów, całkowity koszt CPU, I/O, bajty, koszt; rozwijanie poziomów, zoom, dopasowanie), **wykres
  płomieniowy (flame graph)**, widok zaawansowany (tabela + drzewo).
- **Task Monitor**: lista zadań (połączenie, status Waiting/Created/Executing/Completed/Error, czasy, opis), anulowanie.
- **Raporty predefiniowane** w kategoriach (Database Administration, Data Dictionary, Security…), typy Grid/Charts/
  DBMS_OUTPUT, zmienne wiązane, szczegóły wiersza w panelu dolnym, „Open in Worksheet”, eksport CSV/PDF/HTML.
- **Script Runner** (polecenia SQL*Plus w Worksheet), **SQL History** (bez haseł, limit, sortowanie, wyszukiwanie),
  **Snippets** (fragmenty kodu w grupach: funkcje agregujące, znakowe, wskazówki optymalizatora — przeciąganie).
- **Generowanie kodu przez przeciąganie** obiektu/połączenia do pliku Java: JDBC (nazwa, INSERT, DELETE, UPDATE,
  SELECT, DROP, JOIN wielu obiektów; wybór kolumn), łańcuch połączenia / kod JDBC połączenia.
- **Import danych**: CSV, rozdzielany, tekst, XLS, XLSX; podgląd (separator, ograniczniki, kodowanie, koniec linii,
  pomijanie wierszy, limit podglądu, arkusz, nagłówek), mapowanie, nowa lub istniejąca tabela, zapis i przywracanie stanu.
- **Edytor tabeli**: kolumny, PK, UK, indeksy, FK, więzy, komentarze, storage, DDL, output; edytory widoku i indeksu.
- **Licencje pakietów** na połączeniu z pytaniem przy pierwszym użyciu (AWR, ASH → Diagnostics; RTSM → Tuning).
- Uwierzytelnianie: Entra ID (Azure), Kerberos, połączenia OCI.
- Widoki dualności (tworzenie, edycja, wstawianie i edycja rekordu, diagram JSON Data Guide), moduły JavaScript i
  środowiska MLE (tworzenie, import modułów, kompilacja, usuwanie, debugowanie po wykonaniu).
- APEXlang (eksport/generowanie/import/porównanie aplikacji APEX, usługi językowe) — **pominięte** (wymaga APEX na bazie,
  poza zakresem codziennej pracy z PL/SQL; decyzja D11 — można dodać później jako osobny moduł).

Różnice względem klasycznego SQL Developera: wersja dla VS Code nie ma (jeszcze) Data Modelera, Database Diff/Cart,
kreatorów Data Pump i kopiowania bazy, migracji, raportów użytkownika z wieloma typami, Instance Viewera i panelu DBA
w pełnym zakresie; ma za to Notebook, diagram/flame graph planu, MCP, Task Monitor i generowanie kodu Java.

## 2. SQL Developer (klasyczny) i SQLcl — funkcje brakujące w PL/SQL Developer

| Funkcja | Źródło | Decyzja |
|---|---|---|
| Real-Time SQL Monitoring (lista, raport aktywny) | SQL Developer UG „Real Time SQL Monitoring”, SD VS Code 24.4 | bierzemy (Tuning Pack — ostrzeżenie, agent: Brak) |
| Panel DBA: przestrzenie tabel, pliki danych, parametry inicjalizacji, użytkownicy, sesje, blokady, kopie (RMAN — tylko podgląd) | SQL Developer UG „DBA Navigator” | bierzemy zakres bez RMAN-zmian |
| Raporty AWR, ASH, ADDM | SQL Developer UG, SD VS Code 26.2 | bierzemy (Diagnostics Pack — ostrzeżenie) |
| SQL Tuning Advisor | SQL Developer UG „SQL Tuning Advisor” | bierzemy (Tuning Pack) |
| Porównanie planów (np. plan bieżący vs z AWR/historii kursora) | SQL Developer UG „Explain Plan / Autotrace compare” | bierzemy |
| Autotrace ze statystykami i planem rzeczywistym (V$SQL_PLAN_STATISTICS_ALL) | SQL Developer UG „Autotrace” | bierzemy |
| Instance Viewer (pulpit instancji) | SQL Developer UG „Instance Viewer” | bierzemy uproszczony |
| Database Diff i Cart (pakiet zmian do wdrożenia, skrypt) | SQL Developer UG „Database Diff”, „Cart” | bierzemy (rozszerza Compare User Objects) |
| Kreatory Data Pump (eksport/import) i kopiowania bazy (Database Copy) | SQL Developer UG „Data Pump”, „Database Copy” | Data Pump w Etapie 6 (PD-TOOL-005), Database Copy — Etap 7 |
| Generowanie dokumentacji schematu (HTML) | SQL Developer UG „Generate DB Doc” | bierzemy |
| Przeglądarki/edytory JSON, XML, danych przestrzennych (SDO_GEOMETRY → podgląd mapy/WKT) | SQL Developer UG „Spatial”, LDE | JSON/XML w LDE (Etap 1), przestrzenne — Etap 7 (WKT + prosty podgląd) |
| Polecenia SQLcl: INFO[+], DDL, LOAD, FORMAT (formatowanie skryptu), SET SQLFORMAT (csv, json, xml, html, insert, loader, fixed, delimited, ansiconsole), HISTORY (z czasami), ALIAS, REPEAT, CTAS, Liquibase `lb` | SQLcl UG „Commands” | Command Window: INFO, DDL, LOAD, FORMAT, SET SQLFORMAT, HISTORY, ALIAS, REPEAT, CTAS (Etap 7); Liquibase — **pominięte w pierwszej wersji** (wymaga Javy i biblioteki Liquibase; D11) |
| Snippets (biblioteka fragmentów) | SQL Developer, SD VS Code | już pokryte przez szablony (PD-TPL) + import snippetów w Etapie 7 |
| ORDS: REST-enable schematu i obiektów, moduły REST | SQL Developer UG „REST Data Services” | bierzemy podstawy (włącz/wyłącz AutoREST, lista modułów) przez pakiet ORDS w bazie, Etap 7 |
| Unit Test SQL Developera (repozytorium testów) | SQL Developer UG „Unit Testing” | **pominięte** — utPLSQL (Etap 4) jest standardem; D11 |
| Data Modeler | osobny produkt | **pominięte** (diagramy ER z bazy — DB-DIAG) |
| Migracje z innych baz | SQL Developer | **pominięte** (PROMPT §3.2) |

## 3. DBeaver — funkcje dla Oracle brakujące we wzorcach

| Funkcja | Źródło | Decyzja |
|---|---|---|
| Tunel SSH (hasło, klucz, agent; jump host) | https://dbeaver.com/docs/dbeaver/SSH-Configuration/ | bierzemy już w Etapie 1 (PD-CONN-030) — przez systemowy `ssh` bez haseł w argumentach, jak w Bifoldzie |
| Diagramy ER z bazy (automatyczny układ, relacje FK, eksport obrazu) | https://dbeaver.com/docs/dbeaver/ER-Diagrams/ | bierzemy (rozszerza PD-DIAG) |
| Panel wartości obok siatki (tekst, JSON, XML, HTML, obraz z BLOB, hex) | https://dbeaver.com/docs/dbeaver/Panels/ | bierzemy (podgląd bieżącej komórki bez otwierania LDE) |
| Filtr i grupowanie wyników w siatce (filtr kolumny po wartości, wyrażenie WHERE do siatki, grupowanie z licznikiem) | https://dbeaver.com/docs/dbeaver/Data-Filters/ , „Grouping” | bierzemy |
| Przenoszenie danych między tabelami/schematami/połączeniami (Data Transfer z mapowaniem) | https://dbeaver.com/docs/dbeaver/Data-transfer/ | bierzemy (Oracle → Oracle, pliki ↔ Oracle) |
| Porównanie wyników zapytań / danych (PRO: Data Compare) | dokumentacja PRO „Data Compare” — do weryfikacji | pokryte przez PD-SQLW-021 i PD-TOOL-013 |
| Wykresy z wyników (PRO) | dokumentacja „Charts” — do weryfikacji | pokryte przez PD-GRAPH-001 + SD notatnik z wykresami |
| Zaplanowane zadania (Tasks + scheduler: eksport, skrypt cyklicznie) | https://dbeaver.com/docs/dbeaver/Task-Management/ | bierzemy lokalnie (launchd/zegar aplikacji), bez haseł w plikach — Etap 7 |
| Generowanie SQL z wierszy siatki (INSERT/UPDATE/DELETE/MERGE dla zaznaczonych) | dokumentacja „Generate SQL” | bierzemy |
| Mock data generator | DBeaver PRO | pokryte przez PD-TOOL-011 |

## 4. DataGrip — funkcje dla Oracle brakujące we wzorcach

| Funkcja | Źródło | Decyzja |
|---|---|---|
| Rozwiązywanie nazw w czasie pisania (podkreślanie nieznanych tabel, kolumn, aliasów) | https://www.jetbrains.com/help/datagrip/code-inspections.html | bierzemy (na cache metadanych, Etap 7; podstawy w Code Assistant) |
| Inspekcje kodu: nieużywane zmienne/parametry, nieosiągalny kod, niejawne konwersje, brak WHERE w UPDATE/DELETE | DataGrip „Inspections” | bierzemy (rozszerza podpowiedzi kompilatora PD-PROG-005) |
| Find Usages (użycia obiektu/kolumny w kodzie bazy i plikach) | https://www.jetbrains.com/help/datagrip/find-usages.html | bierzemy (ALL_DEPENDENCIES + PL/Scope + tekst; także dla agenta `find_usages`) |
| Refaktoryzacja z podglądem zmian przed zastosowaniem (rename obiektu/kolumny z aktualizacją odwołań) | https://www.jetbrains.com/help/datagrip/refactoring-source-code.html | bierzemy (podgląd diff przed zapisem) |
| Lokalna historia plików i obiektów (wersje z czasem, porównanie, przywracanie) | https://www.jetbrains.com/help/datagrip/local-history.html | bierzemy (też dla „Cofnij sesję agenta”) |
| Edycja danych ze zmianami oczekującymi i podglądem SQL przed zapisem (Submit) | https://www.jetbrains.com/help/datagrip/table-editor.html | już we wzorcu (PD-GRID-017/020); bierzemy wyróżnienie zmian w siatce |
| Przypinanie wyników | DataGrip „Pin result” | już we wzorcu (PD-SQLW-017) |
| Konsole zapytań per połączenie (zapisywane automatycznie, bez pytania o plik) | https://www.jetbrains.com/help/datagrip/query-consoles.html | bierzemy (konsola = SQL Window bez pliku, zachowywana) |
| Cache metadanych z odświeżaniem w tle (introspekcja) | DataGrip „Introspection” | wymaganie architektury (PROMPT §4.2 p.5) |
| Uruchamianie z parametrami (okno parametrów `:x`, `?`, `${x}`) | https://www.jetbrains.com/help/datagrip/settings-tools-database-user-parameters.html | pokryte przez zmienne (PD-VAR) + parametry Jaspera (D6) |
| Wykonanie w „bezpiecznym trybie” (potwierdzenie DML/DDL na prod) | DataGrip „Database color / read-only” | pokryte przez PD-CONN-006/007 |

## 5. ODBC na macOS (PROMPT §3.2)
ODBC Importer we wzorcu służy do importu z innych źródeł (Access, Excel przez ODBC). Na macOS ODBC wymaga osobnego
menedżera sterowników (unixODBC/iODBC) i sterowników dla źródeł — mało przydatne przy Oracle. Import z plików (CSV, Excel,
JSON) i przenoszenie danych między połączeniami Oracle pokrywają potrzeby. **Decyzja: pomijamy ODBC Importer** (D11).
