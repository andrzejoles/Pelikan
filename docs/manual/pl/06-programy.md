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
  wczytany z bazy i nowe jednostki są bez „/” (chyba że włączysz **Ustawienia › Oracle › Kończ jednostki okna
  programu znakiem „/”**). Plik z „/” zapisuje się bez zmian.
- **F8** (⌘↩) kompiluje wszystkie jednostki po kolei i zatrzymuje się na pierwszej z błędem. Kompilacja odbywa się w
  osobnej sesji w tle, więc nie blokuje okien SQL.
- Błędy i ostrzeżenia kompilatora pojawiają się pod edytorem. Kliknięcie przenosi do linii, dwukrotne kliknięcie otwiera opis błędu
  w dokumentacji Oracle.
- Pasek stanu pokazuje, czy tekst jest zmieniony i niezapisany oraz czy jest nieskompilowany.
- **Plik › Zapisz** (⌘S) zapisuje tekst okna bez zmian (bez dopisywania `/`), z nazwą i rozszerzeniem według
  jednostki (np. `.prc`, `.fnc`, `.trg`).
- **Specyfikacja i ciało w osobnych plikach.** Okno ze specyfikacją i ciałem pakietu zapisuje się do pary plików
  `nazwa.pks` (specyfikacja) i `nazwa.pkb` (ciało), typu — `nazwa.tps` i `nazwa.tpb`, bez „/”. **Zapisz jako…** (i
  pierwsze **Zapisz** nowego okna) pyta o nazwę i tworzy oba pliki w wybranym katalogu; gdy plik ciała już istnieje,
  pyta, czy go zastąpić. Każdy plik zachowuje swoje kodowanie i końce linii, a **Zapisz** zapisuje tylko plik, którego
  jednostka się zmieniła. Plik zawiera tekst swojej karty (z komentarzami nad `CREATE` i poleceniami `GRANT` za
  jednostką). Okno pary, z którego usuniesz ciało albo dodasz inną jednostkę, nie zapisze się do tych plików —
  **Plik › Zapisz jako jeden plik…** zapisuje całe okno w jednym pliku (np. `.pck`), jak dawniej.
- Otwarcie `nazwa.pks` albo `nazwa.pkb`, gdy obok leży plik pary, otwiera obie jednostki w jednym oknie na karcie
  otwartego pliku; tytuł okna to `nazwa.pks + .pkb`. Działa to także z Findera, Przeglądarki plików, listy ostatnich
  plików, projektu i workseta. Pliki, które nie są specyfikacją i ciałem jednego pakietu albo typu, otwierają się
  osobno — także plik `.pks` z komentarzem za `END` specyfikacji (przy zapisie przeszedłby do pliku ciała). Gdy plik
  pary zmienił się na dysku od otwarcia (inny program, `git checkout`), **Zapisz** pyta przed nadpisaniem. Rozszerzenia i otwieranie pary ustawisz w **Ustawienia › Ogólne › Specyfikacja i ciało w osobnych
  plikach**.

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

W **Ustawienia › Oracle › Kompilator** ustawisz `PLSQL_WARNINGS`, `PLSQL_OPTIMIZE_LEVEL`, `PLSQL_CODE_TYPE`,
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
  Panel pokazujesz i ukrywasz w każdym oknie osobno — **Widok › Zawartość kodu** albo przycisk z symbolem
  listy z wcięciami na lewym końcu paska okna; wybór zostaje w oknie (także w worksecie). **Ustawienia › Edytor ›
  Zawartość kodu domyślnie widoczna** decyduje o oknach, w których panelu nie przełączano.
