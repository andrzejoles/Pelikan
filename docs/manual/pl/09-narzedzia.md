# Narzędzia

Ten rozdział opisuje narzędzia z menu **Narzędzia**, **Raporty**, **Projekt** i **Plik**: porównywanie i wdrażanie
zmian, eksport i import, raporty, notatniki, projekty i pliki. Narzędzia wydajności i administracji opisuje rozdział
*Plan wykonania, sesje i administracja*.

## Porównywanie schematów i wdrażanie zmian

### Porównanie obiektów użytkowników

**Narzędzia › Porównaj obiekty użytkowników…** porównuje DDL obiektów schematu ze schematem docelowym — na tym samym
albo innym połączeniu (np. `dev_test` z bazą testów akceptacyjnych).

![Porównanie obiektów użytkowników](../img/porownanie-obiektow.png)

1. Wpisz schemat źródłowy i kliknij **Wczytaj**. Zaznacz obiekty (filtr typu i nazwy, **Zaznacz widoczne**).
2. Wybierz **Połączenie docelowe** i opcjonalnie **Schemat docelowy**. Ustaw opcje: **Ignoruj wielkość liter**,
   **Ignoruj odstępy**, **Składowanie** (porównuj parametry składowania), **Usuń nadmiarowe** (skrypt usuwa obiekty,
   których nie ma w źródle).
3. Kliknij **Porównaj**. Lista pokazuje obiekty tylko w źródle, różne i tylko w celu, w kolejności zależności.
4. **Pokaż różnice** otwiera przeglądarkę różnic, a **Kopiuj SQL** i **Otwórz SQL** dają skrypt wyrównujący cel do
   źródła. Skryptu nie wykonuje się automatycznie — przejrzyj go i wykonaj świadomie.

### Database Diff i koszyk wdrożenia

**Narzędzia › Database Diff…** porównuje schematy według typów obiektów (także między połączeniami); dla tabel
generuje `ALTER TABLE` dodające, zmieniające i usuwające kolumny. Wybrane różnice dodasz przyciskiem **Do koszyka**.

**Narzędzia › Koszyk wdrożenia…** zbiera obiekty (DDL) i dane tabel (z filtrem WHERE) do pakietu zmian. Obiekt
zaznaczony w Przeglądarce obiektów dodasz przez **Narzędzia › Koszyk › Dodaj obiekt do koszyka**, a **Koszyk › Skrypt
wdrożenia koszyka** generuje skrypt w kolejności zależności w nowym oknie SQL — z `WHENEVER SQLERROR EXIT` i `COMMIT`
na końcu.

![Skrypt wdrożenia wygenerowany z koszyka](../img/koszyk.png)

### Porównanie danych tabel

**Narzędzia › Porównaj dane tabel…** porównuje dane po kluczu głównym (wiersze nowe, różne i nadmiarowe) z tabelą w
innym schemacie lub połączeniu. Wynik to skrypt albo bezpośrednia aktualizacja celu z `COMMIT` co n wierszy.

### Przeglądarka różnic

Wszystkie porównania tekstu (okno z plikiem, obiekt z bazą, historia lokalna, **Narzędzia › Porównaj pliki…**) używają
wbudowanej przeglądarki różnic: dwie kolumny, mapa zmian, przejście do następnej i poprzedniej różnicy, różnice
wewnątrz linii, ignorowanie wielkości liter, odstępów i komentarzy, zamiana stron i **Reload**. Zamiast niej możesz
używać własnego programu — **Preferencje › Narzędzia › Zewnętrzna przeglądarka różnic** (argumenty `%1`, `%2` — pliki,
`%3`, `%4` — tytuły).

## Eksport i import

| Narzędzie | Do czego |
|---|---|
| Narzędzia › Eksport obiektów użytkownika… | DDL wybranych obiektów do jednego pliku albo pliku na obiekt (specyfikacja z ciałem albo osobno), z uprawnieniami i składowaniem, w kolejności wykonalnej |
| Narzędzia › Eksport tabel… | dane tabel jako skrypt INSERT (z DROP/CREATE, TRUNCATE/DELETE, wyłączaniem wyzwalaczy i kluczy obcych, COMMIT co n, warunkiem WHERE), w formacie własnym Pelikana (skompresowanym) albo przez Data Pump |
| Narzędzia › Import tabel… | import skryptu INSERT albo formatu własnego z wyborem tabel; import Data Pump z REMAP_SCHEMA |
| Narzędzia › Import tekstu… | pliki CSV i tekstowe: wykrywanie separatora, nagłówka i kodowania, mapowanie pól na kolumny, funkcje przekształceń, filtr, obsługa duplikatów, CREATE TABLE z pliku |
| Narzędzia › Import z Excela… | pliki .xlsx (bez Excela i ODBC): arkusz, linia nagłówka, zakres, mapowanie |
| Narzędzia › Kreator importu danych… | kreator krok po kroku dla CSV, plików o stałej szerokości i XLSX, do nowej albo istniejącej tabeli, z zapisem profilu |
| Narzędzia › Kopiowanie schematu… | obiekty i dane do innego schematu lub połączenia (tabele, dane, obiekty, klucze obce, wyzwalacze) |
| Narzędzia › Przenoszenie danych… | tabela albo zapytanie do tabeli na tym samym lub innym połączeniu, z mapowaniem kolumn i trybem dopisz / TRUNCATE / DELETE; definicje można zapisać i uruchamiać w tle |
| Narzędzia › Generator danych… | dane testowe według wzorców, list, zapytań i zbiorów (imiona, firmy, adresy, e-maile), z relacją master/detail |
| Narzędzia › Dokumentacja schematu… | dokumentacja HTML: tabele z kolumnami i komentarzami, klucze, indeksy, widoki, programy z parametrami |

