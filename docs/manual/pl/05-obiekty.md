# Przeglądarka obiektów i edytory obiektów

## Przeglądarka obiektów

Karta **Obiekty** w lewej kolumnie pokazuje obiekty baz otwartych połączeń w folderach według typu: **Funkcje**,
**Procedury**, **Pakiety**, **Ciała pakietów**, **Typy**, **Wyzwalacze**, **Źródła Java**, **Biblioteki**, **Tabele**,
**Widoki**, **Widoki zmaterializowane**, **Sekwencje**, **Synonimy**, **Indeksy**, **Łącza bazy danych**, **Kolejki**,
**Zadania (Scheduler)**, **Użytkownicy**, **Role**, **Profile**, **Katalogi** i inne. Na bazach 23ai i 26ai dochodzą
**Moduły MLE**, **Środowiska MLE**, **Domeny**, **Grafy właściwości**, **Adnotacje** i **Asercje**. Foldery pojawiają
się tylko wtedy, gdy wersja bazy i Twoje uprawnienia na to pozwalają.

Na najwyższym poziomie drzewa są **otwarte połączenia** — jak w DBeaverze. Połączenia są ułożone alfabetycznie; główne
jest oznaczone gwiazdką, pogrubione i opisane „główne”; pozostałe pojawiają się po połączeniu (np. przez okno na innym
połączeniu albo **Połącz** na liście połączeń) i znikają po rozłączeniu. Każde połączenie ma pod sobą własne foldery,
**Ostatnie** i wybór użytkownika. Czynności na obiekcie (Pokaż dane, Edytuj, DDL, Rekompiluj, przeciągnięcie do
edytora…) działają na połączeniu gałęzi, a okna otwarte dla obiektu innego połączenia niż główne są do niego
przypięte. Menu połączenia w drzewie: **Ustaw jako połączenie główne**, **Nowe okno SQL na tym połączeniu**,
**Odśwież**, **Edytuj połączenie…** i **Rozłącz**. Połączenie główne jest domyślne tylko wtedy, gdy z kontekstu nie
wynika inne — nowe okno z menu, narzędzie bez aktywnego okna.

Na końcu folderów każdego połączenia są **DBA** — obiekty słownika z przedrostkiem `DBA_` — i **DBMS** — obiekty z
przedrostkiem `DBMS_`, głównie pakiety Oracle. Widać w nich tylko obiekty, do których masz uprawnienia (nadane wprost,
przez rolę albo PUBLIC); publiczne synonimy są pominięte, a obiekty schematu SYS pokazane bez przedrostka „SYS.”.
Obiekty rozwijają się i otwierają jak w pozostałych folderach, filtr nazw też działa. Zmiana obiektu schematu
utrzymywanego przez Oracle (SYS, XDB…) — rekompilacja, informacja debugowania, usunięcie, zmiana nazwy, włączenie albo
kompilacja w oknie programu — zawsze wymaga osobnego potwierdzenia (domyślnie **Anuluj**), bo może unieważnić obiekty
w całej bazie.

- **Wybór użytkownika** nad drzewem (osobno dla każdego połączenia):
  - *Bieżący użytkownik* — obiekty Twojego schematu oraz publiczne łącza bazy danych i publiczne synonimy obiektów
    aplikacji (bez tysięcy synonimów do schematów systemowych Oracle);
  - *Dostępne obiekty* — wszystko, czego możesz użyć: własne obiekty, obiekty innych schematów z nadanymi uprawnieniami
    i publiczne (z właścicielem przed nazwą);
  - *Wszyscy użytkownicy* — obiekty wszystkich schematów (z widokami DBA, gdy masz do nich dostęp, także katalogi
    Oracle i prywatne łącza bazy innych schematów — te ostatnie także wtedy, gdy masz odczyt
    samego `DBA_DB_LINKS`; prywatne łącze innego schematu nie jest dla Ciebie „dostępne”, bo używać go może tylko
    jego właściciel);
  - konkretny schemat.
  Folder **Katalogi** (katalogi Oracle nie mają właściciela schematu) pokazuje przy dostępie do widoków DBA wszystkie
  katalogi w każdym trybie, a bez niego — te z nadanym uprawnieniem.
  Zakres po połączeniu ustawisz w **Preferencje › Object Browser › Po połączeniu pokazuj**.
