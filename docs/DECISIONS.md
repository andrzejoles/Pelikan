# Decyzje projektowe

Format: numer · data — decyzja, potem powód, alternatywy i jak zmienić później. Najnowsze na dole.
Założenia oznaczone „do weryfikacji” wymagają potwierdzenia w dokumentacji lub na żywo.

### D1 · 2026-10-22 — Praca autonomiczna zamiast czekania na akceptację
Prompt (`docs/PROMPT.md` §0) każe prowadzić projekt w pełni autonomicznie. Każde miejsce, w którym normalnie
zapytałbym właściciela, zastępuje wpis w tym pliku (decyzja, powód, alternatywy, jak zmienić). Zatrzymuję się
tylko w sytuacjach z §13; opisuję je wtedy w raporcie jako blokady i w międzyczasie robię inne zadania.

### D2 · 2026-10-22 — Pierwszy commit bezpośrednio na `main`
Pull request wymaga istniejącej gałęzi bazowej, więc pierwszy commit (README, LICENSE, `.gitignore`,
`docs/PROMPT.md`) poszedł prosto na `main`. To jedyny wyjątek; dalej wszystko przechodzi przez PR scalane
„Merge pull request” (§10).

### D3 · 2026-10-22 — Tożsamość commitów: adres noreply GitHuba
Globalna konfiguracja gita na tym Macu nie ma `user.email`. Repozytorium jest publiczne, więc commity mają
lokalnie ustawione `Andrzej Oles <47484303+andrzejoles@users.noreply.github.com>`, żeby nie publikować
prywatnego adresu e-mail. Zmiana: `git config user.email …` w katalogu repozytorium.

### D4 · 2026-10-22 — Kontenery: Colima + Docker CLI
Alternatywy: OrbStack (szybki, ale licencja komercyjna przy użyciu firmowym), Docker Desktop (licencja
płatna w większych firmach). Colima jest open source (MIT), instaluje się z Homebrew i uruchamia obrazy
arm64 natywnie (`--vm-type vz`). Baza testowa: `gvenzl/oracle-free:latest` (Oracle Database Free 26ai, arm64),
pełny obraz zamiast `slim`, bo `slim` może nie mieć składników potrzebnych do testów (MLE) — do weryfikacji.

### D5 · 2026-10-22 — Hasła bazy testowej w `.testdb/env`
Baza testowa w kontenerze to jednorazowe środowisko na `127.0.0.1`. Hasła są losowane przy pierwszym
`scripts/testdb.sh up` i zapisane w `.testdb/env` (katalog 0700, plik 0600, w `.gitignore`), a w CI podawane
przez zmienne środowiskowe workflow. Zasada „hasła tylko w Pęku kluczy” (§4.2 p. 6) dotyczy połączeń
użytkownika w aplikacji, nie tej bazy. Port 1531 zamiast 1521, żeby nie kolidować z lokalnymi bazami właściciela.

