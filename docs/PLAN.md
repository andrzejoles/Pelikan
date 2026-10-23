# Plan prac

Etapy wg PROMPT §8. Każdy etap kończy się: aplikacją używalną na co dzień, testami, zrzutami ekranu, scalonymi PR,
aktualnym raportem i szkicem wydania (od Etapu 1 — D13). Postęp funkcji: `docs/FEATURES.md` (kolumna Etap).

## Etap 0 — Analiza i fundament (zakończony 2026-10-22)

| Zadanie | Stan |
|---|---|
| Repozytorium GitHub (publiczne, MIT), pierwszy commit | ✅ |
| Raport postępów HTML (`scripts/progress.py`, `scripts/status.py`, `~/Pelikan-raport`) | ✅ |
| Baza testowa w kontenerze (Colima, Oracle Free 26ai), schematy, obiekty testowe, utPLSQL v3.2.3 | ✅ |
| CI: macOS (testy jednostkowe) + Linux (Oracle Free + utPLSQL + testy warstwy bazy) | ✅ |
| Warstwa bazy: protokół `DatabaseSession`, sterownik ODPI-C + Instant Client (12 testów integracyjnych) | ✅ |
| PelikanSQL: lekser, dzielenie skryptów, klasyfikacja, zmienne (& : JasperReports) | ✅ |
| Analiza źródeł: `docs/research/plsqldev-17.md`, `utplsql.md`, `gap-analysis.md`, `behaviour.md` | ✅ |
| Macierz funkcji `docs/FEATURES.md` (412 wierszy) | ✅ |
| ADR 0001–0005 (sterowniki, parser, edytor, siatka, okna), `ARCHITECTURE.md`, `SECURITY.md` | ✅ |
| `CLAUDE.md`, `THIRD_PARTY.md`, `GLOSSARY.md` | ✅ |
| Szkielet aplikacji: XcodeGen, okno główne (układ wzorca), rejestr komend, menu z rejestru, paleta | ✅ |
| `docs/SKROTY.md` generowany z rejestru | ✅ |

**Kryteria odbioru:** raport HTML pokazuje macierz ✅; CI zielone ✅; `make test` łączy się z bazą testową ✅;
aplikacja się buduje i otwiera okno główne z menu z rejestru (zrzut ekranu).

## Etap 1 — Połączenia, SQL Window, Command Window ✅ (zakończony 2026-10-23, PR #2–#10, szkic wydania — D21)

Kolejność podzadań (każde = gałąź `etap-1/<nazwa>` i PR):
1. **etap-1/polaczenia** — `ConnectionStore` (foldery, kolory, środowisko, sterownik, opcje), hasła w Pęku kluczy
   (Touch ID opcjonalnie), okno definicji połączeń (SwiftUI), Connection List (panel), okno logowania, połączenie
   główne, przypinanie połączeń okien, `SessionManager` (multi/dual/single, sesja kompilacji), TNS (tnsnames.ora z
   katalogu konfiguracji / TNS_ADMIN), EZConnect, wallet, rola, proxy, zmiana wygasłego hasła, skrypt inicjalizacji,
   sprawdzanie połączenia i utrata połączenia. (PD-CONN-*, MAC-KC-001)
2. **etap-1/tunel-ssh** — tunel SSH przez systemowy `ssh` (port lokalny, klucz/agent, hasło przez FIFO jak w Bifoldzie
   D38), bez haseł w argumentach. (PD-CONN-030, DB-SSH-001)
3. **etap-1/edytor** — `CodeEditorView` (TextKit 2, ADR 0003): podświetlanie przyrostowe, numery linii, status linii,
   bieżąca linia, wcięcia, komentarz linii, funkcje zaznaczenia, Find & Replace z regex, Go to line, Duplicate line,
   pasek stanu `linia:kolumna [długość]`, rozmiar czcionki. (PD-EDIT-001…010, 020–022)
4. **etap-1/sql-window** — SQL Window: wykonanie (zaznaczenie / polecenie pod kursorem / wszystko), karty wyników,
   historia okna, DBMS_OUTPUT, Break, transakcje (Commit/Rollback, ostrzeżenia przy zamykaniu), okno zmiennych (& i
   :bind z opcjami `&<…>`, Jasper), dyrektywy `tab=`, `Records=`, zapis/odczyt .sql, błędy z pozycją, Recall Statement.
   (PD-SQLW-*, PD-VAR-*)
