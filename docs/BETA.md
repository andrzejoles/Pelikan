# Pelikan — wydanie beta

Trzecia beta do testów na prawdziwych bazach (poprzednie: 7.9.0, 8.4.0). Wszystkie etapy planu (0–8 i Pro\*C) są zrobione, macierz funkcji
ma ponad 400 pozycji potwierdzonych testami albo zrzutami ekranu, a Pelikan przeszedł próbę tylko do odczytu na dużej
bazie produkcyjnej (Oracle 19c, dziesiątki tysięcy obiektów, setki tysięcy linii PL/SQL). To nadal beta: zachowania
mogą się zmieniać, a nieznane błędy — zdarzać.

## Co nowego od 8.4.0

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
