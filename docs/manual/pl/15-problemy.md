# Rozwiązywanie problemów i ograniczenia

## Najczęstsze problemy

### macOS nie pozwala uruchomić Pelikana

Pelikan nie jest notaryzowany przez Apple. Przy pierwszym uruchomieniu otwórz **Ustawienia systemowe › Prywatność i
ochrona** i kliknij **Otwórz mimo to** (zobacz rozdział *Wprowadzenie*).

### „Nie znaleziono Oracle Instant Client”

- Pobierz Instant Client dla macOS w wersji **ARM64** (Basic albo Basic Light) i rozpakuj go albo zainstaluj według
  instrukcji Oracle.
- Wskaż katalog z plikiem `libclntsh.dylib` w **Preferencje › Oracle › Oracle Instant Client** i uruchom Pelikana
  ponownie.
- Jeśli klient jest w folderze Pobrane, a macOS zapytał o dostęp Pelikana do tego folderu i odmówiłeś, zmień to w
  **Ustawienia systemowe › Prywatność i ochrona › Pliki i foldery** albo przenieś klienta w inne miejsce.
- Tymczasowo możesz przełączyć połączenie na sterownik *Thin* (karta **Ogólne** definicji połączenia).

### Nie mogę się połączyć

- Kliknij **Testuj** w definicji połączenia — komunikat bazy albo klienta Oracle wskaże przyczynę.
- **ORA-12154 / TNS:** alias nie został znaleziony — sprawdź katalog konfiguracji (karta **Zaawansowane** albo
  **Preferencje › Oracle › Oracle Net i Oracle Wallet**) albo użyj adresu `host:port/usługa`.
- **ORA-01017:** błędne hasło — Pelikan zapyta o nie ponownie; zaznacz zapamiętanie, żeby zastąpić hasło w Pęku
  kluczy.
- **ORA-28001:** hasło wygasło — Pelikan pokaże okno zmiany hasła.
- **Oracle Wallet:** pole **Baza** musi być dokładnie aliasem zapisanym w portfelu, a portfel musi mieć plik
  `cwallet.sso` (automatyczne logowanie). Stan portfela widać w **Preferencje › Oracle**. Zmiany w tej sekcji działają
  po ponownym uruchomieniu.
- **Tunel SSH:** Pelikan używa systemowego `ssh` — sprawdź w Terminalu, czy `ssh użytkownik@bastion.example.com`
  działa (klucz w agencie SSH, znany host). Adres bazy podaj tak, jak widzi go serwer SSH.
- **Touch ID:** jeśli włączyłeś potwierdzanie zapisanych haseł i anulujesz okno systemowe, połączenie nie zostanie
  nawiązane.

### Skrót klawiszowy nie działa

- F-klawisze: włącz w Ustawieniach systemowych używanie ich jako standardowych klawiszy funkcyjnych albo naciskaj je z
  klawiszem fn.
- ⌃F8, ⌃F2, ⌃F3 i inne skróty z ⌃ mogą być zajęte przez macOS (**Ustawienia systemowe › Klawiatura › Skróty
  klawiszowe**). Użyj odpowiednika z ⌘ (np. ⇧⌘↩ zamiast ⌃F8) albo wyłącz skrót systemowy.
- ⌃Spacja domyślnie przełącza źródło wprowadzania w macOS — podpowiedź kodu wywołasz przez ⌥⎋.
- Sprawdź skrót komendy w palecie komend (⇧⌘P) albo w **Preferencje › Klawiatura**.

### Zapytanie trwa zbyt długo

**Przerwij** (⌘.) przerywa wykonanie i pobieranie. Jeśli baza nie reaguje (np. podczas `DBMS_SESSION.SLEEP` albo na
sterowniku Thin, który nie obsługuje przerwania), użyj **Sesja › Zakończ sesję okna (Kill)** — wymaga uprawnienia
ALTER SYSTEM.

### Nie mogę edytować wyniku w siatce

Zapytanie musi zwracać kolumnę `ROWID` (np. `select t.*, t.rowid from tabela t`). Najprościej użyć **Edytuj dane** z
menu tabeli w Przeglądarce obiektów. Połączenie tylko do odczytu blokuje zapis.

### Debuger się nie zatrzymuje

- Sprawdź uprawnienia `DEBUG CONNECT SESSION` i `DEBUG ANY PROCEDURE` (albo `DEBUG` na obiekcie) — **Debugowanie ›
  Uprawnienia debugera…** przygotuje polecenia dla administratora.
- Skompiluj obiekt z informacją debugowania (**Narzędzia › Obiekt › Dodaj informację debugowania**).
- Punkt przerwania z pustym znacznikiem nie został przyjęty przez bazę (np. linia bez kodu wykonywalnego).

### Raport AWR / SQL Monitor nie działa