5. **etap-1/siatka** — `ResultGridView` (NSTableView, ADR 0004): dociąganie porcjami, NULL, formaty liczb/dat, LOB z
   Large Data Editor (tekst/JSON/XML/hex/obraz), zaznaczanie bloków, sortowanie, Single Record View, scroll lock, filtr
   kolumn, kopiowanie (z nagłówkiem, Expression List, HTML), eksport CSV/TSV/HTML/XML/SQL/XLSX, edycja z ROWID (Post,
   podgląd SQL zmian), sumy. Test wydajności 1 mln wierszy. (PD-GRID-*, PD-LDE-001)
6. **etap-1/command-window** — Command Window: Dialog + Editor, polecenia SQL*Plus i SET, wyniki tekstowe, SPOOL,
   DEFINE/VARIABLE/PRINT, WHENEVER, @/@@, HOST (tylko użytkownik). (PD-CMDW-*)
7. **etap-1/klawiatura** — dwa profile skrótów, konfiguracja klawiszy, Window List, karty dokumentów, preferencje
   podstawowe (SQL Window, NLS, czcionki, katalogi, rozszerzenia), otwieranie plików z Findera. (MAC-KEY-001, PD-UI-*,
   PD-PREF-001/004–007, MAC-FILE-001)
8. **etap-1/thin** — sterownik OracleNIO za `DatabaseSession`, wybór w połączeniu, testy sparametryzowane sterownikiem,
   wyszarzanie funkcji niedostępnych. (PD-CONN-028)
9. Szkic wydania: `scripts/release.sh`, podpis, DMG/PKG, Sparkle (przeniesione z Etapu 8 — D13). ✅ `docs/WYDANIA.md`

**Kryteria odbioru:** codzienna praca z zapytaniami tylko z klawiatury; 1 mln wierszy przewijany płynnie (pomiar w
Release); brak blokad interfejsu przy długim zapytaniu (Break działa); zrzuty ekranu SQL Window, Command Window,
Connection List; testy integracyjne na obu sterownikach.

## Etap 2 — Object Browser i Program Window ✅ (zakończony 2026-10-23, PR #11–#24, szkic wydania — D27)
Parser strukturalny (ADR 0002), `MetadataProvider` z cache, Object Browser (wszystkie typy, MLE, domeny, adnotacje,
asercje, filtry, foldery), Properties/Describe/DDL, edytory obiektów (tabela, sekwencja, synonim, widok, indeks, użytkownik,
rola…), Program Window (karty jednostek, kompilacja w osobnej sesji, błędy i ostrzeżenia, hints), Code Assistant,
Code Contents/Hierarchy, zwijanie, hiperłącza, nawigacja, refaktoryzacja, szablony, Beautifier, Find Database Objects,
Compile Invalid Objects, przeglądarka różnic. Kryterium: edycja i kompilacja pakietu 50 000 linii bez opóźnień w pisaniu.

Kolejność podzadań (każde = gałąź `etap-2/<nazwa>` i PR):
1. **etap-2/object-browser** — `MetadataProvider` (osobna sesja przeglądarki, cache, widoki DBA/ALL, zapytania odporne
   na wersję, foldery 23ai/26ai), Object Browser (typy, użytkownik, filtr, elementy obiektu, niepoprawne, Recent),
   menu obiektu: Query/Edit data, Describe, DDL, Properties, View/Edit, Recompile, Drop, Copy name, Refresh.
   (PD-OB-001…006, 009, 012–018, 024, 026)
2. **etap-2/program-window** — Program Window: karty jednostek (spec/body), zapis .pck/.spc/.bdy…, kompilacja w sesji
   kompilacji, lista błędów i ostrzeżeń (PLSQL_WARNINGS) z przejściem, wskaźniki zmieniony/nieskompilowany, Compare.
3. **etap-2/parser** — parser strukturalny PL/SQL (ADR 0002): jednostki, podprogramy, deklaracje; Code Contents,
   Code Hierarchy, zwijanie, Go to declaration, hiperłącza do obiektów.
3a. **etap-2/zwijanie** — zwijanie kodu w edytorze (znaczniki ±, Fold All/Unfold All, podgląd zwiniętego) na
   zakresach z parsera (PD-EDIT-013, D22).
4. **etap-2/code-assistant** — podpowiedzi (kolumny, aliasy, elementy pakietów, parametry, słowa kluczowe); szablony
   (Template Window, PD-TPL-001…003) w osobnym podzadaniu **etap-2/szablony**.