### D6 · 2026-10-22 — Parametry JasperReports jako zmienne (decyzja właściciela)
Właściciel poprosił, żeby oprócz `&` i `:bind` rozpoznawać jako zmienne parametry zapytań z raportów
JasperReports. Lekser ma token `jasperParameter`, a `Variables` (PelikanSQL) obsługuje:
`$P{x}` → zmienna wiązana `:x` (nazwa z niedozwolonymi znakami → `:p_…`), `$P!{x}` → tekst wstawiany do SQL
(jak `&`), `$X{FUNKCJA, kolumna, param[, param2]}` → warunek ze zmiennymi wiązanymi `:jx1…`: IN/NOTIN (lista,
pusta → `0 = 0`), EQUAL/NOTEQUAL (NULL → `IS [NOT] NULL`), LESS, LESS], GREATER, [GREATER, BETWEEN z wariantami
nawiasów (brak granicy → pominięta, obie → `0 = 0`). Semantyka `$X{}` wg dokumentacji JasperReports — **do weryfikacji**
z JasperReports Library (zachowanie przy NULL w BETWEEN i LESS). Okno „Zmienne” pyta o nie razem z `&` i `:bind`.

### D7 · 2026-10-22 — Instant Client nie jest dołączany do aplikacji
Warunki „Oracle Technology Network Development and Distribution License Terms for Instant Client”
(https://www.oracle.com/downloads/licenses/instant-client-lic.html) pozwalają na redystrybucję tylko z umową
licencyjną użytkownika końcowego zawierającą ograniczenia Oracle (m.in. zakaz inżynierii wstecznej, użycie tylko
w działalności użytkownika) — to się kłóci z dystrybucją aplikacji na licencji MIT bez osobnej umowy. Dlatego
Pelikan wykrywa Instant Client zainstalowany przez użytkownika (`InstantClientLocator`: ścieżka z ustawień,
`PELIKAN_OCI_LIB_DIR`, `~/Downloads/instantclient_*` — domyślne miejsce instalatora Oracle dla macOS, `/opt/oracle`,
Homebrew) i pokazuje instrukcję instalacji. Na tym Macu do rozwoju zainstalowany Instant Client 23.26.2 (Basic,
SQL*Plus, SDK) w `~/Downloads/instantclient_23_26`. Zmiana: jeśli Oracle zmieni warunki, dołączenie to krok
w `scripts/build-installer.sh` + ścieżka w `InstantClientLocator`.

### D8 · 2026-10-22 — ODPI-C dołączony jako źródła (cel C w SPM)
ODPI-C v26.0.0 (UPL 1.0 / Apache 2.0) w `Packages/PelikanKit/Sources/CODPI` bez zmian. ODPI ładuje Instant Client
dynamicznie (`dlopen`), więc aplikacja i testy budują się bez Instant Client, a na Linuksie (CI) używają wersji
linuksowej. Każda sesja ma własną kolejkę GCD (wywołania OCI blokują — nie w puli kooperacyjnej Swifta),
`breakExecution` wywoływane poza kolejką (tryb `DPI_MODE_CREATE_THREADED`). NUMBER pobierany jako tekst (bez utraty
precyzji). Aktualizacja: podmiana katalogu źródeł i `VENDORED.md`.

### D9 · 2026-10-22 — Źródło dokumentacji wzorca: podręcznik z instalatora wersji próbnej
Podręcznik PL/SQL Developer 17.0 nie jest publikowany na stronie producenta; jest w instalatorze wersji próbnej
(`plsqldev1703x64.msi`). Wypakowałem z niego wyłącznie `manual.pdf` (dokumentacja, nie binaria — bez dekompilacji),
streściłem własnymi słowami w `docs/research/plsqldev-17.md` i nie kopiuję tekstu ani grafik do repozytorium. Instalator
i PDF usunięte z dysku po analizie (pozostał tylko tekst roboczy w katalogu tymczasowym sesji).

### D10 · 2026-10-22 — Zamknięcie z otwartą transakcją: domyślnie pytanie, nie COMMIT
Wzorzec domyślnie zatwierdza otwartą transakcję przy wylogowaniu (UG 23.1). PROMPT §3.1 wymaga ostrzeżenia o
niezatwierdzonej transakcji przy zamykaniu okna i aplikacji, a §4.2 p.6 — ostrożności na prod. Pelikan domyślnie pyta
(Commit / Rollback / Anuluj); preferencja „Wylogowanie z otwartą transakcją” pozwala wybrać zachowanie wzorca.

### D11 · 2026-10-22 — Funkcje pominięte w zakresie
- ODBC Importer — ODBC na macOS wymaga osobnego menedżera sterowników i sterowników źródeł, mało przydatne przy Oracle;
  zastępują go Text/Excel Importer, kreator importu i przenoszenie danych (gap-analysis §5).
- APEXlang (SQL Developer for VS Code) — wymaga APEX w bazie, poza codzienną pracą z PL/SQL.
- Liquibase (`lb` w SQLcl) — wymaga Javy i biblioteki Liquibase (zależność spoza Swift); do rozważenia jako opcja
  korzystająca z zainstalowanego SQLcl.
- Unit Test SQL Developera i Data Modeler — utPLSQL i diagramy ER pokrywają potrzeby.
- AI Assistant wzorców, wtyczki i mechanizm wtyczek — zgodnie z PROMPT §3.2 (rejestr komend nie utrudnia dodania
  wtyczek później).
Każdy pominięty wiersz macierzy ma stan „pominięte (powód)” i nie liczy się do postępu.

### D12 · 2026-10-22 — AutoSelect statement domyślnie włączone
Domyślna wartość preferencji wzorca nie jest opisana w podręczniku (do weryfikacji). Pelikan domyślnie wykonuje
polecenie pod kursorem (bez zaznaczenia), żeby przypadkiem nie uruchomić całego skryptu; F8 z zaznaczeniem wykonuje
zaznaczenie, a osobna komenda „Wykonaj wszystko” — wszystkie polecenia okna.

### D13 · 2026-10-22 — Szkice wydań od Etapu 1
PROMPT §8 przewiduje szkic wydania na koniec każdego etapu. Etap 0 to fundament bez używalnej aplikacji (szkielet okna),
więc pierwszy szkic wydania (z podpisem, DMG/PKG, Sparkle — przeniesione z Etapu 8) powstaje na koniec Etapu 1.

### D14 · 2026-10-22 — Edytor bez STTextView
STTextView ma licencję GPLv3 lub komercyjną — niezgodną z dystrybucją Pelikana na MIT bez zakupu (PROMPT §13). Edytor
własny na TextKit 2 (ADR 0003).

### D15 · 2026-10-22 — Jedno okno główne z kartami zamiast natywnych kart macOS
Natywne karty macOS to osobne okna — wspólne panele (Object Browser, Window List) musiałyby być w każdym oknie. Jedno
okno główne z własnym paskiem kart (SDI wzorca), odłączanie dokumentu do osobnego okna (ADR 0005).

### D16 · 2026-10-22 — `&&` zależnie od okna: SQL Window = dosłowne `&`, Command Window = zmienna zapamiętywana
UG 12.3 (składnia zmiennych SQL Window, Report Window i szablonów) podaje `&&` jako sposób zapisu znaku `&` w tekście
(`'R&&D'`), a w SQL*Plus `&&x` to zmienna o wartości zapamiętanej (DEFINE). `Variables.find/prepare(syntax:)`:
`.sqlWindow` (domyślnie) — `&&` → `&`; `.sqlplus` (Command Window) — `&&x` jako zmienna trwała.

### D17 · 2026-10-22 — Wszystkie skróty komendy działają; Ctrl+F8 koliduje z macOS
Menu macOS pokazuje jeden skrót na pozycję, a komendy mają po dwa (profil PL/SQL Developer + odpowiednik z ⌘). Pierwszy
skrót trafia do menu, pozostałe obsługuje lokalny monitor klawiatury (`MenuBuilder.handleKeyDown`) — tylko w oknie
głównym bez arkusza i tylko dla komend dostępnych w danym stanie. Ctrl+F8 jest w macOS domyślnie skrótem „Przenieś
fokus do menu statusu” (Ustawienia › Klawiatura › Skróty) i nie dociera do aplikacji; Pelikan nie zmienia ustawień
systemu — w SKROTY.md opisany jest odpowiednik ⇧⌘↩ i sposób wyłączenia skrótu systemowego przez użytkownika.

### D18 · 2026-10-22 — Instant Client: wyszukiwanie leniwe, bez sięgania do Pobranych, gdy niepotrzebne
Odczyt `~/Downloads` wywołuje pytanie systemu o dostęp do folderu (TCC). `InstantClientLocator` sprawdza kolejno:
katalog z ustawień, `PELIKAN_OCI_LIB_DIR`, Homebrew / `/usr/local` / `/opt/oracle`, dopiero potem Pobrane i Aplikacje.
Zgoda w oknie systemowym należy do użytkownika — Pelikan (ani agent budujący) jej nie klika. Do testów lokalnych
kopia klienta w `build/instantclient` (ignorowane przez git).

### D19 · 2026-10-23 — Tunel SSH przez systemowy `ssh`, bez haseł
Tunel (funkcja z SQL Developer/DBeaver; PL/SQL Developer jej nie ma) uruchamia `/usr/bin/ssh -N -L 127.0.0.1:port:host:port`
z `BatchMode=yes` i `ExitOnForwardFailure=yes`. Dzięki temu działają `~/.ssh/config`, ProxyJump, agent SSH (klucze w Pęku
kluczy przez `ssh-add --apple-use-keychain`) i weryfikacja `known_hosts` dokładnie jak w Terminalu. Biblioteka SSH w Swifcie
(swift-nio-ssh) wymagałaby własnej obsługi known_hosts, agentów i konfiguracji. Hasło SSH nie jest obsługiwane: przekazanie
go do `ssh` wymagałoby `SSH_ASKPASS` z hasłem w środowisku albo pliku, co łamie zasadę „hasła tylko w Pęku kluczy” — komunikat
prosi o klucz. Port lokalny losowy (bind na 0), tunel współdzielony przez sesje połączenia, zamykany z ostatnią sesją i przy
wyjściu z aplikacji. Testy: kontener sshd w sieci Docker bazy testowej (`scripts/testdb.sh ssh-up`, klucz jednorazowy w `.testdb/ssh`).

### D20 · 2026-10-23 — OracleNIO z commitu na main; NUMBER/DATE dekodowane przez Pelikana
Wydanie 1.0.0-rc.4 nie kompiluje się w Swift 6.4 (makro `@TaskLocal` z `@usableFromInline` daje błędny atrybut);
poprawka jest na gałęzi main (commit 7cda9e0, wymaga swift-tools 6.3 — CI Linux podniesiony do Swift 6.3). Zależność
przypięta do tego commitu (`revision:`), zmiana na wydanie 1.0.0 po jego publikacji. OracleNIO dekoduje NUMBER przez
`Double` i DATE przez `Date`, co gubi cyfry i strefy — Pelikan czyta surowe bajty (format wykładnik + cyfry o podstawie
100; 7/11/13 bajtów dat) jak w sterowniku Instant Client (NUMBER jako tekst). Metadane kolumn (typ, rozmiar, precyzja)
i pozycja błędu są w OracleNIO polami wewnętrznymi — odczyt przez `Mirror` z wartościami zastępczymi, gdy pól nie ma.
Sterownik thin nie obsługuje: TCPS/wallet, uwierzytelniania zewnętrznego, zmiany wygasłego hasła, przerwania wywołania
(brak w API) — komunikat albo wyszarzenie z podpowiedzią „przełącz na Instant Client”.

### D21 · 2026-10-23 — Etap 1 zamknięty; P2/P3 Etapu 1 przechodzą do kolejnych etapów
Kryteria odbioru spełnione: praca z zapytaniami z klawiatury (F8/⇧⌘↩, zmienne, siatka, Command Window, historia,
Znajdź i zamień), 1 mln wierszy (model 1,2 s, przewijanie z dociąganiem sprawdzone), brak blokad UI przy długim
zapytaniu (wykonanie async, równoległe okna, przerwanie). Wiersze P1 bez pełnej realizacji mają stan „⚠️ częściowo”
z opisem braku. Pozostałe wiersze Etapu 1 o priorytecie P2/P3 (m.in. QBE, sumy, filtr kolumn, Auto Refresh, Direct
Query Export, NLS aplikacji, LDAP, EBR) są realizowane przy okazji etapów, które dotykają tych okien, a najpóźniej w
audycie Etapu 8 — plan nie blokuje Etapu 2 (Object Browser i Program Window), od którego zależą kolejne etapy.

### D22 · 2026-10-23 — Code Hierarchy pod edytorem; skrót Przejdź do deklaracji ⌃⌘J; zwijanie w osobnym PR
Ścieżka Code Hierarchy (jednostka › podprogram › blok) jest w pasku pod edytorem obok pozycji kursora, a nie w
osobnym pasku nad edytorem — nad edytorem są już karty jednostek, a pasek pozycji jest stałym miejscem informacji
o kursorze. Skrót macOS dla „Przejdź do deklaracji” to ⌃⌘J (jak w Xcode): ⌥⌘D przechwytuje system (pokaż/ukryj
Dock); w profilu PL/SQL Developer zostaje ⌃⌥D, a Cmd+klik działa zawsze. Parser dostarcza zakresy zwijania (bloki,
IF, LOOP, CASE — test), a zwijanie w edytorze TextKit 2 (ukrywanie akapitów, znaczniki ±, Fold All) jest osobnym
podzadaniem `etap-2/zwijanie`, bo wymaga zmian w warstwie układu edytora niezależnych od parsera.

### D23 · 2026-10-23 — Code Assistant: wielkość liter z prefiksu, ⌥⎋ na macOS, zapytania w sesji głównej
Wstawiany tekst ma wielkość liter wpisanego prefiksu (małe → małe, wielkie → wielkie); bez prefiksu nazwy ze słownika
są wstawiane małymi literami, a deklaracje lokalne w postaci z kodu. Nazwy wymagające cudzysłowu (małe litery w
słowniku) nie są zmieniane. Pełne preferencje stylu (UG 23.14) są w wierszu PD-CA-007. Skrót ręcznej aktywacji: ⌃Space
w profilu PL/SQL Developer; na macOS ⌥⎋ i ⌃Space (⌃Space domyślnie przełącza źródło wprowadzania). Automatyczna
aktywacja po kropce z opóźnieniem 400 ms (ustawienia `codeAssistantAutomatic`, `codeAssistantDelay`). Zapytania
słownika idą przez sesję główną połączenia okna i są buforowane w `MetadataProvider` (kolumny, synonimy, nazwy
obiektów schematu, linki) do odświeżenia komendą „Odśwież podpowiedzi kodu” albo odświeżenia Object Browsera.

### D24 · 2026-10-23 — Formater PL/SQL: styl domyślny i gwarancja niezmienności kodu
Domyślny styl: słowa kluczowe WIELKIE, identyfikatory bez zmian, wcięcie 2, klauzule SQL w kolumnie początku
instrukcji z elementami wyrównanymi do 7. kolumny (`FROM   emp`), element listy w osobnej linii, przecinek na końcu,
prawy margines 100 (zawijanie list w nawiasach po przecinkach, np. parametrów), jedna pusta linia zachowana.
Formater przebudowuje wyłącznie odstępy, podział linii i wielkość liter słów bez cudzysłowu; wynik jest porównywany
ze źródłem token po tokenie (literały, identyfikatory w cudzysłowie i komentarze bez zmian) i przy jakiejkolwiek
różnicy formatowanie jest przerywane z komunikatem, a tekst zostaje bez zmian. Regiony `-- NoFormat Start/End`
są kopiowane bez zmian. Skrót ⇧⌘F (zapowiedziany w Etapie 0) zostaje.

### D25 · 2026-10-23 — Edytor tabeli: zmiany jako ALTER, zatrzymanie przy pierwszym błędzie
Edytor definicji tabeli (UG 9.1) generuje dla istniejącej tabeli różnicę jako polecenia ALTER (zmiana nazwy tabeli,
DROP / RENAME / MODIFY / ADD kolumn, komentarze, więzy: zmiana definicji = DROP + ADD, sama nazwa = RENAME, stan =
ENABLE / DISABLE; indeksy analogicznie), a nie „Recreate table” — przebudowa z kopiowaniem danych zostaje opcją
na później. Polecenia wykonuje sesja kompilacji po strażniku tylko do odczytu / produkcji; przy pierwszym błędzie
wykonanie się zatrzymuje (DDL w Oracle zatwierdza się samo — wykonane polecenia zostają), edytor pokazuje kartę SQL
z komunikatem i wczytuje stan z bazy. „Edytuj” na tabeli w Object Browserze otwiera edytor; agent dostaje definicję
jako DDL (bez wykonania). Komunikaty `OracleError` mają od teraz pełną treść także w `localizedDescription`.

### D26 · 2026-10-23 — Hasła w edytorach użytkowników: tylko w pamięci okna, maskowane wszędzie
Edytor użytkownika przyjmuje hasło w polu bezpiecznym; wartość istnieje wyłącznie w pamięci otwartego okna edytora
i w poleceniu wysyłanym do bazy. Podgląd SQL, strażnik produkcji, lista wykonanych poleceń i komunikaty błędów
dostają wersję z `IDENTIFIED BY ********`; hasło nie trafia do historii, dziennika komend, pliku ani Pęku kluczy
(to hasło innego konta, nie dane logowania Pelikana). Edytor łącza bazy danych (też z hasłem) i profilu — później
z tą samą zasadą.

### D27 · 2026-10-23 — Etap 2 zamknięty; P2/P3 Etapu 2 przechodzą do kolejnych etapów
Kryterium spełnione: edycja i kompilacja pakietu 50 403 linii bez przestojów przy pisaniu (Release, pomiar
`PELIKAN_STALL_LOG`), a Object Browser wczytuje folder ze 100 000 obiektów w 0,3 s bez blokady. Zrobione: Object
Browser, Program Window z kompilacją i listą błędów, parser strukturalny, Zawartość kodu i hierarchia, zwijanie,
nawigacja (deklaracje, Wstecz/Naprzód, hiperłącza), Code Assistant, szablony, formater, Znajdź obiekty bazy, Kompiluj
niepoprawne obiekty, przeglądarka różnic i porównania, edytory tabeli, sekwencji, synonimu, indeksu, użytkownika i
roli, pary nawiasów i bloków. Wszystkie wiersze P1 Etapu 2 mają stan inny niż „do zrobienia” (części opisane jako
„⚠️ częściowo”). Pozostałe 33 wiersze P2/P3 (m.in. refaktoryzacja, hints, zakładki, edycja podzielona, AutoReplace,
wiele kursorów, foldery i filtry Object Browsera, kosz, CCFlags, edytory Library/Directory/Job/Queue/Profile/DB link,
partycje, Safe compilation, MLE w Program Window) są realizowane przy etapach, które dotykają tych okien, najpóźniej
w audycie Etapu 8. Debuger nie odczytuje `:new`/`:old` przez DBMS_DEBUG (GET_VALUE dla pseudorekordów wyzwalacza) —
do rozwiązania w Etapie 3 (alternatywa: JDWP, ADR 0006).

### D28 · 2026-10-23 — Profiler: tabele w schemacie użytkownika, dane w transakcji okna
Profiler liniowy (DBMS_PROFILER) i hierarchiczny (DBMS_HPROF) działają w sesji okna testu. Brakujące tabele są
tworzone w schemacie użytkownika (`DBMS_PROFILER.CREATE_TABLES` w 23ai+, wcześniej DDL jak w PROFTAB.SQL;
`DBMS_HPROF.CREATE_TABLES`) — wyłącznie po przejściu strażnika modyfikacji (połączenie tylko do odczytu: blokada,
produkcja: potwierdzenie). DBMS_PROFILER zapisuje dane przebiegu w transakcji sesji okna (bez COMMIT) — raport czyta
je w tej samej sesji; zatwierdzenie albo wycofanie transakcji okna decyduje o ich zachowaniu, jak w SQL*Plus.
Wariant `START_PROFILER` z numerem przebiegu (OUT) zwraca w 26ai `error_io`, więc numer przebiegu jest odczytywany po
zatrzymaniu z unikalnego komentarza. Bloki pomocnicze Pelikana (start/stop) są pomijane w raporcie.

### D29 · 2026-10-23 — Etap 3 zamknięty; JDWP, ślad i pozostałe P2/P3 przechodzą dalej
Kryterium spełnione testami integracyjnymi na bazie testowej: krokowanie przez pakiet z wyzwalaczem (stos trzech
ramek z typami jednostek), podgląd rekordu (%ROWTYPE) i kolekcji (GET_INDEXES), zmienne globalne pakietu, punkty
przerwania w jednostkach i w bloku testu, zatrzymanie na wyjątku i na kodzie błędu, zmiana wartości, obserwowane
wyrażenia, DBMS_OUTPUT w trakcie, wykonanie SQL w sesji debugowanej. Okno testu (zmienne z typami, kursory, BOOLEAN,
stos błędu, Test z Object Browsera, pliki .tst), profiler liniowy i hierarchiczny, statystyki sesji. Wszystkie wiersze
P1 Etapu 3 zrobione. Przechodzą dalej (najpóźniej audyt Etapu 8): DBMS_DEBUG_JDWP (PD-DBG-002 — także jako droga do
`:new`/`:old`, których DBMS_DEBUG nie udostępnia), karta statystyk okna SQL (PD-SQLW-008), DBMS_TRACE i SQL Trace
(PD-OPT-007/008), ostrzeżenia ORA-04068 (PD-TEST-007), testy standardowe (PD-TEST-009), nadawanie uprawnień DEBUG
(PD-DBG-013), warunki i logpointy punktów przerwania.

### D30 · 2026-10-23 — Weryfikacja bez sterowania interfejsem w czasie pracy właściciela
Właściciel używa komputera w trakcie pracy agenta, więc syntetyczne klawisze i kliknięcia (AppleScript, CGEvent) oraz
aktywowanie okien Pelikana są wyłączone: mogą trafić do aktywnego okna właściciela. Funkcje są weryfikowane testami
(jednostkowymi i integracyjnymi na bazie testowej) oraz zrzutami okien wykonywanymi w tle; wiersze macierzy bez zrzutu
mają tylko ✅ test, a 👁 dochodzi, gdy zrzut da się zrobić bez interakcji albo właściciel na to pozwoli.

### D31 · 2026-10-23 — Instalacja utPLSQL z aplikacji
Instalator pobiera archiwum `utPLSQL.tar.gz` z wydań projektu na GitHubie i odrzuca je bez zgodnej sumy kontrolnej
(SHA-256, a dla starszych wydań, które mają tylko MD5 — MD5). Skrypty instalatora wykonuje silnik Command Window
w osobnym oknie poleceń; każdy krok (`install_headless.sql`, `uninstall.sql`, `install.sql`) to osobne uruchomienie,
bo skrypty kończą się `EXIT`. Nowa instalacja nadaje właścicielowi losowe hasło, którego nikt nie zna, i od razu
blokuje konto (utPLSQL nie loguje się jako właściciel). Instalator sprząta pliki tymczasowe poleceniem `! rm plik`;
tylko w jego przebiegu takie polecenie usuwa plik z katalogu instalatora bez powłoki, a poza tym HOST pozostaje
niedostępny. Komenda działa tylko dla połączeń deweloperskich i testowych i zawsze pyta o potwierdzenie (agent —
poziom „za zgodą”). Przy okazji: `COLUMN … NEW_VALUE` przy zapytaniu bez wierszy definiuje brakującą zmienną jako pustą,
jak SQL*Plus (opcjonalne parametry skryptów).

### D32 · 2026-10-23 — Zamknięcie Etapu 4 (utPLSQL)
Kryteria etapu spełnione testami na bazie testowej: wygenerowany szkielet pakietu testowego kompiluje się i uruchamia,
testy uruchamiają się z eksploratora (ścieżki `schemat:ścieżka`) i z edytora (test pod kursorem), pokrycie trafia do
okna programu (linie pokryte i niepokryte z reportera Sonar). Wszystkie wiersze UT- macierzy mają test; walidacja
adnotacji przy kompilacji jest częściowa (nieznane nazwy, bez sprawdzania procedur wskazanych w `--%beforetest` itd.).
Zrzuty okien eksploratora i wyników czekają na zgodę właściciela na sterowanie interfejsem (D30). Szkic wydania
tworzony z `main` po scaleniu zamknięcia; publikuje właściciel.

### D33 · 2026-10-23 — Kanał agentów przeniesiony z Bifolda; agent tylko przez własne narzędzia bazy
Most, protokół gniazda, serwer z weryfikacją UID/drzewa procesów/tokenu, rejestr sesji, transport MCP i uruchamianie
CLI pochodzą z Bifolda (ten sam autor, licencja MIT), z nazwami Pelikana (`pelikan-mcp`, `PELIKAN_AGENT_TOKEN`).
Biblioteka MCP: oficjalne `modelcontextprotocol/swift-sdk` 0.12.1 (jak w Bifoldzie), tylko na macOS — moduły agenta
nie budują się na Linuksie (CI bazy), a logika bazy agenta leży w PelikanWorkspace, więc jej testy działają na obu
systemach. Agent dotyka bazy wyłącznie przez narzędzia `agent.*`, które używają jego własnej sesji; zwykłe komendy
aplikacji są dla agenta dostępne przez `run_command` tylko z jawnej listy (`AgentPolicy.appCommands`: nowe okna SQL,
programu i testu, nawigacja, formatowanie i operacje na tekście edytora). Heurystyka „skutki tylko w interfejsie” nie
wystarcza: część takich komend czyta bazę sesjami użytkownika (np. otwarcie okna testu z argumentami procedury), co
ominęłoby osobnego użytkownika bazy agenta i maskowanie, a skrypt CLI utPLSQL zawiera łańcuch połączenia.

### D34 · 2026-10-23 — Sesja bazy agenta, odczyt i maskowanie
Agent ma na każdym połączeniu własną sesję (`SessionPurpose.agent`), z `MODULE='Pelikan agent'`, `ACTION` = nazwa
narzędzia i `CLIENT_INFO` z identyfikatorem sesji agenta. Osobny użytkownik bazy agenta jest realizowany połączeniem
proxy `główny[agent]` (`ALTER USER agent GRANT CONNECT THROUGH główny`) — bez drugiego hasła w Pęku kluczy, a sesja ma
wyłącznie uprawnienia użytkownika agenta. `run_query` przyjmuje jedno SELECT/WITH bez `FOR UPDATE` i bez funkcji
zdefiniowanych w klauzuli WITH, wykonuje je w transakcji `READ ONLY` (gdy agent ma niezatwierdzone DML — w tej
transakcji, żeby jej nie wycofać) z limitem wierszy, czasu wywołania i rozmiaru wyniku. Maskowanie działa po nazwie
kolumny (ostatni człon wpisu), niezależnie od tabeli, a zapytanie odwołujące się do kolumny maskowanej jest odrzucane
— granicą pozostają uprawnienia użytkownika bazy (SECURITY §3).

### D35 · 2026-10-23 — Zmiany agenta: transakcja, DDL i cofanie kodu
DDL w Oracle zatwierdza niejawnie bieżącą transakcję, więc DDL agenta jest odrzucane, gdy agent ma niezatwierdzone DML
(najpierw `commit` albo `rollback` — każde za zgodą); bez tego zgoda na DDL oznaczałaby ukryty COMMIT. Przed DDL kodu
(pakiet, ciało, procedura, funkcja, wyzwalacz, typ, widok; także DROP) zapisywany jest kod sprzed zmiany, a po
wykonaniu — kod po zmianie. „Cofnij sesję agenta” przywraca pierwszą wersję sprzed sesji (obiekt utworzony przez agenta
usuwa) sesją kompilacji użytkownika; obiekt, którego kod różni się od zapisanego „po zmianie”, to konflikt pomijany bez
wymuszenia. Testy utPLSQL agenta działają w jego sesjach (`agent/run`, `agent/events`), a instalacja utPLSQL — w oknie
poleceń widocznym dla użytkownika, tylko na dev/test. Bloki PL/SQL mogą zatwierdzać wewnątrz siebie — tego aplikacja nie
zablokuje; okno zgody pokazuje pełny tekst.

### D37 · 2026-10-23 — Makra nagrywają tekst i komendy edytora
Makro (PD-EDIT-015) zapisuje wpisywany tekst, Backspace (łączone w kroki, poprawki literówek skracają ostatni tekst)
oraz komendy rejestru wywołane przez użytkownika ze skutkiem „interfejs” albo „edytor”. Komendy wykonujące polecenia
w bazie, zmieniające ustawienia lub pliki nie są nagrywane — odtworzenie makra nie może niespodziewanie wykonać SQL.
Biblioteka makr leży w `macros.json` katalogu danych; makro ze skrótem jest komendą `edit.macro.<id>` (menu Edycja ›
Makra, paleta), a skrót zajęty przez inną komendę jest pomijany. Makra są niedostępne dla agenta (poziom Brak).

### D38 · 2026-10-23 — Składnia zadań To-Do
Zadanie to komentarz zaczynający się od `TODO` (zamknięte: `DONE`) z opcjonalnymi atrybutami:
`-- TODO(właściciel) !priorytet #kategoria: tekst`, także w kolejnych liniach komentarza blokowego. Słowo musi
otwierać treść komentarza (nie środek zdania), literały są pomijane (lekser). Zamknięcie zamienia TODO na DONE w kodzie,
więc stan zadania podróżuje z plikiem i repozytorium.

### D39 · 2026-10-23 — Historia schowka tylko w pamięci; formaty Special Copy w JSON
Historia schowka (PD-EDIT-024) zbiera teksty kopiowane w Pelikanie (edytor, siatka, Special Copy) i nie jest zapisywana
na dysk — skopiowane wyniki mogą zawierać dane z bazy. Formaty Special Copy (PD-EDIT-016) to prefiks/sufiks linii,
cudzysłów, escapy i znak nowej linii; własne formaty to pliki `CopyFormats/*.json` w katalogu danych (ten sam
identyfikator zastępuje wbudowany). Wklejanie z języka bez formatu wykrywa cudzysłów i styl escapów z tekstu.

### D40 · 2026-10-23 — Przeglądarka plików, Git, worksety
Git obsługuje `/usr/bin/git` (status `--porcelain=v2 -z`, `show HEAD:`, `add`, `commit -F -` z komunikatem przez stdin,
`log`) z `GIT_TERMINAL_PROMPT=0` — bez operacji sieciowych i bez danych logowania w argumentach. SVN pominięty (na
macOS praktycznie nieużywany przy Oracle; wzorzec traktuje go równolegle do Gita), podobnie stan VCS w projektach (Etap
6, projekty). Operacje na plikach i Git są tylko dla użytkownika (agent — Brak), bo ścieżki lokalne ujawniają katalog
domowy, a agent pracuje na bazie i edytorach. Usuwanie zawsze do Kosza, nigdy trwale. Worksety zapisują niezapisany
tekst okien w katalogu danych (`Worksets/*.json`, pliki 0600) — przy autozapisie zamknięcie aplikacji nie pyta o zapis
okien, bo ich stan wraca przy starcie. Okna planu, raportu, diagramu i notatnika nie trafiają do workseta (własne
formaty — Etapy 6–7). Układ okna: ramka, szerokość i karta lewej kolumny, panel agenta (`layout.json`).
### D41 · 2026-10-23 — Diagram jako model w dokumencie, plik JSON .pdd
Okno diagramu trzyma model `Diagram` w dokumencie (nie w tekście okna); Zapisz/Otwórz zapisują go jako JSON z
rozszerzeniem `.pdd` (format własny, czytelny i wersjonowany polem `version`). Współrzędne są w jednostkach przy zoomie
100 %, siatka ma 8 px, a przesuwanie dociąga do niej, gdy siatka jest włączona. Metadane (kolumny z PK, klucze obce,
zależności) idą przez protokół `SchemaMetadataSource` — w aplikacji słownik bazy (`SessionSchemaMetadata` na sesji
metadanych), w testach atrapa — więc model, układ i generator SQL są testowane bez bazy.

### D42 · 2026-10-23 — Query Builder: generator i odczyt prostych SELECT
Query Builder buduje `QueryModel` (tabele z aliasami z pierwszych liter członów nazwy, złączenia z kluczy obcych w obie
strony, pola, sortowanie, grupowanie, WHERE/HAVING/INTO, DISTINCT) i generuje SELECT według preferencji (wielkość liter
słów kluczowych, kolumna w linii, złączenia ANSI albo w WHERE, schemat przed tabelą). Odczyt istniejącego zapytania
obejmuje tylko proste SELECT: tabele rozdzielone przecinkami albo `[LEFT|RIGHT|FULL] JOIN … ON a.x = b.y`, bez
podzapytań w FROM, WITH i operacji zbiorowych — inne zapytania otwierają pusty Query Builder z komunikatem.
### D43 · 2026-10-23 — Narzędzia danych w sesji narzędzi; format własny
Eksport, importy, generator i porównanie danych działają w osobnej sesji narzędzi połączenia (`SessionPurpose.tool`),
nie w sesjach okien — importy zatwierdzają własne transakcje (COMMIT co n wierszy) i nie mogą zatwierdzić pracy
użytkownika. Zmiany danych przechodzą przez `guardModification` (produkcja pyta, połączenie tylko do odczytu odmawia).
Format własny eksportu tabel to JSON (DDL, kolumny z typami, wartości tekstowe: liczby z kropką, daty
`YYYY-MM-DD HH24:MI:SS.FF9`, RAW/BLOB w base64) skompresowany LZFSE z nagłówkiem `PLKT1Z` (bez kompresji — `PLKT1J`,
odczyt na każdym systemie); LOB-y przy imporcie wiązane jako tekst do 32 KiB. Exp/imp zastępuje Data Pump przez
DBMS_DATAPUMP (synchronicznie, dziennik z katalogu bazy przez UTL_FILE); pliki zrzutu zostają na serwerze bazy.

### D44 · 2026-10-23 — Text/Excel Importer: filtr i duplikaty w jednym bloku PL/SQL
Każdy wiersz importu to blok `INSERT … SELECT … FROM dual WHERE filtr` ze zmiennymi wiązanymi nazwanymi jak pola
(`:KWOTA`), więc filtr SQL działa w bazie bez przepisywania; duplikaty klucza głównego są pomijane albo nadpisywane
(UPDATE po kluczu) w obsłudze `DUP_VAL_ON_INDEX`. Liczby są wiązane jako NUMBER z kropką dziesiętną (przecinek
z pliku zamieniany), daty przez `TO_DATE` z formatem pola, a liczby Excela w polu daty zamieniane na datę (dni od
1899-12-30). Plik xlsx czyta własny czytnik ZIP (wpisy stored i deflate przez framework Compression) i XML
(sharedStrings, arkusze) — bez bibliotek zewnętrznych; czytnik deflate działa tylko na macOS.

### D45 · 2026-10-23 — Składnia generatora danych
Generator przyjmuje własną składnię opisaną w `DataGenerator` (wzorce w nawiasach kwadratowych ze zbiorami `a A @ #
* 0 1 9`, powtórzenia `(n)`/`(min..max)`, funkcje Random/Sequence/List/SQL/Text/Uppercase/Lowercase/InitCaps/Parent/
Field i zbiory Firstname…Email z własnymi, krótkimi listami). Podgląd używa stałego ziarna (powtarzalny), zapis do
bazy — losowego. `List(select …)` wykonuje zapytanie raz, `SQL(…)` — dla każdego rekordu (wolne, ale z dostępem do
`:pól` rekordu). Zbiory użytkownika z plików CSV i funkcja File — na później.

### D46 · 2026-10-23 — Druga baza testowa dla subagentów; gałąź integracyjna
Subagent, który potrzebuje bazy, dostaje własny kontener (`PELIKAN_TESTDB_CONTAINER=pelikan-testdb-2`, port 1532)
i własny `.testdb/` w swoim worktree — testy na wspólnej bazie muszą iść szeregowo, a dwie bazy mieszczą się w VM Colimy
(8 GiB, ok. 2,3 GiB na bazę). Kontener zostaje zatrzymany do ponownego użycia. Gałęzie budowane równolegle i nawzajem
konfliktujące (lista komend, UIServices, AppDelegate, dokumenty) są łączone lokalnie w jedną gałąź integracyjną,
sprawdzaną pełnym zestawem testów i budowaniem aplikacji, a potem scalaną jednym PR; pojedyncze PR-y są zamykane
z odnośnikiem — ich commity i scalenia są w historii PR integracyjnego.

### D47 · 2026-10-23 — Polecenia własne okna poleceń; bez SET ENVVAR
BEAUTIFY, BROWSE, DIR, EDIT obiekt, EDITDATA, INFO, PROPERTIES, QUERYDATA, RECOMPILE, TEST, VIEW, ZIP i EXPORT
TABLES/OBJECTS działają przez te same komendy rejestru i modele co menu (Object Browser, eksport), pliki — w katalogu
ustawionym przez CD. SET ENVVAR nie jest obsługiwane: zmienna środowiskowa procesu Pelikana trafiłaby do procesów
potomnych, w tym CLI agentów, a hasła nie mogą być w zmiennych środowiskowych. ZIP używa `/usr/bin/zip` z argumentami
w tablicy (bez powłoki).

### D48 · 2026-10-23 — Monitor zdarzeń bez DBMS_OUTPUT innych sesji; test obciążenia
DBMS_OUTPUT jest buforem prywatnym sesji — monitor w osobnej sesji nie może odczytać wyjścia innej sesji, więc
monitor obsługuje DBMS_ALERT i DBMS_PIPE (wiadomość: elementy tekstowe, liczbowe i daty sklejone ` | `), a wyjście
programów pokazują okna, które je wykonują. Test obciążenia uruchamia każdy wątek w osobnej sesji narzędzi,
wiąże `:thread` i `:iteration`, po iteracji domyślnie wycofuje zmiany, a przed startem przechodzi przez strażnika
zmian (prod potwierdza, tylko do odczytu blokuje); wyniki zapisuje jako CSV (Excel).
### D49 · 2026-10-23 — Wykresy: Swift Charts, definicja po nazwach kolumn, odświeżanie przez okno SQL
Okno wykresu bierze migawkę karty wyników (kolumny i pobrane wiersze) i rysuje ją w Swift Charts (słupkowy, liniowy,
warstwowy, punktowy, kołowy — kołowy z pierwszej serii). Definicja wykresu odwołuje się do kolumn po nazwie, więc
zapisana jako szablon (`ChartTemplates.json` w katalogu danych) pasuje do innych zapytań o tych samych kolumnach;
brakujące kolumny są przy zastosowaniu pomijane. Auto-odświeżanie zaznacza polecenie karty w oknie SQL i wykonuje je
tak jak F8 (ta sama sesja, strażnik zmian, historia), zamiast osobnej sesji — wykres pokazuje to, co zobaczyłby
użytkownik w siatce. Wartości nieliczbowe w seriach są pomijane i zliczane w stopce okna.

### D50 · 2026-10-23 — Narzędzia użytkownika bez powłoki i bez danych logowania
Narzędzie zewnętrzne uruchamia się przez `Process` z programem (ścieżka albo nazwa szukana w katalogach systemowych)
i argumentami jako tablicą — bez powłoki, więc `$(…)`, `;` i spacje w wartościach zmiennych nie są interpretowane.
Zmienne dają plik, zaznaczenie, tekst, obiekt z Przeglądarki obiektów, alias połączenia i schemat — nigdy hasło, host,
port, usługę ani nazwę użytkownika połączenia; środowisko programu nie zawiera zmiennych `PELIKAN_*` (np. tokenu
agenta). Narzędzie sesji nie wykonuje SQL samo: otwiera okno SQL z blokiem (opcjonalnie wykonuje je komendą okna),
żeby obowiązywały te same zasady co przy ręcznym wykonaniu. Poziom agenta „Brak”.
### D51 · 2026-10-23 — Raporty: renderer HTML w Swift, plik .rep w JSON, druk przez WebKit
Raport to definicja (`ReportDefinition`: zapytanie, styl, formaty kolumn, układ, opcje) zapisywana jako JSON `.rep`,
a wynik — HTML generowany w czystym Swifcie (testowalny bez bazy) i pokazywany w `WKWebView`; druk i PDF idą przez
okno druku WebKit. Zmienne raportu korzystają z mechanizmu okna SQL (`&<…>`, `:bind`, parametry Jaspera, okno
„Zmienne”), a wykonanie — z sesji narzędzi `tool("report")`, więc raport nie dotyka transakcji okien. Formaty liczb to
wzorce `NumberFormatter` (np. `#,##0.00`), dat — wzorce Unicode (np. `yyyy-MM-dd`), w lokalizacji systemu. Grupowanie
(Break) zakłada, że zapytanie sortuje po kolumnach grup (ORDER BY), jak we wzorcu.

### D52 · 2026-10-23 — Blokada definicji raportu bez hasła
Blokada ukrywa zapytanie i układ oraz uniemożliwia ich zmianę w oknie; odblokowanie wymaga potwierdzenia, ale nie hasła
— hasło lub jego skrót w pliku `.rep` byłoby sekretem w pliku, a plik JSON i tak da się otworzyć w edytorze tekstu.
Blokada chroni przed przypadkową zmianą, nie przed świadomym odczytem definicji.
