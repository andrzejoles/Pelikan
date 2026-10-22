# Kluczowe zachowania do wiernego odwzorowania (PROMPT §5)

Źródła: UG = PL/SQL Developer 17.0 User's Guide (rozdział), testy Pelikana (plik testu), obserwacje na bazie testowej.
„Do weryfikacji” = zachowanie wzorca nieopisane w dokumentacji; przyjęte założenie zapisane, sprawdzić u właściciela
lub na forum producenta przed uznaniem wiersza za zgodny.

## 1. Dzielenie skryptu na polecenia
- Polecenie SQL kończy `;` albo `/` w osobnej linii; blok PL/SQL kończy `/` w osobnej linii (UG 7.1: „SQL statements
  must be terminated with a semi-colon or a slash, and PL/SQL blocks must be terminated with a slash, just like in
  SQL*Plus”). Ostatnie polecenie bez terminatora też się wykonuje.
- Blok PL/SQL rozpoznajemy po pierwszych słowach: `DECLARE`, `BEGIN`, `<<etykieta>>`, `CREATE [OR REPLACE]
  [EDITIONABLE|NONEDITIONABLE] FUNCTION|PROCEDURE|PACKAGE [BODY]|TRIGGER|TYPE [BODY]|LIBRARY|JAVA|MLE MODULE`,
  `WITH FUNCTION|PROCEDURE` (12c). W bloku średniki nie dzielą.
- `/` zaraz po poleceniu zakończonym `;` nie powtarza polecenia (w SQL*Plus powtórzyłby bufor). **Do weryfikacji**
  w PL/SQL Developer — przyjęto „separator”, bo skrypty zapisane przez wzorzec („Save with history”) rozdzielają
  polecenia `/`.
- Średnik w literale, komentarzu i nawiasie nie dzieli. Komentarz przed poleceniem należy do polecenia.
- Command Window: polecenia SQL*Plus są jednoliniowe (z kontynuacją `-`); treść PROMPT/REM może zawierać apostrof.
- Test: `Packages/PelikanKit/Tests/PelikanSQLTests/ScriptSplitterTests.swift`.

## 2. Co się wykonuje przy zaznaczeniu i bez niego (SQL Window)
- Zaznaczenie → tylko zaznaczony tekst (podzielony na polecenia) (UG 7.1).
- Bez zaznaczenia: z wyłączonym **AutoSelect statement** wykonują się wszystkie polecenia okna, każde z wynikiem w
  osobnej karcie (UG 7.1); z włączonym — polecenie pod kursorem (UG 23.20). Klawisz „Execute current statement” zawsze
  wykonuje polecenie pod kursorem (NF10). **Domyślna wartość AutoSelect do weryfikacji** — w Pelikanie domyślnie
  włączone (bezpieczniej: nie wykona przypadkiem całego skryptu), opcja w preferencjach.
- Kursor między poleceniami → polecenie poprzedzające (pusta linia po `;`); test `statementAtCursor`.

## 3. Zmienne `&` i `:bind`
- `&x` — podstawienie tekstu przed wysłaniem; `&&x` — wartość zapamiętana (DEFINE) do końca sesji okna; kropka kończy
  nazwę (`&tab.`). SQL*Plus podstawia także w literałach; Pelikan też (UG 12.3 przykład `'R&&D'` dowodzi, że wzorzec
  skanuje literały). W komentarzach nie podstawiamy. **Do weryfikacji** dla komentarzy.
- `:x` — zmienna wiązana; w SQL Window od 16.0 (NF16), typ domyślnie tekst, opcje jak dla `&`. W CREATE TRIGGER `:new`
  i `:old` nie są zmiennymi.
- Okno pytania pokazuje wszystkie zmienne naraz w kolejności wystąpienia, z opcjami `&<…>` (UG 12.3); przycisk `&` na
  pasku stanu wyłącza oba rodzaje (NF17).
- Parametry JasperReports — D6.
- Test: `VariablesTests.swift`.

## 4. Siatka wyników
- Początkowo pobierana jedna strona (tyle wierszy, ile widać — „Records per page: Automatically determined”), Next Page
  dociąga kolejną stronę, Last Page wszystko; „(more…)” na pasku stanu (UG 7.1, 23.20). Pelikan pobiera z bazy porcjami
  (fetch array 500) niezależnie od strony widoku; przewijanie do końca siatki dociąga kolejne porcje.
- Break w trakcie pobierania zatrzymuje pobieranie, pobrane wiersze zostają (UG 7.1).
- Edytowalna, gdy w SELECT jest `ROWID` albo `FOR UPDATE` (ten blokuje wiersze) (UG 7.6); przy złączeniu edytowalne
  kolumny tabeli z ROWID; kolumny z aliasem tylko do odczytu; od 17 tabela ustalana z ROWID (NF17). Zmiany lokalne do
  „Post changes”; po Post (bez AutoCommit) transakcja otwarta — Commit/Rollback aktywne. UPDATE/DELETE po `ROWID`.
