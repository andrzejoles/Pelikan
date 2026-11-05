# Połączenia

## Do czego to służy

**Połączenie** to zapisana definicja: dokąd się łączyć (adres bazy), jako kto (użytkownik) i z jakimi zasadami
bezpieczeństwa (środowisko, tylko do odczytu, dostęp agentów AI). Dzięki definicjom nie wpisujesz adresu i nazwy
użytkownika za każdym razem, a Pelikan wie, które bazy są produkcyjne i wymagają ostrożności. Definicje są zapisane
**bez haseł** — hasła trafiają wyłącznie do Pęku kluczy macOS.

Typowy programista ma kilka połączeń: swoją bazę deweloperską, bazę testową zespołu i — czasem — dostęp do odczytu
produkcji. Ten rozdział pokazuje, jak je założyć, uporządkować i jak Pelikan chroni Cię przed pomyłką „to nie ta baza”.

## Lista połączeń

Karta **Połączenia** w lewej kolumnie pokazuje definicje w folderach, a w folderze **Ostatnie** — ostatnio używane.
Pod połączeniem widać jego otwarte okna.

- Dwukrotne kliknięcie połączenia łączy je jako **połączenie główne** (pogrubione na liście). Nowe okna otwierają się na
  połączeniu głównym.
- Menu kontekstowe połączenia (prawy klik): **Połącz jako główne**, **Połącz** (bez zmiany głównego), **Rozłącz**,
  **Nowe okno** (okno SQL, programu, testu albo poleceń na tym połączeniu), **Pokaż okna połączenia**, **Zamknij okna
  połączenia**, **Połącz ponownie okna połączenia**, **Ustaw bieżący schemat…**, **Edytuj…**, **Kopiuj pod inną
  nazwą…** (kopia w tym samym folderze, z zapisanymi hasłami), **Przenieś do folderu** i **Usuń…**.
- Foldery i połączenia są ułożone alfabetycznie. Połączenie przeciągnięte myszą na folder trafia do niego, a na wolne
  miejsce listy — na poziom główny.
- Przyciski nad listą tworzą nowe połączenie (**+**) i folder oraz odświeżają listę.
- **Usuń folder** (menu podręczne folderu, klawisz Delete na zaznaczonym folderze albo **Start › Połączenia › Usuń
  folder** z wyborem spośród pustych folderów) usuwa tylko pusty folder — bez połączeń i podfolderów, więc bez pytania.
  Przy niepustym folderze komunikat (i podpowiedź pozycji menu) podaje, ile połączeń i podfolderów trzeba najpierw
  przenieść albo usunąć. Folder z regułą dopasowania (z importu definicji) usuniesz po potwierdzeniu — połączenia
  pasujące do reguły wracają na poziom główny. Folderu **Ostatnie** nie da się usunąć. Delete na połączeniu to
  **Usuń…** z pytaniem. W skryptach folder wskazuje identyfikator albo ścieżka („Zespół / Archiwum”); nazwa
  wystarczy, gdy jest jednoznaczna.

Możesz też użyć okna logowania: **Sesja › Zaloguj…** (⇧⌘L). Pokazuje ono wszystkie definicje z wyszukiwarką i pozwala
utworzyć nowe połączenie albo edytować istniejące. **Sesja › Wyloguj połączenie główne** kończy sesje połączenia
głównego.

> **Ćwiczenie: uporządkuj połączenia w folderach.**
> 1. Na liście połączeń kliknij przycisk nowego folderu i nazwij go `Deweloperskie`.
>    *Wynik:* na liście pojawia się pusty folder.
> 2. Przeciągnij myszą połączenie `dev_moja_baza` (z rozdziału 1) na folder.
>    *Wynik:* połączenie jest w folderze; folder **Ostatnie** nadal pokazuje je wśród ostatnio używanych.
> 3. Prawym klikiem na połączeniu wybierz **Nowe okno › Okno SQL**.
>    *Wynik:* otwiera się okno SQL na tym połączeniu, a pod połączeniem na liście widać to okno.

## Nowe połączenie

Wybierz **Sesja › Połączenia › Nowe połączenie…** albo kliknij **+** na liście połączeń. Okno definicji ma cztery
karty. Najczęściej wystarczy karta **Ogólne**; pozostałe przydają się w szczególnych sytuacjach.

### Karta Ogólne

- **Nazwa** — nazwa na liście (pusta oznacza `użytkownik@baza`). Dobra nazwa mówi, co to za baza i jakie ma
  znaczenie, np. `dev_hr`, `test_hr`, `prod_hr_odczyt`. Dla lokalnych baz testowych dobrze sprawdza się przedrostek
  `dev_`.