5. **etap-2/beautifier** — PL/SQL Beautifier z regułami i podglądem.
6. **etap-2/narzedzia** — Find Database Objects, Compile Invalid Objects, Difference Viewer, edytory obiektów
   (tabela, sekwencja, synonim, widok, indeks, użytkownik, rola), test wydajności (pakiet 50 000 linii, 100 000 obiektów).

## Etap 3 — Test Window, debuger, profiler ✅ (zakończony 2026-10-23, PR #25–#31, szkic wydania — D29)
Test Window (zmienne, typy, wykonanie, stos błędu), debuger DBMS_DEBUG (Step into/over/out, run to cursor, punkty
przerwania z warunkami i logpointami, error breakpoints, zmienne Local/Global/Input z drzewem rekordów, kolekcji,
obiektów, `:old`/`:new`, stos, watches) i DBMS_DEBUG_JDWP (Pelikan jako serwer JDWP), statystyki, profiler
(DBMS_PROFILER, DBMS_HPROF), trace. Kryterium: krokowanie przez pakiet z wyzwalaczem, podgląd rekordu i kolekcji, test
integracyjny debugera na bazie testowej.

## Etap 4 — utPLSQL ✅ (zakończony 2026-10-23, PR #32–#35, szkic wydania — D32)
PROMPT §6 w całości (docs/research/utplsql.md). Kryterium: wygenerowany szkielet kompiluje się, testy uruchamiają się
z eksploratora i edytora, pokrycie widać na marginesie.

## Etap 5 — Agenci AI ✅ (zakończony 2026-10-23, PR #36–#38, szkic wydania — D36)
PROMPT §7 (docs/SECURITY.md). Kryteria: każdy z czterech agentów czyta stan i obiekty; operacje „Za zgodą” czekają na
decyzję; testy bezpieczeństwa z SECURITY §5.

Podzadania (model kanału przeniesiony z Bifolda, D33):
1. **etap-5/kanal** — most `pelikan-mcp` (stdio ↔ gniazdo Unix 0600 w katalogu 0700), serwer gniazda z weryfikacją UID,
   drzewa procesów i tokenu 256 bit (porównanie stałoczasowe), sesje i unieważnianie, katalog narzędzi MCP z rejestru,
   polityka najmniejszego poziomu, limit wywołań, dziennik JSONL; testy bezpieczeństwa kanału.
2. **etap-5/baza** — własna sesja bazy agenta (MODULE/ACTION/CLIENT_INFO, opcjonalny użytkownik proxy), narzędzia
   odczytu (połączenia pod aliasem, stan, edytor, wyszukiwanie, opis, źródło, DDL, zależności, użycia, `run_query`
   w transakcji READ ONLY z limitami, plan, błędy kompilacji, DBMS_OUTPUT, testy, pokrycie, sesje), maskowanie kolumn,
   `untrusted_content`, polityka środowisk (prod: odczyt i metadane).
3. **etap-5/zmiany** — `execute_statement`, `execute_script`, `compile`, `commit`, `rollback` z podglądem (tekst, obiekty
   z ALL_DEPENDENCIES, plan, szacunek wierszy), DML niezatwierdzone do zgody na COMMIT, ROLLBACK przy zamknięciu, historia
   DDL obiektów przed zmianą i „Cofnij sesję agenta” z wykrywaniem konfliktów; narzędzia edytora (Pełny, cofalne).
4. **etap-5/panel** — uruchamianie CLI (Claude Code, Codex, Grok, Antigravity; lista konfigurowalna) w terminalu
   SwiftTerm z serwerem MCP tylko dla sesji, tryb ścisły, panel aktywności, okno zgody (bez przycisku domyślnego,
   „Zatwierdź” po 0,8 s, Esc odrzuca), macierz uprawnień przy starcie, przeglądarka dziennika, ustawienia agentów.

## Etap 6 — Narzędzia
Explain Plan, Session Browser, porównania obiektów i danych, eksport/import (SQL, format własny, Data Pump), Text/Excel
Importer, Data Generator, Event Monitor, DBMS Scheduler, raporty, Query Builder, diagramy, projekty, worksets, układy,
makra, Test Manager, Load Tester. Kryterium: każde narzędzie z macierzy ma test lub zrzut ekranu.

## Etap 7 — Dodatki z SQL Developer, DBeaver, DataGrip
Wg `docs/research/gap-analysis.md` (wiersze SD-, SC-, DB-, DG-).

## Etap 8 — Dopracowanie i wydanie
Audyt zgodności z macierzą, wydajność, VoiceOver, tłumaczenia (en, de, es, uk), instrukcja w aplikacji, zestawy
preferencji, druk, `docs/STATUS.md` z ograniczeniami.
