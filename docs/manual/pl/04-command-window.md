# Konsola SQL*Plus

## Do czego to służy

**SQL*Plus** to klasyczne, tekstowe narzędzie Oracle do wykonywania skryptów. Wiele zespołów wdraża zmiany w bazie
właśnie skryptami SQL*Plus — z poleceniami `SET`, `PROMPT`, `SPOOL` (zapis wyniku do pliku) czy `WHENEVER SQLERROR`
(zatrzymanie przy błędzie). Okno SQL ich nie rozumie, a **Konsola SQL*Plus** w Pelikanie — tak: wykonuje polecenia
linia po linii i skrypty, a wyniki zapytań pokazuje jako tekst w kolumnach, jak SQL*Plus. Otworzysz ją przez **Plik ›
Nowy › Konsola SQL*Plus** albo z menu połączenia na liście połączeń.

**Kiedy użyć:** do uruchamiania gotowych skryptów wdrożeniowych (`@instaluj.sql`), do skryptów, które zapisują wynik do
pliku, i gdy chcesz zobaczyć, jak skrypt zachowa się w SQL*Plus u administratora. Do zwykłych zapytań i przeglądania
danych wygodniejsze jest okno SQL z siatką wyników (rozdział 3).

Konsola ma dwie karty:

- **Dialog** — wyjście i **linia poleceń** na dole. Wpisz polecenie SQL*Plus, SQL albo blok PL/SQL (blok kończy
  ukośnik `/` w osobnej linii) i naciśnij ↩. Strzałki przewijają historię wpisanych linii.
- **Edytor** — skrypt z podświetlaniem składni. F8 (⌘↩) wykonuje zaznaczenie albo cały skrypt; wynik pojawia się w
  karcie Dialog. **Sesja › Przerwij** (⌘.) zatrzymuje skrypt.

Pasek stanu pokazuje bieżące ustawienia `ECHO`, `TERMOUT`, `FEEDBACK`, `VERIFY`, `AUTOPRINT`, `HEADING` i `TIMING`;
dwukrotne kliknięcie wskaźnika przełącza ustawienie.

> **Ćwiczenie: pierwszy skrypt SQL*Plus.**
> 1. Otwórz **Plik › Nowy › Konsola SQL*Plus**.
>    *Wynik:* okno z literą **C**, karta **Dialog** z linią poleceń na dole.
> 2. W linii poleceń wpisz `DESCRIBE pel_employees` i naciśnij ↩.
>    *Wynik:* lista kolumn tabeli z typami i informacją, czy mogą być puste (NULL).
> 3. Przejdź do karty **Edytor** i wpisz skrypt:
>
>    ```sql
>    SET SERVEROUTPUT ON
>    SET TIMING ON
>    PROMPT Pracownicy działu Informatyka:
>    EXECUTE pel_emp_api.print_department(20)
>    COLUMN last_name HEADING 'Nazwisko' FORMAT A15
>    SELECT last_name, salary FROM pel_employees WHERE dept_id = 20;
>    ```
>
> 4. Naciśnij **F8**.
>    *Wynik:* w karcie Dialog widać tekst z PROMPT, listę z `print_department` (DBMS_OUTPUT), tabelę tekstową
>    z nagłówkiem „Nazwisko” i czas wykonania każdego polecenia (TIMING). Pasek stanu pokazuje włączone TIMING.
> 5. W linii poleceń wpisz `DIR`, żeby zobaczyć bieżący katalog konsoli (zmienisz go poleceniem `CD katalog`). Potem
>    wpisz kolejno `SPOOL pracownicy.txt`, `SELECT * FROM pel_departments;` i `SPOOL OFF`.
>    *Wynik:* w bieżącym katalogu jest plik `pracownicy.txt` z wynikiem zapytania.
>
> ⚠️ **Na co uważać.** Skrypt wdrożeniowy zaczynaj od `WHENEVER SQLERROR EXIT SQL.SQLCODE` — inaczej po błędzie
> jednego polecenia kolejne wykonują się dalej i baza zostaje „w połowie” zmiany. Przed uruchomieniem cudzego skryptu
> przeczytaj go i sprawdź, na jakim połączeniu jest konsola.

## Obsługiwane polecenia SQL*Plus

- Uruchamianie skryptów: `@plik`, `@@plik` (względem bieżącego skryptu), `START`, `RUN`, `/`.
- Zmienne: `DEFINE`, `UNDEFINE`, `ACCEPT`, `VARIABLE` (NUMBER, VARCHAR2, CHAR, CLOB, BLOB, REFCURSOR, DATE, BOOLEAN),
  `PRINT`, `EXECUTE`. `&&nazwa` zapamiętuje wartość jak w SQL*Plus.