- **Folder** i **Środowisko**: *Deweloperskie*, *Testowe*, *Produkcyjne* albo *Inne*. Środowisko decyduje o kolorze
  wskaźnika (testowe — pomarańczowy, produkcyjne — czerwony), o potwierdzaniu zmian i o tym, co wolno agentowi AI.
  **Własny kolor wskaźnika** zastępuje kolor środowiska. ⚠️ Zawsze ustawiaj środowisko zgodnie z prawdą — od niego
  zależą ostrzeżenia przed zmianami na produkcji.
- **Użytkownik**, **Hasło** i **Zapamiętaj hasło w Pęku kluczy**. Bez zapamiętania Pelikan pyta o hasło przy pierwszym
  połączeniu i trzyma je tylko w pamięci do zamknięcia aplikacji. Gdy zapisane hasło przestanie pasować (ORA-01017),
  Pelikan zapyta o nie ponownie.
- **Baza** — gdzie jest baza. Możliwe postacie:
  - adres EZConnect `host:port/usługa` (np. `db.example.com:1521/FREEPDB1`) — najprostszy; port to zwykle 1521;
  - alias z `tnsnames.ora` (np. `DEV`) — przycisk **TNS** obok pola podpowiada aliasy z konfiguracji;
  - pełny deskryptor `(DESCRIPTION=…)` albo adres `tcps://…` dla połączeń szyfrowanych.
- **Połącz jako**: *Normal* (zwykły użytkownik — prawie zawsze ten wybór), SYSDBA, SYSOPER, SYSBACKUP, SYSDG, SYSKM
  albo SYSASM (uprawnienia administracyjne).
- **Uwierzytelnianie**: *Hasło*, *Oracle Wallet (magazyn haseł)*, *Zewnętrzne (Kerberos, system)*, *Microsoft Entra ID
  (przeglądarka)* albo *Token OAuth2 z pliku* (opisane niżej).
- **Sterownik**: *Instant Client (zalecany)* albo *Thin (bez Instant Client)*. Thin nie obsługuje TCPS i portfeli,
  uwierzytelniania zewnętrznego, zmiany wygasłego hasła ani przerywania wykonania.

Kliknij **Testuj**, żeby sprawdzić połączenie, a potem **Zapisz**.

### Karta Zaawansowane

- **Proxy: schemat docelowy** — logowanie użytkownikiem pośredniczącym do innego schematu (`użytkownik[schemat]`).
  Używane, gdy administrator daje Ci dostęp do schematu aplikacji bez podawania jego hasła.
- **Katalog konfiguracji (tnsnames.ora)** — własny katalog TNS tego połączenia.
- **Portfel TLS (mTLS, np. Autonomous Database)** — katalog z `cwallet.sso`. Przycisk **Importuj ZIP…** rozpakowuje
  archiwum portfela pobrane z konsoli chmury obok pliku ZIP i od razu ustawia też katalog konfiguracji.
- **Edition (EBR)** i **Workspace (DBMS_WM)** — edycja i przestrzeń robocza ustawiane po zalogowaniu.
- **Licencja Diagnostics/Tuning Pack** — zobacz *Licencje pakietów Oracle* niżej.
- **Bieżący schemat** — `ALTER SESSION SET CURRENT_SCHEMA` w każdej sesji. Dzięki temu w zapytaniach piszesz
  `SELECT * FROM emp` zamiast `SELECT * FROM hr.emp`, choć logujesz się innym użytkownikiem.
- **Tylko do odczytu (blokada zmian danych i obiektów)** — zobacz *Środowiska i ochrona przed pomyłkami*.
- **Połącz przy starcie aplikacji**.
- **Skrypt inicjalizacji sesji** — polecenia wykonywane w każdej nowej sesji tego połączenia (rozdzielone `;`, bloki
  PL/SQL zakończone `/`), np. `ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD';`.
- **Komunikat przy logowaniu** — tekst pokazywany po połączeniu, np. przypomnienie, że to baza współdzielona.

### Karta Tunel SSH

Gdy baza jest dostępna tylko przez serwer pośredni (tzw. **bastion**), zaznacz **Łącz przez tunel SSH** i podaj:

- **Serwer SSH (bastion)**, np. `bastion.example.com`, **Port** i **Użytkownik SSH**;
- **Plik klucza prywatnego** — puste pole oznacza agenta SSH i ustawienia z `~/.ssh/config`;
- opcjonalnie **Host pośredni (ProxyJump)**;
- albo **Logowanie hasłem SSH (zamiast klucza)** i **Hasło SSH**.

