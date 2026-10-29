# Rozwiązywanie problemów i ograniczenia

## Najczęstsze problemy

### macOS nie pozwala uruchomić Pelikana

Pelikan nie jest notaryzowany przez Apple. Przy pierwszym uruchomieniu otwórz **Ustawienia systemowe › Prywatność i
ochrona** i kliknij **Otwórz mimo to** (zobacz rozdział *Wprowadzenie*).

### „Brak Oracle Instant Client”

- Pobierz Instant Client dla macOS w wersji **ARM64** (Basic albo Basic Light) i rozpakuj go albo zainstaluj według
  instrukcji Oracle.
- Wskaż katalog z plikiem `libclntsh.dylib` w **Ustawienia › Oracle › Oracle Instant Client** i uruchom Pelikana
  ponownie.
- Jeśli klient jest w folderze Pobrane, a macOS zapytał o dostęp Pelikana do tego folderu i odmówiłeś, zmień to w
  **Ustawienia systemowe › Prywatność i ochrona › Pliki i foldery** albo przenieś klienta w inne miejsce.
- Tymczasowo możesz przełączyć połączenie na sterownik *Thin* (karta **Ogólne** definicji połączenia).

### Nie mogę się połączyć

- Kliknij **Testuj** w definicji połączenia — komunikat bazy albo klienta Oracle wskaże przyczynę.
- **ORA-12154 / TNS:** alias nie został znaleziony — sprawdź katalog konfiguracji (karta **Zaawansowane** albo
  **Ustawienia › Oracle › Oracle Net i Oracle Wallet**) albo użyj adresu `host:port/usługa`.
- **ORA-01017:** błędne hasło — Pelikan zapyta o nie ponownie; zaznacz zapamiętanie, żeby zastąpić hasło w Pęku
  kluczy.
- **ORA-28001:** hasło wygasło — Pelikan pokaże okno zmiany hasła.
- **Oracle Wallet:** pole **Baza** musi być dokładnie aliasem zapisanym w portfelu, a portfel musi mieć plik
  `cwallet.sso` (automatyczne logowanie). Stan portfela widać w **Ustawienia › Oracle**. Zmiany w tej sekcji działają
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
- Sprawdź skrót komendy w palecie komend (⇧⌘P) albo w **Ustawienia › Klawiatura**.

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

Błąd ORA-00904 „DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_HTML: invalid identifier” oznacza brak uprawnienia EXECUTE do pakietu
`SYS.DBMS_WORKLOAD_REPOSITORY` (raport ADDM — także `SYS.DBMS_ADDM`): Oracle odpowiada wtedy w SQL „invalid identifier”,
a nie brakiem uprawnień. Uprawnienie daje zwykle rola DBA; potrzebna jest też licencja Oracle Diagnostics Pack.
Pelikan sprawdza uprawnienie przed raportem AWR, ASH i ADDM i podaje polecenie GRANT do wykonania przez administratora
bazy, np. `GRANT EXECUTE ON SYS.DBMS_WORKLOAD_REPOSITORY TO SCOTT;`.

### Agent nie startuje

- Pelikan szuka programu agenta w `PATH` Twojej powłoki logowania — sprawdź w Terminalu, czy polecenie (np. `claude`)
  działa.
- Agent nie widzi połączenia: sprawdź kartę **Agent AI** w definicji połączenia.
- Agent nie może niczego zmienić: połączenie jest tylko do odczytu, produkcyjne bez zgody na zmiany albo obniżyłeś
  poziom narzędzia w macierzy uprawnień sesji.

### Pelikan zamknął się nieoczekiwanie

Przy następnym uruchomieniu Pelikan zaproponuje odzyskanie niezapisanych okien (także później: **Plik › Odzyskaj
okna…**), jeśli w **Ustawienia › Narzędzia** jest włączone zachowywanie niezapisanych okien. Zmiany plików znajdziesz
też w historii lokalnej (**Plik › Historia lokalna**).

### Dziennik aplikacji

Pelikan zapisuje dziennik zdarzeń: start, połączenia i ich błędy (kod ORA-), zakończenie poleceń (rodzaj, czas, liczba
wierszy), zadania w tle, debuger, testy, tunele SSH, agentów AI i aktualizacje. **Pomoc › Dziennik aplikacji**
otwiera go w Konsoli macOS; plik leży w `~/Library/Logs/Pelikan`, a te same wpisy trafiają do dziennika systemowego
(podsystem Pelikana w Konsoli). Pliki mają najwyżej 2 MB, Pelikan trzyma pięć ostatnich.

