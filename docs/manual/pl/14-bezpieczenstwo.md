# Bezpieczeństwo i prywatność

Ten rozdział zbiera w jednym miejscu, jak Pelikan chroni hasła, dane i bazy — także przed pomyłkami i przed agentami
AI.

## Hasła

- Hasła baz danych, hasła SSH (tunele i cele Pro*C) i hasła kluczy SSH są przechowywane **wyłącznie w Pęku kluczy
  macOS** — w pęku logowania, bez synchronizacji z iCloud, dostępne tylko przy odblokowanym Macu.
- Hasła **nigdy** nie trafiają do plików Pelikana (definicji połączeń, preferencji, worksetów), dzienników,
  historii poleceń, argumentów procesów ani zmiennych środowiska. Polecenia z hasłami (`CONNECT`, `ALTER USER …
  IDENTIFIED BY`, `CREATE DATABASE LINK`) nie są zapisywane w historii poleceń.
- Wyjątek, tylko na Twoje wyraźne polecenie: **Eksportuj połączenia z hasłami…** zapisuje hasła do pliku (zaszyfrowane
  frazą albo jawnym tekstem) po potwierdzeniu Touch ID albo hasłem Maca — zobacz rozdział **Połączenia**, „Eksport
  i import definicji”. Agent AI nie ma tej komendy.
- Hasło niezapamiętane w Pęku kluczy jest trzymane tylko w pamięci do zamknięcia aplikacji.
- Opcja **Wymagaj Touch ID albo hasła Maca przed użyciem zapisanego hasła** (**Preferencje › Oracle › Hasła
  połączeń**) wymaga potwierdzenia raz na połączenie w czasie działania aplikacji — także gdy połączenia używa agent
  AI.
- Hasło SSH trafia do programu `ssh` przez jednorazową kolejkę dostępną tylko dla Twojego konta, a nie przez
  argumenty, środowisko czy plik.
- Hasła z portfela Oracle Wallet nigdy nie trafiają do Pelikana — logowaniem zajmuje się klient Oracle.
- Eksport definicji połączeń, eksport preferencji, definicje zadań, przenoszeń i narzędzi użytkownika, skrypty utPLSQL
  dla CI i parametry startowe nie zawierają haseł.

## Ochrona baz przed pomyłkami

- **Środowisko połączenia** (deweloperskie, testowe, produkcyjne) jest widoczne kolorem w całym interfejsie.
- Na połączeniu **produkcyjnym** polecenia zmieniające dane lub obiekty wymagają potwierdzenia.
- Połączenie **tylko do odczytu** blokuje przed wysłaniem do bazy wszystko poza zapytaniami (także `SELECT … FOR
  UPDATE` i bloki PL/SQL). Parametr startowy `readonly=` pozwala otworzyć wybrane połączenia tylko do odczytu na jedno
  uruchomienie.
- Pelikan nie zatwierdza transakcji sam: AutoCommit jest domyślnie wyłączony, a zamknięcie okna lub aplikacji z
  otwartą transakcją kończy się pytaniem.
- Instalacja utPLSQL z aplikacji działa tylko na połączeniach deweloperskich i testowych.
- Narzędzia generujące skrypty (porównania, koszyk, refaktoryzacja, DDL widoków dualności, ORDS) otwierają je w oknie
  SQL do przejrzenia — nie wykonują ich same.

## Agenci AI

Zasady pracy agentów opisuje rozdział *Agenci AI*. W skrócie:

- agent zna połączenia tylko z nazwy i środowiska — nie widzi haseł, hostów, portów, usług ani nazw użytkowników;
- ma własne sesje bazy i nie widzi Twojej transakcji;
- czyta w transakcjach tylko do odczytu, z limitami;
- zmiany wykonuje tylko po Twojej zgodzie w oknie bez przycisku domyślnego, a DML pozostaje niezatwierdzone do osobnej
  zgody na COMMIT;
- nie ma dostępu do okna poleceń, poleceń systemu, debugera, raportów pakietów Oracle ani zdalnego buildu;
- komunikuje się z Pelikanem tylko przez gniazdo dostępne dla Twojego konta, z jednorazowym tokenem sesji;
- dane, które agent przeczyta, trafiają do dostawcy modelu AI — dla danych wrażliwych używaj osobnego użytkownika bazy
  agenta z ograniczonymi uprawnieniami i maskowania kolumn.

## Co wychodzi z Twojego Maca

Pelikan nie ma telemetrii ani analityki. Połączenia sieciowe nawiązuje tylko:

- z bazami danych i serwerami SSH, które skonfigurujesz;
- z GitHubem — raz dziennie, żeby sprawdzić aktualizacje (i pobrać je, gdy się zgodzisz), oraz przy instalacji utPLSQL
  z aplikacji (pobranie oficjalnego wydania);
- w przeglądarce, gdy sam otworzysz dokumentację Oracle (F1), wyszukiwanie w sieci albo dokument z adresem http(s).

Programy agentów AI (Claude Code, Codex, Grok, Antigravity) są niezależnymi aplikacjami dostawców i łączą się z ich
serwerami — wysyłają tam to, co agent przeczyta w Pelikanie.

## Dane na dysku

Dane Pelikana są w katalogu `~/Library/Application Support/Pelikan`: definicje połączeń (bez haseł), preferencje,
historia poleceń, worksety i migawki do odzyskania okien (mogą zawierać tekst niezapisanych okien), historia lokalna
plików, raporty, koszyki, dziennik agentów. Pliki z treścią okien i dziennika są zapisywane z prawami dostępu tylko
dla Twojego konta. Jeśli Twój Mac jest współdzielony, pamiętaj, że osoba z dostępem do Twojego konta macOS ma dostęp
także do tych danych — chroni je hasło logowania do Maca i szyfrowanie dysku FileVault.

## Przed czym Pelikan nie chroni

- Złośliwe oprogramowanie działające na Twoim koncie macOS może czytać pamięć i pliki Twoich programów — to zadanie
  systemu (Gatekeeper, XProtect).
- Program agenta uruchomiony bez trybu ścisłego ma uprawnienia Twojego konta.
- Zmian zatwierdzonych (COMMIT) i DDL na tabelach nie da się cofnąć — Pelikan mówi o tym wprost przed wykonaniem.
- Funkcje wywoływane w zapytaniach mogą mieć skutki uboczne (np. transakcje autonomiczne) — ogranicza je tylko model
  uprawnień bazy.