- Sortowanie lokalne tylko pobranych wierszy; nowe wiersze dopisywane na końcu bez sortowania (UG 7.2).
- NULL na jasnożółtym tle (UG 7.2).

## 5. Kompilacja i PLSQL_WARNINGS
- CREATE z błędami kompilacji zwraca sukces z ostrzeżeniem ORA-24344 (sterownik: `ExecutionResult.warning`, test
  `compilationWarning`); błędy odczytujemy z `USER_ERRORS`/`ALL_ERRORS` (ATTRIBUTE = ERROR/WARNING, LINE, POSITION,
  TEXT). Ostrzeżenia PLW (np. PLW-06002) widoczne przy `PLSQL_WARNINGS='ENABLE:ALL'` (seed `warn_fn`: PLW-05018,
  PLW-07206, PLW-06002).
- Kompilacja w osobnej sesji (DDL robi COMMIT) (UG 20); Program Window kompiluje wszystkie jednostki po kolei i
  zatrzymuje się na pierwszym błędzie (UG 4.4).
- Ustawienia kompilatora z preferencji wykonywane jako `ALTER SESSION SET PLSQL_…` w sesji kompilacji przed CREATE.

## 6. DBMS_OUTPUT
- Bufor włączany w sesji okna przed wykonaniem (`DBMS_OUTPUT.ENABLE(rozmiar|NULL)`), odczyt po wykonaniu
  (`DBMS_OUTPUT.GET_LINES` porcjami), rozmiar 0 = bez limitu (UG 23.5); przekroczenie limitu = ORA-20000 z bazy.
- Czyszczenie przed wykonaniem (preferencja), wskaźnik nowego wyjścia na karcie (NF11, NF15).

## 7. Code Assistant
- Otwiera się automatycznie po `.` za nazwą obiektu/zmiennej po opóźnieniu (preferencja, ms) albo klawiszem; w
  kontekście (słowa kluczowe, obiekty, identyfikatory) po minimalnej liczbie znaków (UG 23.14, 25.4). Filtr podczas
  pisania (Contains/Starts with), Enter wstawia, Esc zamyka.

## 8. NLS i formaty w siatce
- Wzorzec formatuje daty wg ustawień NLS Options (UG 23.17): własny / systemowy / Oracle NLS_DATE_FORMAT; TIMESTAMP wg
  NLS_TIMESTAMP_[TZ_]FORMAT (UG 7.2). Pelikan pobiera daty binarnie (bez TO_CHAR na serwerze) i formatuje lokalnie;
  domyślny format `YYYY-MM-DD HH24:MI:SS` (czytelny i jednoznaczny), zmiana w preferencjach; opcja „Date fields to_char”
  (UG 23.20) — konwersja na serwerze wg NLS sesji. **Do weryfikacji**: domyślny format wzorca (zależny od Windows).
- Liczby: NUMBER jako tekst z pełną precyzją (NF17), wiodące zero dopisywane (`.5` → `0.5`).

## 9. Utrata połączenia
- Wzorzec sprawdza połączenie co 60 s (preferencja Check connection) i po utracie wylogowuje (UG 23.1).
- Pelikan: błąd z grupy utraty połączenia (`OracleError.isConnectionLost`: ORA-03113, 03114, 03135, 12537…, DPI-1010,
  DPI-1080) → okno: „Połączenie utracone. Niezatwierdzona transakcja została wycofana przez serwer.” (jeśli okno miało
  otwartą transakcję) z przyciskiem „Połącz ponownie” (nowa sesja, ustawienia NLS i skrypt inicjalizacji ponownie).
  Zapytanie w toku nie jest ponawiane automatycznie.

## 10. Przerwanie (Break)
- OCIBreak przerywa zapytanie natychmiast (ORA-01013), sesja działa dalej (test `breakExecution`).
- `DBMS_SESSION.SLEEP` i czekanie na blokadę nie reagują do końca oczekiwania — tak samo w SQL*Plus (sprawdzone
  2026-10-22 na bazie testowej: Ctrl+C w trakcie SLEEP(20) → ORA-01013 po 20 s). Zgodne z UG 5.2/7.1 („Break … will not
  always be successful”). Wtedy pozostaje Kill sesji (UG 20.4).

## 11. Transakcje
- Bez auto-commita (UG 23.20 „AutoCommit SQL” domyślnie wyłączone). Zamknięcie okna/aplikacji z otwartą transakcją:
  wzorzec domyślnie robi COMMIT przy wylogowaniu (UG 23.1 „Logoff with open transaction”); **Pelikan domyślnie pyta**
  (D10), z opcjami Commit / Rollback / Anuluj.