Tunel używa systemowego `ssh`, więc działa Twoja konfiguracja `~/.ssh/config`, agent SSH (klucze dodane poleceniem
`ssh-add --apple-use-keychain`) i plik znanych hostów. Host i port bazy w polu **Baza** podaj tak, jak widzi je serwer
SSH (np. `db.internal.example.com:1521/USLUGA`). Hasło SSH jest przechowywane tylko w Pęku kluczy i trafia do `ssh`
przez jednorazową kolejkę — nigdy przez argumenty polecenia, zmienne środowiska ani pliki. Jeden tunel obsługuje
wszystkie sesje połączenia i zamyka się razem z ostatnią z nich.

### Karta Agent AI

Ustawienia dostępu agentów AI do połączenia: czy agent w ogóle je widzi, czy może zmieniać dane i obiekty (za Twoją
zgodą), osobny użytkownik bazy dla agenta i kolumny maskowane. Opisuje je rozdział *Agenci AI*.

## Środowiska i ochrona przed pomyłkami

### Do czego to służy

Najgroźniejsza pomyłka programisty bazy to wykonanie polecenia „na próbę” na produkcji. Pelikan pomaga jej uniknąć na
trzy sposoby: **kolorem** (widać, na jakiej bazie pracujesz), **potwierdzeniem** zmian na bazie produkcyjnej
i **blokadą** zmian na połączeniu tylko do odczytu.

- Kolor połączenia widać na liście połączeń, na karcie okna (kropka przed nazwą), na liście okien i na pasku stanu.
  Opcja **Tło edytora w kolorze połączenia** (**Ustawienia › Ogólne**) barwi też tło edytora. W tej samej karcie
  możesz dodać reguły kolorów według wzorca `użytkownik@baza` (np. `sys@*`) — mają pierwszeństwo przed kolorem
  środowiska.
- Oprócz koloru środowiska każde połączenie z otwartymi oknami dostaje kolor z **palety 10 wyraźnie różnych barw**:
  w nim jest tło kart jego okien, kapsułka grupy połączenia, znak na Liście okien i na pasku stanu (zobacz
  *Wprowadzenie › Grupy kart*). Kolor trzyma się połączenia, dopóki ma otwarte okna, i wraca po ponownym otwarciu
  workseta; po zamknięciu ostatniego okna wraca do puli. Przy ponad 10 połączeniach naraz kolory się powtarzają.
- Na połączeniu **produkcyjnym** polecenia zmieniające dane lub obiekty (DML, DDL, bloki PL/SQL) wymagają
  potwierdzenia w oknie „Zmiany na połączeniu produkcyjnym”.
- Połączenie **tylko do odczytu** odrzuca przed wysłaniem do bazy wszystko poza zapytaniami i sterowaniem sesją —
  także `SELECT … FOR UPDATE` i bloki PL/SQL. Na pasku stanu okna widać wtedy „tylko odczyt”.
- Pelikan nigdy sam nie zatwierdza transakcji. Przy zamykaniu okna albo aplikacji z otwartą transakcją pyta, czy
  zatwierdzić (COMMIT) czy wycofać (ROLLBACK); zachowanie przy wylogowaniu zmienisz w **Ustawienia › Ogólne ›
  Wylogowanie z otwartą transakcją**.

### Ćwiczenie: zobacz ochronę w działaniu (bez ryzyka)

Ćwiczenie używa Twojej bazy deweloperskiej udającej produkcję — nic nie zmienia na prawdziwej produkcji.

1. Prawym klikiem na `dev_moja_baza` wybierz **Kopiuj pod inną nazwą…** i nazwij kopię `dev_udawana_produkcja`.
   *Wynik:* na liście jest druga definicja tej samej bazy.
2. Prawym klikiem na kopii wybierz **Edytuj…**, w karcie **Ogólne** ustaw **Środowisko** na *Produkcyjne* i kliknij
   **Zapisz**.
   *Wynik:* kropka przy połączeniu jest czerwona.
3. Prawym klikiem na kopii wybierz **Nowe okno › Okno SQL** i wpisz:

   ```sql
   UPDATE pel_employees SET salary = salary WHERE emp_id = 1;
   ```

4. Naciśnij **F8**.
   *Wynik:* zamiast wykonania pojawia się okno „Zmiany na połączeniu produkcyjnym”. Kliknij **Anuluj** — polecenie nie
   trafia do bazy.
