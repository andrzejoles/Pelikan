# Wprowadzenie i pierwsze uruchomienie

Pelikan to natywne środowisko macOS do pracy z bazą Oracle: pisania i wykonywania SQL, tworzenia, testowania i
debugowania kodu PL/SQL, przeglądania i edycji obiektów bazy, testów utPLSQL oraz narzędzi porównywania, eksportu i
administracji. Układ okien i skróty klawiszowe odpowiadają programowi PL/SQL Developer, więc jego użytkownicy odnajdą
znajome okna — w Pelikanie noszą polskie nazwy: **Okno SQL**, **Okno poleceń**, **Okno programu**, **Okno testu**,
**Okno planu** i **Przeglądarka obiektów** (karta **Obiekty**).

Ta instrukcja opisuje, jak wykonać typowe zadania. Pełna lista komend z bieżącymi skrótami jest w ostatnim rozdziale,
**Skróty klawiszowe**, generowanym z aplikacji.

## Wymagania

- Mac z procesorem Apple (M1 lub nowszym) i macOS 27 albo nowszy.
- Oracle Instant Client dla macOS (ARM64) — pakiet Basic albo Basic Light. Pelikan go nie zawiera (nie pozwala na to
  licencja Oracle), więc pobierasz go sam ze strony Oracle. Bez Instant Client działa sterownik *Thin* z
  ograniczeniami (zobacz niżej).
- Baza Oracle. Pelikan jest rozwijany i testowany na Oracle Database 26ai Free; zapytania słownika danych mają
  warianty dla wersji 19c, 21c i 23ai. Na starszych wersjach część folderów i funkcji może być niedostępna.

## Instalacja