- **Filtr** pod wyborem użytkownika: część nazwy (szukana w dowolnym miejscu nazwy — `emp` znajdzie `EMP` i `T_EMP_HIST`),
  wzorzec z `%` (np. `EMP%` — tylko początek nazwy; zachowanie bez `%` zmienisz w **Preferencje › Object Browser**), kilka wzorców po przecinku, `status=invalid` (tylko
  niepoprawne obiekty) albo `source=tekst` (obiekty, których źródło zawiera tekst).
- Rozwinięcie obiektu pokazuje jego elementy: kolumny z typami, więzy, indeksy, wyzwalacze, partycje, podprogramy,
  atrybuty, a także zależności (**Zależy od**, **Używany przez**).
- Folder **Ostatnie** zawiera ostatnio otwierane obiekty.
- Obiekty niepoprawne mają czerwony znacznik.
- **Odśwież** w menu (albo **Narzędzia › Obiekt › Odśwież Object Browser**) czyści pamięć podręczną słownika i
  przeładowuje drzewo.

Drzewo działa płynnie także w schematach z dziesiątkami tysięcy obiektów — słownik jest czytany w tle.

### Menu obiektu

Kliknij obiekt prawym przyciskiem myszy (albo z ⌃). W menu, zależnie od typu obiektu:

- **Pokaż dane** — okno SQL z zapytaniem o dane tabeli lub widoku; **Zapytania standardowe** — Twoje zapisane szablony
  zapytań dla tabel;
- **Edytuj dane** — dane tabeli z `ROWID` w trybie edycji;
- **Edytuj** — źródło programu w oknie programu, widok w oknie SQL, a tabela, sekwencja, synonim, indeks, użytkownik
  czy rola — w edytorze obiektu;
- **DDL** (skrypt z DBMS_METADATA w nowym oknie), **Opis** (kolumny, parametry, elementy pakietu), **Właściwości**;
- **Testuj** — okno testu z wywołaniem procedury lub funkcji (zobacz rozdział *Okno testu, debuger i profiler*) i
  **Test standardowy…**;
- **Dodaj źródło do edytora** — wstawia źródło albo DDL w miejscu kursora aktywnego okna;
- **Rekompiluj**, **Włącz** / **Wyłącz** (wyzwalacze, więzy), **Flagi kompilacji warunkowej…**, **Zmień nazwę…**,
  **Duplikuj…** (skrypt kopii w nowym oknie, bez wykonania), **Usuń obiekt…** (po potwierdzeniu);
- **Generuj kod** — SELECT, INSERT, UPDATE, DELETE z kolumnami albo wywołanie procedury, także jako fragment Java JDBC
  lub Python;
- **Kopiuj nazwę**.

Na kolumnie albo więzie tabeli menu ma **Zmień nazwę elementu…**. Gdy zaznaczysz kilka obiektów (⌘+klik albo ⇧+klik),
menu proponuje czynności wspólne: **Kopiuj nazwy po przecinku** (także ⌘C), **DDL zaznaczonych**, **Rekompiluj
zaznaczone** i **Usuń zaznaczone…**.

Pozostałe operacje na zaznaczonym obiekcie są w menu **Narzędzia › Obiekt**: m.in. **Dodaj informację debugowania**,
**Edytuj definicję tabeli**, **Edytor widoku**, **Porównaj z aktywnym oknem**, **Porównaj z obiektem w innej bazie…**,
**Odśwież widok zmaterializowany**, **Testuj łącze**, **Uruchom zadanie**, **Uruchom kolejkę** / **Zatrzymaj
kolejkę**, **Dodaj do folderu…** i **Uruchom testy utPLSQL**.

### Przeciąganie

