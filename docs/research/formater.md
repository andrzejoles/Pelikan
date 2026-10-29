# Formater SQL i PL/SQL — rozpoznanie, braki i propozycja (PD-BEAU-001)

Stan na 2026-10-29, gałąź `p3/formater-rozpoznanie`, kod z `main` po PR #119. Etap rozpoznania — bez zmian w kodzie.

> **Wdrożone (D202, gałąź `p3/formater-poprawki`):** P0 i P1 (F1–F20), decyzje właściciela z rozdz. 7, reguły AND/OR
> osobno dla miejsc warunków, część opcji P2 i podgląd z rozdz. 6. Wynik formatera na korpusie po zmianach:
> [`formater/wynik-po-D202-domyslne.txt`](formater/wynik-po-D202-domyslne.txt) (pliki `wynik-*.txt` poniżej to stan
> sprzed zmian). Pominięte opcje P3 — w D202.

Materiały w katalogu [`formater/`](formater/):

| Plik | Zawartość |
|---|---|
| `korpus.txt` | 66 przypadków (`### NN-nazwa`): listy, SET, CTE, podzapytania, MERGE, INSERT ALL, CASE, analityczne, PL/SQL, DDL (tabele, constrainty, indeksy, widoki, MV, sekwencje, GRANT, wyzwalacze wszystkich rodzajów, typy, pakiety), Java/MLE, przypadki bezpieczeństwa |
| `wynik-domyslne.txt` | wynik obecnego formatera przy ustawieniach domyślnych |
| `wynik-przecinek-z-przodu-wyrownania.txt` | przecinek na początku linii, wszystkie wyrównania, parametry i INSERT „element w linii”, CASE wieloliniowe |
| `wynik-klauzule-w-osobnej-linii.txt` | słowa klauzul w osobnej linii, małe słowa kluczowe, CASE wieloliniowe |
| `podglad/1-plsql.sql` … `4-ddl.sql` | proponowany kod podglądu w Ustawieniach › Formater (cztery przełączane przykłady) |
| `podglad-wynik.md` | wynik podglądu przy ustawieniach domyślnych i pomiar: które przykłady zmienia każda obecna opcja |
| `uruchom-korpus.swift.txt` | tymczasowy test, którym wygenerowano wyniki (skopiować do `Tests/PelikanSQLTests/`, `swift test --filter ZZTmpFormatterCorpus`, usunąć) |

Wyniki są powtarzalne (formater jest deterministyczny); przy każdym przypadku sprawdzono też idempotencję
(drugi przebieg nic nie zmienia — we wszystkich trzech profilach bez wyjątku).

## 1. Streszczenie

- **Dwa błędy bezpieczeństwa (P0):** formater psuje kod z **kompilacją warunkową** (`$IF … $THEN … $END`,
  `$$PLSQL_UNIT` → `$ IF`, `$ $ plsql_unit`; procedura przestaje się kompilować — sprawdzone na bazie testowej, PLS-00103) oraz
  **operatory odległości wektorów 23ai** (`<=>`, `<->`, `<#>` → `<= >`, `< ->`, `< # >`). `Beautifier.verify` tego nie wykrywa,
  bo porównuje tokeny z tego samego leksera, który dzieli te konstrukcje na części.
- **Błędy układu (P1)** — najważniejsze: druga i dalsze instrukcje w gałęzi `WHEN … THEN` obsługi wyjątków i instrukcji CASE
  tracą wcięcie (a IF w obsłudze wyjątku rozjeżdża cały blok); `SELF AS RESULT` w TYPE BODY traktowane jak `AS` otwierające
  deklaracje; zapytanie po `IS`/`AS` (kursor, widok, MV) zostaje w linii nagłówka i dostaje wcięcie 40–100 kolumn;
  `UNION`/`MINUS` — drugi SELECT bez formatowania w linii operatora; `AND` w warunku `JOIN … ON` wyrównane do klauzul zamiast
  pod `ON`; MERGE (`ON (…)` w linii USING, `… DELETE WHERE`), INSERT ALL/FIRST; długie wyrażenia (`||`) łamane wewnątrz
  argumentów funkcji w kolumnie ~150; nagłówki wyzwalaczy, COMPOUND TRIGGER i opcje fizyczne CREATE TABLE w jednej linii
  daleko za marginesem; niespójna wielkość liter słów kluczowych niezastrzeżonych (`PATH`, `DAY` jako nazwy kolumn
  zmieniane na wielkie, a `bitmap`, `parallel`, `refresh`, `value`, `statement` zostają małe).
- **Braki opcji (P2)** w porównaniu z PL/SQL Developerem (wzorzec), DataGrip, SQL Developerem, Toad: czwarta wartość układu
  list z PL/SQL Developera **„W jednej linii, jeśli się mieści”** (i „W jednej linii”), osobne reguły list dla **UPDATE … SET**,
  **GROUP/ORDER BY** i **list w nawiasach (IN, argumenty)**, **układ podzapytań i CTE** (wcięte, `)` w osobnej linii),
  **położenie nawiasu zamykającego**, **lista od lewego marginesu** (PL/SQL Developer: *List at left margin*), łamanie
  **zagnieżdżonych warunków** i **długich wyrażeń** przed/po operatorze, CASE **„wieloliniowo, gdy się nie mieści”**,
  **wyrównanie kolumn tabel i pól rekordów/obiektów** (typ, DEFAULT, NOT NULL), układ **DDL** (kolumny i constrainty,
  klauzule fizyczne, nagłówek wyzwalacza), **wzorce `%` i `*` w pisowni specjalnej** (UG 29.2 — Pelikan ich nie ma).
- **Podgląd w Ustawieniach już jest** (D174): pakiet sformatowany według bieżących ustawień, linie zmienione ostatnią zmianą
  podświetlone, plus para „Teraz / Po zmianie tej opcji”. Braki: jeden przykład (bez DML/DDL/CTE), brak przewinięcia do
  zmiany (zmiana poza widokiem jest niewidoczna), usunięte linie nie są zaznaczane (np. opcja „Zachowuj puste linie” daje
  zmianę 0 linii), brak kolorowania składni. Propozycja w rozdz. 6.

## 2. Formater Pelikana dziś

**Kod.** `Packages/PelikanKit/Sources/PelikanSQL/Beautifier.swift` (1051 linii; `BeautifierOptions`, `Beautifier.format/verify`,
`Formatter` — jednoprzebiegowy automat na tokenach z ramkami `unit/declare/block/exception/ifStmt/loop/caseStmt/caseExpr/sql/paren`),
`BeautifierAligner.swift` (wyrównania — osobny przebieg po gotowych liniach, tylko dodaje spacje), `BeautifierExamples.swift`
(kod podglądu i przykład każdej opcji). Interfejs: `App/Sources/Preferences/BeautifierPane.swift`. Użycia poza edytorem:
Okno poleceń (BEAUTIFY), eksport obiektów, narzędzia (m.in. DBATools, DataGenerator, Scheduler, porównanie schematów).

**Opcje (31 + 3 automatyczne)** — grupy w Ustawieniach › Formater:

| Grupa | Opcje (domyślnie) |
|---|---|
| Układ | wcięcie (2), tabulatory (nie), prawy margines (100), zachowuj puste linie (tak), najwięcej pustych linii z rzędu (1), pusta linia przed podprogramem (nie) |
| Listy i przecinki | listy SELECT/SET/ORDER BY: element w linii / do marginesu (element w linii); deklaracje parametrów, parametry wywołań, listy INSERT: element w linii / do marginesu (do marginesu); przecinek na początku linii (nie) |
| Klauzule SQL i warunki | słowa klauzul: do lewej z elementami w kolumnie / do prawej („rzeka”) / w osobnej linii (do lewej); AND/OR na początku / na końcu linii (na początku); JOIN … ON w nowej linii (tak); THEN w nowej linii (nie); CASE w jednej linii / wieloliniowo (w jednej linii) |
| Wyrównanie | deklaracje, parametry (tryb, typ, DEFAULT), parametry nazwane `=>`, przypisania `:=`, aliasy w SELECT i FROM, `=` w SET, komentarze na końcu linii (wszystkie wyłączone) |
| Odstępy | wokół operatorów (tak), po przecinku (tak), wewnątrz nawiasów (nie) |
| Wielkość liter | słowa kluczowe (WIELKIE), identyfikatory (bez zmian), typy danych (jak słowa kluczowe), funkcje wbudowane i pakiety Oracle (jak identyfikatory), pisownia specjalna (lista słów) |
| Automatycznie | po otwarciu z bazy, przed kompilacją, przed zapisem |
| Regiony | `-- NoFormat Start/End`, `-- @formatter:off/on`; polecenia SQL*Plus, Java i JavaScript (MLE) kopiowane bez zmian |