- **Struktury sterujące** w Zawartości kodu: `IF` z gałęziami `ELSIF` i `ELSE`, pętle `LOOP`, `FOR` (liczbowe
  i kursorowe, także `FOR r IN (SELECT …) LOOP`) i `WHILE`, `FORALL`, instrukcja `CASE` z gałęziami `WHEN`
  (wyrażenie `CASE … END` w SQL i w przypisaniu nie jest węzłem), sekcja
  `EXCEPTION` z obsługami `WHEN wyjątek`, sekcja inicjalizacji ciała pakietu i punkty czasowe wyzwalacza złożonego.
  Węzeł pokazuje słowo otwierające, etykietę `<<nazwa>>` i skrócony warunek (np. „IF v_kwota > 0…”, „FOR r IN c_emp
  LOOP”), pełny nagłówek jest w podpowiedzi. Struktury są domyślnie zwinięte; klik przenosi kursor do słowa
  otwierającego, a drzewo zaznacza najgłębszą strukturę z kursorem. Filtr nazw szuka też w warunkach i etykietach.
  Niedokończona struktura (np. bez `END IF` w trakcie pisania) kończy się na `END` bloku albo przed następnym
  podprogramem, a `$IF … $END` (kompilacja warunkowa) nie jest instrukcją `IF`. Przycisk z symbolem rozgałęzienia obok
  filtra albo **Pokaż struktury sterujące** w menu panelu ukrywa je we wszystkich oknach (np. w dużym pakiecie);
  bloki `BEGIN … END` (także z `DECLARE`) są widoczne zawsze;
  to samo ustawienie: **Ustawienia › Edytor › Struktury sterujące w Zawartości kodu** (domyślnie włączone).
- Menu kontekstowe na nazwie obiektu bazy w edytorze oferuje te same czynności co Przeglądarka obiektów.
- **F1** otwiera dokumentację Oracle dla słowa pod kursorem.

### Pisanie i zaznaczanie

