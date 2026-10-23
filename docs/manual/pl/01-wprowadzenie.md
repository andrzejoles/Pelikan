# Wprowadzenie

Pelikan to natywne środowisko macOS do pracy z bazą Oracle: pisania i uruchamiania SQL, tworzenia i testowania kodu
PL/SQL, przeglądania obiektów bazy, debugowania, testów utPLSQL i narzędzi administracyjnych. Układ i skróty są zgodne
z PL/SQL Developer, więc użytkownicy tego programu odnajdą znajome okna: **SQL Window**, **Command Window**,
**Program Window**, **Test Window** i **Object Browser**.

## Pierwsze kroki

1. Zainstaluj Oracle Instant Client (Basic albo Basic Light) i wskaż jego katalog w **Preferencje › Oracle**. Pelikan
   wykrywa też najnowszy katalog `instantclient_*` w Pobranych. Bez Instant Client działa sterownik *Thin* z mniejszą
   liczbą funkcji.
2. Dodaj definicję połączenia: **Sesja › Połączenia › Nowe połączenie…** albo przycisk w liście połączeń.
3. Połącz się i otwórz **SQL Window** (⌘N). Wpisz zapytanie i wykonaj je (F8 albo ⌘↩).

## Okno główne

Po lewej znajduje się panel z kartami: Object Browser, przeglądarka plików, lista okien, szablony, To-Do i projekt.
W środku są karty dokumentów — każde okno SQL, programu czy testu ma własną kartę. Na pasku stanu widać połączenie
okna, stan transakcji, pozycję kursora, kodowanie pliku i gałąź Git.

Każdą czynność można wywołać z menu, skrótem albo z **palety komend** (⇧⌘P), która wyszukuje komendy po nazwie.

## Języki

Interfejs jest dostępny po polsku, angielsku, niemiecku, hiszpańsku i ukraińsku. Język wybierasz w
**Preferencje › Ogólne › Język interfejsu**; zmiana działa po ponownym uruchomieniu.