Uwaga do semantyki: „Do marginesu” znaczy dwie różne rzeczy. W listach klauzul (SELECT, SET…) wypełnia linię do marginesu
i zawija; w nawiasach (parametry, INSERT, IN, argumenty) znaczy „w jednej linii, a jeśli się nie mieści — **każdy element w
osobnej linii**” (korpus 08, 09: kolumny INSERT w jednej linii, VALUES po jednym w linii). To w praktyce wartość *On one line if
possible* z PL/SQL Developera — dobrze byłoby nazwać ją tak samo i dodać prawdziwe „Do marginesu” (rozdz. 5).

**Testy.** `BeautifierTests` (16 testów: zapytanie, ciało pakietu, specyfikacja/wyzwalacz/WITH/MERGE/pętle, idempotencja, opcje,
zaznaczenie, bezpieczeństwo, literały wieloliniowe w zaznaczeniu, `/` jako dzielenie, polecenia SQL*Plus, MLE/Java, CASE w
PL/SQL, REFERENCING, TYPE BODY, NoFormat w linii kodu, wydajność 50 000 linii) i `BeautifierOptionsTests` (każda opcja zmienia
swój przykład i kod podglądu — przy ustawieniach domyślnych i „ciężkich”; każda właściwość ma przykład; bezpieczeństwo i
idempotencja przy każdej opcji osobno, narastająco i wszystkich naraz; wyrównania; układy klauzul). Ponadto 7 miejsc w
`PelikanWorkspaceTests` (BEAUTIFY, eksport, edytor).

**Bezpieczeństwo — jak jest dziś.** `Beautifier.format` zawsze wywołuje `verify(original:formatted:)`: sygnatura to ciąg tokenów
(bez białych znaków; słowa bez cudzysłowu bez rozróżniania wielkości liter; literały, identyfikatory w cudzysłowie, komentarze
blokowe i hinty dokładnie; komentarz liniowy bez skrajnych spacji), podział na polecenia według ScriptSplitter (`;`, `/` sam w
linii) i polecenia SQL*Plus jako cały tekst linii. Różnica = `BeautifierError.unsafe`, tekst bez zmian. To chroni literały,
q-quote, hinty, komentarze (w tym wciągnięcie kodu do komentarza `--`) i granice poleceń. **Luka:** wszystko, co lekser dzieli
na kilka tokenów, a Oracle czyta jako jeden — wstawienie spacji między takimi częściami przechodzi weryfikację. Znalezione
przypadki: `$IF/$THEN/$ELSE/$ELSIF/$END/$ERROR`, `$$nazwa` (lekser nie zaczyna słowa od `$`), `<=>`, `<->`, `<#>` (brak w
liście operatorów wieloznakowych). Bez szkody, ale też przez tę lukę: `1m` → `1 m` w STORAGE (Oracle przyjmuje — sprawdzone),
`<<outer>>` → `<< OUTER >>` (Oracle przyjmuje — sprawdzone). Bezpieczne w korpusie: `&zmienna`, `&&zmienna..`, `:bind`, `@dblink`,
`1e10`, `1.5f`, `n'…'`, `nq'[…]'`, `q'[…]'` z apostrofami i nawiasami, `DATE '…'`, hinty, `(+)`, `^=`, `~=`, `!=`, `**`, `a - -1`.

## 3. Inne narzędzia

### 3.1 Co oferują (opcje i wartości domyślne)

**PL/SQL Developer 17** (wzorzec; UG rozdz. 29, okno reguł z instalatora 17.0.3 — `manual.pdf` s. 297–298 i
`beautifierpreview.cfg`). Karty reguł: **General**, **Control Structures**, **DML**, **Parameter Declaration**, **Record Type
Declaration**; podgląd na żywo pod kartami (osobny przykład każdej karty). Karta General: *Indent* (2), *Right margin* (na zrzucie
76), *Use tab character*, *Tab character size*, *Align declarations*, *Align assignments*, *Empty Lines* (Remove / Merge into one /
Preserve), *Item Lists — Format*: **On one line / On one line if possible / One item per line / Fit**, *Align*, *Comma after item*;
*Syntax Case* (Keywords, Identifiers: Unchanged/Uppercase/Lowercase/Init Cap), *Use Special Case* z wzorcami `%` i `*`
(np. `DBA_%`). Karta Parameter Declaration ma m.in. *List at left margin* (działa od dwóch parametrów — forum). Przykłady kart
pokazują styl domyślny: SELECT „rzeką” (`  from`, ` where`, `   and`), `select … into …` w jednej linii, `from dept, emp` w jednej
linii, `insert into dept (deptno, …)` ze spacją przed nawiasem i `values (…)` w następnej linii, `update dept / set a = …, / where`,
parametry wyrównane za nawiasem, pola rekordu z `(` w nowej linii pod `type … is record` i typami w kolumnie. Dokładnych nazw
opcji kart DML/Control Structures/Parameter/Record nie ma w podręczniku (są „self-explanatory”) — **do uzupełnienia zrzutami od
właściciela**.

**Oracle SQL Developer / SQLcl** — *Advanced Format* (klucze z pliku ustawień, wartości Trivadis w nawiasach) i *Custom Format*
(program Arbori — dowolne reguły na drzewie składni). Wcięcie `identSpaces` (3), `useTab`, `maxCharLineSize` (120), `kwCase`,
`idCase`; łamanie: `breaksComma` Before/After/None (After), `commasPerLine` (1), `breaksConcat` Before/After/None (Before),
`breaksAroundLogicalConjunctions` Before/After/None (Before), `breakAnsiiJoin` (tak), `breakOnSubqueries` (tak),
`breakParenCondition` (tak — warunki w nawiasach też łamane), `breaksAfterSelect` (nie), `breaksProcArgs` (tak), `flowControl`
(np. IndentedActions / Terse); wyrównania: `alignTabColAliases`, `alignTypeDecl`, `alignNamedArgs`, `alignEquality`,
`alignAssignments`, `alignRight` (rzeka); odstępy: `spaceAroundOperators`, `spaceAfterCommas`, `spaceAroundBrackets`; puste
linie `extraLinesAfterSignificantStatements`; komentarze `singleLineComments`, `forceLinebreaksBeforeComment`. Znaczniki
`@formatter:off/on` i `noformat start/end`. Formater Trivadis/Arbori nie przebudowuje CREATE TABLE (tylko margines i wielkość liter).

**Toad for Oracle (Formatter Plus)** — według bazy wiedzy Quest i forum: układ list *Wrapped* / *Stacked* / *Stacked on more
than N items*, przecinki *Leading* / *Trailing* / *Leading with single space*, sześć trybów nawiasów list, AND/OR *stacked*
z *Allow flat* / *Allow half expanded*, wyrównanie komentarzy do prawego marginesu, słowa klauzul do prawej („rzeka”) w stylu
domyślnym. Brak opcji dla list IN/INTO był długo zgłaszany (ST99437).