Przeciągnij obiekt do edytora, żeby wstawić jego nazwę. Z klawiszem ⌃ (albo gdy w Preferencjach wybrano „Pytaj”) po
upuszczeniu pojawi się menu: nazwa, nazwa z właścicielem, lista kolumn, SELECT, INSERT, UPDATE, DELETE, wywołanie albo
DDL. Upuszczenie obiektu na pusty obszar okien wykonuje akcję z **Preferencje › Object Browser** (np. Edytuj albo
Pokaż dane). Przeciągnięcie folderu wstawia nazwy jego obiektów po przecinku.

### Filtry i foldery własne

W **Preferencje › Object Browser** ustawisz:

- widoczne foldery i ich kolejność oraz akcję dwukliku dla każdego typu;
- **Filtry nazwane** — warunek `WHERE` i `ORDER BY` na widoku obiektów (alias `o`, zmienne `:browser_user` i
  `&browser_filter`), opcjonalnie dla wybranego użytkownika i jako filtr domyślny. Filtr zastosujesz przez **Narzędzia
  › Object Browser › Filtr nazwany…**;
- **Foldery użytkownika** — własne grupy obiektów z listy albo z zapytania (kolumny `OWNER`, `OBJECT_NAME`,
  `OBJECT_TYPE`), z kolorem, folderem nadrzędnym i wzorcem połączeń, na których mają być widoczne.

## Wyszukiwanie obiektów i kompilacja

- **Narzędzia › Znajdź obiekty bazy…** (⇧⌘O) przeszukuje źródła PL/SQL (także moduły MLE), zapytania widoków,
  definicje tabel i nazwy obiektów. Obsługuje wyrażenia regularne, całe słowa i wielkość liter, działa w tle i można
  je przerwać. Dwuklik na wyniku otwiera obiekt w linii z trafieniem. Kryteria możesz zapisać, a wynik wyeksportować
  do CSV.
- **Narzędzia › Kompiluj niepoprawne obiekty…** pokazuje niepoprawne obiekty schematu i kompiluje je w kolejności
  zależności, aż przestanie to cokolwiek zmieniać; błędy kompilacji są na liście.

## Edytor tabeli

Nową tabelę utworzysz przez **Plik › Nowy › Tabela…**, a istniejącą otworzysz poleceniem **Edytuj** z menu tabeli
(albo **Narzędzia › Obiekt › Edytuj definicję tabeli**).

![Edytor tabeli — karta Kolumny](../img/edytor-tabeli.png)

Karty edytora:

- **Ogólne** — nazwa, przestrzeń tabel (zmiana przenosi tabelę z przebudową indeksów), parametry składowania,
  kompresja, logowanie, klaster, tabela tymczasowa, organizacja indeksowa (IOT) albo tabela zewnętrzna, Row Archival,
  komentarz. Zmiany wymagające przebudowy wykonuje **Recreate table** z przeniesieniem danych, wyzwalaczy i kluczy
  obcych innych tabel.
- **Kolumny** — nazwa, typ (z podpowiedzią), NULL, wartość domyślna (także `ON NULL`), kolumna wirtualna, identity,
  kolumna niewidoczna, komentarz; na 23ai także domena i adnotacje. Przycisk dodaje kolumny klucza obcego na podstawie
  klucza głównego wskazanej tabeli.
- **Klucze** (główny, unikalne, obce z `ON DELETE`), **Warunki** (CHECK) i **Indeksy** (zwykłe, unikalne, bitmapowe,
  funkcyjne, malejące, z kompresją, odwrócone, niewidoczne, lokalne).
- **Uprawnienia** — odbiorca, uprawnienie i prawo nadawania; Pelikan wylicza z różnic polecenia GRANT i REVOKE.
- **Partycje i wyzwalacze** — przy tworzeniu partycjonowanie RANGE (także z INTERVAL), LIST i HASH oraz podpartycje
  HASH; w istniejącej tabeli dodawanie, zmiana nazwy i usuwanie partycji. Zmiana metody partycjonowania wymaga
  Recreate. Wyzwalacze tabeli możesz tu włączać i wyłączać.
- **SQL** — polecenia DDL wynikające ze zmian. Możesz je skopiować albo otworzyć w oknie SQL.

