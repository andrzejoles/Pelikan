# Pelikan — wydanie beta

Szósta beta do testów na prawdziwych bazach (poprzednie: 7.9.0, 8.4.0, 8.7.0, 9.0.0, 9.2.0). Wszystkie etapy planu (0–8 i Pro\*C) są zrobione, macierz funkcji
ma ponad 400 pozycji potwierdzonych testami albo zrzutami ekranu, a Pelikan przeszedł próbę tylko do odczytu na dużej
bazie produkcyjnej (Oracle 19c, dziesiątki tysięcy obiektów, setki tysięcy linii PL/SQL). To nadal beta: zachowania
mogą się zmieniać, a nieznane błędy — zdarzać.

## Co nowego od 9.2.0

- **Wstążka** pod paskiem narzędzi: karty Start, Edycja, Obiekty, Debugowanie i testy, Narzędzia, Raporty, Widok i karty
  kontekstowe aktywnego okna (Program, Wynik, Diagram, Raport, Notatnik, Plan, Okno poleceń). Każda komenda z menu jest
  na wstążce; pole **Szukaj czynności…** znajduje komendy bez polskich znaków i po angielskich nazwach z PL/SQL
  Developera (D171).
- **Formater**: 20 nowych opcji — wyrównanie deklaracji, parametrów, `=>`, `:=`, aliasów, UPDATE … SET i komentarzy;
  klauzule do lewej, do prawej albo w osobnej linii; AND/OR, JOIN … ON, THEN, CASE; odstępy; wielkość liter typów,
  funkcji i pakietów. W Preferencjach przykład każdej opcji („Teraz” / „Po zmianie”) i podświetlenie zmienionych linii
  podglądu (D174).
- **Dziennik aplikacji** (`~/Library/Logs/Pelikan`) bez haseł, treści SQL i danych; poziom i nazwy w Preferencjach ›
  Ogólne, eksport do zgłoszenia (D170).
- **Zgłaszanie problemów** na GitHubie: przycisk w komunikatach błędów, pytanie po nieoczekiwanym zamknięciu, Pomoc ›
  Zgłoś problem… — z podglądem treści; wysyłasz ze swojego konta (D173).
- **Logo** — własna ikona aplikacji (D172).

## Co nowego w 9.2.0

- **Drugie przejście przeglądu kodu** (ok. 60 poprawek, D169), m.in.: formater nie zmienia już znaczenia kodu
  (wielolinijkowe teksty, dzielenie `/`, polecenia SET/PROMPT, kod MLE i Java) i odmawia, gdy wynik nie zgadza się
  z oryginałem; Test Manager uruchamia testy we własnej sesji i nie wycofuje zmian innych okien; debuger po błędzie
  wyłącza tryb debugowania i przywraca poziom optymalizacji kompilacji; refaktoryzacje odmawiają, gdy zmieniłyby
  znaczenie kodu; przenoszenie danych w trybie TRUNCATE sprawdza rozmiar LOB-ów przed jakąkolwiek zmianą; dziennik
  agenta maskuje tylko samo hasło.
- Wersje zależności przypięte w projekcie aplikacji — budowanie nie zmienia plików w repozytorium.

## Co nowego w 9.0.0

- **Przegląd całego kodu** (ok. 130 poprawek, D168), m.in.: agent AI kompiluje dokładnie to, na co użytkownik wyraził zgodę;
  sterownik thin nie zatwierdza po cichu transakcji przy rozłączeniu; CONNECT/DISCONNECT w Oknie poleceń pytają
  o COMMIT/ROLLBACK; porównanie i przenoszenie danych przenoszą duże BLOB-y zamiast zapisywać NULL; edytor tabeli
  zachowuje klucze obce do innych schematów i kolumny identity przy odtwarzaniu tabeli; import CSV z końcami linii
  Windows; okno raportu bez JavaScriptu.
- Aktualne zależności (Sparkle 2.10.1, SwiftTerm 1.99.1, swift-crypto 5) i kompilacja bez ostrzeżeń.

## Co nowego w 8.7.0