**JetBrains DataGrip / IntelliJ** — najbogatszy zestaw, **osobno dla każdej klauzuli**. Wspólne: *Align the first word of
clause* (To left / To left with indent / To right), *Place clause elements on* (New line / Same line), *Place comma* (To begin /
To end / Auto), *Collapse short statements*, *Align section elements*, *Align line comments*. Dla SELECT, FROM, WHERE/HAVING,
GROUP/ORDER BY, UPDATE: *Wrap elements* **Chop / Chop if long / Wrap if long**, *Place comma*; SELECT: *Keep elements on one line
if ≤ N*, *Align AS*, *New line after DISTINCT*, *Use AS* (dopisuje AS — zmienia tokeny); FROM/JOIN: *Wrap the first/next JOIN*,
*Indent JOIN*, *Align joined tables/aliases*, *Wrap ON/USING*, *Place ON under* (Table / Table indented); WHERE: *Place top-level
AND/OR* (begin/end); UPDATE: *Align =*; INSERT/VALUES: *Place INTO on new line*, położenie `(`, *Place columns or values* (Same
line aligned / Wrapped unindented / aligned / indented), *Place the closing parenthesis* (At the end / To begin / Under opening /
Under elements), *Align multi-row VALUES*; **Subquery**: `(` w linii albo pod słowem, *Place subquery* (4 warianty), `)` (5
wariantów); **WITH**: *Wrap subqueries* (Chop / Chop if long), *Place comma* (także „In the middle”), *Align AS*. Kod
proceduralny: deklaracje (*Align types / assignments / expressions*), nawiasy i argumenty (jak wyżej), *Wrap THEN/ELSE*, *Indent
END IF*, *Wrap LOOP*, *Collapse when short*. Wyrażenia: *Align operands in binary expressions*; CASE: *Wrap WHEN*, *Wrap THEN*,
*Align THEN*, *Align ELSE under THEN*, *Align END* (z CASE / z WHEN / na końcu), *Collapse short clause*. **DDL**: `(` i `)` jak
wyżej, *Align types*, *Align defaults*, *Align nullabilities*, *Wrap CONSTRAINT*, *Wrap KEY/CHECK*, *Wrap REFERENCES*, *Wrap
cascade and deferrability*, *Wrap/Align alter instructions*, *Wrap AS* i *Indent query* (widoki), opcje po `)` (*Wrap first/next
option*, *Indent/Align options*), puste linie między deklaracjami (min/max).

**DBeaver** — formater *Default* (tokenowy), *Compact* i *External* (dowolny program, np. pgFormatter). Opcje formatera
domyślnego (źródło DBeaver, `SQLTokenizedFormatterConfigurationPage`): *Keyword case*, *Indent size* (4), *Insert spaces for tabs*,
*Insert line feed before commas*, *Indent substatements in parentheses* (nawias zamykający w nowej linii), *Insert delimiters in
empty lines*. Styl: słowo klauzuli w osobnej linii, elementy wcięte pod nim. Brak wyrównań i rozróżniania list.

**sqlfluff** (reguły układu): LT03 operatory na początku linii (domyślnie *leading*), LT04 przecinki na końcu (*trailing*),
LT07 `)` CTE w osobnej linii, LT08 pusta linia po CTE, LT09 każdy element SELECT w osobnej linii (pojedynczy — w linii SELECT),
LT10 DISTINCT w linii SELECT, LT11 operatory zbiorowe (UNION…) w osobnej linii, LT14 słowa klauzul od nowej linii, LT15 limit
pustych linii, LT05 długość linii. **sql-formatter (JS, dialekt plsql)**: `tabWidth` 2, `keywordCase`/`dataTypeCase`/
`functionCase`/`identifierCase`, `indentStyle` (standard / tabularLeft / tabularRight — rzeka), `logicalOperatorNewline`
(before), `expressionWidth` (50 — nawias krótszy zostaje w linii), `linesBetweenQueries`, `denseOperators`; brak opcji położenia
przecinka. **pgFormatter**: `--comma-end` (domyślnie) / `--comma-start`, `--comma-break` (INSERT), `--wrap-limit N`,
`--wrap-after N` (domyślnie każdy element w linii), `--keyword-case` (2 = WIELKIE), `--type-case` (1 = małe), `--function-case`,
`--spaces` (4).

### 3.2 Zestawienie według kategorii

Skróty: **PLD** PL/SQL Developer 17, **SQLD** SQL Developer/SQLcl, **DG** DataGrip, **DB** DBeaver, **Toad**, **inne**
sqlfluff / sql-formatter / pgFormatter, **Pelikan** stan obecny. „1L/1L?/E/M” = w jednej linii / w jednej linii, jeśli się mieści /
element w linii / do marginesu.

| Kategoria | PLD | SQLD | DG | DB | Toad | inne | Pelikan |
|---|---|---|---|---|---|---|---|
| Lista SELECT | Item lists + karta DML: 1L/1L?/E/M, Align, przecinek | E (commasPerLine), wyrównanie aliasów | Chop / Chop if long / Wrap if long, próg N, Align AS | E | Wrapped/Stacked/Stacked > N | sqlfluff E (1 element w linii SELECT); pgF E albo co N | E / M, aliasy |
| UPDATE … SET | karta DML (przykład: E, `=` niewyrównane) | jak listy, alignEquality | osobno: wrap, przecinek, Align = | E | jak listy | — | jak SELECT, Align = |
| INSERT kolumny / VALUES | karta DML (spacja przed `(`, VALUES w nowej linii) | jak listy | INTO w nowej linii, `(`, 4 układy, `)` 4 miejsca, Align multi-row | — | ST99437 (brak) | pgF `--comma-break` | 1L?/E, bez spacji przed `(` |
| IN (…) | Item lists (ogólne) | breakParenCondition | jak argumenty | — | brak opcji (KB) | sql-formatter expressionWidth | 1L? (stałe) |
| GROUP BY / ORDER BY | DML | jak listy | osobno + Align ASC/DESC | E | jak listy | — | jak SELECT |
| Parametry deklaracji | karta Parameter Declaration: format, Align, *List at left margin* | breaksProcArgs, alignTypeDecl | `(`, 4 układy, `)`, Align types | — | lista | — | 1L?/E, Align tryb/typ/DEFAULT |
| Argumenty wywołań, `=>` | Item lists | alignNamedArgs | jak nawiasy | — | lista | — | 1L?/E, Align `=>` |
| Przecinek | *Comma after item* | Before/After/None | To begin / To end / Auto (per klauzula) | *line feed before commas* | Leading / Trailing / Leading + spacja | sqlfluff trailing; pgF end | koniec / początek (globalnie) |
| Wyrównania | deklaracje, przypisania, listy, pola rekordu | aliasy, typy, `=>`, `=`, `:=`, rzeka | AS, `=`, typy, DEFAULT, NULL, operandy, komentarze | — | wiele | — | deklaracje, parametry, `=>`, `:=`, aliasy, `=` SET, komentarze |
| Nawiasy | (rekord: `(` w nowej linii) | spaceAroundBrackets | `(` 2 miejsca, `)` 4–5 miejsc | `)` w nowej linii | 6 trybów | sqlfluff LT07 (CTE) | `(` w linii, `)` za ostatnim elementem; spacje wewnątrz |
| Podzapytania FROM/WHERE/SELECT | — | breakOnSubqueries | 4 układy + nawiasy | wcięcie | — | — | „wiszące” za `(` |
| CTE WITH | — | — | Wrap subqueries, przecinek, Align AS | — | — | LT07, LT08 | każda CTE od nowej linii, treść za `(` |
| JOIN / ON | — | breakAnsiiJoin | wrap first/next, indent JOIN, ON pod tabelą/wcięte, align | — | — | — | JOIN jak klauzula, ON w nowej linii / w linii |
| AND/OR | (przykład: rzeka, `and` pod `where`) | Before/After/None + w nawiasach | top-level begin/end | — | stacked, flat, half expanded | sqlfluff leading; sql-formatter before | początek / koniec; tylko poziom główny |
| CASE | — | — | Wrap WHEN/THEN, Align THEN/ELSE/END, Collapse | — | — | — | 1L / wieloliniowo |
| MERGE, INSERT ALL | — | Arbori | — | — | — | — | częściowo (błędy — rozdz. 4) |
| OVER(…) | — | — | (jak wyrażenia) | — | — | — | 1L, bez łamania |
| Długie wyrażenia, margines | Right margin | maxCharLineSize, breaksConcat | Hard wrap, Align operands | — | Right margin | sqlfluff LT05 | łamanie po przecinku w nawiasie (rozdz. 4) |
| Komentarze w listach | (zachowane) | singleLineComments, forceLinebreaks | Align line comments | — | wyrównanie do marginesu | — | zostają w linii; Align |
| IF/LOOP/EXCEPTION | karta Control Structures | flowControl | Wrap THEN/ELSE/LOOP, Indent END IF | — | — | — | wcięcia; THEN w nowej linii |
| Deklaracje PL/SQL | Align declarations | alignTypeDecl | Align types/assignments/expressions | — | — | — | Align deklaracje |
| CREATE TABLE, constrainty | (Record Type: `(` w nowej linii, typy w kolumnie) | bez przebudowy | Align types/defaults/nullabilities, Wrap CONSTRAINT/KEY/REFERENCES/cascade, opcje po `)` | — | — | — | jak argumenty wywołania (1L?/E za nawiasem), opcje po `)` w jednej linii |
| CREATE INDEX / ALTER / GRANT | — | — | Wrap/Align alter instructions | — | — | — | jedna linia |
| Widok / MV | — | Arbori (podzapytanie) | Wrap AS, Indent query | — | — | — | SELECT w linii `AS` |
| Wyzwalacz | — | Arbori | — | — | — | — | nagłówek w jednej linii; COMPOUND bez struktury |
| Wielkość liter | Keywords, Identifiers, Special Case z `%`/`*` | kwCase, idCase | osobno słowa kluczowe, typy, funkcje, identyfikatory… | Keyword case | tak | sql-formatter i pgF: słowa kluczowe, typy, funkcje | słowa kluczowe, identyfikatory, typy, funkcje, pakiety, Special Case bez wzorców |

