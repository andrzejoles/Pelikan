# Macierz funkcji Pelikana

Z tej macierzy `scripts/progress.py` liczy postęp w raporcie. Każdy wiersz: identyfikator, funkcja, źródło, okno lub menu
wzorca, etap (docs/PLAN.md), priorytet (P1 codzienna praca, P2 ważne, P3 dodatkowe), poziom dostępu agenta
(docs/SECURITY.md: Brak / Odczyt / Za zgodą / Pełny; „—” = funkcja interfejsu bez odpowiednika dla agenta) i stan.

**Stany:** do zrobienia · w toku · ✅ test (zweryfikowane testem automatycznym) · 👁 sprawdzone ręcznie (zrzut ekranu)
· ⚠️ bez weryfikacji (powód) · pominięte (powód).

**Źródła:** `UG x.y` — PL/SQL Developer 17.0 User's Guide, rozdział x.y (PDF z instalatora wersji próbnej
https://www.allroundautomations.com/files/trial/plsqldev1703x64.msi, streszczenie w `docs/research/plsqldev-17.md`);
`NFxx` — https://www.allroundautomations.com/products/pl-sql-developer/features/new-features-pl-sql-xx-0/ ;
pozostałe źródła z adresem URL w wierszu lub w `docs/research/`.

Prefiksy: `PD-` PL/SQL Developer · `UT-` utPLSQL · `AI-` agenci AI · `SD-` SQL Developer / SQL Developer for VS Code ·
`SC-` SQLcl · `DB-` DBeaver · `DG-` DataGrip · `MAC-` integracja z macOS · `PL-` platforma i infrastruktura projektu.

## Platforma i infrastruktura projektu

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| PL-INFRA-001 | Raport postępów HTML (status.json, macierz, git, testy) w docs/progress i ~/Pelikan-raport | PROMPT §11 | — | 0 | P1 | — | 👁 sprawdzone ręcznie |
| PL-INFRA-002 | CI GitHub Actions: macOS (testy jednostkowe) i Linux z Oracle Free + utPLSQL | PROMPT §10 | — | 0 | P1 | — | ✅ test |
| PL-INFRA-003 | Baza testowa w kontenerze (Oracle Free 26ai), schematy, obiekty testowe, utPLSQL (scripts/testdb.sh) | PROMPT §9 | — | 0 | P1 | — | ✅ test |
| PL-INFRA-004 | Wersja z historii scalonych PR (scripts/version.sh) | PROMPT §10 | — | 0 | P1 | — | ✅ test |
| PL-INFRA-005 | Szkielet aplikacji AppKit (XcodeGen), okno główne, menu z rejestru komend | PROMPT §4.2 | — | 0 | P1 | — | 👁 sprawdzone ręcznie |
| PL-INFRA-006 | Rejestr komend z poziomem dostępu agenta i opisem skutków; docs/SKROTY.md generowany | PROMPT §4.2 p.1 | — | 0 | P1 | — | ✅ test |
| PL-INFRA-007 | Podpis stały, instalatory DMG i PKG, Sparkle, szkic wydania (scripts/release.sh) | PROMPT §10 | — | 8 | P2 | — | do zrobienia |
| PL-INFRA-008 | Tłumaczenia pl (źródłowy), en, de, es, uk w String Catalog + test kompletności | PROMPT §1 | — | 8 | P2 | — | do zrobienia |
| PL-INFRA-009 | Warstwa bazy za protokołem DatabaseSession, bez AppKit, testowana na Linuksie | PROMPT §4.2 p.2 | — | 0 | P1 | — | ✅ test |
| PL-INFRA-010 | Instrukcja użytkownika w aplikacji (pl + tłumaczenia) | PROMPT §12 | Help | 8 | P2 | — | do zrobienia |

## PL/SQL Developer — połączenia i sesje

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| PD-CONN-001 | Sterownik Instant Client (ODPI-C): łączenie, zapytania, typy, przerwanie | PROMPT §4.1, UG 3 | Session > Log on | 1 | P1 | — | ✅ test |
| PD-CONN-002 | Okno logowania (użytkownik, hasło, baza, Connect as) z historią i anulowaniem (praca bez połączenia) | UG 3, UG 23.8 | Session > Log on | 1 | P1 | Brak | 👁 sprawdzone ręcznie |
| PD-CONN-003 | Connection List: foldery, podfoldery, połączenia jawne i dopasowane regułami (wzorce * ?), folder Recent | UG 19.1–19.2 | View > Connection List | 1 | P1 | Odczyt | 👁 sprawdzone ręcznie |
| PD-CONN-004 | Definicja połączenia: nazwa, obraz, użytkownik, baza, hasło (Pęk kluczy, puste = pytaj), Connect as, Identified externally | UG 19.2 | Configure > Connections | 1 | P1 | Brak | 👁 sprawdzone ręcznie |
| PD-CONN-005 | Kolor połączenia i wskaźnik (pasek, okno, Window List, tło); reguły Connection Indicators user@db | UG 19.2, UG 23.16 | Configure > Preferences | 1 | P1 | — | w toku |
| PD-CONN-006 | Środowisko połączenia dev/test/prod z ostrzeżeniami przy zmianach na prod | PROMPT §4.2 p.6 | Configure > Connections | 1 | P1 | Odczyt | w toku |
| PD-CONN-007 | Połączenie tylko do odczytu (blokada zmian obiektów i danych) | UG 19.2, NF15 | Configure > Connections | 1 | P1 | Odczyt | do zrobienia |
| PD-CONN-008 | Skrypt inicjalizacji sesji i komunikat przy logowaniu; Test połączenia | UG 19.2, NF11 | Configure > Connections | 1 | P2 | Brak | ✅ test |
| PD-CONN-009 | Edition (EBR) i Workspace (DBMS_WM) połączenia | UG 19.2, NF10 | Configure > Connections | 1 | P3 | Brak | do zrobienia |
| PD-CONN-010 | Connect on startup; eksport i import definicji połączeń (bez haseł) | UG 19.2, NF13 | Configure > Connections | 1 | P2 | Brak | w toku |
| PD-CONN-011 | TNS: tnsnames.ora, sqlnet.ora, TNS_ADMIN (katalog konfiguracji per połączenie), EZConnect | PROMPT §3.1, UG 37.4 | Log on | 1 | P1 | Brak | ✅ test |
| PD-CONN-012 | Wallet (mTLS, Autonomous Database) | PROMPT §3.1 | Log on | 1 | P1 | Brak | do zrobienia |
| PD-CONN-013 | LDAP (directory naming) | PROMPT §3.1 | Log on | 1 | P3 | Brak | do zrobienia |
| PD-CONN-014 | Uwierzytelnianie zewnętrzne / Kerberos | PROMPT §3.1 | Log on | 1 | P2 | Brak | do zrobienia |
| PD-CONN-015 | Role SYSDBA, SYSOPER, SYSBACKUP, SYSDG, SYSKM, SYSASM | UG 19.2 | Log on | 1 | P1 | Brak | w toku |
| PD-CONN-016 | Proxy user (pośrednik[schemat]) | NF12 | Log on | 1 | P2 | Brak | w toku |
| PD-CONN-017 | Zmiana wygasłego hasła (ORA-28001) i Set Password (w bazie i w definicji) | PROMPT §3.1, NF10 | Session > Set Password | 1 | P2 | Brak | ✅ test |
| PD-CONN-018 | Wiele połączeń naraz; połączenie główne (pogrubione, dwuklik, Set Main Connection [to current]) | UG 20.1 | Session | 1 | P1 | Odczyt | ✅ test |
| PD-CONN-019 | Połączenie okna na pasku stanu, zmiana połączenia okna, przypięte / nieprzypięte (preferencja domyślna) | UG 20.2, NF10 | Pasek stanu okna | 1 | P1 | — | do zrobienia |
| PD-CONN-020 | Tryb sesji Multi / Dual / Single; osobna sesja kompilacji | UG 20.3 | Preferences > Oracle > Connection | 1 | P1 | — | ✅ test |
| PD-CONN-021 | Wykonywanie okien równolegle (wątki), kursor „wykonywanie”, blokada edycji okna w trakcie | UG 20.4 | — | 1 | P1 | — | do zrobienia |
| PD-CONN-022 | Menu połączenia: otwórz okno typu, Show/Close/Reconnect All Windows, Connect, Disconnect, Set current schema | UG 19.1 | Connection List | 1 | P2 | Brak | w toku |
| PD-CONN-023 | Sprawdzanie połączenia co 60 s (wszystkie sesje opcjonalnie), reakcja na utratę połączenia | UG 23.1, PROMPT §5 | Preferences | 1 | P1 | — | w toku |
| PD-CONN-024 | Wylogowanie z otwartą transakcją: COMMIT / ROLLBACK / pytaj (w Pelikanie domyślnie pytaj) | UG 23.1 | Preferences | 1 | P1 | — | do zrobienia |
| PD-CONN-025 | Zmienne środowiska Oracle per aplikacja (NLS_LANG, NLS_DATE_FORMAT…), NLS sesji | UG 23.1, PROMPT §3.1 | Preferences | 1 | P2 | — | do zrobienia |
| PD-CONN-026 | Automatyczne zamykanie nieużywanych połączeń; pamiętanie Recent | UG 23.1 | Preferences | 1 | P3 | — | do zrobienia |
| PD-CONN-027 | Kill sesji okna (Session > Kill) gdy Break nie działa | UG 20.4 | Session > Kill | 1 | P2 | Brak | do zrobienia |
| PD-CONN-028 | Sterownik thin (OracleNIO) wybierany w połączeniu; funkcje niedostępne wyszarzone z podpowiedzią | PROMPT §4.1 | Configure > Connections | 1 | P2 | — | do zrobienia |
| PD-CONN-029 | Wykrywanie Instant Client, ścieżka w ustawieniach, ekran pomocy przy braku | PROMPT §4.1 | Preferences > Oracle | 1 | P1 | — | w toku |
| PD-CONN-030 | Tunel SSH do bazy (z DBeaver; ważne na Macu) | PROMPT §3.3 | Configure > Connections | 1 | P1 | Brak | do zrobienia |

