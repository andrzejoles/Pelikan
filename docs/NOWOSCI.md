# Pelikan — nowości w wydaniach

Wydania stabilne od 1.0.0 (numeracja: D184). Historia bet 7.9.0–10.5.0: [`docs/BETA.md`](BETA.md).

## 1.4.0 — karty jednostek w oknie programu, bogatsza Zawartość kodu

- **Okno programu** z pakietem (albo typem) pokazuje naraz tylko specyfikację albo tylko ciało — tę jednostkę, której
  karta jest wybrana; aktywna karta jest wyraźnie zaznaczona. Kartę zmienisz kliknięciem, przez **Plik › Okno
  programu › Pokaż jednostkę…** albo skrótami ⌥⌘] / ⌥⌘[ (w profilu PL/SQL Developer także ⌃⇟ / ⌃⇞). Przejście do
  miejsca w drugiej jednostce — z listy błędów kompilacji, Zawartości kodu, wyszukiwania, deklaracji, zakładki czy
  debugera — przełącza kartę samo. Numery linii i **Przejdź do linii** liczą linie jednostki, tak jak Oracle w
  komunikatach o błędach.
- Przejścia z kart, Zawartości kodu i **Przejdź do linii** zawsze przewijają edytor do celu (wcześniej czasem kursor
  przesuwał się bez przewinięcia).
- **Zawartość kodu** pokazuje osobno specyfikację i ciało, podprogramy z parametrami i typem zwracanym, typy (rekordy,
  tabele, REF CURSOR, podtypy), kursory, stałe, zmienne, wyjątki, pragmy i podprogramy zagnieżdżone; elementy
  prywatne ciała są pochylone. Pojedyncze kliknięcie albo Enter przenosi do elementu, strzałki w drzewie przesuwają
  kursor w edytorze, a pole nad drzewem filtruje nazwy.
- Duże pakiety z tysiącami podprogramów nie blokują już okna podczas analizy kodu.
- **Pliki bez „/”:** okno programu rozpoznaje specyfikację, ciało i inne jednostki po nagłówkach `CREATE …`, także
  gdy jednostki nie kończą się znakiem „/” — karty, kompilacja F8 każdej jednostki osobno i numeracja linii działają
  tak samo. Pelikan nie dopisuje już „/” przy zapisie, a kod otwarty z bazy i nowe jednostki z szablonów są bez „/”
  (preferencja **Kończ jednostki okna programu znakiem „/”** w Preferencje › Oracle przywraca dawny układ).

## 1.3.1 — poprawki zgłoszeń

- **Rekord** na karcie **Wynik** i przycisk w pasku nad siatką przełączają wynik między tabelą a widokiem pojedynczego
  rekordu (wcześniej przycisk na wstążce nic nie robił).
- **Wstaw snippet**, **Wstaw szablon** i inne przyciski wstążki, które potrzebują wartości (kodowanie pliku, układ
  liczb, kopiowanie w formacie, generowanie kodu, otwarcie projektu, operacje Przeglądarki plików…), pytają o nią
  albo biorą zaznaczenie zamiast kończyć się komunikatem „Nieprawidłowy argument” (#111, #112). Makro nagrywa
  wybraną wartość, więc odtworzenie nie pyta ponownie.
- **Raporty AWR, ASH i ADDM** bez uprawnienia do pakietu Oracle pokazują czytelny komunikat z poleceniem GRANT dla
  administratora zamiast błędu ORA-00904 (#113, #114).
- **Autotrace** pyta o zmienne wiązane i podstawiania jak okno SQL — polecenie ze zmienną `:nazwa` nie kończy się już
  błędem ORA-01008.

## 1.3.0 — porządek na liście połączeń, foldery DBA i DBMS

- **Lista połączeń** — foldery i połączenia są ułożone alfabetycznie. Połączenie można skopiować pod inną nazwą
  (menu kontekstowe **Kopiuj pod inną nazwą…** albo **Sesja › Połączenia › Kopiuj połączenie…**) — kopia trafia do
  tego samego folderu razem z zapisanymi hasłami. Połączenia przenosisz między folderami, przeciągając je myszą (na
  wolne miejsce listy — na poziom główny), albo z menu **Przenieś do folderu**.
- **Obiekty** — połączenia w drzewie też są alfabetycznie (główne wyróżnia gwiazdka). Na końcu folderów każdego
  połączenia są nowe foldery **DBA** (obiekty słownika `DBA_…`) i **DBMS** (głównie pakiety Oracle `DBMS_…`) — tylko
  obiekty, do których masz uprawnienia.

## 1.2.5 — poprawka budowania wydania

- Wydanie zawiera wszystkie poprawki z 1.2.4 (niżej), które nie miały osobnego wydania: sprawdzenie podpisu z Hardened
  Runtime w skrypcie wydania odrzucało poprawnie podpisaną aplikację.

## 1.2.4 — poprawki z przeglądu kodu

- **Bezpieczeństwo** — aplikacja jest podpisana z Hardened Runtime. Plik eksportu połączeń z hasłami od początku ma
  prawa 0600; definicje połączeń są chronione razem z hasłami (zmieniony host w pliku odrzuca hasła), a nieudany import
  niczego nie zostawia w Pęku kluczy. Import preferencji pyta, zanim zmieni ustawienia uruchamiające programy (narzędzia
  użytkownika, agenci, edytor zewnętrzny, Instant Client…). Przeglądarka plików nie wykonuje poleceń z konfiguracji gita
  obcego repozytorium. Uszkodzony plik ustawień zostaje zachowany jako kopia `.bad-…` zamiast nadpisania.
- **Połączenia i sesje** — w trybach *Dwie sesje* i *Jedna sesja* CONNECT i DISCONNECT w Oknie poleceń nie zamykają już
  sesji głównej (wcześniej wycofywały niezatwierdzone zmiany innych okien). Rozłączenie i zmiana połączenia czekają, aż
  okno skończy wykonywać polecenie. Debuger nie zawiesza się w trybach *Dwie sesje* i *Jedna sesja*, a blok z błędem
  kompilacji kończy debugowanie po kilku sekundach. Preferencja „przypinaj nowe okna do połączenia” zaczęła działać.
  Znajdź obiekty, Kompiluj niepoprawne, Test Manager i Test Explorer pokazują swoje połączenie z możliwością wyboru
  i otwierają obiekty na nim (wcześniej mogły otworzyć obiekt o tej samej nazwie z innej bazy).
- **Edytory i słownik** — edytor tabeli działa na bazach 19c i starszych (wcześniej ORA-00904), edytor widoku czyta
  pełne zapytanie także ponad 4000 znaków. Wyzwalacze i indeksy innego schematu niż tabela są zmieniane w schemacie
  właściciela. Linia błędu kompilacji jest właściwa także przy `CREATE OR REPLACE` w osobnej linii, a kolumna na pasku
  stanu liczy znaki jak Oracle. Drzewo przeglądarki zachowuje rozwinięcie i zaznaczenie po odświeżeniu; prywatnego
  łącza innego schematu nie da się usunąć ani przetestować (trafiało we własne łącze o tej nazwie). `@plik`, START, GET
  i FORMAT FILE w Oknie poleceń czytają pliki w Windows-1250 i z BOM jak edytor.
- **Narzędzia danych** — import, przeniesienie danych i generator po błędzie lub przerwaniu wycofują niezatwierdzone
  wiersze i przywracają wyzwalacze i klucze. Nazwy tabel i kolumn z małymi literami są zachowane. TIMESTAMP WITH LOCAL
  TIME ZONE przenoszony bez przesunięcia strefy. Porównanie rekordów i wyników oraz „Kolumna do plików” biorą
  zaznaczone wiersze także w posortowanej lub przefiltrowanej siatce. `$X{…}` z nieznaną funkcją jest błędem zamiast
  warunku zawsze prawdziwego.
- **Agent AI** — narzędzia edytora agenta nie sięgają do okien połączeń ukrytych przed agentem, a `get_editor` zakrywa
  hasła. Maskowanie kolumn odrzuca kolejne obejścia (`*` w argumencie funkcji, DBMS_XMLGEN, XMLQUERY, CURSOR). Bardzo
  duży wynik narzędzia jest przycinany z jawnym znacznikiem, a limit „Największy wynik” wynosi najwyżej 1,5 MB.
- **Interfejs** — zamknięcie okna głównego kończy aplikację (z pytaniami o zapis i transakcje); kliknięcie ikony
  w Docku przywraca okno. Komendy panelu agenta są na wstążce (**Narzędzia › Agent AI**) i w wyszukiwarce czynności.
  Czynności na komórkach notatnika, elementach projektu, snippetach, makrach, w panelu debugera i na kanwie diagramu
  trafiają do dziennika komend i makr. Esc w trakcie przeciągania karty narzędzia nie odłącza go.
- **Sterownik thin** — tekst CLOB i DBMS_OUTPUT ponad 65 535 znaków jest obcinany ze znacznikiem zamiast kończyć
  aplikację; obsługa typu VECTOR. Znane ograniczenie: zapytanie zwracające kolumnę INTERVAL YEAR TO MONTH albo BFILE
  kończy aplikację w sterowniku thin (błąd biblioteki OracleNIO) — do takich danych używaj Instant Client.

## 1.2.3 — łącza bazy danych w przeglądarce

- **Łącza bazy danych** — przeglądarka czyta łącza z widoków `ALL_DB_LINKS`/`DBA_DB_LINKS`. W trybie *Wszyscy
  użytkownicy* i po wybraniu schematu widać prywatne łącza innych schematów, także gdy masz odczyt samego
  `DBA_DB_LINKS` (bez uprawnień do całego słownika). Prywatne łącze innego schematu nie pojawia się w trybach
  *Bieżący użytkownik* i *Dostępne obiekty* — używać go może tylko jego właściciel.
- **Łącza publiczne** — `ALL_OBJECTS` nie musi zawierać publicznych łączy bazy danych (są w `ALL_DB_LINKS`),
  dlatego w 1.2.2 część łączy mogła nie być widoczna.
- **Katalogi Oracle** — przy dostępie do widoków DBA folder pokazuje wszystkie katalogi w każdym trybie (wcześniej
  tylko te z nadanym uprawnieniem).

## 1.2.2 — kompletne obiekty w przeglądarce

- **Brakujące obiekty w przeglądarce** — tryb *Bieżący użytkownik* pokazuje też publiczne łącza bazy danych i publiczne
  synonimy obiektów aplikacji; nowy tryb *Dostępne obiekty* pokazuje wszystko, czego możesz użyć, także obiekty innych
  schematów z nadanymi uprawnieniami; *Wszyscy użytkownicy* z widokami DBA pokazuje wszystkie katalogi Oracle. Zakres
  po połączeniu: **Preferencje › Object Browser › Po połączeniu pokazuj**.

## 1.2.0 — eksport i import połączeń z hasłami

- **Połączenia z hasłami** — **Sesja › Połączenia › Eksportuj połączenia z hasłami…** zapisuje definicje razem
  z hasłami baz i tuneli SSH, po potwierdzeniu właściciela Maca (Touch ID albo hasło). Hasła są zaszyfrowane frazą
  albo — po dodatkowym ostrzeżeniu — zapisane jawnym tekstem (np. żeby odczytać dawne hasło do innego narzędzia).
  **Importuj definicje połączeń…** rozpoznaje taki plik, pyta o frazę, zapisuje hasła w Pęku kluczy i usuwa plik.

## 1.1.0 — wiele połączeń w przeglądarce obiektów

- **Przeglądarka obiektów jak w DBeaverze** — na najwyższym poziomie drzewa są wszystkie otwarte połączenia, każde
  z własnymi folderami, **Ostatnimi** i wyborem użytkownika. Połączenie główne jest pierwsze, z gwiazdką, pogrubione
  i opisane „główne”; rozłączone połączenie znika z drzewa. Czynności na obiekcie (Pokaż dane, Edytuj, DDL, Rekompiluj,
  przeciągnięcie do edytora…) działają na połączeniu jego gałęzi, a okna obiektów innego połączenia niż główne są do
  niego przypięte. Menu połączenia w drzewie: ustaw jako główne, nowe okno SQL, odśwież, edytuj, rozłącz.
- **Połączenie z kontekstu** — połączenie główne jest domyślne tylko wtedy, gdy kontekst nie wskazuje innego: obiekt
  wskazany w oknie poleceń albo przez nazwę bierze połączenie okna, „Nowa tabela…” i inne nowe obiekty — połączenie
  aktywnego okna. „Wczytaj ponownie z bazy” w oknie programu czyta źródło z połączenia okna (wcześniej z głównego).

## 1.0.0 — pierwsze wydanie stabilne

Pelikan wychodzi z bety. To natywne IDE dla Oracle SQL i PL/SQL na macOS (Apple Silicon): okna SQL, poleceń,
programu i testu z debugerem i profilerem, testy utPLSQL, przeglądarka i edytory obiektów, porównanie schematów,
raporty, notatniki SQL, narzędzia DBA oraz bezpieczne API MCP dla agentów AI. Interfejs po polsku, angielsku,
niemiecku, hiszpańsku i ukraińsku. Wersje 7.9–10.5 były testowane na prawdziwych bazach, także w próbie tylko do
odczytu na dużej bazie produkcyjnej (Oracle 19c).

Nowe od ostatniej bety (10.4.0):

- **Panele narzędzi** — okna narzędzi (Sesje, Znajdź obiekty, To-Do, instrukcja, edytory tabel, eksport, raporty
  i inne) otwierają się w panelu po prawej stronie okna głównego, każde w karcie. Kartę przeciągasz do panelu na dole
  albo poza panele (osobne okno); okno narzędzia wraca do panelu przyciskiem na pasku tytułu. Pelikan zapamiętuje
  miejsce każdego rodzaju narzędzia. Domyślne miejsce (także osobne okna jak dotąd) i autoukrywanie paneli ustawisz
  w **Preferencje › Ogólne › Panele narzędzi**, polecenia są w **Widok › Panele narzędzi**.
- **Numeracja wersji** — od 1.0.0 numer mówi, co się zmieniło: poprawki podnoszą ostatnią cyfrę, nowe funkcje
  środkową. Zainstalowane bety (10.x) zaktualizują się do 1.0.0 same.

Znane ograniczenia: Kerberos na macOS niedostępny (błąd adaptera Oracle w procesie z AppKit), logowanie Entra ID bez
próby na Azure, podgląd Quick Look wymaga notaryzacji, karty okien własne zamiast natywnych kart macOS — szczegóły
w [`docs/STATUS.md`](https://github.com/andrzejoles/Pelikan/blob/main/docs/STATUS.md).