## 4. Braki znalezione na korpusie

Numer w nawiasie to przypadek w `korpus.txt`; obecny wynik — w plikach `wynik-*.txt`. „Oczekiwane” — wg PL/SQL Developera,
a gdzie nie ma odpowiednika — wg większości narzędzi.

### 4.1 P0 — bezpieczeństwo (formater zmienia znaczenie albo psuje kompilację)

| # | Brak | Przypadek | Oczekiwane |
|---|---|---|---|
| S1 | Kompilacja warunkowa: `$if`, `$then`, `$else`, `$end`, `$$plsql_unit` rozdzielane na `$ IF`, `$ $ plsql_unit`; do tego `$end end;` → `$` + `END END;` w nowej linii. PLS-00103 przy kompilacji (sprawdzone). | 64 | dyrektywy jako jeden token, bez zmian (najlepiej region bez formatowania od `$IF` do `$END`) |
| S2 | `<=>`, `<->`, `<#>` (odległość wektorów, 23ai) → `<= >`, `< ->`, `< # >` | 66 | operator bez zmian |
| S3 | `verify` nie widzi rozdzielenia tokenów, które w źródle były sklejone (przyczyna S1–S2; ryzyko dla każdej przyszłej konstrukcji, której lekser nie zna) | — | dodatkowy warunek w `verify` (rozdz. 5.1) |

### 4.2 P1 — błędy układu przy ustawieniach domyślnych

| # | Brak | Przypadki |
|---|---|---|
| F1 | Druga i dalsze instrukcje w gałęzi `WHEN … THEN` obsługi wyjątków i instrukcji CASE mają wcięcie gałęzi zamiast jej treści; IF/FOR w obsłudze wyjątku dostają złe poziomy (ELSE i END IF cofnięte o poziom). Widoczne też w podglądzie Ustawień (`RAISE` po `v_opis := NULL`). | 21, 31, 40 |
| F2 | TYPE BODY: `RETURN SELF AS RESULT` — `AS` traktowane jak początek deklaracji (`AS` / `result IS` w nowej linii) | 60 |
| F3 | Zapytanie po `IS`/`AS` (kursor, widok, MV, CREATE TABLE AS) zostaje w linii nagłówka, kolejne klauzule wcięte do kolumny 40–110; `WITH READ ONLY`/`WITH CHECK OPTION` doklejone do WHERE | 20, 36, 50, 51, 62 |
| F4 | Operatory zbiorowe: `UNION ALL SELECT …` w jednej linii, lista drugiego SELECT niesformatowana; w CTE rekurencyjnym (z SEARCH/CYCLE) główne SELECT bez nowej linii, łamanie wewnątrz `lpad(…)` w kolumnie 160 | 07, 29 |
| F5 | Warunek złączenia `ON a AND b`: `AND` w kolumnie klauzul (jak WHERE) zamiast pod/za `ON` — wygląda jak drugi warunek WHERE | 15 |
| F6 | MERGE: `ON (…)` w linii `USING (podzapytanie) s`; `WHEN MATCHED THEN UPDATE` / `SET` rozdzielone; `WHERE … DELETE` + `WHERE` w nowej linii; INSERT ALL/FIRST: `WHEN … THEN` doklejone do VALUES | 11, 12 |
| F7 | Długie wyrażenia (konkatenacja, arytmetyka) nie są łamane przy operatorach; formater łamie dopiero po przecinku wewnątrz argumentów funkcji, w kolumnie ~150 | 34, 07 |
| F8 | Długie warunki IF/ELSIF/WHILE i CASE w jednej linii (CASE zagnieżdżony 130 znaków, OVER(…) 110) — margines ignorowany | 13, 14, 18, 30, podgląd |
| F9 | Wyzwalacz: nagłówek (zdarzenia, ON, REFERENCING, FOR EACH ROW, FOLLOWS, WHEN) w jednej linii ponad margines; COMPOUND TRIGGER — sekcje BEFORE/AFTER … IS bez wcięcia, deklaracje w linii `COMPOUND TRIGGER` | 54, 56, 57 |
| F10 | CREATE TABLE: klauzule po `)` (TABLESPACE, STORAGE, PARTITION BY…) w jednej linii ponad margines; constrainty out-of-line długie | 46 |
| F11 | FORALL i FOR … LOOP z DML w tej samej linii: DML niesformatowany | 21, 56 |
| F12 | Przecinek na początku linii + komentarz `--` za elementem: komentarz przechodzi za przecinek następnego elementu; przy przecinku na końcu i komentarzu przed przecinkiem — przecinek sam w linii | 22, 65 |
| F13 | Reguła „Parametry wywołań” obejmuje rozmiary typów i pragmy: przy „element w linii” `NUMBER(14\n, 2)`, `EXCEPTION_INIT(e\n, -54)`; DDL (kolumny tabel, indeksy, typy obiektowe) też podlega tej regule | 19 (profil 2), 46 |
| F14 | Wielkość liter: słowa niezastrzeżone użyte jako nazwy zmieniane jak słowa kluczowe (`PATH`, `DAY`, etykieta `OUTER`), a wiele słów kluczowych nieznanych (`bitmap`, `parallel`, `build`, `refresh`, `fast`, `query rewrite`, `less`, `read`, `value`, `schema`, `logon`, `statement`, `old`/`new` w REFERENCING, `%notfound`) | 07, 32, 36, 39, 49, 51, 54, 56, 57, 58 |
| F15 | Spacja przed `(`: brak po nazwie tabeli (`INSERT INTO emp(`, `CREATE TABLE t(`, `REFERENCES t(c)`, `ON t(cols)`, CTE `hier(…)`) i po słowach spoza listy (`WITHIN GROUP(`, `GROUPING SETS(`, `CROSS APPLY(`, `STORAGE(`, `INTERVAL(`, `ADD(`, `MODIFY(`, `UPDATE(kol)` w GRANT); `VARRAY (10)` ze spacją, `VARCHAR2(30)` bez | 07, 09, 27, 42, 46, 48, 53, 59 |
| F16 | `DELETE` i `FROM` w osobnych liniach (PL/SQL Developer i inne: `DELETE FROM t`); `INSERT /*+ append */` + `INTO t SELECT` — INTO oderwane, SELECT w linii INTO; `RETURNING x` / `INTO v` jako dwie klauzule | 28, 38, 65 |
| F17 | Etykieta `<<outer>>` → `<< OUTER >>`, a następna instrukcja w tej samej linii | 32 |
| F18 | Rozmiar z jednostką `1m` → `1 m` (poprawne dla Oracle, ale zmiana wyglądu) | 46 |
| F19 | Pisownia specjalna bez wzorców `%`/`*` (UG 29.2: `DBA_%`) | — |
| F20 | `CROSS/OUTER APPLY`, `PIVOT`, `MATCH_RECOGNIZE` nie są klauzulami — podzapytanie za `APPLY(` wcięte do kolumny 30+ | 35, 42 |