## PL/SQL Developer — SQL Window

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| PD-SQLW-001 | Dzielenie skryptu na polecenia (`;`, `/`, bloki PL/SQL, CREATE z ciałem) jak SQL*Plus | UG 7.1, PROMPT §5 | SQL Window | 1 | P1 | — | ✅ test |
| PD-SQLW-002 | Wykonanie: zaznaczenie → tylko zaznaczony tekst; wiele poleceń → wszystkie, wyniki w kartach | UG 7.1 | SQL Window > Execute (F8) | 1 | P1 | Za zgodą | ✅ test |
| PD-SQLW-003 | AutoSelect statement / Execute current statement (polecenie pod kursorem) | UG 23.20, NF10 | SQL Window | 1 | P1 | — | ✅ test |
| PD-SQLW-004 | Wynik w siatce z pobieraniem pierwszej strony i dociąganiem (Next Page, Last Page, „(more…)”) | UG 7.1, UG 23.20 | SQL Window | 1 | P1 | Odczyt | ✅ test |
| PD-SQLW-005 | Break w trakcie wykonania i w trakcie pobierania (zostają pobrane wiersze) | UG 7.1 | Break (Shift+Esc) | 1 | P1 | — | w toku |
| PD-SQLW-006 | Refresh result set (ponowne wykonanie karty) i Auto Refresh okna co n s | UG 7.1, NF8 | Siatka | 1 | P2 | — | do zrobienia |
| PD-SQLW-007 | Historia poleceń okna (wstecz/dalej) | UG 7.1 | SQL Window | 1 | P1 | — | ✅ test |
| PD-SQLW-008 | Karta Statistics (statystyki wykonania) | UG 6.2 | SQL Window > Statistics | 3 | P2 | Odczyt | do zrobienia |
| PD-SQLW-009 | Karta Output z DBMS_OUTPUT (bufor, limit, włącz/wyłącz, czyszczenie, wskaźnik nowego wyjścia) | UG 5.8, UG 23.5 | SQL Window > Output | 1 | P1 | Odczyt | ✅ test |
| PD-SQLW-010 | Tytuł karty z komentarza `-- tab=…` i `&Count` | UG 7.1, NF17 | SQL Window | 1 | P2 | — | ✅ test |
| PD-SQLW-011 | Dyrektywy komentarzy: Excel=, CSV=, Records=, Totals=, AltRowColor= | UG 7.12 | SQL Window | 1 | P3 | — | w toku |
| PD-SQLW-012 | Zapis .sql (bieżące polecenie / z historią), Load do istniejącego okna | UG 7.13 | File > Save | 1 | P1 | Pełny | do zrobienia |
| PD-SQLW-013 | Standard Queries dla tabel/widoków w menu kontekstowym | UG 7.14 | Siatka > Save as Standard Query | 6 | P3 | Odczyt | do zrobienia |
| PD-SQLW-014 | AutoCommit SQL (domyślnie wyłączony), AutoCommit posted records | UG 23.20 | Preferences | 1 | P1 | — | ✅ test |
| PD-SQLW-015 | Powiadomienie (dźwięk) o końcu długiego zapytania; czas wykonania na pasku stanu (hh:mm:ss > 100 s) | UG 23.18, NF8, NF17 | SQL Window | 1 | P2 | — | w toku |
| PD-SQLW-016 | Druk okna (SQL + siatka, zaznaczone wiersze) | UG 7.1, UG 23.33 | File > Print | 8 | P3 | — | do zrobienia |
| PD-SQLW-017 | Pinning wyników (Shift+klik karty), Pin All Result Sets, Clear Tab Results | UG 7.10, NF16, NF8 | Karty wyników | 1 | P2 | — | do zrobienia |
| PD-SQLW-018 | Direct Query Export do pliku (CSV, TSV, HTML, XML, Excel, SQL, schowek) bez wyświetlania | UG 7.11 | Siatka > Export Query Results | 1 | P2 | Brak | do zrobienia |
| PD-SQLW-019 | Linked Queries: tabele nadrzędne/podrzędne z FK, master/detail ze zmiennymi `:m_…`, Custom | UG 7.4, NF10 | Siatka > Linked Query | 6 | P2 | — | do zrobienia |
| PD-SQLW-020 | Compare records (identyczne/różne, kolumna/rekord, wielkość liter) | UG 7.8, NF11 | Siatka | 6 | P3 | — | do zrobienia |
| PD-SQLW-021 | Compare result sets (dwie karty naraz, podświetlenie różnic, układ pionowy/poziomy) | UG 7.9, NF14 | Karty wyników | 6 | P3 | — | do zrobienia |
| PD-SQLW-022 | Query By Example (wiersz kryteriów, wyrażenia, preferencje QBE) | UG 7.3, UG 23.20 | Siatka > QBE | 1 | P2 | — | do zrobienia |
| PD-SQLW-023 | Wyróżnienie całego słowa przy błędzie, przejście do pozycji błędu ORA | NF15 | SQL Window | 1 | P1 | — | ✅ test |
| PD-SQLW-024 | Pytanie o zapis nowego okna przy zamykaniu; ostrzeżenie o niezatwierdzonej transakcji przy zamykaniu okna i aplikacji | UG 23.20, PROMPT §3.1 | SQL Window | 1 | P1 | — | do zrobienia |
| PD-SQLW-025 | Wklejenie tekstu na pusty obszar tworzy SQL Window | NF8 | — | 1 | P3 | — | do zrobienia |
| PD-SQLW-026 | Maksymalny rozmiar wyniku (MB) z pytaniem przed dalszym pobieraniem | UG 23.20 | Preferences | 1 | P2 | — | do zrobienia |

## PL/SQL Developer — siatka wyników

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| PD-GRID-001 | Siatka płynna przy milionach wierszy (dociąganie stronami, bez zacięć) | PROMPT §3.4 | Siatka | 1 | P1 | — | ✅ test |
| PD-GRID-002 | NULL na kolorowym tle (osobny kolor dla kolumn obowiązkowych), naprzemienne wiersze | UG 7.2, UG 23.20 | Siatka | 1 | P1 | — | 👁 ręcznie |
| PD-GRID-003 | `<CLOB>`, `<BLOB>`, `<Long>`… z przyciskiem komórki → Large Data Editor; przycisk dla tekstu > 20 znaków | UG 7.2 | Siatka | 1 | P1 | — | ✅ test |
| PD-GRID-004 | Liczby z pełną precyzją Oracle; układ liczb (lewo/prawo/formatowane/z separatorem tysięcy) | NF17, UG 23.20 | Siatka | 1 | P1 | — | w toku |
| PD-GRID-005 | Daty i znaczniki czasu wg formatu (NLS / własny), kalendarz przy edycji DATE | UG 7.2, UG 23.17 | Siatka | 1 | P1 | — | w toku |
| PD-GRID-006 | Kursor zagnieżdżony `<Cursor>` → nowe okno z wynikiem | UG 7.2 | Siatka | 1 | P3 | — | do zrobienia |
| PD-GRID-007 | Zaznaczanie wierszy, kolumn i bloków komórek; Select All; przenoszenie kolumn | UG 7.2 | Siatka | 1 | P1 | — | w toku |
| PD-GRID-008 | Blokada przewijania kolumn i wierszy (Scroll lock) | UG 7.2, NF9 | Siatka > Scroll lock | 1 | P2 | — | do zrobienia |
| PD-GRID-009 | Sortowanie lokalne klikiem nagłówka (rosnąco/malejąco/brak, wtórne, wielkość liter) | UG 7.2 | Siatka | 1 | P1 | — | ✅ test |
| PD-GRID-010 | Single Record View (kolumna, wartość, typ, komentarz; poprzedni/następny rekord) | UG 7.2, NF11 | Siatka | 1 | P1 | — | w toku |
| PD-GRID-011 | Filtr kolumn (nazwy, typy, obowiązkowe, PK/UK/FK, historia, wklejanie wielu linii) | UG 7.2, NF13, NF17 | Siatka > Filter columns | 1 | P2 | — | do zrobienia |
| PD-GRID-012 | Align (szerokość wg nagłówka/treści, wysokość, szablony wyrównania z kolejnością, auto-align), Hide Editor, Adjust Window width | UG 7.2, NF11 | Siatka > Align | 1 | P2 | — | do zrobienia |
| PD-GRID-013 | Eksport zaznaczenia: CSV, TSV, HTML, XML, SQL (INSERT), do pliku i do schowka | UG 7.2 | Siatka > Export Results | 1 | P1 | Brak | ✅ test |
| PD-GRID-014 | Excel (xlsx; „Copy all” — arkusz na wynik; z SQL na osobnym arkuszu, formatowanie, kolory) | UG 7.2, UG 23.30 | Siatka > Copy to Excel | 1 | P2 | Brak | ✅ test |
| PD-GRID-015 | Copy, Copy with Header, Copy Header, Copy as Expression List; kopiowanie także jako HTML | UG 7.2, NF12, NF17 | Siatka | 1 | P1 | — | ✅ test |
| PD-GRID-016 | Column to files (kolumna → plik na wiersz, katalog i nazwa z wyrażeń) | UG 7.2, NF15 | Siatka > Export Results | 6 | P3 | Brak | do zrobienia |
| PD-GRID-017 | Edycja wyniku z ROWID lub FOR UPDATE: Edit data, Insert record, Delete record, Post changes | UG 7.6 | Siatka | 1 | P1 | Za zgodą | ✅ test |
| PD-GRID-018 | Tabela edytowana ustalana z ROWID (złączenia), kolumny z aliasem tylko do odczytu, kolumny niewidoczne edytowalne | UG 7.6, NF17, NF13 | Siatka | 1 | P1 | — | ✅ test |
| PD-GRID-019 | Czerwony tekst przy przekroczeniu rozmiaru/precyzji; przeliczanie kolumn wirtualnych; wartości z wyzwalaczy po Post | UG 7.6, NF9 | Siatka | 1 | P2 | — | w toku |
| PD-GRID-020 | Podgląd SQL zmian siatki (SQL Window / Command Window / schowek) przed Post | UG 7.6, NF15 | Siatka > Post changes ▾ | 1 | P1 | — | ✅ test |
| PD-GRID-021 | Przejście do komórki z błędem po INSERT/UPDATE | NF12 | Siatka | 1 | P2 | — | ✅ test |
| PD-GRID-022 | Informacje słownika w siatce: typ, NOT NULL, komentarz na pasku; listy wartości z CHECK IN i FK do małych tabel | UG 23.20 | Siatka | 1 | P2 | — | do zrobienia |
| PD-GRID-023 | LOB pobierane na żądanie (preferencja) | UG 23.20, NF14 | Preferences | 1 | P2 | — | do zrobienia |
| PD-GRID-024 | Sumy kolumn (Sum/Count/Avg/Min/Max), trwałe po ponownym wykonaniu | UG 7.12, NF11 | Siatka | 1 | P2 | — | do zrobienia |
| PD-GRID-025 | Ctrl +/− rozmiar czcionki siatki | NF13 | Siatka | 1 | P3 | — | do zrobienia |
| PD-GRID-026 | Wielkie/małe litery klawiszem w edytowalnej siatce | NF17 | Siatka | 1 | P3 | — | do zrobienia |
| PD-GRID-027 | Numer wiersza w kopiowaniu/eksporcie (preferencja) | UG 23.20 | Preferences | 1 | P3 | — | do zrobienia |

## PL/SQL Developer — zmienne

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| PD-VAR-001 | Zmienne podstawiania `&nazwa`, `&&nazwa`, wiele wystąpień, okno pytania o wartości | UG 7.5 | SQL Window | 1 | P1 | — | ✅ test |
| PD-VAR-002 | Zmienne wiązane `:nazwa` w SQL Window (typ domyślnie tekst), pomijanie `:new`/`:old` w wyzwalaczach | UG 7.5, NF16 | SQL Window | 1 | P1 | — | ✅ test |
| PD-VAR-003 | Składnia opcji `&"Nazwa"` i `&<name= hint= type= required= default= ifempty= uppercase= lowercase= readonly= hidden= list= description= restricted= multiselect= checkbox= prefix= suffix= lines= editor=>` | UG 12.3, NF11 | SQL / Report Window, szablony | 1 | P1 | — | ✅ test |
| PD-VAR-004 | Listy zależne (`:inna_zmienna` w zapytaniu listy, `&zmienna` w listach) | UG 12.3, NF14 | Okno zmiennych | 1 | P2 | — | do zrobienia |
| PD-VAR-005 | Przycisk `&` na pasku stanu wyłącza podstawianie (także zmiennych wiązanych) | UG 7.5, NF17 | Pasek stanu | 1 | P2 | — | 👁 ręcznie |
| PD-VAR-006 | `&&` jako literał `&` w tekście (np. 'R&&D') | UG 12.3 | SQL Window | 1 | P2 | — | ✅ test |
| PD-VAR-007 | Parametry JasperReports `$P{}`, `$P!{}`, `$X{IN/NOTIN/EQUAL/NOTEQUAL/LESS/GREATER/BETWEEN…}` jako zmienne (decyzja właściciela D6) | D6 | SQL Window | 1 | P1 | — | ✅ test |
| PD-VAR-008 | Zapamiętywanie wartości zmiennych w oknie (.pfi) i przy Auto Refresh | UG 23.18, NF8 | SQL Window | 1 | P2 | — | do zrobienia |

