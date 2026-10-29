# Połączenia

Połączenie to zapisana definicja: dokąd się łączyć, jako kto i z jakimi zasadami bezpieczeństwa. Definicje są zapisane
bez haseł — hasła trafiają wyłącznie do Pęku kluczy macOS.

## Lista połączeń

Karta **Połączenia** w lewej kolumnie pokazuje definicje w folderach, a w folderze **Ostatnie** — ostatnio używane.
Pod połączeniem widać jego otwarte okna.

- Dwukrotne kliknięcie połączenia łączy je jako **połączenie główne** (pogrubione na liście). Nowe okna otwierają się na
  połączeniu głównym.
- Menu kontekstowe połączenia: **Połącz jako główne**, **Połącz** (bez zmiany głównego), **Rozłącz**, **Nowe okno**
  (okno SQL, programu, testu albo poleceń na tym połączeniu), **Pokaż okna połączenia**, **Zamknij okna połączenia**,
  **Połącz ponownie okna połączenia**, **Ustaw bieżący schemat…**, **Edytuj…**, **Kopiuj pod inną nazwą…** (kopia w
  tym samym folderze, z zapisanymi hasłami), **Przenieś do folderu** i **Usuń…**.
- Foldery i połączenia są ułożone alfabetycznie. Połączenie przeciągnięte myszą na folder trafia do niego, a na wolne
  miejsce listy — na poziom główny.
- Przyciski nad listą tworzą nowe połączenie (**+**) i folder oraz odświeżają listę.
- **Usuń folder** (menu podręczne folderu, klawisz Delete na zaznaczonym folderze albo **Start › Połączenia › Usuń
  folder** z wyborem z listy) usuwa tylko pusty folder — bez połączeń i podfolderów, więc bez pytania. Przy niepustym
  pozycja jest wyłączona, a podpowiedź podaje, ile połączeń i podfolderów trzeba najpierw przenieść albo usunąć.
  Folderu **Ostatnie** i folderów z regułą dopasowania (z importu definicji) nie da się usunąć.

Możesz też użyć okna logowania: **Sesja › Zaloguj…** (⇧⌘L). Pokazuje ono wszystkie definicje z wyszukiwarką i pozwala
utworzyć nowe połączenie albo edytować istniejące. **Sesja › Wyloguj połączenie główne** kończy sesje połączenia
głównego.

## Nowe połączenie

Wybierz **Sesja › Połączenia › Nowe połączenie…** albo kliknij **+** na liście połączeń. Okno definicji ma cztery
karty.

### Karta Ogólne

- **Nazwa** — nazwa na liście (pusta oznacza `użytkownik@baza`). Dla lokalnych baz testowych dobrze sprawdzają się
  nazwy z przedrostkiem, np. `dev_test`.
- **Folder** i **Środowisko**: *Deweloperskie*, *Testowe*, *Produkcyjne* albo *Inne*. Środowisko decyduje o kolorze
  wskaźnika (testowe — pomarańczowy, produkcyjne — czerwony), o potwierdzaniu zmian i o tym, co wolno agentowi AI.
  **Własny kolor wskaźnika** zastępuje kolor środowiska.
- **Użytkownik**, **Hasło** i **Zapamiętaj hasło w Pęku kluczy**. Bez zapamiętania Pelikan pyta o hasło przy pierwszym
  połączeniu i trzyma je tylko w pamięci do zamknięcia aplikacji. Gdy zapisane hasło przestanie pasować (ORA-01017),
  Pelikan zapyta o nie ponownie.
- **Baza** — adres EZConnect `host:port/usługa` (np. `db.example.com:1521/FREEPDB1`), alias z `tnsnames.ora` (przycisk
  **TNS** obok pola podpowiada aliasy z konfiguracji), pełny deskryptor albo adres `tcps://…` dla połączeń
  szyfrowanych.
- **Połącz jako**: Normal, SYSDBA, SYSOPER, SYSBACKUP, SYSDG, SYSKM albo SYSASM.
- **Uwierzytelnianie**: *Hasło*, *Oracle Wallet (magazyn haseł)*, *Zewnętrzne (Kerberos, system)*, *Microsoft Entra ID
  (przeglądarka)* albo *Token OAuth2 z pliku* (opisane niżej).
- **Sterownik**: *Instant Client (zalecany)* albo *Thin (bez Instant Client)*. Thin nie obsługuje TCPS i portfeli,
  uwierzytelniania zewnętrznego, zmiany wygasłego hasła ani przerywania wykonania.

Kliknij **Testuj**, żeby sprawdzić połączenie, a potem **Zapisz**.

### Karta Zaawansowane

- **Proxy: schemat docelowy** — logowanie użytkownikiem pośredniczącym do innego schematu (`użytkownik[schemat]`).
- **Katalog konfiguracji (tnsnames.ora)** — własny katalog TNS tego połączenia.
- **Portfel TLS (mTLS, np. Autonomous Database)** — katalog z `cwallet.sso`. Przycisk **Importuj ZIP…** rozpakowuje
  archiwum portfela pobrane z konsoli chmury obok pliku ZIP i od razu ustawia też katalog konfiguracji.
- **Edition (EBR)** i **Workspace (DBMS_WM)** — edycja i przestrzeń robocza ustawiane po zalogowaniu.
- **Licencja Diagnostics/Tuning Pack** — zobacz *Licencje pakietów Oracle* niżej.
- **Bieżący schemat** — `ALTER SESSION SET CURRENT_SCHEMA` w każdej sesji.
- **Tylko do odczytu (blokada zmian danych i obiektów)** — zobacz niżej.
- **Połącz przy starcie aplikacji**.
- **Skrypt inicjalizacji sesji** — polecenia wykonywane w każdej nowej sesji tego połączenia (rozdzielone `;`, bloki
  PL/SQL zakończone `/`).