### 4.3 Braki opcji (bez błędu — brak wyboru)

Lista (z odpowiednikami) w rozdz. 5.3. Najczęściej zgłaszane przez użytkowników narzędzi (forum PL/SQL Developera i Toad,
DataGrip): listy IN i VALUES „do marginesu”, osobny układ SET, nawias zamykający w osobnej linii, podzapytania i CTE wcięte
blokiem, próg „element w linii od N elementów”, wyrównanie kolumn CREATE TABLE, łamanie długich konkatenacji przed `||`.

## 5. Propozycja

Zasada: **zmiana domyślnego wyniku tylko tam, gdzie dziś jest błąd** (P0, P1). Nowe opcje (P2) mają wartości domyślne równe
obecnemu zachowaniu — chyba że właściciel zdecyduje inaczej (rozdz. 7).

### 5.1 P0 — bezpieczeństwo

1. **Lekser**: `$IF`, `$THEN`, `$ELSIF`, `$ELSE`, `$END`, `$ERROR` i `$$identyfikator` jako jeden token (nowy rodzaj, np.
   `.directive`); operatory `<=>`, `<->`, `<#>` w liście operatorów wieloznakowych. Korzysta z tego też podświetlanie składni.
2. **Formater**: region `$IF … $END` kopiowany bez zmian (jak `-- NoFormat`) — najprostsze i bezpieczne, bo gałęzie bywają
   niepełnymi fragmentami składni; ewentualnie później wcinanie dyrektyw.
3. **`verify` — warunek sklejenia**: para tokenów, które w źródle stały obok siebie bez białego znaku, może zostać rozdzielona
   tylko wtedy, gdy para jest na liście bezpiecznych (przecinek, nawiasy, operator znany jako całość, słowo–operator itd.).
   Odwrotnie: tokeny rozdzielone w źródle nie mogą się skleić (dziś pilnuje tego `joinable` tylko przy jednej opcji). To zamyka
   całą klasę błędów S1–S2 również dla konstrukcji, których dziś nie znamy.
4. **Testy**: korpus ryzykownych konstrukcji (przypadki 23, 24, 64–66 + Java/MLE 63) w `BeautifierTests.safety`, przy każdej
   opcji (jak `safetyAllCombinations`); **test integracyjny na bazie testowej**: zestaw jednostek PL/SQL (z kompilacją warunkową,
   wektorami, q-quote, hintami) kompilowany przed i po formatowaniu — te same `USER_ERRORS` (pusty zbiór) i ten sam wynik
   wywołania. Wpływ: bez zmian w istniejących testach.

### 5.2 P1 — poprawki układu (domyślny wynik zmienia się tylko w błędnych miejscach)

| Poprawka | Zachowanie po zmianie | Wpływ na testy / użytkowników |
|---|---|---|
| F1 wcięcie gałęzi WHEN | treść gałęzi (wszystkie instrukcje) na poziomie gałęzi + 1 | żaden test tego nie sprawdza; zmiana widoczna w każdym kodzie z wieloinstrukcyjną obsługą wyjątku — oczekiwana |
| F2 SELF AS RESULT | `AS RESULT` po `RETURN SELF` nie otwiera deklaracji | brak |
| F3 zapytanie po IS/AS | `IS`/`AS` na końcu linii nagłówka, zapytanie w nowej linii o jedno wcięcie głębiej (PL/SQL Developer: `cursor c is` / `  select …`); `WITH READ ONLY`, `WITH CHECK OPTION` jako klauzule | brak testów; mocno czytelniejsze kursory i widoki |
| F4 UNION/MINUS | operator w osobnej linii w kolumnie instrukcji, następny SELECT od nowej linii i formatowany jak pierwszy (sqlfluff LT11); SEARCH/CYCLE jako klauzule CTE | brak |
| F5 AND w ON | kolejne warunki złączenia pod pierwszym warunkiem (`  ON a = b` / `  AND c = d`) | brak (preview się zmieni) |
| F6 MERGE, INSERT ALL | `ON (…)` w nowej linii jak w JOIN; `WHEN MATCHED THEN` + `UPDATE SET …` z listą; `DELETE WHERE` jako klauzula; `WHEN … THEN` / `INTO` / `VALUES` w INSERT ALL wcięte | **zmienia** `BeautifierTests.misc` (`USING  s ON (…)`) |
| F7 długie wyrażenia | po przekroczeniu marginesu łamanie przed operatorem najwyższego poziomu (`||`, `+`, `-`…), kontynuacja wcięta pod początkiem wyrażenia; nigdy w środku argumentów, jeśli można przed operatorem | brak |
| F8 długie warunki i CASE | IF/ELSIF/WHILE/EXIT WHEN — łamanie przed AND/OR (wg „AND/OR na początku/końcu”), gdy nie mieści się; CASE — wieloliniowo, gdy nie mieści się (nowa wartość opcji, 5.3) | brak |
| F9 wyzwalacze | nagłówek: każda część (zdarzenia, ON, REFERENCING, FOR EACH ROW, FOLLOWS, WHEN) w nowej linii wciętej, gdy nie mieści się; COMPOUND: sekcje punktów czasowych jak podprogramy | `misc` (krótki nagłówek) bez zmian |
| F10 CREATE TABLE | klauzule po `)` w nowych liniach, gdy nie mieszczą się | brak |
| F11 FORALL / DML w linii | DML po nagłówku FORALL od nowej linii o wcięcie głębiej, sformatowany | brak |
| F12 komentarze w listach | komentarz `--` zostaje przy swoim elemencie, przecinek przed nim (przy przecinku z przodu: komentarz na końcu linii elementu) | brak |
| F13 typy i pragmy | rozmiary typów (`NUMBER(p,s)`, `VARCHAR2(n CHAR)`, `TIMESTAMP(6)`, `INTERVAL … (n)`) nigdy nie łamane; `PRAGMA` jak deklaracja; DDL dostaje własną regułę (5.3) | brak |
| F14 słowa kluczowe | lista słów kluczowych uzupełniona o słowa DDL/MV/wyzwalaczy/JSON; słowa niezastrzeżone (V$RESERVED_WORDS `RESERVED='N'`) — wielkość jak słowa kluczowe tylko w pozycji słowa kluczowego (po kropce, jako alias, nazwa kolumny w liście — jak identyfikator) | **zmienia** wynik dla nazw `path`, `day`, `name`, `type`… — dziś wielkie, będzie bez zmian; testy: do sprawdzenia `P1EditorTests` |
| F15 spacja przed `(` | po nazwie tabeli w INSERT INTO, CREATE TABLE, REFERENCES, CREATE INDEX … ON, liście kolumn CTE i widoku — spacja (jak PL/SQL Developer: `insert into dept (deptno…)`); po słowach kluczowych z listy uzupełnionej; typy danych zawsze bez spacji | **zmienia** `BeautifierTests.packageBody` (`INSERT INTO emp(empno, ename)`), podgląd i przykłady |
| F16 DELETE FROM, INSERT /*+ */ INTO, RETURNING … INTO | `DELETE FROM t` w jednej linii; INTO po hincie w linii INSERT; `RETURNING x INTO v` jako jedna klauzula (zawijana jak lista) | `DELETE` — brak testów; zmiana widoczna (zgodna z PL/SQL Developerem) |
| F17 etykiety | `<<etykieta>>` bez spacji, w osobnej linii, wielkość jak identyfikator | brak |
| F18 `1m` | liczba z jednostką (K/M/G/T/P/E) jako jeden token | brak |
| F19 Special Case z `%`/`*` | wzorzec `DBA_%` ustala pisownię początku słowa (UG 29.2) | brak (rozszerzenie) |
| F20 APPLY, PIVOT, MATCH_RECOGNIZE | `CROSS/OUTER APPLY` jak JOIN; PIVOT/UNPIVOT/MATCH_RECOGNIZE w nowej linii, treść wcięta | brak |