## PL/SQL Developer — Command Window

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| PD-CMDW-001 | Karta Dialog (linia poleceń, historia linii) i karta Editor (plik skryptu z podświetlaniem) | UG 8.1–8.2 | Command Window | 1 | P1 | Brak | do zrobienia |
| PD-CMDW-002 | Pasek stanu opcji Echo, Termout, Feedback, Verify, Autoprint, Heading, Timing (dwuklik przełącza) | UG 8.1 | Command Window | 1 | P2 | Brak | do zrobienia |
| PD-CMDW-003 | Krokowanie skryptu: Pause Execution, Execute Next Command, SET EXECPAUSE | UG 8.2 | Command Window | 1 | P3 | Brak | do zrobienia |
| PD-CMDW-004 | Polecenia SQL*Plus: /, ?, @, @@, ACCEPT, CLEAR, COLUMN (FORMAT, NEW_VALUE), CONNECT, DEFINE, DESCRIBE, DISCONNECT, EDIT, EXECUTE, EXIT/QUIT, GET, HELP, PAUSE, PRINT, PROMPT, RUN, REMARK, START, STORE SET, UNDEFINE, VARIABLE, WHENEVER | UG 8.3 | Command Window | 1 | P1 | Brak | w toku |
| PD-CMDW-005 | SET: AUTOPRINT, COLSEP, CONCAT, DEFINE, ECHO, ESCAPE, FEEDBACK (ONLY, SQL_ID), HEADING, LONG, NUMWIDTH, PAGESIZE, PROMPT, SCAN, SERVEROUTPUT (SIZE UNLIMITED), SPOOLDIRECTORY, TERMOUT, TIMING, VERIFY | UG 8.3, NF17 | Command Window | 1 | P1 | Brak | ✅ test |
| PD-CMDW-006 | SHOW ERRORS / RELEASE / SQLCODE / USER / CONNECTION / ENVVAR | UG 8.3 | Command Window | 1 | P2 | Brak | ✅ test |
| PD-CMDW-007 | SPOOL (APPEND, OFF, OUT, .zip) | UG 8.3 | Command Window | 1 | P2 | Brak | ✅ test |
| PD-CMDW-008 | HOST (polecenie systemu — tylko użytkownik; agent nigdy) | UG 8.3, PROMPT §7.3 p.9 | Command Window | 1 | P3 | Brak | do zrobienia |
| PD-CMDW-009 | Polecenia własne: BEAUTIFY, BROWSE, CD, DIR, EDIT obiekt, EDITDATA, INFO, PROPERTIES, QUERYDATA, RECOMPILE, TEST, VIEW, ZIP, SET COLWIDTH, SET ENVVAR | UG 8.3 | Command Window | 6 | P3 | Brak | do zrobienia |
| PD-CMDW-010 | EXPORT TABLES / EXPORT OBJECTS (składnia jak narzędzia eksportu), RUNTESTSET | UG 8.4–8.5 | Command Window | 6 | P3 | Brak | do zrobienia |
| PD-CMDW-011 | Nieobsługiwane SET w skrypcie wsadowym bez błędu | NF17 | Command Window | 1 | P3 | Brak | ✅ test |
| PD-CMDW-012 | Code Assistant po `@` — listing katalogu; CONNECT z listą baz po `@` | UG 25.4, NF13, NF14 | Command Window | 2 | P3 | Brak | do zrobienia |
| PD-CMDW-013 | Wyniki zapytań w formacie tekstowym SQL*Plus (kolumny, nagłówki, PAGESIZE, COLSEP) | UG 8.3 | Command Window | 1 | P1 | Brak | ✅ test |

## PL/SQL Developer — Program Window i kompilacja

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| PD-PROG-001 | Program Window: wiele jednostek w pliku jako karty (specyfikacja/ciało), dodaj/usuń jednostkę | UG 4.1 | Program Window | 2 | P1 | Pełny | do zrobienia |
| PD-PROG-002 | Nowy program z szablonu (funkcja, procedura, pakiet, typ, wyzwalacz, Java, MLE) z formularzem zmiennych | UG 4.1, NF17 | File > New > Program Window | 2 | P1 | Pełny | do zrobienia |
| PD-PROG-003 | Kompilacja wszystkich jednostek po kolei, stop przy błędzie, kursor w linii błędu | UG 4.4 | Execute (F8) | 2 | P1 | Za zgodą | do zrobienia |
| PD-PROG-004 | Lista błędów i ostrzeżeń PLSQL_WARNINGS pod edytorem (klik = przejście, dwuklik = pomoc Oracle) | UG 4.4, NF16 | Program Window | 2 | P1 | Odczyt | do zrobienia |
| PD-PROG-005 | Podpowiedzi kompilatora (hints) i konwencje nazw; `-- Ignore` | UG 4.4, UG 23.9 | Tools > Show Compiler Hints | 2 | P2 | Odczyt | do zrobienia |
| PD-PROG-006 | Wskaźniki: zmieniony niezapisany (niebieski), niezskompilowany (żółty) | UG 4.3 | Pasek stanu okna | 2 | P1 | — | do zrobienia |
| PD-PROG-007 | Zapis do pliku zgodnego z SQL*Plus, rozszerzenia per typ, nazwa z jednostki (opcjonalnie z właścicielem), końcowy `/` | UG 4.2, UG 23.19, UG 23.29 | File > Save | 2 | P1 | Pełny | do zrobienia |
| PD-PROG-008 | Porównanie: z plikiem, ze źródłem w bazie, z innym plikiem, z obiektem w innej bazie | UG 4.5, NF10 | Compare to | 2 | P2 | Odczyt | do zrobienia |
| PD-PROG-009 | Edycja źródła prosto z bazy (Edit), pytanie o zapis do pliku, Revert | UG 23.2, UG 15.1 | Object Browser > Edit | 2 | P1 | Pełny | do zrobienia |
| PD-PROG-010 | Safe compilation (próbna kompilacja obiektu tymczasowego) | UG 23.19 | Preferences | 2 | P3 | — | do zrobienia |
| PD-PROG-011 | Wykrywanie zmian obiektu w bazie przez innych (co n s), różnice i przeładowanie | UG 23.19, NF10 | Program Window | 2 | P2 | — | do zrobienia |
| PD-PROG-012 | Kompilacja w tle w osobnej sesji; blokada kompilacji w trakcie wykonywania | UG 23.19 | Preferences | 2 | P2 | — | do zrobienia |
| PD-PROG-013 | Preferencje kompilatora: PLSQL_OPTIMIZE_LEVEL, CODE_TYPE, PL/Scope, flagi kompilacji warunkowej, PLSQL_WARNINGS, wartości `&` | UG 23.3 | Preferences > Oracle > Compiler | 2 | P2 | — | do zrobienia |
| PD-PROG-014 | Moduły MLE (JavaScript) w Program Window: edycja, podświetlanie, kompilacja | NF17 | Program Window | 2 | P2 | Za zgodą | do zrobienia |
| PD-PROG-015 | Podświetlanie poleceń transakcyjnych (COMMIT/ROLLBACK/SAVEPOINT) i par if/loop/case/blok | NF14, UG 23.19 | Program Window | 2 | P2 | — | do zrobienia |
| PD-PROG-016 | Uruchomienie bloku PL/SQL z Program Window z DBMS_OUTPUT | NF13 | Program Window | 2 | P3 | Za zgodą | do zrobienia |
| PD-PROG-017 | Kompilacja tylko do odczytu plików wyłączona (preferencja) | UG 23.2 | Preferences | 2 | P3 | — | do zrobienia |
| PD-PROG-018 | Edycja pakietu 50 000 linii bez opóźnień (podświetlanie, Code Assistant) | PROMPT §3.4, §8 | Program Window | 2 | P1 | — | do zrobienia |

## PL/SQL Developer — edytor

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| PD-EDIT-001 | Podświetlanie składni SQL, PL/SQL, SQL*Plus (kolory, styl, wielkość liter słów kluczowych przy pisaniu) | UG 23.12 | Edytor | 1 | P1 | — | w toku |
| PD-EDIT-002 | Lekser przyrostowy (stan na końcu linii), tolerancyjny | PROMPT §4.1 | Edytor | 1 | P1 | — | ✅ test |
| PD-EDIT-003 | Numery linii (interwał), status linii (zmieniona/nowa), podświetlenie bieżącej linii, margines pionowy, znaki specjalne | UG 23.12 | Edytor | 1 | P1 | — | w toku |
| PD-EDIT-004 | Wcięcia None/Automatic/Smart, Backspace/Delete unindents, tabulacje, zawijanie, kursor za końcem linii | UG 23.12 | Edytor | 1 | P1 | — | do zrobienia |
| PD-EDIT-005 | Funkcje zaznaczenia: wcięcie, usuń końcowe spacje, wielkie/małe litery (bez literałów), komentarz, Apply Syntax Case, sortowanie | UG 25.1 | Edit > Selection | 1 | P1 | Pełny | do zrobienia |
| PD-EDIT-006 | Komentarz/odkomentowanie linii (Ctrl+−) | NF15 | Edytor | 1 | P1 | — | do zrobienia |
| PD-EDIT-007 | Zaznaczenie kolumnowe (Alt+przeciąganie) z pisaniem w wielu liniach | UG 25.2, NF13 | Edytor | 1 | P2 | — | do zrobienia |
| PD-EDIT-008 | Find & Replace: regex (z `$1`, `\t`), całe słowa, wielkość liter, Preserve case, Search in (komentarze/literały/kod), zakres, kierunek, Search All | UG 25.3, NF13, NF16 | Ctrl+F | 1 | P1 | Pełny | do zrobienia |
| PD-EDIT-009 | Recall Statement: globalna historia wykonanych poleceń (bez haseł), filtr, wiele naraz, eksport | UG 25.5 | Ctrl+E | 1 | P1 | Odczyt | w toku |
| PD-EDIT-010 | Go to line (od początku / kursora / początku polecenia) | UG 25.12 | Ctrl+G | 1 | P1 | Pełny | do zrobienia |
| PD-EDIT-011 | Zakładki 0–9 (Ctrl+K n / Ctrl+Q n), nazwy, lista zakładek | UG 25.13, NF15 | Edit > Bookmarks | 2 | P2 | — | do zrobienia |
| PD-EDIT-012 | Color marks (kolorowanie fragmentów) | UG 25.14 | Edit > Color marker | 2 | P3 | — | do zrobienia |
| PD-EDIT-013 | Zwijanie kodu (+/−, Fold All, podgląd zwiniętego), klawisze zwijania | UG 25.17, NF13 | Edytor | 2 | P1 | — | do zrobienia |
| PD-EDIT-014 | Split editing (dwa widoki tego samego źródła, zakładki zsynchronizowane) | UG 25.18, NF16 | Edytor | 2 | P2 | — | do zrobienia |
| PD-EDIT-015 | Makra: nagrywanie F11, odtwarzanie F12, Repeat Play, biblioteka makr z klawiszami | UG 25.11, NF15 | Edit > Macro | 6 | P2 | Brak | do zrobienia |
| PD-EDIT-016 | Special Copy (formaty .copy dla języków) i Paste from host language | UG 25.6–25.7, NF10 | Edit | 6 | P3 | Pełny | do zrobienia |
| PD-EDIT-017 | AutoReplace (skróty → tekst lub szablon), także po symbolach | UG 23.12, NF16 | Edytor | 2 | P2 | — | do zrobienia |
| PD-EDIT-018 | Podświetlanie nawiasów, zmiennych, pasujących słów przy zaznaczeniu, kolumn INSERT ↔ VALUES, tabela.kolumna | UG 23.12, NF13, NF14 | Edytor | 2 | P2 | — | do zrobienia |
| PD-EDIT-019 | Oznaczanie identyfikatorów > 30 znaków | UG 23.12, NF10 | Edytor | 2 | P3 | — | do zrobienia |
| PD-EDIT-020 | Duplicate line, Delete next word, First Character on Line | NF13, NF9 | Edytor | 1 | P2 | — | do zrobienia |
| PD-EDIT-021 | Ctrl +/− rozmiar czcionki edytora; ligatury (Fira Code, JetBrains Mono…) | NF13, NF17 | Edytor | 1 | P3 | — | do zrobienia |
| PD-EDIT-022 | Pasek stanu: `linia:kolumna [długość zaznaczenia]` | NF15 | Edytor | 1 | P2 | — | do zrobienia |
| PD-EDIT-023 | Wiele kursorów (macOS: Option+klik / Ctrl+Shift+strzałki) | PROMPT §3.1 | Edytor | 2 | P3 | — | do zrobienia |
| PD-EDIT-024 | Historia schowka PL/SQL Clipboard (dokowalna, filtr, podgląd, wklejanie) | UG 30, NF12 | View > PL/SQL Clipboard | 6 | P3 | — | do zrobienia |
| PD-EDIT-025 | Menu obiektu bazy na nazwie w edytorze (jak w Object Browserze) | UG 25.9 | Edytor | 2 | P1 | — | do zrobienia |
| PD-EDIT-026 | F1 — pomoc kontekstowa w dokumentacji Oracle; pomoc błędu (Oracle Error Help URL) | UG 25.8, UG 23.10, NF16 | Edytor | 2 | P2 | — | do zrobienia |
| PD-EDIT-027 | Web Search (konfigurowalne wyszukiwania z %s) | UG 25.23, NF10 | Edit > Web Search | 8 | P3 | — | do zrobienia |
| PD-EDIT-028 | Otwórz w zewnętrznym edytorze (np. VS Code) | NF17 | Edytor | 8 | P3 | — | do zrobienia |
| PD-EDIT-029 | Zachowanie stanu okna (.pfi): pozycja, zakładki, znaczniki, zmienne | UG 23.18 | Preferences | 2 | P3 | — | do zrobienia |