5. Edytuj kopię jeszcze raz, w karcie **Zaawansowane** zaznacz **Tylko do odczytu** i zapisz. Wykonaj to samo UPDATE.
   *Wynik:* Pelikan odrzuca polecenie z komunikatem „Połączenie … jest tylko do odczytu — polecenie zmieniające
   zablokowane”, a pasek stanu okna pokazuje „tylko odczyt”.
6. Na koniec usuń kopię: prawy klik › **Usuń…**.

> ⚠️ **Na co uważać.** Ochrona działa tylko wtedy, gdy środowisko jest ustawione poprawnie. Zakładając połączenie do
> produkcji, ustaw *Produkcyjne*, a jeśli potrzebujesz tylko czytać — zaznacz też **Tylko do odczytu**.

## Hasła i Touch ID

Hasła baz i hasła SSH są przechowywane wyłącznie w Pęku kluczy logowania macOS (bez synchronizacji z iCloud). Nie
trafiają do plików, dzienników, historii poleceń ani argumentów procesów.

W **Ustawienia › Oracle › Hasła połączeń** możesz włączyć **Wymagaj Touch ID albo hasła Maca przed użyciem zapisanego
hasła**. Pelikan zapyta wtedy o potwierdzenie raz na połączenie w czasie działania aplikacji — także wtedy, gdy
połączenia użyje agent AI.

Gdy hasło w bazie wygasło (ORA-28001), Pelikan pokaże okno zmiany hasła: wpisz nowe hasło dwa razy. Przy włączonym
zapamiętywaniu nowe hasło zastąpi w Pęku kluczy stare, gdy tylko połączenie się powiedzie.

Hasło możesz też zmienić w każdej chwili: **Sesja › Zmień hasło…** (połączenie musi być otwarte). Pelikan zmienia je
przez interfejs OCI — hasło nie trafia do tekstu SQL ani do historii poleceń — i zapisuje nowe w Pęku kluczy, jeśli
połączenie zapamiętuje hasło.

## Oracle Wallet

**Portfel** (Oracle Wallet) to zaszyfrowany plik, który przechowuje hasła albo certyfikaty. Pelikan obsługuje dwa
rodzaje:

- **Magazyn haseł** (Secure External Password Store) — logowanie bez hasła w Pelikanie (`/@alias`). Katalog portfela
  i katalog konfiguracji Oracle Net wskazujesz w **Ustawienia › Oracle › Oracle Net i Oracle Wallet**; Pelikan pokazuje
  tam stan portfela (portfel z automatycznym logowaniem `cwallet.sso` jest wymagany). W definicji połączenia wybierz
  uwierzytelnianie *Oracle Wallet (magazyn haseł)*. Pole **Baza** musi być dokładnie aliasem albo connect stringiem
  zapisanym w portfelu. Zmiany w tej sekcji Ustawień działają po ponownym uruchomieniu Pelikana.
- **Portfel TLS** (mTLS, np. Autonomous Database) — ustawiany w karcie **Zaawansowane** definicji połączenia.

Hasła z portfela nigdy nie trafiają do Pelikana.

## Inne sposoby uwierzytelniania

- **Zewnętrzne (Kerberos, system)** — logowanie poświadczeniami systemu operacyjnego albo Kerberos.
- **Microsoft Entra ID (przeglądarka)** — dla baz Oracle na Azure. Podajesz identyfikator dzierżawy, identyfikator
  aplikacji klienta i URI aplikacji bazy; Instant Client 23 otwiera przeglądarkę do logowania i sam przekazuje token
  bazie. Pelikan nie widzi ani nie zapisuje tokenu. Wymaga połączenia TCPS.
- **Token OAuth2 z pliku** — token przygotowany wcześniej narzędziem zewnętrznym (np. Azure CLI); podajesz plik albo
  katalog tokenu.

Te sposoby konfiguruje zwykle administrator — jeśli nie wiesz, którego użyć, wybierz *Hasło*.

## Okna, sesje i połączenie okna

### Do czego to służy

Każde okno ma swoje połączenie, widoczne na pasku stanu. Kliknij je, żeby przełączyć okno na inne połączenie; gdy okno
ma otwartą transakcję, Pelikan najpierw zapyta o COMMIT albo ROLLBACK. Okno z **przypiętym** połączeniem (📌) nie
zmienia go, gdy zmienisz połączenie główne; domyślne przypinanie nowych okien włączysz w **Ustawienia › Ogólne**.

Tryb sesji (**Ustawienia › Ogólne › Tryb sesji**; skutki każdego trybu opisuje rozdział 13):

- **Multi** (domyślny) — każde okno ma własną sesję bazy, więc długie zapytanie w jednym oknie nie blokuje innych, a
  transakcje okien są niezależne;