### 5.3 P2 — nowe opcje (Ustawienia › Formater)

Nazwy interfejsu po polsku (klucz = polskie zdanie, glosariusz: „Formater”, „Formatuj kod PL/SQL”). Identyfikatory dla
`BeautifierOptions` w nawiasach.

| Opcja | Wartości (domyślna **pogrubiona**) | Odpowiednik | Zmiana domyślnego wyniku |
|---|---|---|---|
| Układ list — czwarta i piąta wartość wszystkich reguł list (`ListLayout.oneLine`, `.oneLineIfFits`) | W jednej linii / W jednej linii, jeśli się mieści / Element w linii / Do marginesu | PLD Item Lists; DG Chop if long | nie (istniejące wartości bez zmian; obecne „Do marginesu” w nawiasach to semantycznie „W jednej linii, jeśli się mieści” — migracja ustawień 1:1) |
| Listy w nawiasach: IN, argumenty funkcji SQL (`parenthesisLists`) | W jednej linii, jeśli się mieści / **…** / Do marginesu | PLD Item Lists, DG, sql-formatter expressionWidth | nie (dziś: jeśli się mieści) |
| UPDATE … SET (`setList`) | **Element w linii** / … | DG UPDATE, owner | nie (dziś jak SELECT) |
| GROUP BY / ORDER BY (`groupOrderList`) | **Element w linii** / … | DG, PLD DML | nie |
| Element w linii od … elementów (`listThreshold`) | **1** … 9 | DG *Keep elements on one line if ≤ N*, Toad *Stacked on more than N* | nie |
| Kolumny i constrainty CREATE TABLE, ALTER … ADD (`ddlColumns`) | W jednej linii, jeśli się mieści / **Element w linii** / … | DG DDL | **tak** — dziś DDL podlega „Parametry wywołań” (do marginesu, czyli jeśli się mieści); proponuję element w linii jak PLD rekordy i wszystkie narzędzia |
| Lista od lewego marginesu: parametry, argumenty, kolumny tabel (`listIndent`) | **Za nawiasem** / Wcięta w nowej linii | PLD *List at left margin*, DG *Wrapped indented* | nie |
| Nawias zamykający list wieloliniowych (`closingParenthesis`) | **Za ostatnim elementem** / W osobnej linii | DG *Place the closing parenthesis*, DB *Indent substatements* | nie |
| Podzapytania i CTE (`subqueryLayout`) | **Za nawiasem** / Wcięte pod nawiasem, „)” w osobnej linii | DG Subquery/WITH, sqlfluff LT07, DB | nie |
| Pusta linia po CTE i między instrukcjami skryptu (`blankLineAfterStatement`) | **nie** / tak | sqlfluff LT08, sql-formatter linesBetweenQueries, pgF, SQLD extraLines | nie |
| Warunki w nawiasach: łam AND/OR (`breakNestedConditions`) | **Nie** / Gdy się nie mieszczą / Zawsze | SQLD breakParenCondition, Toad stacked | nie |
| Długie wyrażenia: operator (`expressionOperatorPosition`) | **Na początku linii** / Na końcu linii | SQLD breaksConcat (Before), sqlfluff LT03 (leading) | nie (samo łamanie — F7) |
| Wyrażenie CASE — trzecia wartość (`CaseLayout.multilineIfLong`) | W jednej linii / **Wieloliniowo, gdy się nie mieści** / Wieloliniowo | DG *Collapse short clause* | **tak** dla CASE dłuższych niż margines — pytanie 4 |
| Wyrównanie: kolumny tabel, pola rekordów i atrybuty typów — typ, DEFAULT, NOT NULL (`alignColumnDefinitions`) | **nie** / tak | PLD Record Type Declaration, DG Align types/defaults/nullabilities, SQLD alignTypeDecl | nie |
| Wyrównanie ASC/DESC w ORDER BY (`alignSortOrder`) | **nie** / tak | DG | nie |
| JOIN wcięte pod FROM (`indentJoins`) | **nie** / tak | DG Indent JOIN | nie |
| Nagłówek wyzwalacza (`triggerHeader`) | **W jednej linii, jeśli się mieści** / Każda część w nowej linii | DG DDL options | nie (poza F9) |
| Klauzule fizyczne tabel i indeksów (`ddlOptionsOnNewLine`) | **Gdy się nie mieszczą** / Każda w nowej linii | DG *Wrap first/next option* | nie (poza F10) |
| Przecinek osobno dla list w nawiasach (`commaBeforeInParentheses`) | **jak listy** / na końcu / na początku | DG per klauzula, Toad | nie |

Świadomie **pominięte**: opcje dopisujące lub usuwające tokeny (DG *Use AS*, dopisywanie nawiasów czy średników) — model
bezpieczeństwa Pelikana dopuszcza tylko białe znaki i wielkość liter. (Średnik w osobnej linii, jak sql-formatter
`newlineBeforeSemicolon`, byłby dozwolony — P3.)
DECODE formatowane jak CASE (prośba z forum PLD) — P3.

**Wpływ na istniejące testy i użytkowników (zbiorczo).** P0 — bez zmian w wyniku poprawnego kodu. P1 — zmienią się
oczekiwania w `BeautifierTests.packageBody` (spacja przed `(` w INSERT), `BeautifierTests.misc` (MERGE … ON), w kodzie podglądu
`BeautifierExamples.preview` i części przykładów opcji; testy Workspace używające formatera (BEAUTIFY, eksport, 7 miejsc) —
do przejrzenia po F14/F15/F16. Użytkownik, który formatuje już sformatowany kod, zobaczy różnice tylko w miejscach z tabeli 5.2
(przede wszystkim: wcięcie wieloinstrukcyjnych gałęzi wyjątków, kursory/widoki, `DELETE FROM`, spacja po nazwie tabeli). P2 —
zero zmian przy ustawieniach domyślnych poza `ddlColumns` i ewentualnie CASE (decyzja właściciela). Ustawienia zapisane
(`Codable` z wartościami domyślnymi dla brakujących kluczy) — wczytują się bez migracji.

**Kolejność prac (sugestia):** PR 1 — P0 (lekser, region `$IF`, `verify`, testy + test kompilacji na bazie); PR 2 — F1–F6, F11,
F12 (struktura); PR 3 — F7–F10, F13, F20 (margines, DDL, wyzwalacze); PR 4 — F14–F19 (słowa kluczowe, spacje, etykiety, Special
Case); PR 5 — podgląd (6.); PR 6+ — opcje P2 grupami (listy; nawiasy i podzapytania; warunki i wyrażenia; DDL i wyrównania).
Każdy PR: FEATURES.md (PD-BEAU-001), podręcznik (06-programy, 13-preferencje), L10n (en/de/es/uk), zrzut w tle karty Formater.

## 6. Podgląd w Ustawieniach › Formater

### 6.1 Stan obecny (D174)