## PL/SQL Developer — Code Assistant i nawigacja

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| PD-CA-001 | Code Assistant po `obiekt.`: elementy pakietu, parametry (notacja nazwana), kolumny, NEXTVAL/CURRVAL, obiekty użytkownika | UG 25.4 | Edytor | 2 | P1 | — | do zrobienia |
| PD-CA-002 | Code Assistant dla zmiennych: kursor, rekord, %ROWTYPE (bez niewidocznych), obiekt, kolekcja, `:new`/`:old`, Self | UG 25.4, NF17 | Edytor | 2 | P1 | — | do zrobienia |
| PD-CA-003 | Kontekst: obiekty dostępne, kolumny tabel DML (bez aliasu), słowa kluczowe, identyfikatory jednostki i specyfikacji | UG 25.4, NF12, NF17 | Edytor | 2 | P1 | — | do zrobienia |
| PD-CA-004 | Aliasy tabel w zapytaniu (`e.` → kolumny EMP) | PROMPT §3.1 | Edytor | 2 | P1 | — | do zrobienia |
| PD-CA-005 | `@` — linki bazy | UG 25.4, NF9 | Edytor | 2 | P3 | — | do zrobienia |
| PD-CA-006 | Wybór wielu elementów i „(all)” (kolumny, parametry, konstruktory, pola widoku inline), układ w liniach, wyrównanie `=>`, przecinek przed | UG 25.4, UG 23.14 | Edytor | 2 | P2 | — | do zrobienia |
| PD-CA-007 | Preferencje: auto/klawisz, opóźnienie, Contains/Starts with, styl wielkości liter, oryginalna wielkość liter, min. liczba znaków, funkcje standardowe | UG 23.14 | Preferences | 2 | P2 | — | do zrobienia |
| PD-CA-008 | Deklaracja zmiennej/typu w dymku po najechaniu | UG 23.14, NF8 | Edytor | 2 | P2 | — | do zrobienia |
| PD-CA-009 | Refresh Code Assistant (cache metadanych odświeżany w tle) | NF14, PROMPT §4.2 p.5 | Edytor | 2 | P1 | — | do zrobienia |
| PD-CA-010 | Code Contents: drzewo struktury, śledzenie kursora, hot track, sortowanie, menu (zaznacz, wytnij, test…) | UG 25.15 | Program Window | 2 | P1 | Odczyt | do zrobienia |
| PD-CA-011 | Code Hierarchy nad edytorem (ścieżka od kursora, zaznaczanie, menu) | UG 25.16 | Program Window | 2 | P2 | — | do zrobienia |
| PD-CA-012 | Hyperlink navigation (Cmd/Ctrl+klik) do deklaracji: w źródle, w oknach, w nowym oknie; tabela → definicja / zapytanie | UG 25.19, NF17 | Edytor | 2 | P1 | Pełny | do zrobienia |
| PD-CA-013 | Navigate back / forward (historia skoków) | UG 25.20 | Edit > Navigation | 2 | P1 | Pełny | do zrobienia |
| PD-CA-014 | Refaktoryzacja: Rename item, Extract procedure, Extract local/global constant, Replace assignment with initialization | UG 25.21, NF13 | Edytor > Refactoring | 2 | P2 | Pełny | do zrobienia |
| PD-CA-015 | Search Bar: wszystkie edytory / bieżący / pliki w katalogach, lista wyników | UG 25.22, NF11 | View > Search Bar | 2 | P2 | Odczyt | do zrobienia |

## PL/SQL Developer — Test Window, debuger, optymalizacja

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| PD-TEST-001 | Test Window: blok PL/SQL + lista zmiennych (nazwa, typ, wartość), skanowanie zmiennych (auto) | UG 5.1, UG 23.21 | File > New > Test Window | 3 | P1 | Za zgodą | do zrobienia |
| PD-TEST-002 | Typy zmiennych: Integer, Float, String, Date, Long, Long Raw, Cursor, CLOB/BLOB/BFile, PL/SQL String, Char, Substitution, Temporary CLOB/BLOB, Boolean | UG 5.3 | Test Window | 3 | P1 | — | do zrobienia |
| PD-TEST-003 | Wykonanie: zmienione wartości na żółto, czas, Break, Commit/Rollback, AutoCommit after execute | UG 5.2, UG 23.21 | Test Window | 3 | P1 | Za zgodą | do zrobienia |
| PD-TEST-004 | Test z Object Browsera (skrypt ze zmiennymi parametrów i wyniku, właściwe przeciążenie) | UG 5.1, NF14 | Object Browser > Test | 3 | P1 | Pełny | do zrobienia |
| PD-TEST-005 | Zapis .tst (blok, zmienne, obserwowane), Load, zapis jako skrypt SQL*Plus | UG 5.4 | File > Save | 3 | P1 | Pełny | do zrobienia |
| PD-TEST-006 | Stos błędu wykonania z kartami jednostek i liniami na czerwono | UG 5.5 | Test Window | 3 | P1 | Odczyt | do zrobienia |
| PD-TEST-007 | Ostrzeżenia ORA-04068 / ORA-29549 na pasku stanu | UG 5.6 | Test Window | 3 | P3 | — | do zrobienia |
| PD-TEST-008 | Karty Results (SELECT), Output (DBMS_OUTPUT), HTP Output, niejawne wyniki 12c jako zmienne | UG 5.7–5.9, NF12 | Test Window | 3 | P2 | Odczyt | do zrobienia |
| PD-TEST-009 | Standard Tests dla funkcji/procedur w menu kontekstowym | UG 5.13, NF12 | Test Window | 3 | P3 | Odczyt | do zrobienia |
| PD-DBG-001 | Debuger DBMS_DEBUG: Start, Run, Step into (także do wyzwalacza), Step over, Step out, Run to cursor, Run until exception | UG 5.10, NF11 | Test Window > Debug | 3 | P1 | Brak | do zrobienia |
| PD-DBG-002 | Debuger DBMS_DEBUG_JDWP (wybór systemu, port, kreator konfiguracji JDWP); sprawdzenie dostępności na wersji bazy | UG 5.10, NF17 | Test Window > Start ▾ | 3 | P2 | Brak | do zrobienia |
| PD-DBG-003 | Stos wywołań (klik = ramka i jej zmienne), panel po prawej/lewej/dole | UG 5.10, NF17 | Test Window | 3 | P1 | Brak | do zrobienia |
| PD-DBG-004 | Zmienne automatycznie: Local, Global Private, Global Public, Input Values; rekordy, kolekcje, obiekty jako drzewo; Self; Old/New w wyzwalaczu | UG 5.10, NF17, NF12 | Test Window | 3 | P1 | Brak | do zrobienia |
| PD-DBG-005 | Wartość w dymku po najechaniu; Set Variable; Copy variable / Append to clipboard | UG 5.10, UG 23.4, NF14, NF17 | Test Window | 3 | P2 | Brak | do zrobienia |
| PD-DBG-006 | Obserwowane wyrażenia (watches) | PROMPT §3.1, UG 5.4 | Test Window | 3 | P2 | Brak | do zrobienia |
| PD-DBG-007 | Punkty przerwania na marginesie (Program i Test Window), znacznik nie zastosowanego, warunki, komunikaty, Don't Break, Pass Count, Logpoint | UG 5.10, NF13 | Edit > Breakpoints | 3 | P1 | Brak | do zrobienia |
| PD-DBG-008 | Error breakpoints (kody błędów), zapis/odczyt punktów, Enable/Disable All | UG 5.10, NF12, NF10 | Modify Breakpoints | 3 | P2 | Brak | do zrobienia |
| PD-DBG-009 | Wykonanie SQL w sesji debugowanej (DBMS_DEBUG) z wynikiem | UG 5.10, NF10 | Test Window > Debug | 3 | P3 | Brak | do zrobienia |
| PD-DBG-010 | DBMS_OUTPUT w trakcie debugowania | NF10 | Test Window | 3 | P2 | Brak | do zrobienia |
| PD-DBG-011 | Add debug information (z Object Browsera i automatycznie przy kompilacji; listy NEVER/ALWAYS dla połączeń i obiektów) | UG 21.1, UG 23.4 | Object Browser | 3 | P2 | Za zgodą | do zrobienia |
| PD-DBG-012 | Preferencje: pomijanie inicjalizacji pakietów i obiektów SYS | UG 23.4 | Preferences > Debugger | 3 | P3 | — | do zrobienia |
| PD-DBG-013 | Nadawanie uprawnień DEBUG z interfejsu | NF12 | Object Browser | 3 | P3 | Brak | do zrobienia |
| PD-OPT-001 | Explain Plan Window: plan w drzewie, Optimizer goal, nawigacja w kolejności wykonania, tworzenie PLAN_TABLE, kolumny | UG 6.1, UG 23.22 | File > New > Explain Plan Window | 6 | P1 | Odczyt | do zrobienia |
| PD-OPT-002 | Explain Plan z zaznaczenia (F5) z zamianą zmiennych PL/SQL na wiązane | UG 6.1, UG 25.10 | Tools > Explain Plan (F5) | 6 | P1 | Odczyt | do zrobienia |
| PD-OPT-003 | Plan w formacie HTML, Text, XML (DBMS_XPLAN) | UG 6.1, NF11 | Explain Plan Window | 6 | P2 | Odczyt | do zrobienia |
| PD-OPT-004 | Statystyki automatyczne (V$SESSTAT): ostatnie i suma sesji, wybór statystyk, filtr, sortowanie, eksport | UG 6.2, UG 23.2, NF15 | Karta Statistics | 3 | P2 | Odczyt | do zrobienia |
| PD-OPT-005 | Profiler PL/SQL (DBMS_PROFILER): raport na linię, przebiegi, jednostki, wykres, preferencje | UG 6.3, UG 23.7 | Test Window > Profiler | 3 | P2 | Brak | do zrobienia |
| PD-OPT-006 | Profiler hierarchiczny (DBMS_HPROF) | PROMPT §3.1 | Test Window | 3 | P2 | Brak | do zrobienia |
| PD-OPT-007 | Trace (DBMS_TRACE): poziomy, raport, historia przebiegów, kolumny | UG 5.11, UG 23.6 | Test Window > Trace | 3 | P3 | Brak | do zrobienia |
| PD-OPT-008 | SQL Trace sesji okna (przełącznik) | UG 6.4 | Session > SQL Trace | 3 | P3 | Brak | do zrobienia |