1. Pobierz najnowsze wydanie ze strony projektu:
   [github.com/andrzejoles/Pelikan/releases](https://github.com/andrzejoles/Pelikan/releases) — plik `.dmg` albo
   instalator `.pkg`.
2. Z obrazu `.dmg` przeciągnij **Pelikan** na skrót **Aplikacje (Applications)**. Instalator `.pkg` zrobi to sam.
3. Uruchom Pelikana z folderu Aplikacje.

### Ostrzeżenie Gatekeepera przy pierwszym uruchomieniu

Pelikan jest podpisany własnym certyfikatem autora („Pelikan Self-Signed”), ale nie jest notaryzowany przez Apple
(wymagałoby to płatnego konta dewelopera). Dlatego przy pierwszym uruchomieniu macOS zablokuje aplikację i pokaże
ostrzeżenie. Aby ją otworzyć:

1. Zamknij okno ostrzeżenia.
2. Otwórz **Ustawienia systemowe › Prywatność i ochrona**, przewiń do sekcji **Ochrona** i kliknij **Otwórz mimo to**
   przy komunikacie o Pelikanie.
3. Potwierdź hasłem albo Touch ID.

Robisz to tylko raz. Stały podpis sprawia też, że po aktualizacji macOS nie pyta ponownie o dostęp Pelikana do haseł w
Pęku kluczy.

## Oracle Instant Client

Pobierz „Instant Client for macOS (ARM64)”, pakiet **Basic** albo **Basic Light**, ze strony
[oracle.com](https://www.oracle.com/database/technologies/instant-client/macos-arm64-downloads.html) i zainstaluj go
według instrukcji Oracle. Pelikan szuka biblioteki `libclntsh.dylib` w tej kolejności:

1. katalog wskazany w **Ustawienia › Oracle › Oracle Instant Client**;
2. `/opt/homebrew/lib`, `/usr/local/lib`, `/usr/local/oracle/instantclient` i katalogi `/opt/oracle/instantclient*`;
3. katalogi `instantclient_*` w Twoich folderach **Pobrane** i **Aplikacje** (najnowsza wersja pierwsza).

Przy przeszukiwaniu folderu Pobrane macOS może zapytać, czy pozwolić Pelikanowi na dostęp do niego — to zwykłe pytanie
systemu o prywatność. Jeśli wolisz go uniknąć, wskaż katalog klienta ręcznie: **Pelikan › Ustawienia…** (⌘,), karta
**Oracle**, przycisk **Wybierz…**. Zmiana katalogu działa po ponownym uruchomieniu Pelikana.

Bez Instant Client możesz łączyć się sterownikiem *Thin* (wybór w definicji połączenia, zobacz rozdział *Połączenia*).
Thin nie obsługuje połączeń TCPS i portfeli Oracle Wallet, uwierzytelniania zewnętrznego, zmiany wygasłego hasła ani
przerywania wykonania (**Przerwij**).

## Pierwsze kroki

1. Kliknij kartę **Połączenia** w lewej kolumnie, a potem przycisk **+** (albo wybierz **Sesja › Połączenia › Nowe
   połączenie…**).
2. Wpisz nazwę, użytkownika, hasło i bazę (`host:port/usługa` albo alias z `tnsnames.ora`), wybierz środowisko i
   kliknij **Testuj**, a potem **Zapisz**.
3. Kliknij dwukrotnie połączenie na liście — stanie się **połączeniem głównym** (pogrubione).
4. Otwórz nowe okno SQL (**Plik › Nowy › Okno SQL**, ⌘N), wpisz zapytanie i wykonaj je klawiszem F8 albo ⌘↩.

![Okno główne: lista połączeń po lewej, okno SQL z wynikiem zapytania](../img/okno-glowne.png)

## Okno główne

Pelikan ma jedno okno główne:

- **Lewa kolumna** z kartami: **Połączenia** (lista połączeń z folderami i ostatnio używanymi), **Obiekty**
  (Przeglądarka obiektów), **Okna** (lista otwartych okien), **Szablony** i **Pliki** (przeglądarka plików).
- **Karty dokumentów** w środku — każde okno SQL, programu, testu czy planu ma własną kartę z kolorową literą typu: S
  — okno SQL, P — okno programu, T — okno testu, C — okno poleceń, E — okno planu, R — okno raportu, D — okno
  diagramu, N — notatnik SQL. Środkowy klik na karcie zamyka okno; menu karty zamyka pozostałe okna albo okna z lewej
  i prawej.
- **Pasek narzędzi** z najczęstszymi czynnościami (nowe okno, otwórz, zapisz, wykonaj, przerwij, COMMIT, ROLLBACK,
  logowanie) i grupą **Szybki dostęp**. Układ zmienisz przez **Widok › Dostosuj pasek narzędzi…**.
- **Pasek stanu** okna: połączenie okna (z kolorem środowiska, przypięciem 📌 i oznaczeniem „tylko odczyt”), stan
  transakcji („● transakcja otwarta”), liczba wierszy i czas wykonania, pozycja kursora oraz gałąź Git pliku.
  Kliknięcie nazwy połączenia pozwala zmienić połączenie okna.
- **Panele narzędzi** po prawej i na dole — narzędzia (Sesje, Znajdź obiekty, Zadania To-Do, Historia schowka,
  instrukcja, edytory tabel, eksport i import, raporty i inne) otwierają się domyślnie w panelu po prawej, każde we
  własnej karcie. Kartę przeciągasz do drugiego panelu albo poza panele — wtedy narzędzie dostaje osobne okno
  w miejscu upuszczenia; to samo robi menu karty i przyciski w nagłówku panelu. Okno narzędzia wraca do panelu
  przyciskiem na pasku tytułu. Pelikan zapamiętuje miejsce każdego rodzaju narzędzia. Zwinięty panel z narzędziami
  pokazuje na pasku stanu przycisk z ich liczbą. Polecenia są w **Widok › Panele narzędzi**, a w **Ustawienia ›
  Ogólne › Panele narzędzi** wybierasz miejsce nowych narzędzi (także osobne okna) i autoukrywanie paneli.
  Skróty narzędzia w panelu (Enter, Esc) działają tylko wtedy, gdy kursor jest w tym narzędziu.
- **Panel agenta** po prawej (domyślnie zwinięty) — terminal agenta AI z listą jego działań. Pokazuje go **Widok ›
  Panel agenta** (zobacz rozdział *Agenci AI*).

Tytuł okna pokazuje połączenie główne i aktywny zestaw roboczy (workset), a podtytuł — bieżące okno.

## Wstążka i „Szukaj czynności”

Pod paskiem narzędzi jest **wstążka** — każda czynność jednym kliknięciem, bez szukania w menu i bez pamiętania skrótów.
Karty stałe to **Start** (nowe okna, pliki, wykonanie, COMMIT i ROLLBACK, połączenie, wyszukiwanie), **Edycja**,
**Obiekty**, **Debugowanie i testy**, **Narzędzia**, **Raporty** i **Widok**. Przy oknie programu, wyniku zapytania,
diagramu, raportu, notatnika, planu albo poleceń pojawia się kolorowa **karta kontekstowa** (np. **Program** z
kompilacją, jednostkami, porównaniem ze źródłem w bazie i testami). Wstążka pamięta, którą kartę wybrałeś przy oknie
danego rodzaju — po przełączeniu okna wraca do niej sama.

Częste czynności mają duże przyciski, pozostałe — małe; rzadsze są w listach rozwijanych grup (oznaczonych ▾). Podpowiedź
przycisku pokazuje opis i skrót, więc skrótów uczysz się przy okazji. Prawy klik na przycisku dodaje komendę do paska
szybkiego dostępu. Dwukrotne kliknięcie karty albo strzałka po prawej zwija wstążkę do samych kart; **Widok › Wstążka** ją ukrywa
(także w **Ustawienia › Ogólne › Wstążka**).

Pole **Szukaj czynności…** po prawej stronie kart znajduje każdą komendę — wpisz kilka liter: „plan”, „eksport tabel”,
„zrodlo” (bez polskich znaków) albo angielską nazwę znaną z PL/SQL Developera, np. „beautifier”, „compile invalid”.
Wyniki pokazują, gdzie komenda leży na wstążce, skrót i to, czy jest teraz dostępna; Enter albo kliknięcie ją wykonuje.

## Paleta komend

Każda czynność Pelikana jest komendą: ma pozycję w menu, opcjonalny skrót i opis skutków. **Paleta komend** (**Widok ›
Paleta komend…**, ⇧⌘P) wyszukuje komendy po nazwie i pokazuje, w którym menu są i jaki mają skrót. To najszybszy
sposób, żeby znaleźć funkcję, której położenia w menu nie pamiętasz.

## Profile klawiatury

Pelikan ma dwa profile skrótów: **PL/SQL Developer** (klawisze F, Ctrl — np. F8 wykonuje, F9 rozpoczyna debugowanie) i
**macOS** (skróty z ⌘). W obu profilach działają odpowiedniki z ⌘, np. ⌘↩ wykonuje polecenie. Profil wybierasz w
**Ustawienia › Klawiatura**. Jeśli klawisze F1–F12 sterują jasnością czy głośnością, włącz w Ustawieniach systemowych
opcję używania ich jako standardowych klawiszy funkcyjnych albo naciskaj je z klawiszem fn.

## Aktualizacje

Pelikan raz dziennie sprawdza, czy jest nowe wydanie, i proponuje jego instalację. Możesz też sprawdzić ręcznie:
**Pelikan › Sprawdź uaktualnienia…**. Każde wydanie jest podpisane kluczem autora — aplikacja nie przyjmie pliku z
innego źródła. Ustawienia, połączenia i hasła zostają bez zmian.

## Języki

Interfejs jest dostępny po polsku, angielsku, niemiecku, hiszpańsku i ukraińsku. Język wybierasz w **Ustawienia ›
Ogólne › Język interfejsu**; zmiana działa po ponownym uruchomieniu. Nazwy niektórych okien i narzędzi (np. Explain
Plan, Large Data Editor, Query Builder) pozostają w oryginalnym brzmieniu.

## Gdzie Pelikan trzyma dane

Definicje połączeń (bez haseł), ustawienia, historia, worksety, historia lokalna plików, dziennik agentów i inne dane
aplikacji są w katalogu `~/Library/Application Support/Pelikan`. Hasła są wyłącznie w Pęku kluczy macOS — zobacz
rozdział *Bezpieczeństwo i prywatność*.

## Pomoc

- **Pomoc › Instrukcja Pelikana** (⇧⌘/) otwiera tę instrukcję.
- **F1** w edytorze otwiera dokumentację Oracle dla słowa pod kursorem (kod błędu, pakiet, widok słownika, polecenie
  SQL).
- **Pomoc › Dokumentacja Oracle…** wyszukuje w podręcznikach Oracle wybranej wersji.

## O programie

Pelikan jest projektem otwartym na licencji MIT:
[github.com/andrzejoles/Pelikan](https://github.com/andrzejoles/Pelikan). Autor: Andrzej Oleś w kooperacji z Claude
AI. Licencje użytych bibliotek są w pliku „Licencje zewnętrzne” dołączonym do aplikacji.