Eksport Data Pump zapisuje pliki po stronie serwera (katalog `DATA_PUMP_DIR`), nie na Macu. Narzędzia zapisujące do
bazy przechodzą przez te same zabezpieczenia co okno SQL: na połączeniu produkcyjnym pytają o potwierdzenie, na
połączeniu tylko do odczytu są zablokowane. Żadna zapisana definicja (przenoszenia, zadania, importu) nie zawiera
haseł.

## Raporty

### Raporty predefiniowane

**Raporty › Raporty predefiniowane…** otwiera zestaw gotowych raportów o bazie w kategoriach: *O bazie danych*,
*Obiekty*, *Tabele*, *PL/SQL*, *Bezpieczeństwo* i innych. Raport może pokazywać siatkę, wykres albo wyjście
DBMS_OUTPUT, pytać o zmienne i mieć szczegóły wiersza. **Otwórz raport w oknie SQL** pozwala zmodyfikować zapytanie, a
wynik wyeksportujesz do CSV, HTML albo XLSX.

![Raporty predefiniowane](../img/raporty-predefiniowane.png)

Menu **Raporty** ma też szybkie raporty: **Błędy kompilacji**, **Niepoprawne obiekty**, **Ostatnio zmienione
obiekty**, **Rozmiary tabel**, **Kolumny tabel**, **Uprawnienia użytkownika** i **Sesje**.

### Własne raporty

1. Otwórz **Plik › Nowy › Okno raportu** i wpisz zapytanie. Zmienne (`&<name="…">`, `:nazwa`, parametry JasperReports)
   działają jak w oknie SQL.
2. Wykonaj raport (F8). Wynik jest dokumentem HTML.
3. W karcie **Układ** ustaw dla kolumn tytuł, wyrównanie, format liczb (np. `#,##0.00`) i dat (np. `yyyy-MM-dd`),
   ukrywanie, **Grupa** (grupowanie z nagłówkiem grupy, master/detail) i **Suma** (sumy grup i suma końcowa).
4. Wybierz **Styl** z biblioteki (*Standardowy*, *Zielony*, *Kompaktowy*) i opcjonalnie **Dodatkowy CSS**; w
   **Opcjach** — nagłówek ze zmiennymi (`#title`, `#date`, `#user`, `#connection`, `#zmienna`), połączenie raportu,
   układ formularza zamiast tabeli, nową stronę po każdej grupie i tło.
5. Zapisz raport jako plik `.rep`. **Raport › Dodaj raport do menu Raporty** umieszcza go w **Raporty › Moje
   raporty**.

![Raport z grupami i sumami w stylu Zielony](../img/raport-styl.png)

**Raport › Zapisz raport jako HTML…**, **Eksportuj dane raportu…** (CSV, TSV, XML, Excel) i **Drukuj raport…** (także
do PDF) udostępniają wynik. **Zablokuj definicję raportu** ukrywa zapytanie i układ — raport można wtedy tylko
wykonywać (do odblokowania).

## Notatnik SQL

Notatnik (**Plik › Nowy › Notatnik SQL**) łączy komórki SQL/PL/SQL z komórkami Markdown — dobrze nadaje się do analiz
i instrukcji krok po kroku.

![Notatnik z komórką Markdown, zapytaniem i wykresem](../img/notatnik.png)

- **Dodaj komórkę** wstawia komórkę SQL albo Markdown; strzałki przesuwają komórki, kosz je usuwa.
- ▶ wykonuje komórkę, **Wykonaj wszystkie** — wszystkie po kolei (zatrzymuje się na błędzie).
- Przycisk wykresu tworzy wykres z wyniku komórki (Pelikan proponuje kategorię i serie).
- Wyniki i wykresy zapisują się w pliku `.sqlnb`, więc po otwarciu widać je bez ponownego wykonania.
- **Eksport Markdown…** (**Plik › Notatnik › Eksportuj notatnik jako Markdown…**) zapisuje notatnik z wynikami jako
  dokument Markdown.

## Query Builder

**Narzędzia › Query Builder…** buduje zapytanie wizualnie: przeciągnij tabele (także synonimy i podzapytania), Pelikan
doda złączenia z kluczy obcych (rodzaj złączenia zmienisz), zaznacz kolumny, ustaw aliasy, warunki WHERE i HAVING,
GROUP BY, ORDER BY i DISTINCT. Zapytanie trafia do edytora. Zaznaczony prosty SELECT otworzysz w Query Builderze do
modyfikacji.