## PL/SQL Developer — Object Browser i edytory obiektów

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| PD-OB-001 | Drzewo folderów wg typów obiektów (tabele, widoki, MV, sekwencje, synonimy, pakiety, funkcje, procedury, typy, wyzwalacze, Java, kolejki, linki, użytkownicy, role, profile, katalogi, biblioteki, joby, obiekty schedulera, kosz…) | UG 21.1, NF8 | View > Object Browser | 2 | P1 | Odczyt | do zrobienia |
| PD-OB-002 | Foldery 23ai/26ai: MLE Modules, Domains, Annotations (+ użycie), Assertions | NF17 | Object Browser | 2 | P1 | Odczyt | do zrobienia |
| PD-OB-003 | Podfoldery obiektu (kolumny z typami, klucze, indeksy, wyzwalacze, zależności, przeciążenia) | UG 21.1, UG 23.11, NF14 | Object Browser | 2 | P1 | Odczyt | do zrobienia |
| PD-OB-004 | Recent objects; cache słownika w pamięci; Refresh obiektu / całości | UG 21.1 | Object Browser | 2 | P1 | — | do zrobienia |
| PD-OB-005 | Wybór użytkownika (<CURRENT USER>, <ALL USERS>, konkretny, ostatni per połączenie) | UG 21.1, UG 23.11, NF10 | Object Browser | 2 | P1 | — | do zrobienia |
| PD-OB-006 | Filtr ad hoc (nazwy z %, wiele po przecinku) i formularz: Name, Source, Status, Created/Modified After/Before | UG 21.1, NF11, NF14 | Object Browser | 2 | P1 | — | do zrobienia |
| PD-OB-007 | Filtry nazwane (WHERE/ORDER BY na all_objects, :browser_user, &browser_filter, per użytkownik, domyślny) | UG 21.2 | Configure > Object Browser Filters | 2 | P2 | — | do zrobienia |
| PD-OB-008 | Foldery użytkownika (zapytanie i/lub lista obiektów, kolor, hierarchia, widoczność per połączenie, Suppress owner); Add to folder | UG 21.3 | Configure > Object Browser Folders | 2 | P2 | — | do zrobienia |
| PD-OB-009 | Obiekty niepoprawne z czerwonym znacznikiem; Recompile; Recompile referencing objects | UG 21.1 | Object Browser | 2 | P1 | Za zgodą | do zrobienia |
| PD-OB-010 | Przeciąganie obiektu do edytora (menu: nazwa, właściwości, opis, SELECT/INSERT…) i na obszar roboczy (akcja z preferencji); folder → nazwy po przecinku | UG 21.1, UG 23.11 | Object Browser | 2 | P1 | — | do zrobienia |
| PD-OB-011 | Wybór wielu obiektów (akcje wspólne), Copy comma separated, Cmd+C | UG 21.1, NF17 | Object Browser | 2 | P2 | — | do zrobienia |
| PD-OB-012 | Properties (okno niemodalne, zwijane) | UG 21.1 | Object Browser > Properties | 2 | P1 | Odczyt | do zrobienia |
| PD-OB-013 | Describe (kolumny / parametry / elementy pakietu / metody typu), kopiowanie, eksport, dwuklik wstawia do edytora | UG 21.1 | Object Browser > Describe | 2 | P1 | Odczyt | do zrobienia |
| PD-OB-014 | View / Edit (Program Window, SQL Window dla widoków, edytory tabel/sekwencji/synonimów) | UG 21.1 | Object Browser | 2 | P1 | Odczyt | do zrobienia |
| PD-OB-015 | DDL obiektu (DBMS_METADATA), prefiks właściciela, FORCE i lista aliasów dla widoków | UG 23.2, NF17 | Object Browser > DDL | 2 | P1 | Odczyt | do zrobienia |
| PD-OB-016 | Rename (tabele, widoki, sekwencje, synonimy, kolumny, indeksy, więzy), Drop (z potwierdzeniem), Duplicate | UG 21.1, NF11 | Object Browser | 2 | P1 | Za zgodą | do zrobienia |
| PD-OB-017 | Query data / Edit data (SQL Window z ROWID, AutoExecute), z synonimu | UG 21.1, NF13 | Object Browser | 2 | P1 | Odczyt | do zrobienia |
| PD-OB-018 | Browse (obiekty powiązane), zależności (używa / używany przez) | UG 21.1 | Object Browser > Browse | 2 | P1 | Odczyt | do zrobienia |
| PD-OB-019 | Enable/Disable wyzwalaczy i więzów; Run job (DBMS_JOB); kolejki enqueue/dequeue; Refresh MV; Test linku | UG 21.1, NF13 | Object Browser | 2 | P2 | Za zgodą | do zrobienia |
| PD-OB-020 | PL/SQL CCFlags (podgląd i zmiana flag z rekompilacją) | UG 21.1 | Object Browser | 2 | P3 | Za zgodą | do zrobienia |
| PD-OB-021 | Kosz: Purge / Restore (pod starą lub nową nazwą) | UG 21.1 | Object Browser > Recycle bin | 2 | P2 | Za zgodą | do zrobienia |
| PD-OB-022 | Compare obiektu (z bazą/schematem, plikiem, bieżącym oknem) | UG 21.1, NF12 | Object Browser > Compare | 2 | P2 | Odczyt | do zrobienia |
| PD-OB-023 | Add source to editor (Program/Test Window) | UG 21.1 | Object Browser | 2 | P3 | — | do zrobienia |
| PD-OB-024 | Object Browser ze 100 000 obiektów bez blokady interfejsu | PROMPT §9 | Object Browser | 2 | P1 | — | do zrobienia |
| PD-OB-025 | Preferencje: widoczne foldery i kolejność, limit Recent, akcja dwukliku/przeciągania per typ, typy danych, Confirm Recompile, publiczne linki | UG 23.11 | Preferences | 2 | P2 | — | do zrobienia |
| PD-OB-026 | Zapytania słownika odporne na wersję (19c, 21c, 23ai/26ai; starsze — brak kolumn/widoków), DBA views gdy dostępne | PROMPT §9, UG 23.2 | — | 2 | P1 | — | do zrobienia |
| PD-OED-001 | Table Definition Editor: General (właściciel, przestrzeń, storage, klaster, temporary, organizacja heap/IOT/external, komentarz, Recreate table) | UG 9.1 | File > New > Table | 2 | P1 | Za zgodą | do zrobienia |
| PD-OED-002 | Tabela — Columns (typ z podpowiedzią, domyślna, wirtualna, identity, DEFAULT ON NULL, niewidoczne, tabela obiektowa, Add foreign key columns) | UG 9.1, NF11, NF13 | Table Editor | 2 | P1 | Za zgodą | do zrobienia |
| PD-OED-003 | Tabela — domeny i adnotacje (kolumny i tabela) 23ai | NF17 | Table Editor | 2 | P2 | Za zgodą | do zrobienia |
| PD-OED-004 | Tabela — Keys, Checks, Indexes (normal/unique/bitmap, funkcyjne, DESC, kompresja, reverse, niewidoczne, lokalne partycjonowane, storage) | UG 9.1, NF10, NF11 | Table Editor | 2 | P1 | Za zgodą | do zrobienia |
| PD-OED-005 | Tabela — Privileges (Select/Insert/Update/Delete/References/Alter/Index/Read: brak/Yes/Grantable) | UG 9.1, NF12 | Table Editor | 2 | P2 | Za zgodą | do zrobienia |
| PD-OED-006 | Tabela — Partitions (Range/Hash/List, subpartycje), Triggers (nowy, usuń, Enabled, edycja), External | UG 9.1, NF10 | Table Editor | 2 | P2 | Za zgodą | do zrobienia |
| PD-OED-007 | Tabela — View SQL (DDL zmian, edycja SQL i zastosowanie, zapis/schowek/Command Window), Apply, Refresh, Query | UG 9.1 | Table Editor | 2 | P1 | Za zgodą | do zrobienia |
| PD-OED-008 | Edytory: Sequence, Synonym, Library, Directory, Job (DBMS_JOB), Queue, Queue Table | UG 9.2–9.8 | File > New | 2 | P2 | Za zgodą | do zrobienia |
| PD-OED-009 | Edytory: User (uprawnienia obiektowe, role, systemowe, quoty), Role, Profile, Database link | UG 9.9–9.12 | File > New | 2 | P2 | Za zgodą | do zrobienia |
| PD-OED-010 | Edytor widoku w SQL Window z szablonu; edytory widoku i indeksu (z SQL Developer for VS Code) | UG 21.1 | File > New > View | 2 | P2 | Za zgodą | do zrobienia |
| PD-OED-011 | Domena (File > New > Domain z szablonem; View/Edit/Drop/Properties) i Assertion (26ai) | NF17 | File > New | 2 | P2 | Za zgodą | do zrobienia |
| PD-OED-012 | Row Archival w edytorze tabeli | NF14 | Table Editor | 2 | P3 | Za zgodą | do zrobienia |