Sprawdź deklarację licencji w definicji połączenia (karta **Zaawansowane**) i parametr bazy
`CONTROL_MANAGEMENT_PACK_ACCESS`. Funkcje Tuning Pack wymagają wartości `DIAGNOSTIC+TUNING`.

### Agent nie startuje

- Pelikan szuka programu agenta w `PATH` Twojej powłoki logowania — sprawdź w Terminalu, czy polecenie (np. `claude`)
  działa.
- Agent nie widzi połączenia: sprawdź kartę **Agent AI** w definicji połączenia.
- Agent nie może niczego zmienić: połączenie jest tylko do odczytu, produkcyjne bez zgody na zmiany albo obniżyłeś
  poziom narzędzia w macierzy uprawnień sesji.

### Pelikan zamknął się nieoczekiwanie

Przy następnym uruchomieniu Pelikan zaproponuje odzyskanie niezapisanych okien (także później: **Plik › Odzyskaj
okna…**), jeśli w **Preferencje › Narzędzia** jest włączone zachowywanie niezapisanych okien. Zmiany plików znajdziesz
też w historii lokalnej (**Plik › Historia lokalna**).

## Znane ograniczenia

Poniższe funkcje działają inaczej niż we wzorcu, są niepełne albo nie zostały sprawdzone w prawdziwym środowisku:

- **Sterownik Thin** nie obsługuje TCPS i portfeli, uwierzytelniania zewnętrznego, zmiany wygasłego hasła ani
  przerywania wykonania.
- **Uwierzytelnianie Kerberos**, **LDAP** (katalog nazw), **Workspace Manager (DBMS_WM)**, **Microsoft Entra ID** i
  **połączenia TCPS** są zaimplementowane według dokumentacji Oracle, ale nie zostały sprawdzone na prawdziwym
  serwerze KDC, LDAP, bazie z DBMS_WM, Azure ani listenerze TCPS.
- **ORDS**: lista modułów REST nie była sprawdzana na działającym ORDS; skrypty włączające REST trafiają do okna SQL
  do przejrzenia.
- **Debuger**: brak debugowania przez DBMS_DEBUG_JDWP; w wyzwalaczach nie są dostępne wartości `:new` i `:old`; w
  jednej linii może być tylko jeden punkt przerwania.
- **Siatka** nie potrafi zablokować przewijania (zamrozić) kolumn ani wierszy.
- **Okno poleceń**: polecenia `COPY` i `SET ENVVAR` nie są obsługiwane.
- **Monitor zdarzeń** nie odczytuje DBMS_OUTPUT innych sesji (Oracle tego nie udostępnia).
- **Narzędzia w lewej kolumnie** są kartami jednego panelu (Połączenia, Obiekty, Okna, Szablony, Pliki); nie można ich
  dowolnie dokować ani automatycznie ukrywać. Zadania To-Do, projekt, historia schowka i inne narzędzia otwierają się
  w osobnych oknach. Dokumenty są kartami jednego okna głównego, a nie natywnymi kartami macOS.
- **Sesja › Zmień hasło…** i **Widok › Przeglądarka obiektów** są w menu wyszarzone (zapowiedziane). Hasło w bazie
  zmienisz poleceniem `ALTER USER … IDENTIFIED BY` w oknie SQL (nie trafi ono do historii) albo w oknie zmiany hasła
  po jego wygaśnięciu; Przeglądarkę obiektów pokazuje karta **Obiekty**.
- **Quick Look** dla plików SQL (podgląd w Finderze) może nie działać — rozszerzenie podpisane certyfikatem własnym
  macOS może odrzucić.
- **Zdalny build Pro*C** był testowany na lokalnym serwerze SSH z powłoką ksh93; parsery komunikatów `proc` i `xlc`
  powstały na podstawie dokumentacji. Działanie na AIX 6.1 (ksh88) czeka na potwierdzenie na prawdziwym serwerze.
- **Pominięte** w tej wersji: importer ODBC (zastępują go importery tekstu i Excela oraz kreator importu), APEXlang,
  Liquibase (`lb` z SQLcl).
- **VoiceOver**: elementy interfejsu mają etykiety dostępności, ale aplikacja nie była jeszcze sprawdzana z
  VoiceOverem.

## Zgłaszanie błędów

Błędy i propozycje zgłaszaj na stronie projektu:
[github.com/andrzejoles/Pelikan/issues](https://github.com/andrzejoles/Pelikan/issues). Nie dołączaj haseł, nazw
serwerów ani danych z baz produkcyjnych — wystarczy opis kroków i komunikat błędu.

## Słownik

Polskie nazwy okien i pojęć w Pelikanie oraz ich odpowiedniki w PL/SQL Developer (np. *Okno SQL* — SQL Window,
*Przeglądarka obiektów* — Object Browser, *Zatwierdź zmiany (Post)* — Post changes) zawiera słownik terminów:
[docs/GLOSSARY.md](https://github.com/andrzejoles/Pelikan/blob/main/docs/GLOSSARY.md).