## Testy wielu przypadków i obciążenia

- **Narzędzia › Test Manager** — zestawy testów (`.pts`): bloki z wartościami wejściowymi i oczekiwanymi (`=`, `LIKE`,
  `IN`, `NULL`, `NOT NULL`), zmienne globalne, DBMS_OUTPUT i limit czasu. Zmiany wykonywane przez testy są wycofywane.
  Test z błędem otworzysz w oknie testu do debugowania.
- **Narzędzia › Test obciążenia…** wykonuje kroki SQL/PL/SQL w wielu sesjach równolegle (zmienne `:thread` i
  `:iteration`), z wynikami na żywo (czasy, błędy, przepustowość) i zapisem do Excela.
- **Narzędzia › Monitor zdarzeń…** odbiera w osobnej sesji alerty DBMS_ALERT i wiadomości DBMS_PIPE.

## Wyszukiwanie

- **Edycja › Szukaj w edytorach i plikach…** (⌥⇧⌘F) szuka w bieżącym edytorze, we wszystkich otwartych oknach albo w
  plikach skryptów w katalogach (domyślnie w lokalizacjach przeglądarki plików), z wielkością liter, całymi słowami i
  wyrażeniami regularnymi. Kliknięcie wyniku otwiera plik w linii z trafieniem.
- **Narzędzia › Znajdź obiekty bazy…** (⇧⌘O) przeszukuje kod w bazie — zobacz rozdział *Przeglądarka obiektów*.
- **Projekt › Szukaj w projekcie…** szuka w plikach, źródłach obiektów i notatkach projektu.

## Historia lokalna

Pelikan zapisuje wersję pliku albo obiektu przy każdym zapisie, kompilacji, refaktoryzacji i przywróceniu —
niezależnie od Gita i bez połączenia z bazą. **Plik › Historia lokalna › Historia lokalna** pokazuje wersje aktywnego
okna; **Porównaj z bieżącym** otwiera różnice, a **Przywróć** wstawia starą wersję (bieżący tekst zostaje w historii).
**Zapisz wersję w historii** dodaje wersję ręcznie, z opisem. Historia przechowuje do 50 wersji z ostatnich 30 dni.

![Historia lokalna pliku](../img/historia-lokalna.png)

## Projekty, worksety i pliki

- **Projekt** grupuje pliki i obiekty bazy (z notatkami i grupami) w pliku `.prj`. **Projekt › Buduj projekt**
  kompiluje wszystko w kolejności elementów, a **Make projektu** — tylko pliki zmienione od ostatniego budowania i
  obiekty niepoprawne. Opcje projektu to m.in. połączenie, zatrzymanie po pierwszym błędzie i formatowanie. **Zapisz
  pulpit projektu** zapamiętuje otwarte okna.
- **Workset** (zestaw roboczy) zapamiętuje otwarte okna — także z niezapisanymi zmianami i wartościami zmiennych — i
  przywraca je przy następnym uruchomieniu (**Plik › Workset**: nowy, otwórz, zapisz, przywróć, zamknij, porównaj,
  autozapis). Układ okna głównego zapisujesz w **Widok › Zapisz układ okna**.
- **Przeglądarka plików** (karta **Pliki**) pokazuje wybrane katalogi (lokalizacje z filtrem i kolorem) z menu: otwórz
  jako, zmień nazwę, nowy plik lub katalog, przenieś do Kosza, pokaż w Finderze. Filtr działa po nazwie, stanie,
  stanie Git, rozmiarze i dacie.
- **Git**: gałąź i stan pliku są na pasku stanu, w przeglądarce plików i w projekcie. **Narzędzia › Git** ma stan
  pliku, porównanie z HEAD, `git add`, `git commit` i historię pliku.

## Inne

- **Narzędzia › Narzędzia użytkownika…** — własne narzędzia: programy zewnętrzne ze zmiennymi (`#file`, `#object`,
  `#selection`, `#connection`…) albo bloki SQL dla sesji. Programy są uruchamiane bez powłoki, a zmienne nigdy nie
  zawierają haseł.
- **Narzędzia › Zadania lokalne…** — skrypty, eksporty i przenoszenia danych uruchamiane cyklicznie (co n minut,
  codziennie, w wybrane dni), gdy Pelikan działa. Definicje nie zawierają haseł; dziennik pokazuje wynik każdego
  przebiegu.
- **Widok › Zadania w tle** — lista długich operacji (Autotrace, eksporty, dokumentacja) ze stanem, czasem i
  anulowaniem.
- **Narzędzia › Dokumenty…** — Twoje dokumenty i adresy http(s) z listy w **Preferencje › Narzędzia**.
- Usługi macOS (menu **Usługi** w dowolnej aplikacji): **Pelikan: Formatuj SQL** formatuje zaznaczony tekst w miejscu,
  a **Pelikan: Otwórz w SQL Window** przenosi zaznaczony tekst do nowego okna SQL Pelikana.
