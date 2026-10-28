# Okno programu i edytor kodu

## Okno programu

Okno programu służy do pisania i kompilowania jednostek PL/SQL: pakietów, procedur, funkcji, typów i wyzwalaczy, a
także źródeł Java i modułów MLE (JavaScript). Otworzysz je przez **Plik › Nowy › Okno programu** (⇧⌘N) albo poleceniem
**Edytuj** na obiekcie w Przeglądarce obiektów (kod zostanie wczytany prosto z bazy).

![Okno programu: pakiet z kartami specyfikacji i ciała, z lewej Zawartość kodu](../img/okno-programu.png)

- Każda jednostka pliku ma własną kartę (np. specyfikacja i ciało pakietu). Przycisk **+** obok kart albo **Plik ›
  Okno programu › Dodaj jednostkę…** dodaje jednostkę z szablonu (procedura, funkcja, pakiet, typ, wyzwalacz, źródło
  Java, moduł MLE) z formularzem nazw i parametrów. **Usuń jednostkę** usuwa kartę z tekstu (obiekt w bazie zostaje).
- **Edytuj** na pakiecie albo typie — także na jego ciele z folderów „Ciała pakietów” i „Ciała typów” — otwiera
  specyfikację i ciało w jednym oknie na dwóch kartach (otwarte z ciała: aktywna karta ciała). Obiekt bez ciała ma
  jedną kartę.