- **Dual** — okna dzielą jedną sesję, a kompilacja ma osobną;
- **Single** — wszystko w jednej sesji.

### Ćwiczenie: niezależne transakcje dwóch okien

To ćwiczenie pokazuje, czym jest transakcja i dlaczego COMMIT jest ważny.

1. Otwórz dwa okna SQL na bazie deweloperskiej (**⌘N** dwa razy). Nazwijmy je A i B.
2. W oknie A wykonaj (F8):

   ```sql
   UPDATE pel_employees SET salary = 20000 WHERE emp_id = 1;
   ```

   *Wynik:* pasek stanu okna A pokazuje „Wierszy: 1” i „● transakcja otwarta”.
3. W oknie B wykonaj:

   ```sql
   SELECT salary FROM pel_employees WHERE emp_id = 1;
   ```

   *Wynik:* 12000 — okno B **nie widzi** niezatwierdzonej zmiany z okna A (osobna sesja).
4. Wróć do okna A i naciśnij **⇧F10** (ROLLBACK).
   *Wynik:* znacznik transakcji znika; zmiana jest cofnięta. Gdybyś nacisnął **F10** (COMMIT), okno B po ponownym
   zapytaniu zobaczyłoby 20000.

> ⚠️ Dopóki nie zatwierdzisz albo nie wycofasz zmiany, wiersz jest **zablokowany** — inne sesje, które spróbują go
> zmienić, będą czekać. Nie zostawiaj otwartych transakcji na długo, zwłaszcza na bazach współdzielonych.

### Utrata połączenia i zawieszone zapytania

Pelikan co 60 sekund sprawdza, czy połączenie żyje (interwał zmienisz w Ustawieniach), i reaguje na jego utratę.
Opcjonalnie zamyka sesje okien bezczynnych dłużej niż zadany czas, jeśli nie mają otwartej transakcji (**Ustawienia ›
Oracle**).

Gdy zapytania nie da się przerwać (**Przerwij**, ⌘.), użyj **Sesja › Zakończ sesję okna (Kill)** — Pelikan zakończy
sesję okna w bazie z osobnej sesji (wymaga uprawnienia ALTER SYSTEM) i połączy okno ponownie.

### Konsola połączenia

**Sesja › Konsola połączenia** otwiera okno SQL przypisane do połączenia (jedno na połączenie). Jego treść jest
zapisywana automatycznie i wraca po ponownym otwarciu, także po ponownym uruchomieniu Pelikana — dobre miejsce na
podręczne zapytania, których często używasz na danej bazie.

## Eksport i import definicji

**Sesja › Połączenia › Eksportuj definicje połączeń…** zapisuje definicje z folderami do pliku JSON bez haseł —
np. żeby przekazać nowej osobie w zespole gotową listę baz. **Importuj definicje połączeń…** wczytuje je na innym Macu;
hasła podasz przy pierwszym połączeniu.

**Sesja › Połączenia › Eksportuj połączenia z hasłami…** zapisuje definicje razem z hasłami baz i tuneli SSH — na
przykład żeby przenieść połączenia na nowego Maca albo odczytać hasło sprzed lat do konfiguracji innego narzędzia.
Eksport wymaga potwierdzenia właściciela Maca (Touch ID albo hasło). Hasła mogą być **zaszyfrowane frazą** (bez frazy
nie da się ich odzyskać) albo **jawnym tekstem** — wtedy Pelikan dodatkowo ostrzega, a plik może odczytać każdy, kto
go ma. **Importuj definicje połączeń…** rozpoznaje plik z hasłami, przy zaszyfrowanym pyta o frazę, zapisuje hasła
w Pęku kluczy i **usuwa plik**. ⚠️ Pliku z hasłami nigdy nie wysyłaj mailem ani nie wrzucaj do repozytorium.

## Licencje pakietów Oracle

Raporty AWR, ASH i ADDM wymagają płatnego Oracle Diagnostics Pack, a SQL Monitor i SQL Tuning Advisor — Tuning Pack.
Przy pierwszym użyciu takiej funkcji Pelikan pyta, jaką licencję ma baza (*Diagnostics i Tuning Pack*, *Tylko
Diagnostics Pack*, *Brak licencji*), i zapamiętuje odpowiedź w definicji połączenia (zmienisz ją w karcie
**Zaawansowane**). Funkcja nie działa też, gdy parametr bazy `CONTROL_MANAGEMENT_PACK_ACCESS` na nią nie pozwala.
Jeśli nie wiesz, jaką licencję ma Twoja firma, zapytaj administratora — użycie funkcji bez licencji narusza umowę
z Oracle.