`BeautifierPane` — po lewej formularz opcji, po prawej: (a) „Przykład opcji” — krótki fragment z `BeautifierExamples.all`
w dwóch kolumnach **Teraz** / **Po zmianie tej opcji** dla opcji wskazanej kursorem albo ostatnio zmienionej; (b) **podgląd**
`BeautifierExamples.preview` (pakiet ~30 linii) sformatowany według bieżących ustawień, odświeżany przy każdej zmianie, linie
zmienione ostatnią zmianą podświetlone na żółto (do następnej zmiany; `TextDiff.lineStatus`). Test
`BeautifierOptionsTests.everyOptionVisible` pilnuje, że każda opcja zmienia swój przykład i podgląd, a każda właściwość ma
przykład.

Braki: jeden przykład (pakiet) — nie ma w nim CTE, UNION, MERGE, DDL ani wyzwalacza, więc nowe opcje nie będą miały gdzie się
pokazać; zmiana poza widocznym fragmentem nie jest widoczna (brak przewinięcia); **usunięte linie nie są zaznaczane**
(`keepBlankLines` daje 0 zmienionych linii — w `podglad-wynik.md`); podświetlenie nie gaśnie; podgląd bez kolorowania składni;
para „Teraz / Po zmianie” — właściciel uważa zestawienia przed/po za zbędne.

### 6.2 Propozycja (P1)

1. **Jeden podgląd, cztery przełączane przykłady** (segment nad podglądem): **PL/SQL**, **Zapytania**, **DML**, **DDL**
   (pliki `formater/podglad/1-plsql.sql` … `4-ddl.sql` — kompletne, krótkie, 10–35 linii każdy). Wskazanie albo zmiana opcji
   przełącza na przykład, w którym ta opcja coś zmienia (mapa opcja → przykład, tabela 6.3), chyba że użytkownik sam wybrał
   przykład w tej sesji.
2. **Podświetlenie zmian**: linie zmienione i dodane — tło; miejsce usuniętych linii — znacznik na marginesie (cienka kreska
   między liniami); podświetlenie wygasa po ~3 s albo przy następnej zmianie (do decyzji — pytanie 6); **przewinięcie do pierwszej
   zmienionej linii**, gdy jest poza widokiem.
3. **Kolorowanie składni** w podglądzie (te same kolory co edytor — `CodeHTML`/lekser), numery linii, linia marginesu prawego
   (pionowa kreska w kolumnie `rightMargin`) — od razu widać, co go przekracza.
4. **„Teraz / Po zmianie”** — usunąć albo zwinąć w podpowiedź (dymek) przy opcji; test „każda opcja ma przykład” przenieść na
   „każda opcja zmienia podgląd”.
5. Ten sam podgląd z przełączaniem przykładów — także dla zestawów preferencji (podgląd zestawu przed zastosowaniem).

### 6.3 Opcja → fragment podglądu, który ją pokazuje

Obecne opcje — pomiar na plikach z `podglad/` (liczba zmienionych linii w `podglad-wynik.md`); proponowane — fragment, który
po wdrożeniu musi się zmieniać.

| Opcja | Przykład | Fragment |
|---|---|---|
| `indent`, `useTabs` | PL/SQL | całe ciało pakietu, BEGIN/IF/EXCEPTION |
| `rightMargin` | wszystkie | parametry `podwyzka`, długi IF, konkatenacja `v_opis`, lista NOT IN, constrainty |
| `keepBlankLines`, `maxBlankLines` | PL/SQL | dwie puste linie przed `procedure podwyzka` (usunięcie — znacznik usuniętej linii) |
| `blankLineBetweenSubprograms` | PL/SQL | między `END podwyzka;` a `FUNCTION suma_dzialu` |
| `listLayout` | Zapytania | lista SELECT, `ORDER BY 1, 2 DESC` |
| `setList` (nowa) | DML | `SET sal = …, comm = …, data_zmiany = …` |
| `groupOrderList` (nowa) | Zapytania | `ORDER BY 1, 2 DESC`; `GROUP BY` w CTE |
| `listThreshold` (nowa) | Zapytania | `ORDER BY 1, 2` (2 elementy) vs lista SELECT (5) |
| `parenthesisLists` (nowa) | Zapytania | `NOT IN ('SMITH', … 11 nazwisk)` |
| `parameterDeclarations`, `alignParameters` | PL/SQL | `podwyzka(…)` (4 parametry, ponad margines), `suma_dzialu(p_dzial, p_rok)` (mieści się) |
| `callParameters`, `alignNamedArguments` | PL/SQL | `zapisz_log(p_dzial => …, p_opis => …, p_kiedy => …)` |
| `listIndent`, `closingParenthesis` (nowe) | PL/SQL, DDL | parametry `podwyzka`; kolumny `log_zmian` |
| `insertLists` | DML | `INSERT INTO log_zmian (dzial, procent, kiedy, kto) VALUES (…)` |
| `commaBefore` | wszystkie | listy SELECT, SET, parametry, kolumny tabeli |
| `commaBeforeInParentheses` (nowa) | Zapytania, DDL | `NOT IN (…)`, kolumny tabeli |
| `clauseLayout` | Zapytania, DML | SELECT/FROM/WHERE, UPDATE/SET/WHERE |
| `andOrPosition` | Zapytania, DML | `WHERE (…) AND … AND …`, `WHERE deptno = … AND job <> …` |
| `breakNestedConditions` (nowa) | Zapytania | `(e.job = 'CLERK' OR e.job = 'ANALYST')` |
| `joinConditionOnNewLine`, `indentJoins` (nowa) | Zapytania | `JOIN dept d ON d.deptno = e.deptno AND d.loc IS NOT NULL` (także F5) |
| `subqueryLayout` (nowa) | Zapytania, DML | CTE `dzialy`, `duze`; `IN (SELECT deptno FROM duze)`; `USING (SELECT …)` w MERGE |
| `blankLineAfterStatement` (nowa) | DML, DDL | między instrukcjami; po CTE |
| `thenOnNewLine` | PL/SQL | `IF … THEN`, `ELSIF … THEN` |
| `caseLayout` (+ `multilineIfLong`) | PL/SQL, Zapytania | `v_opis := CASE …` (krótkie), `CASE WHEN e.sal > 3000 …` w SELECT (długie) |
| `expressionOperatorPosition` (nowa) | PL/SQL | `v_opis := 'Dział ' || … || c_limit` (ponad margines) |
| `spaceAroundOperators`, `spaceAfterComma`, `spaceInsideParentheses` | wszystkie | `g_licznik+1`, `nvl(e.comm,0)`, `NUMBER(12,2)` |
| `alignDeclarations`, `alignAssignments`, `alignTrailingComments` | PL/SQL | `c_limit`/`g_licznik` z komentarzami; `g_licznik := …`/`v_suma := …` |
| `alignAliases`, `alignSortOrder` (nowa) | Zapytania | aliasy `imie`, `dzial`, `prowizja`…; `ORDER BY 1, 2 DESC` |
| `alignSetValues` | DML | `SET sal = …` |
| `alignColumnDefinitions` (nowa) | DDL | kolumny `log_zmian`, atrybuty `t_zmiana` |
| `ddlColumns` (nowa) | DDL | `CREATE TABLE log_zmian (…)`, `ALTER TABLE … ADD (uwagi …, zrodlo …)` |
| `ddlOptionsOnNewLine` (nowa) | DDL | `) TABLESPACE users`, `COMPRESS 1` |
| `triggerHeader` (nowa) | DDL | `BEFORE INSERT OR UPDATE OF procent ON log_zmian FOR EACH ROW WHEN (…)` |
| `keywordCase`, `identifierCase` | wszystkie | słowa kluczowe i nazwy |
| `dataTypeCase` | PL/SQL, DDL | `NUMBER`, `VARCHAR2`, `PLS_INTEGER`, `DATE` |
| `functionCase` | wszystkie | `to_char`, `round`, `nvl`, `rank`, `sum` |
| `packageCase` | PL/SQL | `dbms_output.put_line` |
| `specialCase` (+ wzorce `%`) | PL/SQL | `dbms_output` (`DBMS_Output`), wzorzec `DBMS_%` |

