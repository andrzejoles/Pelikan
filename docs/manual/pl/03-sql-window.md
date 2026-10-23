# SQL Window

SQL Window służy do wykonywania zapytań i skryptów. Wynik zapytania pojawia się w siatce pod edytorem, komunikaty — na
karcie *Output*, a wyjście DBMS_OUTPUT — na osobnej karcie.

## Wykonywanie

- **F8 / ⌘↩** — wykonuje zaznaczenie albo polecenie pod kursorem (zależnie od ustawienia *AutoSelect*).
- **⌃F8 / ⇧⌘↩** — wykonuje odwrotnie do *AutoSelect* (np. wszystkie polecenia okna zamiast polecenia pod kursorem).
- **Przerwij** (⌘.) — przerywa długie zapytanie.
- Zmienne podstawiania `&` i `&&` oraz zmienne wiązane `:nazwa` Pelikan wykrywa sam i pyta o wartości. Rozpoznaje też
  parametry raportów JasperReports `$P{…}`, `$P!{…}` i `$X{…}`.

## Siatka wyników

Siatka pobiera wiersze porcjami i dociąga kolejne przy przewijaniu. Kliknięcie nagłówka sortuje, a filtr działa lokalnie
na pobranych wierszach. Komórki można edytować, gdy zapytanie pobiera `ROWID` albo pochodzi z jednej tabeli z kluczem —
zmiany zatwierdza się przyciskiem i potwierdza zatwierdzeniem transakcji. Duże wartości (CLOB, BLOB, XML, JSON) otwiera
**Large Data Editor**.

Wynik wyeksportujesz do CSV, TSV, HTML, XML, XLSX, poleceń INSERT albo do schowka. **Panel wartości** (⌥⌘V) pokazuje
bieżącą komórkę jako tekst, JSON, XML, HTML, obraz albo hex.

## Transakcje

Pasek stanu pokazuje otwartą transakcję. **Commit** (F10, ⌥⌘↩) i **Rollback** są w menu Sesja i na pasku narzędzi. W trybie
*Multi session* każde okno ma własną sesję, w trybie *Dual session* okna dzielą jedną sesję.

## Explain Plan i Autotrace

**Explain Plan** (F5) pokazuje plan wykonania polecenia pod kursorem w postaci drzewa z kosztem, liczbą wierszy i
predykatami. Plany można porównywać, a **Autotrace** wykonuje polecenie i pokazuje plan rzeczywisty ze statystykami.