Dziennik nigdy nie zawiera haseł, treści poleceń SQL ani danych z bazy. Nazwy połączeń, serwerów, obiektów i ścieżki
plików są domyślnie ukryte albo zastąpione skrótem (te same nazwy mają ten sam skrót). W **Ustawienia › Ogólne ›
Dziennik aplikacji** wybierzesz zakres wpisów (*Ostrzeżenia i błędy*, *Zdarzenia*, *Szczegóły — diagnostyka*) i
możesz włączyć jawne nazwy — przydaje się, gdy szukasz przyczyny problemu na własnym komputerze.

## Znane ograniczenia

Poniższe funkcje działają inaczej niż we wzorcu, są niepełne albo nie zostały sprawdzone w prawdziwym środowisku:

- **Sterownik Thin** nie obsługuje TCPS i portfeli, uwierzytelniania zewnętrznego, zmiany wygasłego hasła ani
  przerywania wykonania. CLOB i DBMS_OUTPUT czyta do 65 535 znaków (dłuższe z oznaczeniem obcięcia), a zapytanie
  z kolumną INTERVAL YEAR TO MONTH albo BFILE kończy aplikację (błąd biblioteki OracleNIO) — do takich danych używaj
  sterownika Instant Client.
- **Kerberos** na macOS: gdy `sqlnet.ora` włącza KERBEROS5, połączenie kończy się czytelnym błędem (adapter
  Instant Client koliduje z systemowym Kerberosem w aplikacji); na Linuksie logowanie biletem działa. **Microsoft
  Entra ID** i **połączenia TCPS** są zaimplementowane według dokumentacji Oracle, ale nie były sprawdzone na Azure ani
  listenerze TCPS. **LDAP** (katalog nazw): Pelikan rozwiązuje alias sam, przez LDAPv3 bez logowania — bez LDAPS
  i wiązania portfelem.
- **Debuger**: brak debugowania przez DBMS_DEBUG_JDWP; w wyzwalaczach nie są dostępne wartości `:new` i `:old`; w
  jednej linii może być tylko jeden punkt przerwania.
- **Siatka** nie potrafi zablokować przewijania (zamrozić) kolumn ani wierszy.
- **Konsola SQL*Plus**: polecenia `COPY` i `SET ENVVAR` nie są obsługiwane.
- **Monitor zdarzeń** nie odczytuje DBMS_OUTPUT innych sesji (Oracle tego nie udostępnia).
- **Narzędzia w lewej kolumnie** są kartami jednego panelu (Połączenia, Obiekty, Okna, Szablony, Pliki); nie można ich
  dowolnie dokować ani automatycznie ukrywać. Dokumenty są kartami jednego okna głównego, a nie natywnymi kartami macOS.
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

Najprościej zgłosisz problem z aplikacji: **Pomoc › Zgłoś problem…** (także na wstążce: **Widok › Pomoc**), przycisk
**Zgłoś problem…** w komunikacie błędu albo pytanie po nieoczekiwanym zamknięciu Pelikana (z opisem awarii z raportu
macOS: wyjątek i stos — bez ścieżek). W oknie zgłoszenia wpisz tytuł i opis, wybierz, czy dołączyć opis środowiska i
ostatnie wpisy dziennika, i sprawdź podgląd. **Otwórz zgłoszenie na GitHubie** otwiera stronę nowego zgłoszenia z
wypełnioną treścią (kopia jest w schowku) — wysyłasz je ze swojego konta GitHub, Pelikan niczego nie wysyła sam.
Zgłoszenia są publiczne: treść przechodzi przez filtr haseł i ścieżki domowej, a dziennik domyślnie ukrywa nazwy.

Do zgłoszenia dołącz dziennik: **Pomoc › Eksportuj dziennik…** zapisuje go z opisem środowiska (wersja, system,
sterowniki) do pliku tekstowego. Przed wysłaniem przejrzyj plik, zwłaszcza gdy włączone były jawne nazwy.

## Słownik

Polskie nazwy okien i pojęć w Pelikanie oraz ich odpowiedniki w PL/SQL Developer (np. *Okno SQL* — SQL Window,
*Przeglądarka obiektów* — Object Browser, *Zapisz zmiany w bazie (Post)* — Post changes) zawiera słownik terminów:
[docs/GLOSSARY.md](https://github.com/andrzejoles/Pelikan/blob/main/docs/GLOSSARY.md).