## PL/SQL Developer — narzędzia

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| PD-TOOL-001 | Find Database Objects: pełnotekstowo w źródłach/DDL (regex, całe słowa), kryteria, typy (MLE), w tle, Locate text, eksport, zapis kryteriów | UG 24.2, NF17 | Tools > Find Database Objects | 2 | P1 | Odczyt | do zrobienia |
| PD-TOOL-002 | Compile Invalid Objects (kolejność zależności, błędy, użytkownik, MLE) | UG 24.3, NF12 | Tools > Compile Invalid Objects | 2 | P1 | Za zgodą | do zrobienia |
| PD-TOOL-003 | Export Tables — SQL Inserts (Drop/Create/Truncate/Delete, wyzwalacze, FK, storage, uprawnienia, Commit every, Batch, WHERE, Zip) | UG 24.4, NF16 | Tools > Export Tables | 6 | P2 | Brak | do zrobienia |
| PD-TOOL-004 | Export Tables — format własny (skompresowany) i Import Tables tego formatu z wyborem tabel | UG 24.4–24.5 | Tools > Export/Import Tables | 6 | P3 | Brak | do zrobienia |
| PD-TOOL-005 | Export/Import przez Data Pump (DBMS_DATAPUMP) zamiast exp/imp | PROMPT §3.1, UG 24.4 | Tools > Export/Import Tables | 6 | P2 | Brak | do zrobienia |
| PD-TOOL-006 | Import Tables — SQL Inserts (wewnętrzny Command Window) | UG 24.5 | Tools > Import Tables | 6 | P2 | Brak | do zrobienia |
| PD-TOOL-007 | Export User Objects (DDL; single file / plik na obiekt / spec+body razem; uprawnienia, storage, właściciel; sekwencje pierwsze) | UG 24.6, NF16 | Tools > Export User Objects | 6 | P2 | Brak | do zrobienia |
| PD-TOOL-008 | Text Importer (auto-wykrywanie, definicja pól, filtr SQL, Create table, mapowanie, funkcje `#`, duplikaty, skrypty, Import / Import to Script, zapis definicji) | UG 24.7, NF10 | Tools > Text Importer | 6 | P2 | Brak | do zrobienia |
| PD-TOOL-009 | Excel Importer (.xlsx bez ODBC, arkusz, nagłówek, zakres linii, wklejanie z Excela, mapowanie, funkcje `#`) | UG 24.8, NF17 | Tools > Excel Importer | 6 | P2 | Brak | do zrobienia |
| PD-TOOL-010 | ODBC Importer | UG 24.9 | Tools > ODBC Importer | 6 | P3 | — | pominięte (ODBC na macOS bez sensu dla Oracle; zastępuje Text/Excel Importer i kreator importu — gap-analysis) |
| PD-TOOL-011 | Data Generator (tabele, liczba rekordów, master/detail, składnia [Aa0], funkcje, zbiory danych, opcje, test run / SQL / DB) | UG 24.10 | Tools > Data Generator | 6 | P2 | Brak | do zrobienia |
| PD-TOOL-012 | Compare User Objects (wybór obiektów, sesja docelowa, opcje ignorowania, lista różnic w kolejności zależności, SQL wyrównujący, Show Differences, Apply/Save/Copy SQL) | UG 24.11, NF15 | Tools > Compare User Objects | 6 | P2 | Odczyt | do zrobienia |
| PD-TOOL-013 | Compare Table Data (akcje, Commit every, skrypt / aktualizacja, schemat docelowy, przegląd różnic) | UG 24.12 | Tools > Compare Table Data | 6 | P2 | Odczyt | do zrobienia |
| PD-TOOL-014 | Event Monitor (DBMS_ALERT, DBMS_PIPE, DBMS_OUTPUT) | UG 24.13, PROMPT §3.1 | Tools > Event Monitor | 6 | P3 | Brak | do zrobienia |
| PD-TOOL-015 | Sessions: lista sesji, filtry, Kill (immediate), SQL Trace, Auto refresh, karty szczegółów (SQL, blokady, statystyki, SQL Monitor), Single Record View | UG 24.14, NF11, NF12 | Tools > Sessions | 6 | P1 | Odczyt | do zrobienia |
| PD-TOOL-016 | Define Session Queries: Filters, Details (`:sid`, `/* concatenate */`), Actions (z DBMS_OUTPUT), minimalna wersja bazy | UG 24.14, NF14 | Sessions | 6 | P2 | — | do zrobienia |
| PD-TOOL-017 | User Defined Tools (External / Session, zmienne #file #object…, opcje; bez haseł w argumentach) | UG 24.15, NF17 | Configure > Tools | 6 | P3 | Brak | do zrobienia |
| PD-TOOL-018 | Test Manager (Test Set, zmienne wejście/oczekiwane, LIKE/IN/null, Global, dbms_output, wydajność, Run, Debug, RunTestSet) | UG 24.16 | Tools > Test Manager | 6 | P3 | Za zgodą | do zrobienia |
| PD-TOOL-019 | Load Tester (kroki, zmienne, wątki, połączenia, wyniki na żywo: tekst, słupki, linie; zapis do Excela) | UG 24.17, NF13 | Tools > Load Tester | 6 | P3 | Brak | do zrobienia |
| PD-SCHED-001 | DBMS Scheduler: drzewo obiektów (Windows, Window groups, Job classes, Schedules, Programs, Chains, Jobs, File watchers, Credentials) | UG 10, NF8, NF10, NF15 | Tools > DBMS Scheduler | 6 | P2 | Odczyt | do zrobienia |
| PD-SCHED-002 | Tworzenie, edycja (inline / nazwany harmonogram), View SQL, Drop obiektów schedulera; powiadomienia e-mail zadań | UG 10.1–10.3, NF10 | DBMS Scheduler | 6 | P2 | Za zgodą | do zrobienia |
| PD-SCHED-003 | Job runs: raporty (All, Failed…), własne raporty z warunkami kolorów; Running jobs ze Stop (Force) | UG 10.4–10.5, NF13 | DBMS Scheduler | 6 | P2 | Odczyt | do zrobienia |
| PD-DIAG-001 | Diagram Window: obiekty z Object Browsera, relacje z FK (dodaj powiązane), Reference links (zależności), elementy pokaż/ukryj, sortowanie | UG 11.1, NF13 | File > New > Diagram Window | 6 | P2 | Odczyt | do zrobienia |
| PD-DIAG-002 | Diagram: linie (łamanie, zakończenia, kolor, etykiety), grupy, notatki, siatka 8 px, zoom 10–200 % | UG 11.1–11.2 | Diagram Window | 6 | P3 | — | do zrobienia |
| PD-DIAG-003 | Diagram: zapis pliku (format własny), Update from DB, druk, eksport do obrazu (PNG/PDF) i schowka | UG 11.3–11.6 | Diagram Window | 6 | P3 | — | do zrobienia |
| PD-REP-001 | Raporty standardowe (m.in. Compilation errors) w menu Reports, wynik HTML, druk, zapis HTML/PDF, eksport CSV/TSV/XML/Excel | UG 12.1 | Reports | 6 | P2 | Odczyt | do zrobienia |
| PD-REP-002 | Report Window: własny raport z SELECT, zmienne (składnia 12.3), Execute | UG 12.2–12.3 | File > New > Report Window | 6 | P2 | Odczyt | do zrobienia |
| PD-REP-003 | Układ raportu: style CSS, biblioteka stylów, wyrównanie, format liczb/dat, Break / Master-Detail, Sum, nagłówki stron ze zmiennymi | UG 12.4–12.5 | Report Window > Layout | 6 | P3 | — | do zrobienia |
| PD-REP-004 | Opcje raportu: parametry połączenia, zabezpieczenie (blokada definicji), Form layout, page break, tło; menu Reports z katalogów | UG 12.6–12.7 | Report Window > Options | 6 | P3 | — | do zrobienia |
| PD-GRAPH-001 | Graph Window z wyniku SQL/Report Window: kreator osi, style, szablony, auto-odświeżanie | UG 13, NF15 | Siatka > Graph | 6 | P3 | — | do zrobienia |
| PD-QB-001 | Query Builder: tabele przeciągane, aliasy, złączenia z FK, pola, INTO, WHERE, ORDER BY, DISTINCT, synonimy, SQL, modyfikacja istniejącego SELECT, preferencje formatu | UG 28 | Tools > Query Builder | 6 | P2 | — | do zrobienia |
| PD-BEAU-001 | PL/SQL Beautifier: reguły (wcięcie, margines, tabulacje, puste linie, listy, wielkość liter, Special Case), podgląd | UG 29.1–29.2 | Configure > PL/SQL Beautifier | 2 | P1 | Pełny | do zrobienia |
| PD-BEAU-002 | Beautifier: całe źródło lub zaznaczenie, automatycznie (po utworzeniu, po wczytaniu, przed kompilacją, przed zapisem), `-- NoFormat Start/End` | UG 29.3–29.4, NF13 | Tools > PL/SQL Beautifier | 2 | P1 | Pełny | do zrobienia |
| PD-TPL-001 | Template Window (dokowalny, foldery, filtr) z szablonami domyślnymi (DML, pętle, typy, funkcje SQL, jednostki programów…) | UG 31.1, NF16 | View > Templates | 2 | P1 | Odczyt | do zrobienia |
| PD-TPL-002 | Użycie szablonu (dwuklik, przeciągnięcie, menu edytora), formularz zmiennych, `$OSUSER $DBUSER $DATE $TIME`, `[#]`, wiele jednostek z `/` | UG 31.2–31.3 | Template Window | 2 | P1 | Pełny | do zrobienia |
| PD-TPL-003 | Tworzenie i edycja szablonów i folderów | UG 31.3 | Template Window | 2 | P2 | — | do zrobienia |
| PD-LDE-001 | Large Data Editor: Text, XML, JSON, HTML (podgląd), obraz, Hex; Parse/Format, Auto Format; Open/Save/Clear; Post, następny/poprzedni rekord | UG 27, NF15, NF17 | Siatka > przycisk komórki | 1 | P1 | — | w toku |
| PD-LDE-002 | Large Data Editor: edytor zewnętrzny (plik tymczasowy, wykrywanie zapisu, skojarzenie z kolumną), RTF | UG 27.2, UG 27.8 | Large Data Editor | 6 | P3 | — | do zrobienia |
| PD-DIFF-001 | Wewnętrzna przeglądarka różnic (dwie kolumny, mapa, następna/poprzednia, różnice w linii, ignoruj wielkość liter/białe znaki/komentarze, Swap, Reload) | UG 26, NF14, NF15 | — | 2 | P1 | Odczyt | do zrobienia |
| PD-DIFF-002 | Zewnętrzna przeglądarka różnic z dyrektywami parametrów | UG 23.23 | Preferences | 8 | P3 | — | do zrobienia |

## PL/SQL Developer — projekty, worksets, pliki, kontrola wersji

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| PD-PROJ-001 | Projekty: pliki, obiekty bazy, notatki, opcje (połączenie, Halt after first error, Beautifier, historia folderów), Project Items, grupy | UG 14, NF8, NF11, NF13 | Project | 6 | P2 | Odczyt | do zrobienia |
| PD-PROJ-002 | Build / Make projektu (kolejność, pominięte aktualne, niepoprawne obiekty) | UG 14.6 | Project > Build / Make | 6 | P2 | Za zgodą | do zrobienia |
| PD-PROJ-003 | Pulpit projektu (otwarte okna) i Find in Project | UG 14, UG 14.5 | Project | 6 | P3 | Odczyt | do zrobienia |
| PD-WSET-001 | Worksets: okna z niezapisanymi zmianami między uruchomieniami, New/Open/Close/Apply/Revert/Compare/Manage, autozapis | UG 15, NF14, NF15 | File > Workset | 6 | P2 | — | do zrobienia |
| PD-WSET-002 | Układy okien (desktops): Autosave desktop/layout, Save Layout | UG 23.10, UG 37.2, PROMPT §3.1 | View > Save Layout | 6 | P2 | — | do zrobienia |
| PD-FB-001 | File Browser: lokalizacje (filtry, kolor, hierarchia), drzewo, menu (Open as, Rename, Create, Delete, Sort, Save window in…), auto-odświeżanie | UG 22, NF8, NF14 | View > File Browser | 6 | P2 | Odczyt | do zrobienia |
| PD-FB-002 | File Browser: filtr (Name, Status, VCS, rozmiar, data) z historią | UG 22.3, NF14 | File Browser | 6 | P3 | — | do zrobienia |
| PD-VCS-001 | Git (i SVN): status pliku na pasku stanu, w File Browserze i projekcie, gałąź Git, operacje z menu | UG 17, NF14, NF17 | Pasek stanu okna | 6 | P2 | Odczyt | do zrobienia |
| PD-TODO-001 | To-Do Items w komentarzach (edytor, lista, Goto, priorytety/kategorie/właściciele, zamykanie) | UG 18, UG 23.25 | Edytor > To-Do Items | 6 | P3 | Odczyt | do zrobienia |
| PD-FILE-001 | Kopie zapasowe plików przy zapisie (`plik.~ext`) i odzyskiwanie po awarii (przy wykonaniu, co interwał, Open Recovery, przywracanie połączeń) | UG 23.31, NF13 | Preferences > Backup | 8 | P2 | — | do zrobienia |
| PD-FILE-002 | Format plików: końce linii LF/CRLF (per katalog), kodowanie UTF-8/auto, BOM | UG 23.30 | Preferences > Format | 1 | P2 | — | do zrobienia |
| PD-FILE-003 | Okno/plik tylko do odczytu (menu Read Only) | NF13 | Okno | 2 | P3 | — | do zrobienia |
| PD-FILE-004 | Otwieranie pliku z wyborem połączenia; przeciągnięcie katalogu otwiera pliki | NF13, NF10 | File > Open | 1 | P3 | — | do zrobienia |

## PL/SQL Developer — interfejs, preferencje, dostosowanie

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| PD-UI-001 | Okno główne: Object Browser po lewej, obszar dokumentów, paski narzędzi, pasek stanu | UG 33–35 | — | 0 | P1 | — | w toku |
| PD-UI-002 | Window List (status niezapisany/nieskompilowany/transakcja, wskaźnik połączenia, przypięcie, auto-refresh; menu: Execute, Reconnect, Rename, Short Text, New, Sort; środkowy klik zamyka) | UG 32, NF11, NF13, NF15 | View > Window List | 1 | P1 | Odczyt | w toku |
| PD-UI-003 | Narzędzia dokowane/pływające (Object Browser, File Browser, Connection List, Window List, Templates, Bookmarks, Search, To-Do, Project, Clipboard), autoukrywanie | UG 33, NF8 | View | 1 | P2 | — | do zrobienia |
| PD-UI-004 | Karty dokumentów (SDI) i/lub okna (MDI): zamknij z lewej/prawej, „Same for all Windows”, pozycja kart, Ctrl+Tab | UG 35, NF12, NF15, NF17 | View > Single Document | 1 | P1 | — | w toku |
| PD-UI-005 | Menu wg Apple HIG odpowiadające wstążkom wzorca (File, Project, Edit, Session, Debug, Tools, Reports, Configure, View, Help) + paski narzędzi | UG 34, PROMPT §3.4 | — | 0 | P1 | — | w toku |
| PD-UI-006 | Własne paski narzędzi i Quick Access Toolbar (dostosowanie komend) | UG 34, NF10 | View > Customize Toolbar | 8 | P3 | — | do zrobienia |
| PD-UI-007 | Wyszukiwarka komend (paleta) | PROMPT §3.1 | Help / Cmd+Shift+P | 1 | P1 | — | 👁 sprawdzone ręcznie |
| PD-UI-008 | Tryb jasny/ciemny/auto (systemowy) | UG 23.16, NF15 | Preferences > Appearance | 1 | P1 | — | do zrobienia |
| PD-UI-009 | Tytuł aplikacji z połączeniem / oknem / worksetem; nazwa bazy w tytułach okien | UG 23.16, NF17 | Preferences > Appearance | 1 | P2 | — | do zrobienia |
| PD-UI-010 | Kolor ikony per typ okna; status transakcji na pasku stanu okna | NF12 | — | 1 | P2 | — | do zrobienia |
| PD-UI-011 | Pełny ekran z dostępem do narzędzi | NF11, PROMPT §3.4 | View | 1 | P3 | — | do zrobienia |
| PD-PREF-001 | Okno preferencji: kategorie Oracle / UI / Window Types / Tools / Files / Other, wyszukiwarka, Apply | UG 23 | Configure > Preferences | 1 | P1 | — | do zrobienia |
| PD-PREF-002 | Zestawy preferencji (osobiste, per połączenie, domyślne), pierwszeństwo, wskaźnik dziedziczenia | UG 23.35 | Preferences | 8 | P2 | — | do zrobienia |
| PD-PREF-003 | Eksport/import preferencji (profile do pliku, wybrane sekcje) | UG 23, NF11, PROMPT §3.1 | Preferences > Import/Export | 8 | P2 | — | do zrobienia |
| PD-PREF-004 | NLS Options aplikacji (data, czas, liczby: własne / systemowe / Oracle) | UG 23.17 | Preferences > NLS | 1 | P2 | — | do zrobienia |
| PD-PREF-005 | Czcionki edytora, siatek, przeglądarki (z kolorem i tłem) | UG 23.13 | Preferences > Fonts | 1 | P2 | — | do zrobienia |
| PD-PREF-006 | Katalogi startowe (programy, testy, skrypty, raporty, makra, szablony, projekty, worksety…) i rozszerzenia plików | UG 23.28–23.29 | Preferences > Files | 1 | P2 | — | do zrobienia |
| PD-PREF-007 | Konfiguracja klawiszy (wszystkie funkcje, filtr, czyszczenie) | UG 23.15 | Preferences > Key Configuration | 1 | P1 | — | do zrobienia |
| PD-PREF-008 | DSA Dialogs (przywracanie „nie pokazuj więcej”) | UG 23.10 | Preferences | 8 | P3 | — | do zrobienia |
| PD-DOC-001 | Dokumentacja Oracle: wyszukiwanie słów kluczowych w podręcznikach (F1), wybór książek | UG 36, NF16 | Help > Oracle Manuals | 8 | P2 | — | do zrobienia |
| PD-DOC-002 | Dokumenty użytkownika w menu (Tools > Documents) | UG 37.3 | Configure > Documents | 8 | P3 | — | do zrobienia |
| PD-CLI-001 | Parametry startowe (połączenie z definicji, ViewObject, EditObject, CommandFile, Project, workset, ReadOnly, NoLoadDesktop…) bez haseł w argumentach | UG 37.4, PROMPT §4.2 p.6 | — | 8 | P3 | — | do zrobienia |

## utPLSQL

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| UT-RUN-001 | Uruchom wszystkie testy bieżącego użytkownika | docs/research/utplsql.md (wtyczka PL/SQL Developer) | Tools > utPLSQL | 4 | P1 | Za zgodą | do zrobienia |
| UT-RUN-002 | Uruchom testy ze ścieżki (`schemat.pakiet.procedura`, `schemat:ścieżka.suity`) | wtyczka PL/SQL Developer | Tools > utPLSQL > Run path | 4 | P1 | Za zgodą | do zrobienia |
| UT-RUN-003 | Menu Object Browsera: testy lub pokrycie dla pakietu, ciała, procedury, użytkownika | wtyczka PL/SQL Developer | Object Browser | 4 | P1 | Za zgodą | do zrobienia |
| UT-RUN-004 | Uruchomienie z edytora: test/suita pod kursorem, cały pakiet | wtyczka SQL Developer | Program Window | 4 | P1 | Za zgodą | do zrobienia |
| UT-RUN-005 | Wyniki na żywo przez ut_realtime_reporter (dwie sesje: produkująca i konsumująca; postęp, licznik, bieżący test) | utPLSQL-dotnet-api RealTimeTestRunner | Okno wyników testów | 4 | P1 | Odczyt | do zrobienia |
| UT-RUN-006 | Ponowne uruchomienie nieudanych; uruchomienie pojedynczego testu z wyników; przerwanie | wtyczka PL/SQL Developer, PROMPT §6.2 | Okno wyników | 4 | P1 | Za zgodą | do zrobienia |
| UT-RUN-007 | Uruchomienie testu z debugerem (blok wygenerowany, wydłużony limit reportera) | wtyczka SQL Developer | Okno wyników | 4 | P2 | Brak | do zrobienia |
| UT-RES-001 | Okno wyników: drzewo suit/kontekstów/testów, czasy, statusy, filtr statusu, sortowanie | wtyczka PL/SQL Developer 1.1.0 | Okno wyników | 4 | P1 | Odczyt | do zrobienia |
| UT-RES-002 | Szczegóły: oczekiwane vs otrzymane (porównanie), DBMS_OUTPUT testu, stos błędu z przejściem do linii | PROMPT §6.2 | Okno wyników | 4 | P1 | Odczyt | do zrobienia |
| UT-RES-003 | Historia uruchomień i porównanie dwóch uruchomień | PROMPT §6.2 | Okno wyników | 4 | P2 | Odczyt | do zrobienia |
| UT-EXP-001 | Eksplorator testów (ut_runner.get_suites_info), odświeżany po kompilacji, z ostatnim wynikiem | PROMPT §6.2 | View > Test Explorer | 4 | P1 | Odczyt | do zrobienia |
| UT-COV-001 | Pokrycie kodu: okno opcji (schematy, include/exclude), raport HTML (ut_coverage_html_reporter) | wtyczka PL/SQL Developer | Tools > utPLSQL > Coverage | 4 | P1 | Za zgodą | do zrobienia |
| UT-COV-002 | Pokrycie na marginesie edytora (linie pokryte/niepokryte/częściowo), procent obiektu i schematu | PROMPT §6.2 | Program Window | 4 | P1 | Odczyt | do zrobienia |
| UT-COV-003 | Eksport pokrycia Cobertura i Sonar; ostrzeżenie o uprawnieniach i danych profilera | PROMPT §6.2 | Coverage | 4 | P2 | Brak | do zrobienia |
| UT-GEN-001 | Generowanie szkieletu pakietu testowego ze specyfikacji (test na procedurę/funkcję, adnotacje) — kompiluje się | wtyczka SQL Developer, PROMPT §6.2 | Object Browser > Generate test | 4 | P1 | Za zgodą | do zrobienia |
| UT-GEN-002 | Szablony i fragmenty adnotacji `--%…` oraz oczekiwań | wtyczka SQL Developer | Templates | 4 | P2 | — | do zrobienia |
| UT-CA-001 | Code Assistant dla adnotacji `--%` i matcherów `ut.expect(...).to_…` | PROMPT §6.2 | Edytor | 4 | P1 | — | do zrobienia |
| UT-CA-002 | Walidacja adnotacji przy kompilacji (nieznana adnotacja, brak `--%suite`, zła lista procedur) | PROMPT §6.2 | Program Window | 4 | P2 | Odczyt | do zrobienia |
| UT-NAV-001 | Przejście między pakietem a jego pakietem testowym | PROMPT §6.2 | Program Window | 4 | P2 | Pełny | do zrobienia |
| UT-INS-001 | Wykrycie utPLSQL i wersji (ut_runner.version) na połączeniu | PROMPT §6.2 | Status | 4 | P1 | Odczyt | do zrobienia |
| UT-INS-002 | Instalacja/aktualizacja z oficjalnego wydania tylko dla połączeń dev/test, po potwierdzeniu | PROMPT §6.2 | Tools > utPLSQL > Install | 4 | P2 | Za zgodą | do zrobienia |
| UT-CI-001 | Eksport wyników JUnit, Sonar, TeamCity; skrypt uruchamiania tych samych testów z wiersza poleceń | PROMPT §6.2 | Okno wyników | 4 | P2 | Brak | do zrobienia |

## Agenci AI (jak w Bifoldzie)

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| AI-PANEL-001 | Panel agenta: terminal SwiftTerm z CLI (claude, codex, grok, agy; lista konfigurowalna) | PROMPT §7.1 | View > Agent | 5 | P1 | — | do zrobienia |
| AI-PANEL-002 | Panel aktywności (wywołania narzędzi: parametry, wynik, czas, decyzja) i oczekujące prośby o zgodę | PROMPT §7.1 | Panel agenta | 5 | P1 | — | do zrobienia |
| AI-PANEL-003 | Konfiguracja MCP tylko dla sesji (claude --mcp-config --strict-mcp-config, codex -c, GROK_CONFIG, agy za zgodą) i tryb ścisły | PROMPT §7.1–7.2, Bifold D21 | Panel agenta | 5 | P1 | — | do zrobienia |
| AI-SEC-001 | Most pelikan-mcp stdio ↔ gniazdo Unix 0600 w katalogu 0700, bez portów TCP | PROMPT §7.2 | — | 5 | P1 | — | do zrobienia |
| AI-SEC-002 | Token sesji 256 bit w środowisku CLI, porównanie stałoczasowe, UID (getpeereid), drzewo procesów (LOCAL_PEERPID), unieważnienie, limit wywołań | PROMPT §7.2 | — | 5 | P1 | — | do zrobienia |
| AI-SEC-003 | Agent widzi połączenia tylko pod aliasem i środowiskiem (bez hasła, hosta, portu, usługi, użytkownika OS) | PROMPT §7.3 p.1 | — | 5 | P1 | Odczyt | do zrobienia |
| AI-SEC-004 | Własna sesja bazy agenta (MODULE/ACTION), nigdy transakcja użytkownika; opcjonalny osobny użytkownik bazy dla agenta | PROMPT §7.3 p.2, p.4 | — | 5 | P1 | — | do zrobienia |
| AI-SEC-005 | Klasyfikacja poleceń parserem przed wykonaniem; nierozpoznane = najwyższe ryzyko | PROMPT §7.3 p.3 | — | 5 | P1 | — | ✅ test |
| AI-SEC-006 | Odczyt = SELECT/WITH w transakcji READ ONLY z limitem wierszy, czasu i rozmiaru | PROMPT §7.3 p.4 | — | 5 | P1 | Odczyt | do zrobienia |
| AI-SEC-007 | Zmiany za zgodą z podglądem: tekst, obiekty (ALL_DEPENDENCIES), plan, szacunek wierszy; DML niezatwierdzone do osobnej zgody na COMMIT; ROLLBACK przy zamknięciu | PROMPT §7.3 p.5 | Okno zgody | 5 | P1 | Za zgodą | do zrobienia |
| AI-SEC-008 | Historia DDL obiektów przed zmianą kodu; „Cofnij sesję agenta” z wykrywaniem konfliktów | PROMPT §7.3 p.6, §7.6 | Panel agenta | 5 | P1 | — | do zrobienia |
| AI-SEC-009 | Dane z bazy oznaczone `untrusted_content` | PROMPT §7.3 p.7 | — | 5 | P1 | — | do zrobienia |
| AI-SEC-010 | Prod: domyślnie tylko metadane i odczyt; maskowanie wskazanych kolumn | PROMPT §7.3 p.8 | Configure > Connections | 5 | P1 | — | do zrobienia |
| AI-SEC-011 | Brak dostępu agenta do terminala, Command Window, HOST, AWR/ASH/Tuning Pack, haseł i połączeń | PROMPT §7.3 p.9, §7.5 | — | 5 | P1 | Brak | do zrobienia |
| AI-PERM-001 | Poziomy Brak/Odczyt/Za zgodą/Pełny, efektywny = min(komenda, sesja, połączenie); macierz sesji przy starcie | PROMPT §7.4 | Panel agenta | 5 | P1 | — | do zrobienia |
| AI-PERM-002 | Okno zatwierdzania bez przycisku domyślnego, „Zatwierdź” po 0,8 s, Esc odrzuca | PROMPT §7.4, Bifold D23 | Okno zgody | 5 | P1 | — | do zrobienia |
| AI-TOOL-001 | Narzędzia odczytu: list_connections, get_state, get_editor, search_objects, describe_object, get_source, get_ddl, get_dependencies, find_usages, run_query, explain_plan, get_compile_errors, get_dbms_output, list_tests, get_test_results, get_coverage, session_list | PROMPT §7.5 | MCP | 5 | P1 | Odczyt | do zrobienia |
| AI-TOOL-002 | Narzędzia pełne (cofalne, tylko w aplikacji): open_object, open_editor, insert_text, replace_range, format_code, navigate_to | PROMPT §7.5 | MCP | 5 | P1 | Pełny | do zrobienia |
| AI-TOOL-003 | Narzędzia za zgodą: compile, execute_statement, execute_script, commit, rollback, create_test_package, run_tests, generate_test_skeleton, install_utplsql, run_command (≤ Za zgodą) | PROMPT §7.5, Bifold D20 | MCP | 5 | P1 | Za zgodą | do zrobienia |
| AI-LOG-001 | Dziennik JSONL każdego wywołania (bez danych wrażliwych) i przeglądarka dziennika | PROMPT §7.6 | Panel agenta | 5 | P1 | — | do zrobienia |
| AI-E2E-001 | Testy E2E z prawdziwymi CLI (lokalnie, opcjonalnie) | PROMPT §9 | — | 5 | P2 | — | do zrobienia |

## Dodatki z SQL Developer / SQL Developer for VS Code / SQLcl

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| SD-NB-001 | SQL Notebook: komórki SQL/PL/SQL i Markdown, Run All, wyniki zapisywane w pliku | SD VS Code 25.2, gap-analysis §1 | File > New > SQL Notebook | 7 | P2 | Pełny | do zrobienia |
| SD-NB-002 | Wykresy z wyników komórek notatnika | SD VS Code 25.3 | SQL Notebook | 7 | P2 | — | do zrobienia |
| SD-PLAN-001 | Plan wykonania jako diagram (kardynalność, koszty, kolejność) i flame graph; widok zaawansowany | SD VS Code 24.1, gap-analysis §1 | Explain Plan Window | 7 | P2 | Odczyt | do zrobienia |
| SD-PLAN-002 | Autotrace (plan rzeczywisty i statystyki z V$SQL_PLAN_STATISTICS_ALL) | SQL Developer UG | SQL Window > Autotrace | 7 | P2 | Odczyt | do zrobienia |
| SD-PLAN-003 | Porównanie dwóch planów | SQL Developer UG | Explain Plan Window | 7 | P3 | Odczyt | do zrobienia |
| SD-MON-001 | Real-Time SQL Monitoring (Tuning Pack: ostrzeżenie licencyjne, zgoda zapamiętana na połączeniu) | SD VS Code 24.4, PROMPT §3.3 | Tools > SQL Monitor | 7 | P2 | Brak | do zrobienia |
| SD-MON-002 | Task Monitor (zadania w tle: status, czasy, anulowanie) | SD VS Code 24.3 | View > Task Monitor | 7 | P2 | — | do zrobienia |
| SD-DBA-001 | Panel DBA: przestrzenie tabel, pliki danych, parametry, użytkownicy, role, sesje, blokady | SQL Developer UG, SD VS Code 26.2 | View > DBA | 7 | P2 | Odczyt | do zrobienia |
| SD-DBA-002 | Raporty AWR, ASH, ADDM (Diagnostics Pack — ostrzeżenie licencyjne) | SQL Developer UG, SD VS Code 26.2, PROMPT §3.3 | DBA > Performance | 7 | P2 | Brak | do zrobienia |
| SD-DBA-003 | SQL Tuning Advisor (Tuning Pack) | SQL Developer UG | SQL Window > Tuning Advisor | 7 | P3 | Brak | do zrobienia |
| SD-DBA-004 | Instance Viewer (pulpit instancji) | SQL Developer UG | DBA > Instance Viewer | 7 | P3 | Odczyt | do zrobienia |
| SD-LIC-001 | Licencje Diagnostics/Tuning Pack na połączeniu (CONTROL_MANAGEMENT_PACK_ACCESS), pytanie przy pierwszym użyciu | SD VS Code 26.2, PROMPT §3.3 | Configure > Connections | 7 | P1 | Brak | do zrobienia |
| SD-REP-001 | Raporty predefiniowane w kategoriach (Grid/Chart/DBMS_OUTPUT, zmienne, szczegóły, Open in Worksheet, eksport) | SD VS Code 24.4 | Reports | 7 | P2 | Odczyt | do zrobienia |
| SD-DIFF-001 | Database Diff i Cart (pakiet zmian do wdrożenia jako skrypt) | SQL Developer UG | Tools > Database Diff / Cart | 7 | P2 | Odczyt | do zrobienia |
| SD-COPY-001 | Kreator kopiowania bazy/schematu (Database Copy) | SQL Developer UG | Tools > Database Copy | 7 | P3 | Brak | do zrobienia |
| SD-DOC-001 | Generowanie dokumentacji schematu (HTML) | SQL Developer UG | Tools > Generate DB Doc | 7 | P3 | Odczyt | do zrobienia |
| SD-IMP-001 | Kreator importu danych (CSV, rozdzielany, tekst, XLS/XLSX; podgląd, kodowanie, mapowanie, nowa/istniejąca tabela, zapis stanu) | SD VS Code 25.4, 26.1 | Object Browser > Import | 7 | P2 | Brak | do zrobienia |
| SD-GEN-001 | Generowanie kodu przez przeciąganie obiektu/połączenia (SQL, Java JDBC: SELECT/INSERT/UPDATE/DELETE/JOIN, łańcuch połączenia) | SD VS Code 25.3, 25.4 | Object Browser > przeciągnij | 7 | P3 | — | do zrobienia |
| SD-AUTH-001 | Uwierzytelnianie Entra ID (Oracle na Azure) | SD VS Code 25.4 | Configure > Connections | 7 | P3 | Brak | do zrobienia |
| SD-DV-001 | Widoki dualności JSON-relacyjnej (tworzenie, edycja, rekordy, diagram JSON Data Guide) | SD VS Code 24.2 | Object Browser | 7 | P3 | Za zgodą | do zrobienia |
| SD-MLE-001 | Środowiska MLE (tworzenie, import modułów, kompilacja) i debugowanie modułów JavaScript po wykonaniu | SD VS Code 26.1–26.3 | Object Browser | 7 | P3 | Za zgodą | do zrobienia |
| SD-DATA-001 | Podgląd danych przestrzennych (SDO_GEOMETRY jako WKT, prosty podgląd) | SQL Developer UG | Large Data Editor | 7 | P3 | — | do zrobienia |
| SD-ORDS-001 | ORDS: włączenie REST dla schematu i obiektów, lista modułów | SQL Developer UG | Object Browser > REST | 7 | P3 | Za zgodą | do zrobienia |
| SD-APEX-001 | APEXlang (eksport/import/porównanie aplikacji APEX) | SD VS Code 26.1–26.2 | — | 7 | P3 | — | pominięte (wymaga APEX; poza codzienną pracą z PL/SQL — D11) |
| SC-CMD-001 | Command Window: INFO / INFO+, DDL, LOAD (CSV do tabeli), FORMAT (formatowanie skryptu), HISTORY z czasami, ALIAS, REPEAT, CTAS | SQLcl UG | Command Window | 7 | P2 | Brak | do zrobienia |
| SC-CMD-002 | SET SQLFORMAT (csv, json, xml, html, insert, loader, fixed, delimited, ansiconsole) | SQLcl UG | Command Window | 7 | P2 | Brak | do zrobienia |
| SC-LB-001 | Liquibase (`lb`) | SQLcl UG | Command Window | 7 | P3 | — | pominięte w pierwszej wersji (wymaga Javy i biblioteki Liquibase — D11) |
| SC-SNIP-001 | Snippets (biblioteka fragmentów kodu do przeciągania) | SD VS Code, SQL Developer | View > Snippets | 7 | P3 | — | do zrobienia |

## Dodatki z DBeaver

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| DB-SSH-001 | Tunel SSH (hasło z Pęku kluczy, klucz, agent, jump host) przez systemowy ssh | gap-analysis §3 | Configure > Connections | 1 | P1 | — | do zrobienia |
| DB-DIAG-001 | Diagramy ER z bazy (automatyczny układ, relacje FK, eksport obrazu) | gap-analysis §3 | Object Browser > ER Diagram | 7 | P2 | Odczyt | do zrobienia |
| DB-PANEL-001 | Panel wartości obok siatki (tekst, JSON, XML, HTML, obraz z BLOB, hex) | gap-analysis §3 | Siatka > Value panel | 7 | P2 | — | do zrobienia |
| DB-GRID-001 | Filtr wyników w siatce (po wartości komórki, wyrażenie) i grupowanie z licznikami | gap-analysis §3 | Siatka | 7 | P2 | — | do zrobienia |
| DB-GRID-002 | Generowanie SQL z zaznaczonych wierszy (INSERT/UPDATE/DELETE/MERGE) | gap-analysis §3 | Siatka > Generate SQL | 7 | P3 | — | do zrobienia |
| DB-XFER-001 | Przenoszenie danych między tabelami/schematami/połączeniami z mapowaniem | gap-analysis §3 | Tools > Data Transfer | 7 | P2 | Brak | do zrobienia |
| DB-TASK-001 | Zaplanowane zadania lokalne (eksport, skrypt cyklicznie) bez haseł w plikach | gap-analysis §3 | Tools > Tasks | 7 | P3 | Brak | do zrobienia |

## Dodatki z DataGrip

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| DG-RES-001 | Rozwiązywanie nazw w czasie pisania (podkreślanie nieznanych tabel, kolumn, aliasów) | gap-analysis §4 | Edytor | 7 | P2 | — | do zrobienia |
| DG-INSP-001 | Inspekcje kodu: nieużywane zmienne, nieosiągalny kod, niejawne konwersje, UPDATE/DELETE bez WHERE | gap-analysis §4 | Edytor | 7 | P2 | Odczyt | do zrobienia |
| DG-USE-001 | Find Usages obiektu/kolumny (zależności, PL/Scope, pliki) | gap-analysis §4 | Edytor > Find Usages | 7 | P1 | Odczyt | do zrobienia |
| DG-REF-001 | Refaktoryzacja z podglądem zmian (diff) przed zastosowaniem | gap-analysis §4 | Edytor > Refactoring | 7 | P2 | Za zgodą | do zrobienia |
| DG-HIST-001 | Lokalna historia plików i obiektów (wersje, porównanie, przywracanie) | gap-analysis §4 | File > Local History | 7 | P1 | Odczyt | do zrobienia |
| DG-CONS-001 | Konsole zapytań per połączenie (zachowywane automatycznie) | gap-analysis §4 | Session > Console | 7 | P2 | — | do zrobienia |
| DG-GRID-001 | Wyróżnienie zmian oczekujących w siatce (wstawione/zmienione/usunięte) przed zapisem | gap-analysis §4 | Siatka | 7 | P2 | — | do zrobienia |

## Integracja z macOS

| ID | Funkcja | Źródło | Okno / menu | Etap | Priorytet | Agent | Stan |
|---|---|---|---|---|---|---|---|
| MAC-KEY-001 | Dwa profile klawiatury: zgodny z PL/SQL Developer (F-klawisze, Ctrl, zamienniki dla MacBooka) i macOS (Cmd); skróty konfigurowalne | PROMPT §3.4 | Preferences > Keys | 1 | P1 | — | do zrobienia |
| MAC-KC-001 | Hasła w Pęku kluczy; odblokowanie zapisanych haseł Touch ID (opcja) | PROMPT §3.4, §4.2 p.6 | Preferences | 1 | P1 | Brak | w toku |
| MAC-FILE-001 | Otwieranie .sql, .pks, .pkb, .pck, .tst (i pozostałych rozszerzeń wzorca) z Findera; przeciąganie plików | PROMPT §3.4 | — | 1 | P1 | — | do zrobienia |
| MAC-QL-001 | Quick Look dla plików SQL/PL/SQL z podświetlaniem | PROMPT §3.4 | — | 8 | P3 | — | do zrobienia |
| MAC-SVC-001 | Usługi macOS (np. „Formatuj SQL”, „Otwórz w Pelikanie”) | PROMPT §3.4 | — | 8 | P3 | — | do zrobienia |
| MAC-UI-001 | Natywne karty, pełny ekran, tryb ciemny/jasny, menu wg HIG | PROMPT §3.4 | — | 1 | P1 | — | do zrobienia |
| MAC-A11Y-001 | Dostępność (VoiceOver) dla siatki, drzew, edytora | PROMPT §8 | — | 8 | P2 | — | do zrobienia |
| MAC-UPD-001 | Aktualizacje Sparkle 2 (kanał releases/latest/download/appcast.xml) | PROMPT §4.1 | Help > Check for Updates | 8 | P2 | — | do zrobienia |