- **Diagram ER** z dużego schematu (tysiące tabel) buduje się w kilka sekund zamiast półtorej minuty.
- **Znajdź obiekty w bazie** z przeszukiwaniem definicji tabel (kolumny, komentarze, warunki CHECK): około trzy razy
  szybciej na dużej bazie.

## Co nowego w 8.4.0 (względem 7.9.0)

- **Bezpieczeństwo** (przegląd całej aplikacji): agent AI jest przypięty do połączenia z okna zgody i nie zatwierdzi
  cudzej transakcji poleceniem PL/SQL; linki do Pelikana przyjmują tylko znane parametry; nieznany klucz serwera SSH
  wymaga potwierdzenia odcisku; błędy połączeń widziane przez agenta nie zawierają szczegółów serwera.
- **Narzędzia na dużych bazach**: Znajdź obiekty w bazie, diagram ER, eksport DDL i dokumentacja schematu pytają
  słownik zbiorczo — na bazie z dziesiątkami tysięcy obiektów działają w sekundach zamiast minut.
- Menu Usługi macOS w języku interfejsu; pliki wykonywalne bez ścieżek z komputera, na którym je zbudowano.

## Zanim zaczniesz

- **Testuj najpierw na kopii albo bazie testowej.** Na produkcji ustaw środowisko połączenia „Produkcja” — okna dostają
  kolor ostrzegawczy, a agent AI ma na takim połączeniu tylko odczyt.
- Domyślnie przy zamykaniu okna albo rozłączaniu z otwartą transakcją Pelikan pyta o COMMIT/ROLLBACK (Preferencje ›
  Ogólne › Wylogowanie z otwartą transakcją).
- Hasła trafiają wyłącznie do Pęku kluczy. Dane aplikacji (połączenia bez haseł, ustawienia, historia) leżą w
  `~/Library/Application Support/Pelikan` — kopia tego katalogu wystarczy do przeniesienia konfiguracji.

## Co sprawdzić w pierwszej kolejności

1. Połączenia, których używasz na co dzień (TNS, wallet, SSH) i przełączanie się między nimi.
2. Okno SQL na dużych wynikach: pobieranie, edycja, eksport.
3. Otwieranie, edycja i kompilacja pakietów — także z innych schematów (nagłówek zawiera właściciela).
4. Podkreślenia analizy kodu w edytorze: czy zgłaszają tylko prawdziwe problemy.
5. Debuger i utPLSQL na Twoich pakietach.
6. Jeśli używasz agentów AI: okno zgody, dziennik agenta, cofanie zmian agenta.

## Znane ograniczenia

- Aplikacja nie jest notaryzowana (podpis własnym certyfikatem) — przy pierwszym uruchomieniu „Otwórz mimo to”.
- Karty okien są własne, w jednym oknie (nie natywne karty macOS); narzędzia nie dokują się swobodnie jak w Windows —
  są kartami lewej kolumny i osobnymi oknami.
- Bez próby na prawdziwym środowisku: logowanie Entra ID (Azure), Quick Look dla plików SQL (wymaga notaryzacji).
- Kerberos (sqlnet.ora z KERBEROS5) na macOS: adapter Instant Client koliduje z systemowym Kerberos w aplikacji —
  Pelikan zgłasza błąd zamiast łączyć; na Linuksie działa. Logowanie hasłem, walletem i przez SSH bez zmian.
- Wydajność sprawdzona na łączu z opóźnieniem ~50 ms; przy wolniejszym łączu duże eksporty i metadane trwają dłużej.

## Zgłaszanie błędów

[GitHub Issues](https://github.com/andrzejoles/Pelikan/issues): co robiłeś, czego się spodziewałeś, co się stało,
wersja Pelikana (Pelikan › O programie Pelikan) i wersja bazy. **Nie wklejaj haseł, nazw serwerów ani danych z bazy.**
Dziennik agenta i diagnostyka połączenia nie zawierają haseł, ale przejrzyj je przed wysłaniem.

Autor: Andrzej Oleś w kooperacji z Claude AI · licencja MIT