- **Komunikat przy logowaniu** — tekst pokazywany po połączeniu, np. przypomnienie, że to baza współdzielona.

### Karta Tunel SSH

Gdy baza jest dostępna tylko przez serwer pośredni, zaznacz **Łącz przez tunel SSH** i podaj:

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

- Kolor połączenia widać na liście połączeń, na karcie okna (kropka przed nazwą), na liście okien i na pasku stanu. Opcja **Tło edytora w
  kolorze połączenia** (**Ustawienia › Ogólne**) barwi też tło edytora. W tej samej karcie możesz dodać reguły
  kolorów według wzorca `użytkownik@baza` (np. `sys@*`) — mają pierwszeństwo przed kolorem środowiska.
- Na połączeniu **produkcyjnym** polecenia zmieniające dane lub obiekty (DML, DDL, bloki PL/SQL) wymagają
  potwierdzenia w oknie „Zmiany na połączeniu produkcyjnym”.
- Połączenie **tylko do odczytu** odrzuca przed wysłaniem do bazy wszystko poza zapytaniami i sterowaniem sesją —
  także `SELECT … FOR UPDATE` i bloki PL/SQL. Na pasku stanu okna widać wtedy „tylko odczyt”.
- Pelikan nigdy sam nie zatwierdza transakcji. Przy zamykaniu okna albo aplikacji z otwartą transakcją pyta, czy
  zatwierdzić (COMMIT) czy wycofać (ROLLBACK); zachowanie przy wylogowaniu zmienisz w **Ustawienia › Ogólne ›
  Wylogowanie z otwartą transakcją**.

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

Pelikan obsługuje dwa rodzaje portfela:

- **Magazyn haseł** (Secure External Password Store) — logowanie bez hasła w Pelikanie (`/@alias`). Katalog portfela i
  katalog konfiguracji Oracle Net wskazujesz w **Ustawienia › Oracle › Oracle Net i Oracle Wallet**; Pelikan pokazuje
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

## Okna, sesje i połączenie okna

Każde okno ma swoje połączenie, widoczne na pasku stanu. Kliknij je, żeby przełączyć okno na inne połączenie; gdy okno
ma otwartą transakcję, Pelikan najpierw zapyta o COMMIT albo ROLLBACK. Okno z **przypiętym** połączeniem (📌) nie
zmienia go, gdy zmienisz połączenie główne; domyślne przypinanie nowych okien włączysz w **Ustawienia › Ogólne**.

Tryb sesji (**Ustawienia › Ogólne › Tryb sesji**):

- **Multi** (domyślny) — każde okno ma własną sesję bazy, więc długie zapytanie w jednym oknie nie blokuje innych, a
  transakcje okien są niezależne;
- **Dual** — okna dzielą jedną sesję, a kompilacja ma osobną;
- **Single** — wszystko w jednej sesji.

Pelikan co 60 sekund sprawdza, czy połączenie żyje (interwał zmienisz w Ustawieniach), i reaguje na jego utratę.
Opcjonalnie zamyka sesje okien bezczynnych dłużej niż zadany czas, jeśli nie mają otwartej transakcji (**Ustawienia ›
Oracle**).

Gdy zapytania nie da się przerwać (**Przerwij**, ⌘.), użyj **Sesja › Zakończ sesję okna (Kill)** — Pelikan zakończy
sesję okna w bazie z osobnej sesji (wymaga uprawnienia ALTER SYSTEM) i połączy okno ponownie.

**Sesja › Konsola połączenia** otwiera okno SQL przypisane do połączenia (jedno na połączenie). Jego treść jest
zapisywana automatycznie i wraca po ponownym otwarciu, także po ponownym uruchomieniu Pelikana — dobre miejsce na
podręczne zapytania.

## Eksport i import definicji

**Sesja › Połączenia › Eksportuj definicje połączeń…** zapisuje definicje z folderami do pliku JSON bez haseł.
**Importuj definicje połączeń…** wczytuje je na innym Macu; hasła podasz przy pierwszym połączeniu.

**Sesja › Połączenia › Eksportuj połączenia z hasłami…** zapisuje definicje razem z hasłami baz i tuneli SSH — na
przykład żeby przenieść połączenia na nowego Maca albo odczytać hasło sprzed lat do konfiguracji innego narzędzia.
Eksport wymaga potwierdzenia właściciela Maca (Touch ID albo hasło). Hasła mogą być **zaszyfrowane frazą** (bez frazy
nie da się ich odzyskać) albo **jawnym tekstem** — wtedy Pelikan dodatkowo ostrzega, a plik może odczytać każdy, kto
go ma. **Importuj definicje połączeń…** rozpoznaje plik z hasłami, przy zaszyfrowanym pyta o frazę, zapisuje hasła
w Pęku kluczy i **usuwa plik**.

## Licencje pakietów Oracle

Raporty AWR, ASH i ADDM wymagają płatnego Oracle Diagnostics Pack, a SQL Monitor i SQL Tuning Advisor — Tuning Pack.
Przy pierwszym użyciu takiej funkcji Pelikan pyta, jaką licencję ma baza (*Diagnostics i Tuning Pack*, *Tylko
Diagnostics Pack*, *Brak licencji*), i zapamiętuje odpowiedź w definicji połączenia (zmienisz ją w karcie
**Zaawansowane**). Funkcja nie działa też, gdy parametr bazy `CONTROL_MANAGEMENT_PACK_ACCESS` na nią nie pozwala.