- Edytor pokazuje tylko jednostkę wybranej karty; aktywna karta jest wciśnięta i pogrubiona. Kartę zmienisz
  kliknięciem, przez **Plik › Okno programu › Pokaż jednostkę…**, **Następna jednostka** (⌥⌘], w profilu PL/SQL
  Developer też ⌃⇟) i **Poprzednia jednostka** (⌥⌘[, ⌃⇞) — kursor wraca tam, gdzie był na tej karcie. Każde przejście
  do miejsca w innej jednostce (błąd kompilacji, Zawartość kodu, Znajdź następne, Przejdź do deklaracji, zakładka,
  debuger, Wstecz/Naprzód, Cofnij) samo przełącza kartę. Strzałki i ⌘A nie wychodzą poza kartę. Numery linii na
  karcie, lista błędów i **Przejdź do linii** liczą linie jednostki jak Oracle (ALL_SOURCE, ALL_ERRORS) — linia 1 to
  linia `PACKAGE BODY …`. **Zamień wszystko** zamienia w całym oknie (wszystkich jednostkach).
- Jednostki rozpoznawane są po nagłówkach `CREATE … PACKAGE`, `PACKAGE BODY`, `TYPE`, `PROCEDURE`, `FUNCTION`,
  `TRIGGER` na początku linii — plik nie musi mieć „/” po jednostkach. Pelikan nie dopisuje „/” przy zapisie, a kod
  wczytany z bazy i nowe jednostki są bez „/” (chyba że włączysz **Preferencje › Oracle › Kończ jednostki okna
  programu znakiem „/”**). Plik z „/” zapisuje się bez zmian.
- **F8** (⌘↩) kompiluje wszystkie jednostki po kolei i zatrzymuje się na pierwszej z błędem. Kompilacja odbywa się w
  osobnej sesji w tle, więc nie blokuje okien SQL.
- Błędy i ostrzeżenia kompilatora pojawiają się pod edytorem. Kliknięcie przenosi do linii, dwuklik otwiera opis błędu
  w dokumentacji Oracle.
- Pasek stanu pokazuje, czy tekst jest zmieniony i niezapisany oraz czy jest nieskompilowany.
- **Plik › Zapisz** (⌘S) zapisuje tekst okna bez zmian (bez dopisywania `/`), z nazwą i rozszerzeniem według
  jednostki (np. `.pck`, `.prc`, `.fnc`, `.typ`, `.trg`).

### Bezpieczna praca z kodem w bazie

- **Sesja › Kompilacja próbna** kompiluje jednostki pod tymczasową nazwą i pokazuje błędy, nie zastępując obiektów w
  bazie.
- **Sesja › Sprawdź zmiany obiektów w bazie** sprawdza, czy ktoś inny zmienił obiekt od chwili wczytania albo
  kompilacji (Pelikan sprawdza to też cyklicznie i ostrzega na pasku stanu). Różnice obejrzysz przez **Plik › Porównaj
  › Porównaj ze źródłem w bazie**, a wersję z bazy wczytasz przez **Sesja › Wczytaj ponownie z bazy**.
- **Plik › Przywróć** odrzuca zmiany i wraca do tekstu z chwili otwarcia, wczytania albo zapisu.
- **Plik › Porównaj › Porównaj z plikiem…** i **Porównaj z obiektami w innej bazie…** (np. z bazą testową) otwierają
  przeglądarkę różnic.
- **Sesja › Uruchom blok w oknie testu** wykonuje zaznaczony blok anonimowy w nowym oknie testu z DBMS_OUTPUT.

### Ustawienia kompilatora

W **Preferencje › Oracle › Kompilator** ustawisz `PLSQL_WARNINGS`, `PLSQL_OPTIMIZE_LEVEL`, `PLSQL_CODE_TYPE`,
`PLSCOPE_SETTINGS` i `PLSQL_CCFLAGS` — Pelikan ustawia je w sesji kompilacji przed każdą kompilacją okna programu. W
sekcji **Debuger** włączysz automatyczne dodawanie informacji debugowania, **Podpowiedzi kompilatora** (dodatkowe
inspekcje kodu po kompilacji) i sprawdzanie **konwencji nazw** (przedrostki parametrów, zmiennych lokalnych i
globalnych, stałych, kursorów i typów). Komentarz `-- Ignore` na końcu linii wycisza podpowiedź dla tej linii.

## Edytor kodu

Ten sam edytor działa w oknach SQL, programu, testu i poleceń. Edytuje bez opóźnień nawet pakiety liczące
kilkadziesiąt tysięcy linii.

### Podpowiedzi i nawigacja

- **Podpowiedź kodu** pojawia się sama po kropce (np. `pakiet.`, `alias.`, `sekwencja.`) albo na żądanie: ⌥⎋ (w
  profilu PL/SQL Developer ⌃Spacja). Podpowiada obiekty schematu, kolumny (także przez aliasy tabel), elementy
  pakietów, parametry w notacji nazwanej, pola rekordów i `%ROWTYPE`, metody kolekcji, `:new`/`:old`, łącza baz po `@`
  oraz adnotacje i asercje utPLSQL. Pozycja **(all)** wstawia wszystkie kolumny albo parametry naraz. **Edycja ›
  Odśwież podpowiedzi kodu** odświeża pamięć podręczną słownika.
- Najechanie myszą na zmienną pokazuje jej deklarację.
- **⌘+klik** na nazwie albo **Edycja › Przejdź do deklaracji** (⌃⌘J) przenosi do deklaracji — w tym samym źródle, w
  innym otwartym oknie albo w obiekcie z bazy (w nowym oknie). **Edycja › Nawigacja › Wstecz** (⌃⌘←) i **Naprzód**
  (⌃⌘→) wracają po skokach.
- **Widok › Zawartość kodu** pokazuje drzewo struktury: osobno specyfikację i ciało pakietu (typu), w nich podprogramy
  z parametrami i typem zwracanym (pełny nagłówek w podpowiedzi), typy (rekord, tabela, REF CURSOR, podtyp), kursory,
  zmienne, stałe, wyjątki, pragmy i podprogramy zagnieżdżone. Elementy prywatne ciała (niezadeklarowane w
  specyfikacji) są pochylone. Klik albo Enter przenosi kursor do elementu (także na innej karcie), strzałki w drzewie
  przesuwają kursor bez opuszczania drzewa. Pole nad drzewem filtruje nazwy. Drzewo śledzi kursor, ma sortowanie i menu
  (zaznacz, kopiuj, wytnij, testuj podprogram, rozwiń/zwiń wszystko). Pod edytorem **hierarchia kodu** pokazuje
  ścieżkę od kursora (pakiet › procedura › blok); kliknięcie poziomu zaznacza go albo przenosi do nazwy.
- Menu kontekstowe na nazwie obiektu bazy w edytorze oferuje te same czynności co Przeglądarka obiektów.
- **F1** otwiera dokumentację Oracle dla słowa pod kursorem.

### Pisanie i zaznaczanie

| Czynność | Skrót (macOS) | Menu |
|---|---|---|
| Komentarz linii | ⌘/ | Edycja › Zaznaczenie |
| Powiel linię | ⇧⌘D | Edycja › Zaznaczenie |
| Wielkie / małe litery | ⌥⌘U / ⌥⇧⌘U | Edycja › Zaznaczenie |
| Zwiększ / zmniejsz wcięcie | ⌘] / ⌘[ | Edycja › Zaznaczenie |
| Formatuj kod PL/SQL | ⇧⌘F | Edycja |
| Znajdź i zamień | ⌘F | Edycja |
| Znajdź następne / poprzednie | ⌘G / ⇧⌘G | Edycja |
| Przejdź do linii | ⌘L | Edycja |
| Zwiń / rozwiń blok | ⌥⌘← / ⌥⌘→ | Edycja |
| Zwiń / rozwiń wszystko | ⌥⇧⌘← / ⌥⇧⌘→ | Edycja |
| Przełącz zakładkę | ⌘F3 | Edycja › Zakładki |
| Dodaj kursor powyżej / poniżej | ⌃⇧↑ / ⌃⇧↓ | Edycja › Wiele kursorów |
| Powiększ / pomniejsz czcionkę | ⌘= / ⌘− | Widok |

- **Zwijanie kodu**: strzałka w marginesie obok numerów linii zwija i rozwija blok (zwinięty blok — strzałka
  w kolorze akcentu, a w tekście „⋯” z podglądem zwiniętego kodu w podpowiedzi).
- **Wiele kursorów**: ⌥+klik dodaje kursor, Esc zostawia jeden. **Zaznaczenie kolumnowe**: przeciągnij z ⌥ — pisanie,
  Backspace i wklejanie działają we wszystkich liniach naraz.
- **Znajdź i zamień** obsługuje wyrażenia regularne (z `$1`), całe słowa, wielkość liter, zachowanie wielkości liter i
  wyszukiwanie tylko w kodzie, komentarzach albo literałach.
- **Zakładki** 0–9 (w profilu PL/SQL Developer ⌃K n ustawia, ⌃Q n przechodzi), nazwy zakładek i lista zakładek
  wszystkich okien. **Znaczniki kolorów** wyróżniają fragmenty tekstu jednym z sześciu kolorów.
- Edytor podświetla pary nawiasów i `BEGIN`/`IF`/`LOOP`/`CASE` ↔ `END`, wystąpienia nazwy pod kursorem, kolumnę
  `INSERT` odpowiadającą wartości w `VALUES` oraz polecenia `COMMIT`, `ROLLBACK` i `SAVEPOINT`.
- **AutoReplace** (Preferencje › Edytor) zamienia skróty na tekst podczas pisania; `|` w zamianie wyznacza pozycję
  kursora.
- **Widok › Podziel edytor** pokazuje dwa widoki tego samego tekstu. **Widok** ma też **Zawijaj wiersze**, **Znaki
  specjalne** i **Status linii** (znaczniki linii zmienionych i nowych od otwarcia albo zapisu).

### Formatowanie

**Edycja › Formatuj kod PL/SQL** (⇧⌘F) formatuje zaznaczenie albo całe źródło według reguł z **Preferencje ›
Formater** (wcięcia, listy, przecinki, puste linie, wielkość liter słów kluczowych i identyfikatorów, pisownia
specjalna). Formater może działać automatycznie po otwarciu źródła z bazy, przed kompilacją i przed zapisem. Fragment
między komentarzami `-- NoFormat Start` i `-- NoFormat End` zostaje bez zmian. Formatowanie nigdy nie zmienia
znaczenia kodu.

Karta **Preferencje › Formater** ma grupy **Układ**, **Listy i przecinki**, **Klauzule SQL i warunki** (słowa klauzul do
lewej, do prawej albo w osobnej linii; AND/OR na początku albo końcu linii; warunek JOIN … ON; THEN w nowej linii;
wieloliniowe CASE), **Wyrównanie w kolumnach** (deklaracje, parametry z trybem i typem, parametry nazwane `=>`,
przypisania `:=`, aliasy w SELECT i FROM, `=` w UPDATE … SET, komentarze na końcu linii), **Odstępy** i **Wielkość
liter** — osobno dla słów kluczowych, identyfikatorów, typów danych, funkcji wbudowanych i pakietów Oracle. Po prawej
jest podgląd: przykładowy pakiet, na którym widać każdą opcję, z podświetlonymi liniami zmienionymi ostatnią zmianą, a
nad nim przykład opcji wskazanej kursorem albo ostatnio zmienionej — **Teraz** i **Po zmianie tej opcji**. Region bez
formatowania można też oznaczyć komentarzami `-- @formatter:off` i `-- @formatter:on`.

### Szablony, snippety i makra

- **Szablony** (karta **Szablony** w lewej kolumnie albo **Widok › Okno szablonów**) wstawiają gotowe fragmenty:
  polecenia DML, pętle, typy, funkcje SQL, jednostki programów i szablony utPLSQL. Dwuklik albo przeciągnięcie do
  edytora wstawia szablon; zmienne szablonu wypełniasz w formularzu (`$OSUSER`, `$DBUSER`, `$DATE`, `$TIME` są
  podstawiane same). Własne szablony tworzysz przez **Narzędzia › Szablony › Zapisz zaznaczenie jako szablon…**.
- **Widok › Snippety** to biblioteka krótkich fragmentów do przeciągania (wbudowane i własne).
- **Makra**: F11 rozpoczyna i kończy nagrywanie, F12 odtwarza, ⇧F12 odtwarza wielokrotnie. Makro zapiszesz w
  bibliotece ze skrótem (**Edycja › Makra › Zapisz makro w bibliotece…**).
- **Edycja › Kopiuj jako literał** kopiuje zaznaczony SQL jako literał tekstowy języka (Swift, Java, C#, JavaScript,
  Python, C/C++, PHP, Delphi, Visual Basic); **Wklej z języka programowania** robi odwrotnie.
- **Historia schowka** (**Widok › Historia schowka**) przechowuje w pamięci ostatnie kopiowane teksty.

### Analiza kodu i refaktoryzacja

![Analiza w czasie pisania: podkreślona nieznana tabela i kolumna; edytor podzielony na dwa widoki](../img/analiza-kodu.png)

- Podczas pisania Pelikan podkreśla nieznane tabele, widoki, kolumny i aliasy (według słownika połączenia okna) oraz
  problemy: nieużywane zmienne i parametry, kod po `RETURN`/`RAISE`, `UPDATE`/`DELETE` bez `WHERE`, niejawne
  konwersje. F2 i ⇧F2 przechodzą do następnego i poprzedniego problemu, a **Edycja › Analiza kodu › Lista problemów**
  pokazuje wszystkie. Analizę wyłączysz w **Edycja › Analiza kodu › Analiza kodu w czasie pisania**.
- **Edycja › Refaktoryzacja › Znajdź użycia** (⌥F7) szuka użyć obiektu albo kolumny: obiekty zależne, linie ich kodu,
  PL/Scope, otwarte okna i pliki projektu.
- **Edycja › Refaktoryzacja › Zmień nazwę…** (⇧F6) zmienia nazwę zmiennej lub parametru w jej zakresie albo obiektu
  czy kolumny w oknach i plikach projektu. Przed zastosowaniem widzisz podgląd różnic; zmiana w bazie (DDL) trafia do
  nowego okna, nie jest wykonywana.
- **Wydziel stałą lokalną…**, **Wydziel stałą globalną…**, **Wydziel procedurę…** i **Zamień przypisanie na
  inicjalizację** w tym samym podmenu przekształcają zaznaczony kod; każdą zmianę cofniesz przez ⌘Z.

### Zadania To-Do

Komentarze `TODO` i `DONE` (z właścicielem, priorytetem i kategorią) są zbierane w oknie **Widok › Zadania To-Do**.
**Edycja › Wstaw zadanie To-Do** wstawia komentarz, a **Zamknij lub otwórz zadanie To-Do** zmienia jego stan.

## Pliki

- Pelikan otwiera z Findera i przez przeciągnięcie pliki `.sql`, `.pck`, `.pks`, `.pkb`, `.spc`, `.bdy`, `.prc`,
  `.fnc`, `.trg`, `.typ`, `.tps`, testy `.tst` i notatniki `.sqlnb`. Dodatkowe rozszerzenia programów i testów
  dopiszesz w **Preferencje › Ogólne**. Przeciągnięcie katalogu otwiera wszystkie jego skrypty.
- Pliki zachowują swoje kodowanie (UTF-8, ISO-8859-2, Windows-1250) i końce linii. Znak, którego nie da się zapisać w
  kodowaniu pliku, blokuje zapis z dokładnym wskazaniem linii i kolumny — kodowanie zmienisz tylko świadomie przez
  **Plik › Kodowanie pliku…**.
- **Plik › Tylko do odczytu** blokuje edycję okna.
- **Plik › Otwórz z połączeniem…** otwiera plik z od razu przypiętym połączeniem.
- **Edycja › Otwórz w zewnętrznym edytorze** przekazuje tekst do programu wskazanego w **Preferencje › Narzędzia**
  (np. Visual Studio Code); po powrocie do Pelikana zmiany są wczytywane.
- **Edycja › Szukaj w sieci** otwiera wyszukiwanie zaznaczonego słowa (adresy wyszukiwarek w Preferencjach).
- Pelikan zapamiętuje stan okien plików (kursor, zakładki, znaczniki, zwinięcia, wartości zmiennych).
- Po nieoczekiwanym zamknięciu aplikacji Pelikan proponuje odzyskanie niezapisanych okien (**Plik › Odzyskaj okna…**).