| Czynność | Skrót (macOS) | Menu |
|---|---|---|
| Przełącz komentarz linii | ⌘/ | Edycja › Zaznaczenie |
| Powiel linię | ⇧⌘D | Edycja › Zaznaczenie |
| Wielkie / małe litery | ⌥⌘U / ⌥⇧⌘U | Edycja › Zaznaczenie |
| Zwiększ / zmniejsz wcięcie | ⌘] / ⌘[ | Edycja › Zaznaczenie |
| Formatuj kod PL/SQL | ⇧⌘F | Edycja |
| Formatuj linię przy Enter (włącz / wyłącz) | — (do przypisania) | Edycja, pasek narzędzi |
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
- **AutoReplace** (Ustawienia › Edytor) zamienia skróty na tekst podczas pisania; `|` w zamianie wyznacza pozycję
  kursora.
- **Widok › Podziel edytor** pokazuje dwa widoki tego samego tekstu. **Widok** ma też **Zawijaj wiersze**, **Znaki
  specjalne** i **Status linii** (znaczniki linii zmienionych i nowych od otwarcia albo zapisu).

### Formatowanie

**Edycja › Formatuj kod PL/SQL** (⇧⌘F) formatuje zaznaczenie albo całe źródło według reguł z **Ustawienia ›
Formater** (wcięcia, listy, przecinki, puste linie, wielkość liter słów kluczowych i identyfikatorów, pisownia
specjalna). Formater może działać automatycznie po otwarciu źródła z bazy, przed kompilacją i przed zapisem. Fragment
między komentarzami `-- NoFormat Start` i `-- NoFormat End` zostaje bez zmian. Formatowanie nigdy nie zmienia
znaczenia kodu.

**Formatowanie podczas pisania.** Istniejący kod formater zmienia tylko na żądanie, ale nowy kod układa na bieżąco:
Enter w oknie SQL, programu i testu formatuje linię, którą opuszczasz — wielkość liter słów kluczowych i
identyfikatorów, odstępy wokół operatorów i przecinków, a linię zaczynającą się słowem klauzuli (`FROM`, `WHERE`,
`ORDER BY`, `JOIN`…), `AND`/`OR`, `END`, `ELSE`, `EXCEPTION` albo `)` wyrównuje do „rzeki” i struktury polecenia — i
wcina nową linię: pod pierwszym elementem listy po przecinku, o poziom głębiej po `BEGIN`, `THEN`, `LOOP`, wcięcie treści
podzapytania po `(`. Tekst nigdy nie przechodzi między liniami, wyrównanie wpisane w deklaracjach zostaje, a
komentarze, literały wieloliniowe, kompilacja warunkowa `$IF … $END`, kod Java/JavaScript i polecenia SQL*Plus — bez
zmian; linia z niedomkniętym nawiasem dostaje tylko wielkość liter. Formatowana jest tylko linia zmieniona od otwarcia, zapisu albo wczytania pliku — istniejąca, nieedytowana linia
zostaje bez zmian (nowa linia dostaje tylko wcięcie); Enter na początku linii albo w jej wcięciu to zwykły Enter, a ⌥↩
wstawia nową linię bez wcięcia i formatowania. Pierwsze ⌘Z cofa samo formatowanie, drugie —
Enter. Włączasz i wyłączasz je przełącznikiem z różdżką na pasku narzędzi (u góry po prawej), w menu **Edycja ›
Formatuj linię przy Enter**, na wstążce (karta **Edycja**) albo w **Ustawienia › Formater › Podczas pisania**;
konsola SQL*Plus nie formatuje.

Karta **Ustawienia › Formater** ma grupy **Układ**, **Listy i przecinki** (osobno listy SELECT/INTO/FROM, UPDATE …
SET, GROUP BY i ORDER BY, deklaracje parametrów, parametry wywołań, listy INSERT, listy w nawiasach — IN, argumenty
funkcji — oraz kolumny tabel, pola rekordów i typów: element w linii, w jednej linii, jeśli się mieści, albo do
marginesu), **Klauzule SQL i warunki** (słowa klauzul do prawej — „rzeka”, domyślnie — do lewej albo w osobnej linii;
AND/OR na początku albo końcu linii; warunek JOIN … ON; THEN w nowej linii; CASE w osobnych liniach — bardzo krótkie,
z jedną gałęzią WHEN, w jednej linii do zadanej liczby znaków; podzapytania i CTE wcięte z `)` w osobnej linii albo
za nawiasem; położenie operatora w długich wyrażeniach), **Warunki AND / OR** (dla każdego miejsca osobno — WHERE,
HAVING, JOIN … ON, MERGE … ON, START WITH / CONNECT BY, CASE … WHEN, IF / ELSIF, WHILE, EXIT / CONTINUE WHEN, WHEN
wyzwalacza, CHECK, nawiasy zagnieżdżone: łamanie — każdy w osobnej linii, tylko gdy warunek się nie mieści, nie łam;
położenie AND/OR; wyrównanie do słowa kluczowego — „rzeka”, pod pierwszym warunkiem albo pod nim z wcięciem),
**Wyrównanie w kolumnach** (deklaracje, parametry z trybem i typem, parametry nazwane `=>`, przypisania `:=`, aliasy w
SELECT i FROM, `=` w UPDATE … SET, kolumny tabel i pola rekordów — typ, DEFAULT, NOT NULL, komentarze na końcu linii),
**Odstępy** i **Wielkość liter** — osobno dla słów kluczowych, identyfikatorów, typów danych, funkcji wbudowanych i
pakietów Oracle; pisownia specjalna przyjmuje też wzorce z `%` albo `*` (np. `DBMS_%`). Po prawej jest podgląd z
kolorami składni, numerami linii i pionową linią prawego marginesu; przełącznik nad nim wybiera przykład: **PL/SQL**,
**Zapytania**, **DML** albo **DDL**. Linie zmienione ostatnią zmianą są podświetlone przez 5 s (albo do następnej
zmiany), miejsce usuniętych linii oznacza czerwona kreska; zmiana opcji przełącza na przykład, w którym ją widać, i
przewija do niej, a kliknięcie opcji pokazuje jej przykład. Region bez formatowania można też oznaczyć komentarzami
`-- @formatter:off` i `-- @formatter:on`; fragmenty kompilacji warunkowej `$IF … $END` formater zostawia bez zmian.

### Szablony, fragmenty kodu i makra

- **Szablony** (karta **Szablony** w lewej kolumnie albo **Widok › Okno szablonów**) wstawiają gotowe fragmenty:
  polecenia DML, pętle, typy, funkcje SQL, jednostki programów i szablony utPLSQL. Dwukrotne kliknięcie albo przeciągnięcie do
  edytora wstawia szablon; zmienne szablonu wypełniasz w formularzu (`$OSUSER`, `$DBUSER`, `$DATE`, `$TIME` są
  podstawiane same). Własne szablony tworzysz przez **Narzędzia › Szablony › Zapisz zaznaczenie jako szablon…**.
- **Widok › Fragmenty kodu** to biblioteka krótkich fragmentów kodu do przeciągania (wbudowane i własne).
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
- **Wyodrębnij stałą lokalną…**, **Wyodrębnij stałą globalną…**, **Wyodrębnij procedurę…** i **Zamień przypisanie na
  inicjalizację** w tym samym podmenu przekształcają zaznaczony kod; każdą zmianę cofniesz przez ⌘Z.

### Zadania To-Do

Komentarze `TODO` i `DONE` (z właścicielem, priorytetem i kategorią) są zbierane w oknie **Widok › Zadania To-Do**.
**Edycja › Wstaw zadanie To-Do** wstawia komentarz, a **Zamknij lub otwórz zadanie To-Do** zmienia jego stan.

## Pliki

- Pelikan otwiera z Findera i przez przeciągnięcie pliki `.sql`, `.pck`, `.pks`, `.pkb`, `.spc`, `.bdy`, `.prc`,
  `.fnc`, `.trg`, `.typ`, `.tps`, testy `.tst` i notatniki `.sqlnb`. Dodatkowe rozszerzenia programów i testów
  dopiszesz w **Ustawienia › Ogólne**. Przeciągnięcie katalogu otwiera wszystkie jego skrypty.
- Pliki zachowują swoje kodowanie (UTF-8, ISO-8859-2, Windows-1250) i końce linii. Znak, którego nie da się zapisać w
  kodowaniu pliku, blokuje zapis z dokładnym wskazaniem linii i kolumny — kodowanie zmienisz tylko świadomie przez
  **Plik › Kodowanie pliku…**.
- **Plik › Tylko do odczytu** blokuje edycję okna.
- Otwarty plik nie jest blokowany — inne programy (agent, git, edytor) mogą go zmieniać. Gdy wrócisz do okna, karty
  pary albo do Pelikana, a plik zmienił się na dysku, Pelikan pyta, czy **wczytać go ponownie**; okno z niezapisanymi
  zmianami ostrzega, że je utracisz (**Zachowaj moje zmiany** zostawia tekst okna, a późniejsze **Zapisz** jeszcze raz
  ostrzega przed nadpisaniem). Sama zmiana daty pliku (np. `touch`) nie wywołuje pytania. W oknie pary `.pks`/`.pkb`
  wczytywany jest tylko zmieniony plik. Plik usunięty albo przeniesiony: **Zachowaj w oknie** albo **Zamknij okno**.
  **Plik › Wczytaj ponownie z dysku** robi to na żądanie. W **Ustawienia › Ogólne › Pliki** wyłączysz wykrywanie
  albo włączysz wczytywanie bez pytania, gdy okno nie ma zmian.
- **Plik › Otwórz z połączeniem…** otwiera plik z od razu przypiętym połączeniem.
- **Edycja › Otwórz w zewnętrznym edytorze** przekazuje tekst do programu wskazanego w **Ustawienia › Narzędzia**
  (np. Visual Studio Code); po powrocie do Pelikana zmiany są wczytywane.
- **Edycja › Szukaj w sieci** otwiera wyszukiwanie zaznaczonego słowa (adresy wyszukiwarek w Ustawieniach).
- Pelikan zapamiętuje stan okien plików (kursor, zakładki, znaczniki, zwinięcia, wartości zmiennych).
- Po nieoczekiwanym zamknięciu aplikacji Pelikan proponuje odzyskanie niezapisanych okien (**Plik › Odzyskaj okna…**).