- Wyjście: `PROMPT`, `PAUSE`, `SPOOL plik` (także `APPEND`, `OFF`, `OUT`), `COLUMN` (`FORMAT`, `HEADING`,
  `NEW_VALUE`), `BREAK` (`SKIP`, `DUP`/`NODUP`), `COMPUTE` (`SUM`, `AVG`, `COUNT`, `MIN`, `MAX`, `NUM` z `LABEL`),
  `CLEAR`.
- `SET`: m.in. `AUTOPRINT`, `COLSEP`, `CONCAT`, `DEFINE`, `ECHO`, `ESCAPE`, `FEEDBACK`, `HEADING`, `LONG`, `NUMWIDTH`,
  `PAGESIZE`, `SCAN`, `SERVEROUTPUT` (`SIZE UNLIMITED`), `TERMOUT`, `TIMING`, `VERIFY`, `EXECPAUSE`. Nieobsługiwane
  opcje `SET` w skryptach są pomijane bez błędu.
- `SHOW` (`ERRORS`, `USER`, `RELEASE`, `SQLCODE`, `CONNECTION`, `ALL`…), `DESCRIBE`, `WHENEVER SQLERROR`, `CONNECT`,
  `DISCONNECT`, `EXIT`/`QUIT`, `REMARK`, `HELP`.
- Bufor poleceń: `LIST`, `APPEND`, `CHANGE`, `DEL`, `INPUT`, `SAVE`, `GET`, `STORE SET`.
- `HOST`, `!` i `$` — polecenie systemu operacyjnego. Pelikan zawsze pokazuje je do potwierdzenia, wykonuje bez
  zmiennych środowiska Pelikana, z limitem 120 sekund. Agent AI nie ma dostępu do konsoli SQL*Plus.

Polecenie nieobsługiwane jest pomijane z informacją, więc skrypty pisane dla SQL*Plus wykonują się do końca. `COPY`
nie jest obsługiwane.

Po `@`, `@@` i `START` podpowiadanie kodu pokazuje pliki skryptów z bieżącego katalogu, a po `CONNECT użytkownik@` —
aliasy z `tnsnames.ora`. Polecenia z hasłami (`CONNECT`, `ALTER USER … IDENTIFIED BY`, `CREATE DATABASE LINK`) nie
trafiają do historii poleceń.

## Polecenia SQLcl

- `INFO` i `INFO+` — opis tabeli albo programu z kolumnami, indeksami i statystykami.
- `DDL obiekt [plik]` — DDL obiektu na ekran albo do pliku.
- `LOAD tabela plik.csv [NEW]` — wczytanie CSV do tabeli (z `NEW` — tworzy tabelę).
- `FORMAT BUFFER` / `FORMAT FILE` — formatowanie kodu.
- `HISTORY` (z czasami, `CLEAR`), `ALIAS`, `REPEAT`, `CTAS`.
- `SET SQLFORMAT csv | json | xml | html | insert | loader | fixed | delimited | ansiconsole | default` — format
  wyników zapytań.

## Polecenia Pelikana

- `BEAUTIFY plik` — formatuje plik formaterem Pelikana.
- `EDIT obiekt`, `VIEW obiekt`, `BROWSE obiekt`, `PROPERTIES obiekt` — otwierają obiekt w odpowiednim oknie.
- `QUERYDATA tabela`, `EDITDATA tabela` — dane tabeli w oknie SQL (z możliwością edycji).
- `TEST program`, `RECOMPILE obiekt`, `INFO obiekt`.
- `CD katalog`, `DIR` — katalog bieżący okna dla skryptów i `SPOOL`.
- `ZIP`, `EXPORT TABLES …`, `EXPORT OBJECTS …` — eksport tabel i obiektów jak w narzędziach eksportu.
- `RUNTESTSET plik.pts` — uruchamia zestaw testów Test Managera.

## Krokowe wykonanie skryptu

`SET EXECPAUSE ON` albo **Sesja › Wstrzymaj wykonanie** sprawia, że przed każdym poleceniem skryptu Pelikan pyta, czy
je wykonać, wykonać resztę skryptu, czy przerwać. To bezpieczny sposób na pierwsze uruchomienie skryptu, którego nie
znasz: widzisz każde polecenie, zanim trafi do bazy.