**Zastosuj** wykonuje zmiany jako `ALTER` i zatrzymuje się przy pierwszym błędzie; **Odśwież** wczytuje definicję z
bazy ponownie. Na połączeniu produkcyjnym potrzebne jest potwierdzenie.

## Inne edytory obiektów

W **Plik › Nowy** znajdziesz edytory: **Sekwencja…**, **Synonim…**, **Indeks…**, **Widok (edytor)…** (zapytanie,
FORCE, READ ONLY, CHECK OPTION, komentarz), **Widok…** (szablon w oknie SQL), **Użytkownik…**, **Rola…**, **Profil…**,
**Łącze bazy danych…**, **Biblioteka…**, **Katalog…**, **Zadanie…**, **Kolejka…**, a na nowszych bazach **Domena…** i
**Asercja…**. Każdy edytor pokazuje podgląd DDL przed wykonaniem; istniejące obiekty otwierasz poleceniem **Edytuj** z
Przeglądarki obiektów.

- **Użytkownik** — hasło (maskowane), przestrzenie tabel, profil, blokada konta, role, uprawnienia systemowe i
  obiektowe, limity w przestrzeniach. **Rola** — uprawnienia; **Profil** — limity.
- **Łącze bazy danych** — hasło łącza jest maskowane i nie pojawia się w podglądzie DDL.
- **Zadanie** tworzy zadanie DBMS_SCHEDULER (starsze DBMS_JOB zastąpił harmonogram).
- **Kolejka** tworzy kolejkę Advanced Queuing wraz z tabelą kolejki; kolejkę możesz uruchomić i zatrzymać.

Hasła wpisane w edytorach użytkowników i łączy są tylko w pamięci okna — nie trafiają do plików ani historii.

## Kosz

**Narzędzia › Kosz** pokazuje usunięte tabele (USER_RECYCLEBIN). **Kosz › Przywróć z kosza…** przywraca obiekt pod
starą albo nową nazwą, a **Kosz › Opróżnij kosz…** usuwa obiekty trwale (po potwierdzeniu).

## Diagramy

- **Narzędzia › Diagram › Diagram ER ze schematu…** rysuje tabele schematu (albo pasujące do maski) z kluczami obcymi
  i automatycznym układem warstwowym.
- **Plik › Nowy › Okno diagramu** tworzy pusty diagram; obiekty dodasz przeciągając je z Przeglądarki obiektów albo
  komendą **Narzędzia › Diagram › Dodaj do diagramu**.

![Diagram ER schematu](../img/diagram-er.png)

W oknie diagramu: **Powiązane** dodaje tabele połączone kluczami obcymi, **Zależności** — linie zależności,
**Notatka** i **Grupa** porządkują rysunek, **Kolumny** pokazuje lub ukrywa kolumny, **Siatka** włącza przyciąganie do
siatki 8 px, a powiększenie zmienisz od 10 do 200%. Dwuklik na linii dodaje punkt załamania, ⌥+klik go usuwa. Diagram
zapiszesz jako plik `.pdd`, zaktualizujesz z bazy (**Aktualizuj z bazy**), wydrukujesz albo wyeksportujesz do PNG lub
PDF.

## Oracle 23ai i 26ai

- **Narzędzia › Widoki dualności JSON** — lista widoków dualności JSON-relacyjnej z dokumentami i strukturą (Data
  Guide); **Nowy widok dualności…** generuje DDL z tabeli głównej i tabel podrzędnych.
- **Narzędzia › Moduły i środowiska MLE** — moduły JavaScript i środowiska; **Importuj moduł JavaScript…** tworzy
  moduł z pliku `.js`. Moduł edytujesz w oknie programu (z podświetlaniem JavaScript i błędami kompilacji).
- **Narzędzia › REST (ORDS)** — moduły REST i skrypty włączające REST dla schematu lub obiektu (wymaga ORDS w bazie).
- Domeny i adnotacje kolumn edytujesz w edytorze tabeli, a folder **Adnotacje** pokazuje, gdzie adnotacja jest użyta.