Pomiar dla obecnych opcji (`podglad-wynik.md`): każda zmienia co najmniej jeden przykład; `keepBlankLines` zmienia wynik, ale
`TextDiff.lineStatus` zgłasza 0 linii (samo usunięcie) — dlatego punkt 6.2.2.

### 6.4 Test pokrycia (do wdrożenia — szkic)

```swift
@Test("podgląd: każda wartość każdej opcji zmienia przypisany przykład, a zmiana jest widoczna")
func previewCoverage() throws {
    for e in BeautifierExamples.all {                          // także nowe opcje
        for base in [BeautifierOptions(), Self.heavy] {
            for variant in e.values(base) {                    // wszystkie wartości opcji, nie jedna
                let sample = BeautifierExamples.previews[e.preview]   // przykład z mapy 6.3
                let a = try Beautifier.format(sample.code, options: base)
                let b = try Beautifier.format(sample.code, options: variant)
                guard base != variant else { continue }
                #expect(a != b, "\(e.id): \(sample.title) bez zmiany")
                // zmiana musi być widoczna: zmienione/dodane linie albo znacznik usunięcia
                let marks = PreviewDiff.marks(baseline: a, current: b)
                #expect(!marks.isEmpty, "\(e.id): zmiana bez podświetlenia")
                // i dotyczyć wskazanego fragmentu (marker z tabeli 6.3)
                #expect(marks.lines.contains { b.line($0).contains(e.marker) || a.line($0).contains(e.marker) })
            }
        }
    }
    // każda właściwość BeautifierOptions (poza automatycznym formatowaniem) ma wpis w mapie
    #expect(Set(Mirror(reflecting: BeautifierOptions()).children.compactMap(\.label))
        .subtracting(["afterLoad", "beforeCompile", "beforeSave"]) == Set(BeautifierExamples.all.map(\.id)))
}
```

Plus: podgląd każdego przykładu przy każdej opcji przechodzi `verify` i jest idempotentny (rozszerzenie
`safetyAllCombinations` o cztery przykłady).

## 7. Pytania do właściciela (domyślne zachowania)

1. **Przecinek** — na końcu linii (dziś; PL/SQL Developer *Comma after item*, SQL Developer, sqlfluff, pgFormatter) czy na
   początku (Toad, częsty styl Oracle)? Czy osobno dla list w nawiasach?
2. **Listy SELECT/SET/ORDER BY** — zostaje „element w linii” zawsze, czy „W jednej linii, jeśli się mieści” (PL/SQL Developer —
   na zrzucie reguł w podręczniku zaznaczone *On one line if possible*; czy to domyślne — do potwierdzenia), czy próg „element w linii od N elementów” (np. 3)? To
   zmieni wygląd krótkich zapytań (`SELECT a, b FROM t`).
3. **Listy IN (…) i VALUES** — „W jednej linii, jeśli się mieści” (dziś: inaczej element w linii) czy „Do marginesu”
   (długie listy literałów zajmują 2–3 linie zamiast 17)?
4. **CASE** — domyślnie „Wieloliniowo, gdy się nie mieści” (proponuję; zmienia tylko CASE dłuższe niż margines)?
5. **Podzapytania i CTE** — zostaje „za nawiasem” (wiszące, dziś) czy „wcięte, `)` w osobnej linii” (DataGrip, DBeaver,
   sqlfluff)? Przy wcięciu głęboko zagnieżdżone zapytania mieszczą się w marginesie.
6. **Podświetlenie w podglądzie** — do następnej zmiany (dziś) czy wygaszane po ok. 3 s? Czy usunąć parę „Teraz / Po zmianie”?
7. **Słowa klauzul** — zostaje „do lewej” (dziś) czy „do prawej / rzeka” jak w przykładach PL/SQL Developera (`  FROM`, ` WHERE`,
   `   AND`)?
8. **Spacja przed `(` po nazwie tabeli** (`INSERT INTO emp (…)`) i `DELETE FROM` w jednej linii — jak PL/SQL Developer (zmienia
   wynik dla istniejącego kodu)?
9. **Kolumny CREATE TABLE** — domyślnie element w linii (proponuję) i czy wyrównywać typy/DEFAULT/NOT NULL domyślnie?
10. **Wyrównania** (deklaracje i przypisania) — PL/SQL Developer ma je włączone na zrzucie reguł w podręczniku; w Pelikanie są
    wyłączone. Włączyć domyślnie?
11. Prośba: **zrzuty kart reguł PL/SQL Developera** — Control Structures, DML, Parameter Declaration, Record Type Declaration —
    żeby nazwy i wartości domyślne opcji odwzorować 1:1 (podręcznik ich nie wymienia).

## 8. Źródła

- PL/SQL Developer 17.0 User's Guide, rozdz. 29 (s. 296–299) i plik `beautifierpreview.cfg` — z instalatora `plsqldev1703x64.msi`
  (lokalnie, nie w repozytorium); forum Allround Automations:
  [List at left margin](https://forums.allroundautomations.com/threads/question-about-beautifiers-option-list-at-left-margin.15280/),
  [Beautifier Options for Parameter Calls](https://forums.allroundautomations.com/threads/enhancement-request-beautifier-options-for-parameter-calls.3538),
  [Wishlist: Beautifier](https://forums.allroundautomations.com/threads/wishlist-beautifier.4293),
  [More beautifier options](https://forums.allroundautomations.com/threads/more-beautifier-options.9710).
- SQL Developer/SQLcl: [Trivadis plsql-formatter-settings](https://github.com/Trivadis/plsql-formatter-settings),
  [trivadis_advanced_format.xml](https://raw.githubusercontent.com/Trivadis/plsql-formatter-settings/main/settings/sql_developer/trivadis_advanced_format.xml),
  [forum Oracle — line breaks on comma](https://forums.oracle.com/ords/apexds/post/code-formatting-issues-in-sql-developer-with-line-breaks-on-8978),
  [thatjeffsmith — formatter](https://www.thatjeffsmith.com/?p=5796).
- Toad: [Quest KB — list arrangements, commas](https://support.quest.com/toad-for-oracle/kb/4240276/toad-formatter-error-list-arrangements-commas),
  [stack IN/INTO (ST99437)](https://support.quest.com/ja-jp/toad-for-oracle/kb/4231938/is-there-an-option-to-stack-values-for-an-in-or-into-clause-in-the-sql-formatter),
  [AND/OR stacked, allow flat](https://support.quest.com/kb/4333827/format-options-allow-flat-and-allow-half-expanded-do-not-work-when-operators-punctuation-and-or-is-set-to-stacked-),
  [Editing Toad's formatting options](https://forums.toadworld.com/t/editing-toads-formatting-options/9209).
- DataGrip: [Queries](https://www.jetbrains.com/help/datagrip/code-style-sql-queries.html),
  [Code](https://www.jetbrains.com/help/datagrip/code-style-sql-code.html),
  [DDL](https://www.jetbrains.com/help/datagrip/code-style-sql-ddl.html),
  [Expressions](https://www.jetbrains.com/help/datagrip/code-style-sql-expressions.html).
- DBeaver: źródło `plugins/org.jkiss.dbeaver.ui.editors.sql/…/format/tokenized/SQLTokenizedFormatterConfigurationPage.java` i
  `SQLEditorMessages.properties` w [dbeaver/dbeaver](https://github.com/dbeaver/dbeaver);
  [SQL Formatting (wiki)](https://github.com/dbeaver/dbeaver/wiki/SQL-Formatting).
- [sqlfluff — reguły układu](https://docs.sqlfluff.com/en/stable/reference/rules/layout.html),
  [sql-formatter](https://github.com/sql-formatter-org/sql-formatter), [pgFormatter](https://github.com/darold/pgFormatter).
- Baza testowa Pelikana (`scripts/testdb.sh`): `STORAGE (INITIAL 1 M)` — poprawne; `<< OUTER >>` — poprawne;
  procedura po formatowaniu z `$ IF`/`$ $plsql_unit` — PLS-00103.
