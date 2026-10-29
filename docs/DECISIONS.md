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

### D36 · 2026-10-23 — Zamknięcie Etapu 5 (agenci AI); praca równoległa
Kryteria spełnione testami: każde CLI z listy dostaje serwer MCP tylko dla sesji (specyfikacje uruchomienia, token poza
argumentami), agent czyta stan, edytory i obiekty bazy przez własną sesję, operacje „Za zgodą” czekają na decyzję
(atrapa okna zgody), testy bezpieczeństwa z SECURITY §5 przechodzą (kanał: 16, baza: 8). Testy E2E z prawdziwymi CLI
(AI-E2E-001, opcjonalne) nie są uruchamiane automatycznie — używałyby kont dostawców właściciela; zostają do ręcznego
uruchomienia. Od tego etapu część zadań bez bazy (interfejs panelu, funkcje edytora, przeglądarka plików) budują
równolegle subagenty w osobnych worktree, a zadania z testami na wspólnej bazie testowej — sesja główna, szeregowo.

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

### D53 · 2026-10-23 — Oracle Wallet: magazyn haseł przez katalog Oracle Net Pelikana, TLS per połączenie
Próby z Instant Client 23 pokazały, że portfel magazynu haseł (SEPS, logowanie `/@alias`) działa tylko przez
`WALLET_LOCATION` w `sqlnet.ora` katalogu TNS_ADMIN klienta — portfel wskazany w deskryptorze (`MY_WALLET_DIRECTORY`,
`WALLET_LOCATION`) albo w EZConnect (`wallet_location`) dotyczy wyłącznie TLS. Dlatego Preferencje › Oracle mają
katalog konfiguracji Oracle Net użytkownika i katalog portfela; Pelikan generuje z nich własny katalog
(`oracle-net/` w katalogu danych: `sqlnet.ora` z portfelem i `IFILE` do plików użytkownika, `tnsnames.ora` z `IFILE`)
i przekazuje go klientowi przy inicjalizacji (`oracleClientConfigDir`) — zmiana działa po ponownym uruchomieniu.
Połączenie w trybie „Oracle Wallet” to dla sterownika uwierzytelnianie zewnętrzne, a alias trafia do klienta bez
rozwijania (poświadczenie jest szukane po dokładnym tekście). Portfel TLS (mTLS, np. Autonomous Database) jest
ustawieniem połączenia (import ZIP rozpakowuje portfel obok archiwum). Hasła z portfela nigdy nie trafiają do Pelikana;
w plikach generowanych są tylko ścieżki. Test na bazie testowej używa portfela z `scripts/testdb.sh wallet`; właściciel
potwierdził działanie na własnym aliasie (jednorazowa próba `select 'OK' from dual`, bez zapisu danych).

### D54 · 2026-10-23 — Pro*C przez SSH: założenia do pytań otwartych
Zakres z `docs/tasks/proc-ssh.md` (dawniej `zadanie-pelikan-proc-ssh.md` w katalogu głównym). Do czasu odpowiedzi właściciela (D1 — bez pytań w trakcie pracy):
1. Wersja gita na AIX nieznana — skrypty używają `cd` zamiast `git -C` i tylko opcji z gita 1.7; „Testuj” pokazuje
   `git --version`, a skrypty sprawdzają wersję przed użyciem nowszych opcji.
2. Korzeń repo: osobne pole „katalog working copy” (domyślnie `<baza>/src`); kontrola czystości dotyczy tylko jego,
   `bin` poza nim.
3. Binarki: lista nazw w konfiguracji celu (domyślnie jedna, nazwa projektu); instalacja kopiuje każdą.
4. Kodowanie repo: ustawienie projektu, wykrywane z istniejących plików (bajty spoza UTF-8, poprawne w ISO-8859-2 →
   ISO-8859-2); domyślnie UTF-8.
5. Build próbny: po pierwszej wersji pipeline'u.
Pelikan nie łączy się z serwerem właściciela; skrypty ksh88 i parsery są testowane na lokalnym `sshd` i próbkach
z dokumentacji, a akceptację na AIX 6.1 i prawdziwe próbki wyjścia (fixture'y) dostarcza właściciel.

### D55 · 2026-10-23 — Plik nie zmienia kodowania po cichu
Zapis znaku spoza kodowania pliku (np. „ ” w ISO-8859-2) jest blokowany z linią, kolumną i znakiem — wcześniej plik
przechodził na UTF-8, co dla źródeł Pro*C na AIX psułoby repozytorium. Zmiana kodowania tylko jawnie (Plik › Kodowanie
pliku). Pliki jednobajtowe bez BOM: 0x80–0x9F → Windows-1250, polskie litery na pozycjach ISO-8859-2 → ISO-8859-2;
projekt może narzucić kodowanie swoich plików (`ProjectOptions.encoding`), a `TextFileCodec.detectEncoding` ustala je
z istniejących plików.

### D56 · 2026-10-23 — Touch ID / hasło Maca przed użyciem zapisanego hasła
Na prośbę właściciela przełącznik w Preferencjach › Oracle („Hasła połączeń”). Atrybut kontroli dostępu w Pęku kluczy
(`.userPresence`) działa tylko w pęku chronionym danymi, a ten wymaga aplikacji podpisanej certyfikatem dewelopera
Apple — Pelikan jest podpisywany ad hoc (płatne konto poza zakresem, PROMPT §13). Dlatego hasła zostają w pęku logowania
(usługa `<bundle id>.connection`, konto = id połączenia, dostęp po odblokowaniu Maca, bez iCloud), a menedżer sesji przed
użyciem zapisanego hasła prosi o potwierdzenie przez LocalAuthentication (Touch ID albo hasło Maca), raz na połączenie
w trakcie działania aplikacji — także dla sesji agenta. Stan „hasło zapisane” na liście połączeń sprawdzany bez odczytu
sekretu. Ograniczenie: inna aplikacja, której użytkownik pozwoli czytać wpis Pelikana w Pęku kluczy, nie przejdzie
przez to potwierdzenie (macOS i tak pyta wtedy o zgodę na dostęp do wpisu).

### D57 · 2026-10-23 — Filtr siatki lokalny, w modelu siatki
Filtr wyników (DB-GRID-001) działa na pobranych wierszach jako część permutacji widoku (`order`) modelu siatki,
razem z sortowaniem: `rowCount` to liczba wierszy widoku, a `fetchedRowCount` — pobranych. Dociągnięte wiersze
przechodzą przez filtr. Wyrażenie ma składnię podobną do SQL (porównania, LIKE, IS NULL, AND/OR), ale nie jest
wysyłane do bazy — nie da się przez nie wykonać kodu. NULL nie spełnia porównań (jak w SQL). Grupowanie liczy
wartości w wierszach widoku.

### D58 · 2026-10-23 — Generowanie SQL i kodu bez danych logowania; podgląd HTML bez skryptów
SQL z wierszy (DB-GRID-002) używa klucza głównego tabeli, a gdy nie ma go w wyniku — ROWID (MERGE wymaga klucza
głównego). Kod generowany z obiektu (SD-GEN-001) ma zmienne wiązane zamiast wartości, a połączenie w Java/Python
wskazuje alias — bez hasła, hosta i użytkownika. Przeciągnięcie obiektu z Option wstawia SELECT albo wywołanie
programu; zwykłe przeciągnięcie — nazwę. Panel wartości pokazuje HTML z bazy bez JavaScriptu i bez zasobów
sieciowych (Content-Security-Policy), bo treść z bazy jest niezaufana. SET SQLFORMAT formatuje tylko wyniki zapytań
okna poleceń; `ansiconsole` to wyrównane kolumny z nagłówkiem (bez kolorów ANSI w konsoli okna).

### D59 · 2026-10-23 — Autotrace bez Tuning Pack; kursor odnajdywany znacznikiem
Autotrace wykonuje polecenie w sesji narzędzi ze wskazówką `GATHER_PLAN_STATISTICS` i unikalnym komentarzem, po którym
odnajduje kursor w V$SQL (niezależnie od kolejności zapytań pomocniczych), a plan rzeczywisty czyta z
V$SQL_PLAN_STATISTICS_ALL i DBMS_XPLAN.DISPLAY_CURSOR('ALLSTATS LAST') — bez Real-Time SQL Monitoring (Tuning Pack).
DML jest wykonywane przez strażnika zmian i zawsze wycofywane. A-Rows różniące się od E-Rows×Starts ponad 10 razy są
wyróżniane (wskazówka do statystyk optymalizatora).

### D60 · 2026-10-23 — Panel DBA i Instance Viewer tolerują brak uprawnień; zadania w tle w Workspace
Sekcje panelu DBA i części Instance Viewera czytają słownik DBA_/V$ i przy ORA-00942/01031 pokazują komunikat o braku
uprawnień zamiast błędu (użytkownik bez SELECT_CATALOG_ROLE widzi to, do czego ma dostęp). Zmiany (ALTER SYSTEM SET,
blokada konta) to komendy z potwierdzeniem i strażnikiem zmian. Task Monitor to wspólna lista `WorkspaceTaskCenter`
w Workspace (nazwa bez kolizji z `BackgroundTask` SwiftUI); długie operacje uruchamia się przez `ws.tasks.run`.

### D61 · 2026-10-23 — Warstwa SSH jako moduł PelikanRemote (tylko macOS)
Kod z Bifolda (`Spawn`, `NameEncoding`, `SSHSession`, katalog gniazd, parser `ls -la`) trafił do osobnego celu SPM
`PelikanRemote` bez zależności od PelikanWorkspace — jak PelikanAgent, w `#if canImport(Darwin)`, więc Linux CI buduje
pusty moduł. Zależności BifoldCore zastąpił `SSHError` z przypadkami strukturalnymi (negotiationFailed,
permissionDenied, hostKeyChanged, timeout, cancelled, io, invalidName, unencodable) — teksty dla użytkownika powstaną
w warstwie interfejsu przez `L10n.tr`. Sekrety SSH trafią do istniejącego `SecretStore` (Pęk kluczy) przy menedżerze
połączeń; sesja dostaje sekret przez domknięcie, a do `ssh` idzie on przez kolejkę FIFO (w środowisku procesu tylko
ścieżka kolejki, `PELIKAN_ASKPASS_FIFO`). Parser zwraca własny typ `RemoteFileEntry` zamiast `FileItem` z VFS Bifolda.

### D62 · 2026-10-23 — Stop zdalnego builda i prolog środowiska
Każde polecenie strumieniowe zaczyna się od `echo "@@PID $$"` — powłoka polecenia jest liderem sesji i grupy
procesów na serwerze (sshd robi `setsid`). Stop kończy lokalne `ssh` (przy `-tt` zamknięcie pty wysyła SIGHUP do
grupy), a zapasowo osobnym połączeniem wysyła `kill -TERM -<pid>`, sprawdza grupę `kill -0` i po 5 s `kill -KILL`;
znacznik jest odcinany z wyjścia. Prolog środowiska ustawia zmienne w dwóch krokach (`NAZWA='wartość'; export NAZWA;`)
z wartościami dosłownymi (bez rozwijania `$PATH`) — konfiguracja celu podaje pełne wartości; nazwy tylko
`[A-Za-z_][A-Za-z0-9_]*`. Na AIX 6.1 (ksh88, stary OpenSSH) zachowanie Stop wymaga potwierdzenia przez właściciela.

### D63 · 2026-10-23 — Funkcje Diagnostics/Tuning Pack za deklaracją licencji
AWR, ASH, ADDM (Diagnostics Pack), SQL Monitor i SQL Tuning Advisor (Tuning Pack) działają tylko wtedy, gdy parametr
bazy CONTROL_MANAGEMENT_PACK_ACCESS na nie pozwala i użytkownik zadeklarował licencję dla połączenia — przy pierwszym
użyciu Pelikan pyta, a odpowiedź zapamiętuje w definicji połączenia (zmiana w edytorze połączenia). Agent nie ma do nich
dostępu (PROMPT §7.3). W PDB migawki AWR mają DBID kontenera (`CON_DBID`), więc raporty używają go zamiast DBID z
V$DATABASE. Oracle Free ma pakiety w licencji — testy działają na bazie testowej.

### D64 · 2026-10-23 — Widoki dualności, MLE i dane przestrzenne: zakres
Generator widoku dualności tworzy DDL z tabeli głównej (klucz główny → `_id`) i tabel podrzędnych połączonych kluczem
obcym (tablice obiektów, insert/update/delete na każdym poziomie) i otwiera go w oknie SQL — Pelikan nie wykonuje DDL
sam. Słownik 23ai: `ALL_MLE_MODULES.MODULE_OWNER`, `ALL_MLE_ENVS.ENV_OWNER`, flagi widoków dualności jako TRUE/FALSE.
Debugowanie po wykonaniu: DBMS_MLE.ENABLE_DEBUGGING ze specyfikacją JSON (nazwa modułu kwalifikowana schematem,
migawka albo obserwacja), kod wywołujący w jednym bloku z wyłączeniem debugowania także przy wyjątku, wynik z
PARSE_DEBUG_OUTPUT jako lista trafień. Podgląd przestrzenny rysuje WKT z SDO_UTIL (bez układów współrzędnych i podkładu mapy).

### D65 · 2026-10-23 — Analiza kodu w czasie pisania bez łączenia z bazą; agent tylko inspekcje
Rozwiązywanie nazw (DG-RES-001) i inspekcje (DG-INSP-001) liczy `Workspace.analyzeCode` z opóźnieniem po zmianie
tekstu. Inspekcje są lokalne (lekser, zarys PL/SQL). Nazwy sprawdza się w słowniku tylko wtedy, gdy połączenie okna
ma już otwartą sesję główną — analiza nigdy nie łączy z bazą ani nie pyta o hasło; odpowiedzi słownika są w pamięci
podręcznej na 5 minut. Źródło metadanych to protokół `NameResolutionSource` (atrapa w testach). Ostrzeżenia są
zachowawcze: kwalifikator w SQL osadzonym w PL/SQL może być zmienną rekordową, więc nie jest zgłaszany, a funkcje
tabelaryczne i linki baz są pomijane. Agent (`edit.analyzeCode`) dostaje tylko inspekcje tekstu — słownik czyta
wyłącznie przez własną sesję i narzędzia `agent.*`.

### D66 · 2026-10-23 — Find Usages dla użytkownika, agent przez istniejące find_usages
`edit.findUsages` (DG-USE-001) łączy ALL_DEPENDENCIES, linie kodu obiektów zależnych (tylko wystąpienia
identyfikatora, bez komentarzy i literałów), ALL_IDENTIFIERS z PL/Scope (gdy kod skompilowano z PLSCOPE_SETTINGS) oraz
otwarte okna i pliki projektu. Komenda działa w sesji głównej użytkownika, więc nie jest narzędziem agenta (poziom
`.none`); agent ma `agent.findUsages` z własną sesją i regułami dostępu.

### D67 · 2026-10-23 — Refaktoryzacja zmienia teksty, DDL tylko do przejrzenia
Zmiana nazwy (DG-REF-001) zmienia tokeny identyfikatorów w oknach i plikach projektu po podglądzie różnic. Zmiennej
lub parametru — w zakresie deklaracji, bez pól po kropce i notacji nazwanej `=>`; obiektu — `NAZWA` i
`WŁAŚCICIEL.NAZWA`, bez nazw kwalifikowanych innym schematem; kolumny — tylko w poleceniach z tą tabelą. Skrypt
DDL (ALTER TABLE … RENAME, RENAME) trafia do nowego okna SQL bez wykonania: zmiana w bazie przechodzi zwykłą ścieżką
ze strażnikiem zmian. Przed zmianą tekstu wersja trafia do historii lokalnej. Agent — za zgodą, z podglądem
zmienionych linii.

### D68 · 2026-10-23 — Historia lokalna w katalogu danych, bez bazy
Historia lokalna (DG-HIST-001) to jeden plik JSON na plik albo obiekt w `LocalHistory/` katalogu danych aplikacji
(nazwa: czytelny fragment klucza + skrót FNV-1a). Wersje powstają przy zapisie pliku, kompilacji jednostki (klucz:
połączenie, właściciel, typ, nazwa), refaktoryzacji, przed przywróceniem i ręcznie; tekst identyczny z ostatnią
wersją jest pomijany; najwyżej 50 wersji i 30 dni. Przywrócenie zapisuje najpierw bieżący tekst, więc da się je
cofnąć. Historia może zawierać kod, ale nie hasła (te są tylko w Pęku kluczy).

### D69 · 2026-10-23 — Konsola połączenia to okno SQL z tekstem w katalogu danych
Konsola (DG-CONS-001) to zwykłe okno SQL przypięte do połączenia, jedno na połączenie, z tekstem w
`Consoles/<id połączenia>.sql`. Tekst zapisuje się przy zamknięciu okna, co 30 s i przy zakończeniu aplikacji, więc
okno nie pyta o zapis. Wyniki zapytań nie są zachowywane.

### D70 · 2026-10-23 — Zmiany oczekujące liczone względem wartości pierwotnych
Wyróżnienie zmian w siatce (DG-GRID-001) korzysta z istniejącego stanu edycji (`changed`, `inserted`, `deleted`).
Komórka zmieniona i przywrócona do wartości pierwotnej nie jest już zmianą (znacznik i licznik). Nagłówek wiersza
pokazuje `+`, `~`, `−` z kolorem tła; nawigacja po zmianach i cofnięcie zmian wybranych wierszy to komendy rejestru.

### D71 · 2026-10-23 — Notatnik SQL jako plik JSON z wynikami
Notatnik (`.sqlnb`) to JSON z komórkami SQL/PL/SQL i Markdown; wynik komórki (kolumny, typy, do 200 wierszy jako
tekst, komunikaty, DBMS_OUTPUT, błąd, czas) i opcjonalny wykres zapisują się w pliku, więc notatnik otwiera się z
wynikami bez bazy. Komórka wykonuje się w sesji okna przez strażnika zmian; polecenia SQL*Plus w komórce są
pomijane. Run All zatrzymuje się na pierwszym błędzie. Eksport do Markdown (tabele wyników). Komendy notatnika mają
poziom agenta Brak — agent pracuje przez własne narzędzia zapytań.

### D72 · 2026-10-23 — Raporty predefiniowane na słowniku ALL_/USER_
Katalog raportów predefiniowanych (SD-REP-001) jest wbudowany w kod i używa tylko widoków ALL_/USER_ (bez uprawnień
DBA), z zmienną `:owner` domyślnie równą bieżącemu schematowi. Styl: siatka, wykres (definicja wykresu w raporcie)
albo DBMS_OUTPUT. Raport szczegółów dostaje wartości wiersza jako `:parent_<kolumna>`. Raporty standardowe okna
raportu (PD-REP-001, HTML) zostają osobno — to inny mechanizm wzorca.

### D73 · 2026-10-23 — Database Diff wyrównuje kolumny tabel; koszyk w katalogu danych
Diff korzysta z porównania obiektów (PD-TOOL-012); dla różnych tabel generuje ALTER TABLE ADD/MODIFY (typ, DEFAULT,
NULL/NOT NULL), a kolumny tylko w celu — DROP COLUMN jako komentarz, chyba że użytkownik zaznaczy usuwanie.
Różnice więzów i indeksów pozostają do ręcznego przejrzenia. Koszyk (`cart.json` w katalogu danych, eksport `.cart`)
przechowuje obiekty po nazwie; skrypt wdrożenia ma DDL w kolejności typów i dane INSERT (tabele nadrzędne pierwsze).

### D74 · 2026-10-23 — Kolejność kopiowania schematu
Kopiowanie: sekwencje i typy, tabele bez więzów FK (`REF_CONSTRAINTS=false`), dane (format własny tabel),
pozostałe obiekty, klucze obce, na końcu wyzwalacze — żeby wyzwalacze nie odpalały się na kopiowanych danych.
DDL bez nazwy schematu, wykonywane z `CURRENT_SCHEMA` celu (przywracanym po zakończeniu). Istniejące obiekty są
pomijane (raport), chyba że wybrano zastępowanie (DROP tabel, sekwencji, indeksów, typów; kod przez CREATE OR REPLACE).

### D75 · 2026-10-23 — Kreator importu obok importerów tekstu i Excela
Importery PD-TOOL-008/009 zostają; kreator SD-IMP-001 łączy je i dodaje pliki o stałej szerokości (wykrywanie kolumn
po wspólnych spacjach), jawny wybór kodowania (UTF-8, UTF-16, ISO-8859-2, Windows-1250/1252), podgląd i profile
(`ImportProfiles/*.json` w katalogu danych, bez danych połączenia).

### D76 · 2026-10-23 — Polecenia SQLcl w oknie poleceń
INFO+ (statystyki kolumn z ALL_TAB_COL_STATISTICS), DDL [plik] (DBMS_METADATA), LOAD tabela plik [NEW] (wykrycie
separatora, NEW tworzy tabelę z typów danych), FORMAT BUFFER/FILE (formater Pelikana), HISTORY [TIME|n|CLEAR]
(historia okna z czasami — w pamięci okna), ALIAS nazwa=polecenie / LIST / DROP (aliasy okna), REPEAT n [s]
(bufor), CTAS tabela nowa (polecenie do bufora). Linia aliasu bez średnika łączy się przy podziale skryptu z
następnym poleceniem — po aliasie wykonuje się reszta.

### D77 · 2026-10-23 — Układ diagramu ER warstwami kluczy obcych
Diagram ER z bazy umieszcza tabele w kolumnach według poziomu w grafie FK (rodzice po lewej; cykle przerywane),
w kolumnie alfabetycznie; wysokie kolumny dzielone dla proporcji obrazu. Powyżej 60 tabel bez listy kolumn.
Eksport obrazu — istniejący eksport diagramu (PD-DIAG-003).

### D78 · 2026-10-23 — Przenoszenie danych literałami, definicje bez haseł
Przenoszenie (DB-XFER-001) czyta źródło partiami i wstawia wiersze do celu jako INSERT z literałami (jak porównanie
danych) — działa między dowolnymi połączeniami i typami kosztem szybkości. Definicje (`Transfers/*.json`) wskazują
połączenia nazwą; zmiana celu przechodzi przez strażnika zmian.

### D79 · 2026-10-23 — Zadania lokalne tylko w działającej aplikacji
Zadania lokalne (DB-TASK-001) uruchamia planista w aplikacji (co 30 s sprawdza terminy) — bez agenta launchd, bo to
trwała zmiana konfiguracji systemu (PROMPT §13). Definicje (`Tasks/tasks.json`) zawierają nazwę połączenia, nigdy
hasła; hasło pochodzi z Pęku kluczy w chwili uruchomienia. Stan i dzienniki osobno (`Tasks/state.json`,
`Tasks/logs/`). Skrypt bez zaznaczonego COMMIT jest wycofywany; z COMMIT — przez strażnika zmian.

### D80 · 2026-10-23 — Cele SSH: osobny moduł, plik bez sekretów, osobna usługa Pęku kluczy
Model `PelikanSSHTarget`, magazyn celów, „Testuj” i parsery błędów są w nowym module `PelikanProC` (zależy od
`PelikanWorkspace` i `PelikanRemote`), żeby `PelikanWorkspace` nie zależał od warstwy SSH, która działa tylko na macOS;
komendy (`ssh.manager`, `ssh.test`, `ssh.export`, `ssh.import`, agent — Brak) są w rejestrze i otwierają okno przez
`UIServices.showSSHTargets`. Cele i foldery w `ssh-targets.json` w katalogu danych — bez haseł; hasło SSH albo hasło
klucza w pęku logowania w usłudze `<bundle id>.ssh` (konto = id celu), osobnej od haseł baz (`.connection`), z tym samym
potwierdzeniem właściciela co hasła baz, gdy włączone (D56) — raz na cel w trakcie działania aplikacji. Sekret podany
bez „Zapamiętaj” zostaje tylko w pamięci. Eksport/import nie przenosi sekretów, a import nadaje nowe identyfikatory
(dołącza, nie nadpisuje). Gałąź porównywana dokładnie (`MASTER` ≠ `master`). Katalog roboczy Pelikana
`<backupy>/.pelikan` nie może leżeć w working copy (walidacja). Brak katalogu backupów przy „Testuj” — utworzenie po
potwierdzeniu, dla PROD dodatkowo wpisaniem nazwy celu (`ProductionConfirmation`, gotowe dla pipeline'u wdrożenia).
Wersja serwera SSH czytana z banera TCP (przed logowaniem, bez sekretów) — log negocjacji `ssh` jest kasowany przez
`SSHSession` po połączeniu. `which make` zamiast `make -v`, bo `make` z AIX może nie mieć opcji wersji.

### D81 · 2026-10-23 — Parsery proc/xlc z formatu dokumentowanego
Parsery rozpoznają: Pro*C `Error at line L, column C in file F` / `Semantic error at line L, column C, file F:` /
`Syntax error …` z następującym kodem `PCC-x-NNNNN` (przy SQLCHECK=SEMANTICS także `PLS-x-NNNNN`; F = błąd krytyczny,
także bez lokalizacji); XL C `"plik", line L.C: NNNN-NNN[N] (I|W|E|S|U) treść` (kolumna opcjonalna, numery komunikatów
trzy- i czterocyfrowe) oraz układ `-qsrcmsg` (linia `  N | źródło`, znacznik `....a..`, komunikat `a - NNNN-NNN (S)`,
plik z ostatniego polecenia kompilacji `xlc… -c plik.c` w wyjściu `make`). Ścieżka z komunikatu (względna wobec katalogu
`make` albo bezwzględna) jest mapowana na ścieżkę względną working copy; pliki spoza repozytorium (nagłówki Oracle) nie
dają skoku. Fixture'y odtwarzają format z dokumentacji — do zastąpienia prawdziwymi próbkami z AIX właściciela.
Sukces builda wyznacza kod wyjścia `make`, nie parser.

### D82 · 2026-10-23 — Entra ID i ORDS bez środowisk do prób
**Entra ID:** Pelikan nie implementuje OAuth sam — używa obsługi tokenów w Instant Client 23 (`TOKEN_AUTH=AZURE_INTERACTIVE`
z `TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_DB_APP_ID_URI`; albo `TOKEN_AUTH=OAUTH` z `TOKEN_LOCATION`). Parametry trafiają
do sekcji SECURITY deskryptora albo do EZConnect; alias rozwijany z konfiguracji Oracle Net. Logowanie bez użytkownika
i hasła; token nie przechodzi przez Pelikana i nie jest zapisywany. Bez konta Azure (płatne konto — PROMPT §13) nie da
się sprawdzić logowania, więc wiersz ⚠️ do potwierdzenia przez właściciela.
**ORDS:** baza testowa (gvenzl/oracle-free) nie ma ORDS; Pelikan wykrywa jego brak, pokazuje moduły i obiekty AutoREST
z widoków USER_ORDS_*, a włączenie REST generuje jako skrypt do okna SQL (jak DDL — bez samodzielnego wykonania).

### D83 · 2026-10-23 — Skrypt wdrożenia jako jeden plik ksh88 z kodami wyjścia
Pipeline wysyła jeden skrypt (`run-<id>.ksh`, `scp -O` do `<backupy>/.pelikan`) zamiast serii poleceń: blokada,
kontrola working copy, `git pull --ff-only`, backup, `make`, instalacja i wpis historii działają w obrębie jednej
blokady, a Stop zabija jedną grupę procesów. Każdy krok wypisuje `@@STEP nazwa` / `@@END nazwa kod`; dodatkowe
znaczniki (`@@HEAD_BEFORE/AFTER`, `@@LOCKINFO`, `@@DIRTY_BEGIN/END`, `@@BACKUP`, `@@INSTALLED`, `@@MISSING`, `@@NO_FF`,
`@@DONE`) czyta `DeployProgress`. Wynik wyznacza kod wyjścia skryptu (stałe `DeployScripts.Exit`), build — kod `make`.
Znacznik czasu i właściciel (`użytkownik@host-Maca`) pochodzą z Maca (bez `date +%s`); numer linii retencji wyliczany
w Pelikanie (bez arytmetyki w skrypcie). W sesji z pty (`ssh -tt`) git uruchomiłby pager i czekał — skrypt ustawia
`GIT_PAGER=cat`, `PAGER=cat` i używa `git --no-pager`. Konstrukcje spoza ksh88 pilnuje test `forbiddenConstructs`;
składnię sprawdza `ksh -n` i przebiegi na lokalnym sshd — to ksh93 z macOS, więc akceptacja na AIX 6.1 należy do
właściciela (D54).

### D84 · 2026-10-23 — Blokada i jej zdejmowanie; binarki z katalogu `make`
Blokada to katalog `.lock` z plikiem `info` (`id`, właściciel, czas, PID powłoki skryptu na serwerze). Istniejąca
blokada z żywym procesem → „zablokowane” (kod 10), z martwym albo bez PID → „przeterminowana” (11); żadna nie jest
zdejmowana automatycznie — ręczne zdjęcie po potwierdzeniu (PROD: nazwa celu). Skrypt zdejmuje własną blokadę pułapką
(`trap … 0` i sygnały 1 2 15); po Stop albo zerwaniu połączenia Pelikan zdejmuje ją osobnym poleceniem, ale tylko gdy
`info` zawiera identyfikator tego wdrożenia. Binarki do instalacji bierze z `<baza>/src` (katalog `make`; inny
katalog — parametr planu), kopiuje wszystkie do `.new`, dopiero potem zamienia (`nazwa` → `.prev`, `.new` → `nazwa`),
więc brak którejkolwiek nie zostawia `bin` w połowie. Wycofanie z kopii rozpakowuje do `.new` po skopiowaniu bieżącej
binarki (zachowanie praw bez `stat`). Lokalne repo projektu = katalog otwartego projektu Pelikana; remote i gałąź
lokalnie mają te same nazwy co na serwerze. Przed PROD Pelikan sprawdza, czy commit był już z powodzeniem wdrożony na
celu UAT z tego samego folderu drzewa celów. Build próbny (D54 p.5) — nadal poza zakresem.

### D85 · 2026-10-23 — Synonimy w Query Builderze, porównanie worksetów, Git w projekcie
Query Builder rozwija synonim (prywatny, PUBLIC, łańcuch do 8 poziomów) do tabeli lub widoku tylko po to, żeby pobrać
kolumny — w SQL zostaje nazwa synonimu, a synonim PUBLIC jest bez schematu. Złączeń z kluczy obcych dla synonimów nie
dodaje sam (klucze opisują tabelę, nie synonim) — złączenie ręczne. Porównanie worksetów zestawia tekst opisujący okna
(typ, nazwa, stan, treść okna albo pliku) przeglądarką różnic. Stan Git projektu liczony poza wątkiem głównym przy
otwarciu widoku i na żądanie (bez cyklicznego odpytywania).

### D86 · 2026-10-23 — Zamknięcie Etapów 6, 7 i P (po stronie Pelikana)
Wszystkie wiersze Etapów 6 i 7 mają test albo są pominięte decyzją. Częściowe zostają jawnie w macierzy:
PD-DIAG-002 (punkty łamania linii zapisywane i rysowane, bez edycji myszą), PD-QB-001 (bez podzapytań), SD-AUTH-001
(Entra ID bez próby na Azure — brak konta, PROMPT §13) i SD-ORDS-001 (baza testowa bez ORDS). Etap P: warstwa SSH,
cele SSH, parsery, pipeline wdrożenia, konsola i lokalny git przetestowane na lokalnym `sshd` (ksh93 z macOS);
akceptacja na AIX 6.1 / ksh88 i próbki komunikatów proc/xlc — właściciel (D54). Zawieszanie testów SSH w CI usunięte
(sshd testowy bez dziedziczenia stdout/stderr, zestawy SSH w CI osobno z limitem i diagnostyką). Okna nowe w tych
etapach nie mają zrzutów (D30) — do zrobienia w Etapie 8 w czasie, gdy właściciel nie pracuje na komputerze.
Szkic wydania po scaleniu zamknięcia.

### D87 · 2026-10-23 — Klucze tłumaczeń odtwarzalne ze źródeł; język przez AppleLanguages
`L10n.tr` przyjmuje własny typ `L10n.Key` (interpolacja) zamiast `String.LocalizationValue`: Xcode nie wyciągał tekstów
z wywołań własnej funkcji ani z pakietu SPM, więc katalog był pusty. Klucz to polski tekst, każda interpolacja → `%@`,
`%` → `%%`; ten sam klucz buduje `scripts/l10n.py` z literałów źródeł (mini-lekser z zagnieżdżonymi interpolacjami),
co pozwala utrzymywać `Localizable.xcstrings` skryptem i sprawdzać go w CI. Argumenty jako tekst (`String(describing:)`)
— bez formatowania liczb zależnego od języka; tłumaczenia mogą zmieniać kolejność (`%2$@`). Podstawianie własne, bez
`String(format:)`, żeby błędny specyfikator w tłumaczeniu nie wywrócił aplikacji. Okna i narzędzia wzorca zostają w
tłumaczeniach pod angielskimi nazwami (SQL Window, Object Browser…). Wybór języka w Preferencjach zapisuje standardowe
`AppleLanguages` w domenie aplikacji (jak Ustawienia systemowe › Język › Aplikacje) — działa po ponownym uruchomieniu.

### D88 · 2026-10-23 — Pomoc F1 w dokumentacji Oracle online
F1 otwiera stronę docs.oracle.com dobraną z rodzaju słowa pod kursorem (kody błędów → Oracle Error Help, DBMS_/UTL_ →
PL/SQL Packages and Types Reference, V$/ALL_/DBA_/USER_ → Reference, polecenia i funkcje SQL → SQL Language Reference,
polecenia PL/SQL → PL/SQL Language Reference), w pozostałych przypadkach wyszukiwanie ograniczone do wybranej wersji
bazy. Wzorce adresów sprawdzone na docs.oracle.com (19, 21, 23, 26). Pelikan nie dołącza lokalnej kopii podręczników
(licencja Oracle i rozmiar); aplikacja otwiera tylko adresy http(s), nigdy pliki ani inne schematy z tekstu edytora.
### D89 · 2026-10-23 — Programy zewnętrzne edytora: tylko http(s) dla adresów, bez powłoki dla programów
Wyszukiwania w sieci i dokumenty użytkownika otwierają wyłącznie adresy http(s) albo istniejące pliki — adres z
Preferencji nie uruchomi programu przez inny schemat URL. Zewnętrzna przeglądarka różnic jest uruchamiana jak
narzędzia użytkownika (D49): program wskazany ścieżką albo z katalogów systemowych, argumenty jako tablica po
podstawieniu dyrektyw `%1`/`%2` (pliki) i `%3`/`%4` (tytuły), bez powłoki i bez zmiennych środowiska Pelikana
(`Process` z pakietu Foundation, jak w narzędziach użytkownika — ten sam poziom ochrony co `posix_spawn`: brak
interpretacji przez powłokę). Pliki porównań i edycji zewnętrznej w katalogu danych (`Diff/`, `External/`), 0600.

### D90 · 2026-10-23 — „Nie pytaj więcej” pamięta odpowiedź, a nie samo ukrycie
Pytanie z zaznaczonym „Nie pytaj więcej” zapamiętuje wybrany przycisk (anulowanie nigdy) i do czasu przywrócenia w
Preferencjach › Narzędzia odpowiada nim bez pytania. Wyłączyć można tylko pytania o czynności odwracalne albo
potwierdzające wybór użytkownika (zatwierdzenie/wycofanie przy włączonej opcji potwierdzania, Kosz, przywrócenie
workseta, odzyskiwanie okien) — nie potwierdzenia zmian na produkcji ani zgody agentów.

### D91 · 2026-10-23 — Odzyskiwanie po awarii: znacznik sesji i migawka co interwał
Przy starcie powstaje znacznik `Recovery/running`; czyste zamknięcie go usuwa. Znacznik zastany przy starcie oznacza
nieczyste zamknięcie — wtedy migawka niezapisanych okien (`Recovery/windows.json`, 0600, zapisywana co interwał z
Preferencji) jest proponowana do odzyskania (pytanie albo Plik › Odzyskaj okna…). Migawka nie powstaje przy każdym
wykonaniu polecenia (wzorzec ma taką opcję) — interwał wystarcza, a zapis przy wykonaniu spowalniałby pracę na dużych
skryptach. Połączenie okna odtwarzane jest tak jak w worksetach — dla okien z przypiętym połączeniem.
### D92 · 2026-10-23 — Zestawy preferencji jako warstwy częściowych wartości
Zestaw to słownik `pole Settings → wartość JSON`; obowiązujące preferencje to wartości wbudowane z nałożonymi zestawami
w kolejności wzorca (domyślny globalny < domyślny połączenia < osobisty < osobisty połączenia). Zestaw osobisty to
`settings.json`, od teraz zapisywany częściowo (tylko pola zmienione przez użytkownika; stary pełny plik wczytuje się
jako zestaw osobisty z wszystkimi polami). Pozostałe zestawy w `Preferences/sets.json` katalogu danych. Zmiana w
Preferencjach trafia do zestawu wybranego w karcie Zestawy (domyślnie osobisty), a połączeniowe przeliczają się po
zmianie połączenia głównego. Wzorzec porównywany z `użytkownik@baza` i nazwą połączenia. Eksport i import obejmują
wybrane sekcje (jak karty Preferencji), nigdy historii plików; hasła nie są preferencjami (Pęk kluczy).

### D93 · 2026-10-23 — Parametry startowe bez haseł; URL z marki
Argumenty jak we wzorcu (`klucz=wartość`, bez rozróżniania wielkości liter) i w stylu `--klucz[=wartość]`; argumenty
AppKit (`-Klucz wartość`, `-psn_…`) są pomijane. `userid=u/hasło@baza` daje połączenie `u@baza` i ostrzeżenie — hasło
nie jest używane (widać je w `ps`), więc łączenie idzie przez Pęk kluczy albo pytanie. Połączenie z definicji po nazwie
albo `użytkownik@baza`. `readonly=` blokuje polecenia zmieniające tylko w tym uruchomieniu (bez zapisu definicji).
Schemat URL (`PELIKAN_URL_SCHEME`) jest w `Config/Brand.xcconfig`, kod czyta go z Info.plist.

### D94 · 2026-10-23 — Usługi macOS i pasek narzędzi
Usługi: „Formatuj SQL” (zwraca sformatowany tekst do aplikacji źródłowej), „Otwórz w SQL Window” i „Otwórz plik”;
nazwy w menu Usługi z marki, po polsku (lokalizacja nazw usług — Etap 8, ServicesMenu.strings). Pasek narzędzi okna
głównego dostaje elementy z rejestru komend z symbolami SF i standardowe dostosowanie macOS (paleta z ~30 najczęstszymi
komendami, układ zapamiętywany przez system). Quick Access Toolbar to jedna grupa paska z dowolnymi komendami rejestru
(do 20) wybieranymi w Preferencjach › Zestawy albo komendą `view.addToQuickAccess` — prostsze niż osobne paski
użytkownika wzorca, a pokrywa ich zastosowanie.
### D95 · 2026-10-23 — Quick Look jako podgląd oparty na danych, bez rejestracji w systemie
Rozszerzenie `PelikanQuickLook` (com.apple.quicklook.preview, `QLIsDataBasedPreview`) zwraca HTML z `CodeHTML`
(PelikanSQL — ten sam lekser co edytor), więc nie potrzebuje WebKitu ani PelikanWorkspace. Obsługuje typy UTI
aplikacji (.sql, pakiety, programy, .tst), pierwsze 2 MB pliku. Rozszerzenia muszą działać w sandboxie; podpis jest ad
hoc jak aplikacji — macOS może odmówić załadowania rozszerzenia bez podpisu dewelopera Apple (płatne konto — PROMPT
§13), a rejestracja na próbę (`pluginkit -e use`, uruchomienie aplikacji) to trwała zmiana systemu w czasie pracy
właściciela (D30). Działanie w Finderze sprawdzi właściciel; wiersz ⚠️. Identyfikator i typy UTI liczone z nowej
zmiennej `PELIKAN_BUNDLE_ID` w `Config/Brand.xcconfig` (także w Info.plist aplikacji — wcześniej wpisane na sztywno).

### D96 · 2026-10-23 — Dostępność pilnowana audytem źródeł
VoiceOver potrzebuje etykiety dla elementów bez tekstu. Przyciski i menu SwiftUI z samą ikoną dostają `.iconLabel(_:)`
(podpowiedź i etykieta z jednego przetłumaczonego tekstu), tabele i drzewa AppKit — `setAccessibilityLabel`,
przyciski AppKit z obrazkiem — `accessibilityDescription`. `AccessibilityAuditTests` czyta App/Sources i odrzuca
nowe elementy bez etykiety (testy pakietu nie uruchamiają interfejsu). Próba z VoiceOverem i Accessibility Inspector —
w Etapie 8 w czasie, gdy właściciel nie pracuje na komputerze.


### D97 · 2026-10-23 — Domknięcie połączeń: Kill, NLS, LDAP, Kerberos, Workspace Manager
Zakończenie sesji okna używa SID zapamiętanego przy otwarciu sesji (SYS_CONTEXT — bez uprawnień do V$SESSION) i numeru
seryjnego z GV$SESSION w chwili zabicia, z osobnej sesji narzędziowej; ORA-00031 to sukces (ODPI-C zgłasza go jako
zamknięcie połączenia, więc sesję narzędziową zamykamy). Wymaga uprawnienia ALTER SYSTEM — bez niego błąd bazy w oknie.
Parametry NLS z Preferencji (biała lista nazw, wartości bez apostrofów i bez przycinania) — ALTER SESSION po połączeniu;
kodowanie klienta to zawsze UTF-8 (ODPI-C), więc NLS_LANG jako zmienna środowiska nie jest potrzebna i nie jest
ustawiana. LDAP: `ldap.ora` dowiązany do katalogu Oracle Net Pelikana (klient czyta go tylko z TNS_ADMIN, bez IFILE).
Kerberos i Workspace Manager działają tymi samymi ścieżkami co przetestowane uwierzytelnianie zewnętrzne i skrypt po
połączeniu, ale bez KDC i bez DBMS_WM w bazie testowej — wiersze ⚠️ do potwierdzenia przez właściciela.

### D98 · 2026-10-23 — Testy standardowe jako szablony z %CALL%
Wzorzec pozwala zapisać skrypt testu jako „Standard Test” i wybrać go z menu procedury lub funkcji. Pelikan zapisuje
szablon jako zwykły plik `.tst` w `StandardTests/` katalogu danych; znacznik `%CALL%` w bloku to miejsce, w które trafia
wywołanie programu generowane jak w „Testuj” (notacja nazwana, zmienne parametrów i wyniku). Bez znacznika wywołanie
jest dopisywane na końcu. Zmienne szablonu dochodzą do zmiennych wywołania (bez duplikatów nazw).

### D99 · 2026-10-23 — Operacje na obiektach: kompilacja próbna, zmiany w bazie, kolejki
Kompilacja próbna zmienia nazwę jednostki w poleceniu CREATE na tymczasową `PELIKAN$SAFE_…` (specyfikacja i ciało
pakietu wspólnie), odczytuje błędy z USER_ERRORS z nazwą pierwotną w treści i od razu usuwa obiekty tymczasowe — także
przy błędzie. Wyzwalacze są pomijane: tymczasowy wyzwalacz działałby na prawdziwej tabeli. Wykrywanie zmian porównuje
LAST_DDL_TIME z chwilą wczytania/kompilacji (cykl jak sprawdzanie połączeń) i tylko ostrzega — nie nadpisuje tekstu bez
decyzji użytkownika. Kolejki AQ (enqueue/dequeue z menu obiektu) odłożone: wymagają edytora ładunku dla typów
obiektowych; test łącza i DBMS_JOB.RUN zaimplementowane bez próby (baza testowa nie ma łączy ani zadań DBMS_JOB).
### D100 · 2026-10-23 — „(all)” i parametry w Code Assistant
Pozycja „(all)” pojawia się po kwalifikatorze, gdy lista ma co najmniej dwie kolumny albo pola (tabela, alias, widok
inline, rekord, kursor): pierwszy element bez kwalifikatora (jest już wpisany), kolejne z nim. Po `nazwa(` Code
Assistant podaje parametry podprogramu lokalnego (zarys kodu) albo z bazy (ALL_ARGUMENTS, poziom 0, pierwsza
przeciążona wersja wygrywa przy powtórzeniach nazw) jako `parametr => `, a „(all)” — wszystkie w notacji nazwanej;
w układzie „po jednym w linii” `=>` jest wyrównane. Konstruktory typów obiektowych — nie zrobione (wymagają atrybutów
typu z ALL_TYPE_ATTRS i rozróżnienia wywołania funkcji od konstruktora).

### D101 · 2026-10-23 — Search Bar jako okno narzędzia
Pelikan nie ma dokowanych paneli narzędzi (D15, PD-UI-003), więc Search Bar to okno narzędzia z tekstem, zakresem
(bieżący edytor, wszystkie edytory, pliki w katalogach — domyślnie lokalizacje File Browsera), opcjami i listą wyników
jak w Find Usages. Komenda `edit.searchBar` z parametrami działa też dla agenta (poziom Odczyt), ale tylko w oknach —
przeszukiwanie plików użytkownika jest poza jego zakresem. Limity: 5000 plików, 5000 trafień, pliki do 5 MB.

### D102 · 2026-10-23 — Tryb tylko do odczytu okna
„Tylko do odczytu” blokuje edycję w edytorze i komendy zmieniające zaznaczenie oraz refaktoryzacje; stan zapamiętywany
w stanie okna pliku. Narzędzia agenta zmieniające tekst okna (PelikanWorkspace/Agent) nie sprawdzają jeszcze trybu —
poza zakresem tego zadania, wiersz PD-FILE-003 ⚠️. Ctrl+K n / Ctrl+Q n (zakładki) przechwytuje edytor tylko w profilu
skrótów PL/SQL Developer — w profilu macOS Ctrl+K usuwa do końca linii (skrót systemowy NSTextView).

### D103 · 2026-10-24 — Filtry i foldery Object Browsera w katalogu danych
Filtry nazwane i foldery użytkownika są zapisywane w `browser.json` w katalogu danych (bez danych logowania). Warunek
filtra jest fragmentem SQL użytkownika wklejanym do zapytania o obiekty w jego własnej sesji — tak jak we wzorcu;
agent nie korzysta z filtrów. `:browser_user` to zmienna wiązana (bieżący schemat), `&browser_filter` — tekst pola
filtra z podwojonymi apostrofami; gdy filtr go używa, pole nie filtruje już nazw osobno. Folder może łączyć listę
obiektów i zapytanie zwracające OWNER, OBJECT_NAME, OBJECT_TYPE; widoczność według wzorca połączenia jak w zestawach
preferencji. Ukrywanie właściciela w nazwach folderu jest w modelu, a widok pokazuje nazwy jak w drzewie bieżącego
użytkownika.

### D104 · 2026-10-24 — Edytor tabeli 23ai: zakres partycji i domen
Partycjonowanie jest edytowane tylko przy tworzeniu tabeli (RANGE z opcjonalnym INTERVAL, LIST, HASH); dla istniejącej
tabeli edytor pokazuje opis z ALL_PART_TABLES — zmiany partycji (ADD/SPLIT/MERGE) to osobne operacje administracyjne,
których edytor nie generuje, a subpartycje i tabele zewnętrzne zostają poza zakresem. Adnotacje są przechowywane jako
lista nazwa=wartość; zmiana wartości to DROP i ADD (Oracle nie ma zamiany w miejscu). Uprawnienia ze zmienioną opcją
nadawania są odbierane i nadawane ponownie. Domena: szablon CREATE DOMAIN i DDL z DBMS_METADATA (typ SQL_DOMAIN);
asercje (26ai) czekają na wersję bazy testowej, która je obsługuje.

### D105 · 2026-10-24 — HOST w Command Window dla użytkownika, z potwierdzeniem (zmienia D31)
Wiersz PD-CMDW-008 wymaga HOST dla użytkownika (agent nigdy). HOST, `!` i `$` uruchamiają polecenie przez `/bin/sh -c`
w katalogu ustawionym przez CD, ze środowiskiem bez zmiennych `PELIKAN_*` i bez TNS_ADMIN katalogu zarządzanego, z limitem
120 s i wyjściem w oknie. Każde wywołanie — także ze skryptu `@plik` — wymaga potwierdzenia z pełną treścią polecenia,
żeby cudzy skrypt nie uruchomił niczego po cichu. Agent nie ma dostępu do Command Window (AI-SEC-011, test), więc nie
dociera do HOST. Wyjątek instalatora utPLSQL (D31: `! rm plik` bez powłoki i bez pytania) zostaje bez zmian.

### D106 · 2026-10-24 — Debuger JDWP pominięty, DBMS_TRACE z tabelami tracetab
Debugowanie przez DBMS_DEBUG_JDWP wymagałoby, żeby Pelikan był serwerem protokołu Java Debug Wire Protocol (baza łączy
się do IDE przez TCP) — to osobny, duży komponent sieciowy, a debuger na DBMS_DEBUG (ADR 0006) działa na wszystkich
obsługiwanych wersjach, także 26ai. Wiersz PD-DBG-002 pominięty do czasu, gdy Oracle usunie DBMS_DEBUG. DBMS_TRACE używa
tabel SYS.PLSQL_TRACE_RUNS/EVENTS z `tracetab.sql`; bez nich Pelikan podaje, co zainstalować (instaluje administrator),
a baza testowa dostaje je w `scripts/testdb.sh seed`. Uprawnienia debugera Pelikan tylko przygotowuje jako skrypt
w oknie SQL — nadaje je administrator, nie aplikacja.
### D107 · 2026-10-24 — Kursor zagnieżdżony w nowej karcie wyniku
Wzorzec otwiera wynik `<Cursor>` w nowym SQL Window. Pelikan dokłada kartę wyniku w tym samym oknie: kursor jest częścią
sesji okna (zamknięcie okna zamyka kursor), a nowe okno nie miałoby polecenia do ponownego wykonania.

### D108 · 2026-10-24 — Bez blokady przewijania kolumn i wierszy
NSTableView nie ma zamrażania kolumn ani wierszy; dwie zsynchronizowane tabele komplikowałyby edycję, sortowanie i
przenoszenie kolumn. Kolumna numerów wierszy i nagłówek zostają widoczne przy przewijaniu; filtr kolumn (PD-GRID-011)
pozwala zawęzić siatkę do potrzebnych kolumn.

### D109 · 2026-10-24 — Wyrównanie kolumn bez wysokości wierszy i zmiany okna
„Align” ustawia szerokości (nagłówek, treść z pierwszych 500 wierszy, oba) i zapisuje szablon kolejności i szerokości
dla zapytania (klucz: tekst zapytania ze zwiniętymi odstępami), stosowany automatycznie (preferencja). Wysokość
wierszy, „Hide Editor” i „Adjust Window width” pominięte — siatka ma stałą wysokość wiersza zależną od czcionki.

### D110 · 2026-10-24 — LOB na żądanie jako podgląd 4000 bajtów
Sterownik zawsze zwraca lokator i rozmiar LOB; przy „LOB na żądanie” siatka pobiera tylko 4000 bajtów (zamiast 1 MB),
oznaczonych jako obcięte, a Large Data Editor dociąga całość przez ROWID. Zero bajtów odebrałoby panelowi wartości
podgląd i znacznik obcięcia.

### D111 · 2026-10-24 — Wartości zmiennych okna w worksecie zamiast .pfi
Wzorzec trzyma wartości zmiennych w pliku `.pfi` obok skryptu. Pelikan zapisuje je w stanie okna w worksecie (także dla
okien bez pliku); odświeżenie karty i automatyczne odświeżanie używają zapamiętanych wartości bez pytania (NF8).


### D112 · 2026-10-24 — Narzędzia w kartach i kolory z motywu systemu
Wzorzec pozwala dokować i odrywać każde narzędzie oraz ustawiać kolor i tło czcionek. Pelikan trzyma narzędzia w kartach
lewej kolumny (zwijanej) i w osobnych oknach narzędzi — to układ zgodny z HIG i z trybem jasnym/ciemnym; dowolne
dokowanie paneli wymagałoby własnego menedżera układu na AppKit (dokowanie narzędzi — D183). Kolory tekstu i tła biorą się z motywu systemu
(czytelność w obu trybach, VoiceOver); w Preferencjach są czcionka i rozmiary. Oba wiersze ⚠️.

### D113 · 2026-10-24 — Przebieg zrzutów w tle
`scripts/screenshots.sh` uruchamia aplikację Debug przez `open -g -n` (bez aktywacji) z osobnym katalogiem danych
(`PELIKAN_DATA_DIR`) i skryptem komend (`PELIKAN_UI_SCRIPT`, hak tylko w kompilacji Debug): aplikacja nie aktywuje się,
nie pyta o odzyskanie okien, łączy się z bazą testową przez portfel z magazynem haseł (bez hasła w plikach, środowisku
i Pęku kluczy), wykonuje komendy i zapisuje znacznik końca. Zrzuty pojedynczych okien robi `screencapture -l` według listy
okien procesu (CGWindowList) — nic nie steruje klawiaturą ani myszą (D30). WebKit nie rysuje okien w tle w takim zrzucie,
więc treść WKWebView zapisuje krok `debug.snapshotWebViews` (zrzut w procesie). Instant Client jest kopiowany do
`.testdb/instantclient`, bo odczyt chronionego folderu Pobrane przez aplikację Debug wywołuje pytanie macOS o dostęp.
Przebieg znalazł dwa błędy: karty edytora tabeli chowały się pod przepełnieniem (teraz przełącznik segmentowy) i
instrukcja nie znajdowała rozdziałów (folder zasobów `manual` małą literą).

### D114 · 2026-10-24 — Zamknięcie Etapu 8 i planu
Wszystkie wiersze macierzy mają stan po audycie: ✅ z testem, 👁 zrzut, ⚠️ częściowo z opisem braków albo pominięte
decyzją — żadnego „do zrobienia”. Interfejs jest w pięciu językach, z instrukcją w aplikacji i kompletem tłumaczeń
sprawdzanym w CI. `docs/STATUS.md` (generowany z macierzy) zbiera ograniczenia i listę rzeczy do potwierdzenia przez
właściciela (AIX, Entra ID, ORDS, Kerberos/LDAP/DBMS_WM, Quick Look, asercje 26ai). Dalsze prace to domykanie wierszy ⚠️
według priorytetów właściciela; szkic wydania po scaleniu zamknięcia.

### D115 · 2026-10-24 — Command Window: bufor, BREAK/COMPUTE, bez COPY
Bufor SQL ma linie i bieżącą linię (LIST, APPEND, CHANGE, DEL, INPUT jak w SQL*Plus; `APPEND ;;` dokleja średnik).
GET/SAVE dopisują `.sql`, SAVE bez REPLACE nie nadpisuje pliku; STORE SET zapisuje polecenia SET do odtworzenia przez
`@plik`. BREAK/COMPUTE działają w formatowaniu tekstowym wyniku (nie w SET SQLFORMAT): ukrywanie powtórzeń, SKIP, sumy
grup od najgłębszej i REPORT na końcu. Samotny `/` w Command Window wykonuje bufor, chyba że kończy polecenie zakończone
`;` (wtedy pozostaje separatorem) — wcześniej był pomijany zawsze. COPY pominięte: Oracle oznacza je jako przestarzałe,
a składnia wymaga haseł w poleceniu (`user/hasło@baza`), co łamie zasadę haseł tylko w Pęku kluczy; kopiowanie danych
między połączeniami robi Transfer danych (DB-XFER-001).
### D116 · 2026-10-24 — Status linii, margines i podgląd zwiniętego kodu
Stan bazowy okna (`Document.baselineText`) to tekst z chwili otwarcia, wczytania z bazy albo zapisu — ustawiany przy
każdym `isModified = false`, więc obejmuje wszystkie ścieżki otwierania i zapisu. Margines rysuje pasek: pomarańczowy —
linia zmieniona, zielony — nowa (diff linii w tle; wspólny początek i koniec pomijane, przy bardzo dużej zmianie cały
środek oznaczony bez kosztownego diffu). Wzorzec rozróżnia też „zmienione i zapisane” — Pelikan po zapisie zeruje
znaczniki (stan bazowy = zapisany tekst), bo historia lokalna i porównanie z plikiem pokazują starsze zmiany. Numer co n
linii (pierwsza i bieżąca zawsze), pionowy margines w kolumnie i znaki specjalne (·, →, ¶) rysuje edytor TextKit 2.
Podgląd zwiniętego obszaru: podpowiedź nad znacznikiem „⋯” z ukrytymi liniami (do 20).

### D117 · 2026-10-24 — Wcięcia Smart i bez kursora za końcem linii
Tryb Smart wcina nową linię o jednostkę po słowie otwierającym (BEGIN, THEN, LOOP, ELSE, DECLARE, IS, AS, EXCEPTION,
CASE, „(”), a linię zaczynającą się od END/ELSE/ELSIF/EXCEPTION z wcięciem nadanym automatycznie wyrównuje do poziomu
struktury przy Enter (wcięcie poprawione ręcznie zostaje). Backspace w wiodących spacjach usuwa do poprzedniej
wielokrotności jednostki. Zawijanie wierszy — przełącznik w Widoku i Preferencjach. Kursor za końcem linii (virtual
space) pominięty: NSTextView nie ma pozycji poza tekstem, a emulacja dopisywałaby spacje do pliku.

### D118 · 2026-10-24 — Code Assistant: notacja nazwana, kolekcje, SELF, synonimy publiczne
Parametry w notacji nazwanej są podpowiadane po „(” i po każdym przecinku wywołania (nawias szukany po tokenach, bez
literałów i komentarzy), bez parametrów już podanych z `=>`. Z wpisanym prefiksem pozycje parametrów trafiają na początek
zwykłej listy — zmienne jako argumenty pozycyjne nadal są dostępne. Kolekcje lokalne: COUNT, FIRST, LAST, NEXT, PRIOR,
EXISTS, DELETE, a dla tablic zagnieżdżonych i VARRAY także EXTEND i TRIM (LIMIT tylko VARRAY). `self.` w ciele typu —
atrybuty i metody ze specyfikacji w tym samym oknie, a bez niej z bazy. Bez kwalifikatora po obiektach schematu idą
synonimy publiczne (obiekty dostępne).

### D119 · 2026-10-24 — Code Contents: sortowanie i menu przez komendy
Kolejność: jak w źródle, alfabetycznie, według rodzaju (preferencja `codeContentsOrder`, menu panelu). Menu elementu:
Przejdź, Zaznacz, Kopiuj, Wytnij, Testuj — komendy `codeContents.*` z pozycją elementu (dostępne też dla agenta); element
obejmuje pełne linie, Testuj otwiera okno testu z pakietem jako obiektem i podprogramem jako elementem.

### D120 · 2026-10-24 — Nawigacja hiperłączami: źródło, okna, baza
Wzorzec ma preferencję, gdzie otwierać deklarację. Pelikan szuka kolejno: lokalna deklaracja w zasięgu, jednostka albo
jej podprogram w źródle bieżącego okna, w innych otwartych oknach (programu, SQL, testu — ciało przed specyfikacją dla
podprogramu), a dopiero potem obiekt z bazy w nowym oknie. Bez osobnej preferencji — kolejność zawsze daje najbliższą
deklarację, a otwarte okno ma pierwszeństwo przed źródłem z bazy (niezapisane zmiany). Menu obiektu na nazwie w edytorze
ma listę działań w warstwie modelu (`EditorObjectMenu`), sprawdzaną testem względem rejestru komend; doszło „Testuj”.

### D121 · 2026-10-24 — Dodawanie i usuwanie jednostek, szablony Java i MLE
„+” na pasku kart okna programu dodaje jednostkę z szablonu folderu jednostek programów (na końcu, po „/”); menu karty
usuwa jednostkę razem z kończącym ukośnikiem i pustymi liniami (z potwierdzeniem; obiekt w bazie zostaje). Agent używa
`prog.addUnit` (szablon z wartościami albo gotowy tekst) i `prog.removeUnit`. Nowe szablony: źródło Java
(`CREATE AND COMPILE JAVA SOURCE`, nagłówek rozpoznawany przez kompilator okna) i moduł MLE w JavaScript.

### D122 · 2026-10-24 — Przywróć (Revert)
`prog.revert` przywraca stan bazowy okna (z chwili otwarcia, wczytania z bazy albo zapisu) albo — z `source=database` —
źródło jednostek okna z bazy (ALL_SOURCE, jak przy porównaniu). Użytkownik potwierdza odrzucenie zmian; cofnięcie w
edytorze nadal działa. Po przywróceniu stanu bazowego okno jest niezmienione; po wczytaniu z bazy — zgodne z bazą, ale
nadal zmienione względem pliku.

### D123 · 2026-10-24 — Osobne reguły formatera dla parametrów i INSERT
Do wspólnej reguły list SQL doszły trzy osobne: deklaracje parametrów podprogramów, parametry wywołań w PL/SQL i listy
kolumn oraz wartości INSERT — „do marginesu” (domyślnie, jak dotąd) albo „element w linii” wyrównany za nawiasem.
Formater nadal porównuje tokeny wyniku ze źródłem.

### D124 · 2026-10-24 — Okno szablonów: pływające okno i przeciąganie
Dokowanie realizuje para: panel w pasku bocznym i to samo drzewo w osobnym, pływającym oknie (Widok › Okno szablonów) —
jak inne narzędzia (D112). Przeciągnięcie szablonu do edytora wstawia go w miejscu upuszczenia przez
`edit.insertTemplate` (formularz zmiennych); poza edytorem przeciąga się tekst szablonu.

### D125 · 2026-10-24 — Reload w przeglądarce różnic
Porównania, których źródło da się odczytać ponownie (okno z bazą, okno z plikiem, obiekt z oknem, dwa pliki), przekazują
przeglądarce funkcję ponownego wczytania obu stron; przycisk ⟳ zachowuje zamianę stron i opcje ignorowania. Porównania
stałych tekstów (historia lokalna, wyniki narzędzi) nie mają Reload.

### D126 · 2026-10-24 — Preferencje: wyszukiwarka z generowanego indeksu, bez przycisku Zastosuj
Zmiany ustawień zapisują się od razu, jak w ustawieniach macOS (przycisk Zastosuj wzorca nie ma odpowiednika).
Wyszukiwarka nad kartami dopasowuje etykiety kontrolek (bez wielkości liter i znaków diakrytycznych, w języku
interfejsu i po polsku) i przełącza na kartę ustawienia. Indeks etykiet generuje `scripts/prefs-index.py` z paneli
`App/Sources/Preferences`; CI sprawdza, że jest aktualny, więc nowe ustawienie bez regeneracji indeksu zatrzyma CI.
### D127 · 2026-10-24 — Układ liczb w siatce
„Formatowane” stosuje separator dziesiętny z ustawień regionalnych, „z separatorem tysięcy” dodatkowo grupuje cyfry
części całkowitej. Pełna precyzja zostaje (tekst liczby z bazy), notacja wykładnicza i Inf/Nan bez zmian. Układ dotyczy
tylko wyświetlania w siatce — w trybie edycji komórka pokazuje tekst surowy, a kopiowanie i eksport wartości bez
separatorów (żeby dało się je wkleić i wczytać).

### D128 · 2026-10-24 — Blok komórek przez Shift+klik
NSTableView zaznacza wiersze, nie komórki. Blok to zaznaczone wiersze i zakres kolumn od komórki kotwicy (zwykły klik)
do komórki klikniętej z Shift, w kolejności widocznej; wiersz w trybie bloku nie jest podświetlany w całości, tylko
komórki bloku. Kopiowanie i eksport biorą kolumny bloku. Agent i makra używają `grid.selectBlock` / `grid.selectColumn`.

### D129 · 2026-10-24 — Zakres edytora tabeli: składowanie, klaster, tabela zewnętrzna, Recreate
Składowanie: PCTFREE, INITRANS, INITIAL/NEXT, LOGGING i kompresja wierszy; INITIAL zmienia się tylko przez Recreate.
Klaster, tabela obiektowa i zewnętrzna — tylko przy tworzeniu. Zmiana przestrzeni istniejącej tabeli to
`MOVE TABLESPACE … UPDATE INDEXES`. Recreate table: kopia `CREATE TABLE PLK$nazwa AS SELECT`, `DROP … CASCADE CONSTRAINTS`
(tabela w koszu — można ją przywrócić), CREATE wg nowej definicji, przeniesienie zachowanych i przemianowanych kolumn,
DDL wyzwalaczy (DBMS_METADATA pobrany przed usunięciem) i klucze obce innych tabel, na końcu usunięcie kopii. Przed
wykonaniem edytor pyta o zgodę. Parametry partycji indeksów lokalnych i składowanie LOB-ów — poza zakresem.

### D130 · 2026-10-24 — Duplicate jako skrypt, nie wykonanie
„Duplikuj” otwiera w nowym oknie SQL skrypt kopii (DDL z DBMS_METADATA albo źródło z ALL_SOURCE) z nową nazwą w
nagłówku CREATE i w `END nazwa;`; w tabeli nazwy więzów zawierające starą nazwę dostają nową, pozostałe — przedrostek
nowej nazwy (inaczej kolidowałyby z oryginałem). Użytkownik przegląda i wykonuje skrypt sam, dla tabel opcjonalnie z
`INSERT … SELECT`. Zmiana nazwy widoków, sekwencji i synonimów to `RENAME` — tylko w bieżącym schemacie.

### D131 · 2026-10-24 — Słownik wg wersji: opis możliwości i warianty zapasowe
Foldery zależą od `DictionaryFeatures`: wersji serwera i obecności widoków ALL_MLE_*, ALL_DOMAINS, ALL_PROPERTY_GRAPHS,
ALL_ANNOTATIONS, ALL_ASSERTIONS (jedno zapytanie do ALL_VIEWS na 23+; bez dostępu — wnioskowanie z wersji, asercje od
23.26). Zapytania z kolumnami nowszych wersji mają warianty zapasowe wykonywane przy ORA-00904/00942. Adnotacje nie są
obiektami ALL_OBJECTS, a asercje mają tam typ UNDEFINED — foldery czytają ALL_ANNOTATIONS i ALL_ASSERTIONS, DDL powstaje
ze słownika (DBMS_METADATA zwraca ORA-31600). Seed bazy testowej nadaje CREATE ASSERTION tam, gdzie uprawnienie istnieje.

### D132 · 2026-10-24 — Przeciąganie z Object Browsera
Domyślnie upuszczenie wstawia nazwę (jak dotąd), z Option — kod (SD-GEN-001), z Control albo przy preferencji „Pytaj” —
menu: nazwa, z właścicielem, lista kolumn, SELECT/INSERT/UPDATE/DELETE, wywołanie, DDL. Preferencja może też ustawić
jedną z tych akcji na stałe. Obiekt upuszczony poza edytorem (pasek kart, pusty obszar okien) wykonuje akcję z
preferencji: Edytuj, Pokaż dane, DDL, Opis albo Właściwości. Folder elementów albo folder obiektów daje nazwy po przecinku.


### D133 · 2026-10-24 — Debuger: SELF i obiekty, bez :new/:old, warunki i logpointy po stronie Pelikana
Sonda na 23.26: `DBMS_DEBUG.GET_VALUE('SELF.ATRYBUT')` działa w metodzie typu, więc SELF i zmienne obiektowe są
drzewem atrybutów z ALL_TYPE_ATTRS. `NEW.KOL`/`OLD.KOL` zwracają „brak obiektu”, a nazwa z dwukropkiem (`:NEW.KOL`)
**zawiesza** sesję debugera — Pelikan nie wysyła do GET_VALUE/SET_VALUE nazw z dwukropkiem (obserwowane i warunki
też), a w wyzwalaczu pokazuje informację, że :new/:old są niedostępne. DBMS_DEBUG nie ma warunków ani komunikatów
punktów: Pelikan po zatrzymaniu wypisuje komunikat (`{zmienna}` → wartość), dla „Nie zatrzymuj” kontynuuje, a warunek
liczy jako `select case when … then 1 else 0 end from dual` z wartościami zmiennych ramki podstawionymi jako literały
(błąd warunku — zatrzymanie z komunikatem). Punkt odrzucony przez SET_BREAKPOINT ma pusty znacznik. Jedna linia —
jeden punkt (DBMS_DEBUG trzyma jeden punkt na linię).

### D134 · 2026-10-24 — Hasło SSH tunelu przez askpass z kolejki (zmienia D19)
D19 wykluczyło hasło SSH, bo `SSH_ASKPASS` wymagałby hasła w środowisku albo pliku. Etap P pokazał rozwiązanie bez
tego: `SSH_ASKPASS` to skrypt `exec cat "$PELIKAN_ASKPASS_FIFO"` (bez sekretu), kolejka FIFO 0600 w prywatnym katalogu
0700, a wątek Pelikana zapisuje do niej hasło z Pęku kluczy jeden raz i usuwa kolejkę. W środowisku `ssh` jest tylko
ścieżka kolejki. Tunel z hasłem: `BatchMode=no`, `PreferredAuthentications=password,keyboard-interactive`,
`NumberOfPasswordPrompts=1`, bez kluczy. Hasło tunelu leży w Pęku kluczy pod kontem `<uuid połączenia>.ssh`, osobno od
hasła bazy; edytor połączenia zapisuje je tylko tam. Test: użytkownik `haslo` w kontenerze sshd testów (losowe hasło
w `.testdb/env`, jak hasła bazy testowej).
### D135 · 2026-10-24 — Parametry kompilatora przez ALTER SESSION
Preferencje kompilatora (PLSQL_WARNINGS, PLSQL_OPTIMIZE_LEVEL, PLSQL_CODE_TYPE, PLSCOPE_SETTINGS, PLSQL_CCFLAGS) są
ustawiane w sesji kompilacji przed kompilacją okna programu; puste — parametr serwera bez zmian. Wartości przechodzą
przez filtr znaków (bez apostrofu i średnika — idą do literału), błąd parametru (np. NATIVE bez uprawnień) nie zatrzymuje
kompilacji. Program Window kompiluje tekst bez podstawiania zmiennych `&` (jak domyślnie wzorzec) — podstawianie jest
w SQL Window i Command Window.

### D136 · 2026-10-24 — Podświetlenia w edytorze: wystąpienia, INSERT ↔ VALUES, polecenia transakcyjne
Wystąpienia identyfikatora pod kursorem albo zaznaczonego słowa (co najmniej dwa, bez słów kluczowych, literałów i
komentarzy; nazwa w cudzysłowie — dokładnie) mają żółte tło; para kolumna INSERT ↔ wartość VALUES — tło jak pary
nawiasów (pozycje po przecinkach najwyższego poziomu, różna liczba elementów — brak pary). COMMIT/ROLLBACK/SAVEPOINT
tylko na początku polecenia (po `;`, `/`, BEGIN, THEN, ELSE, LOOP…), więc `ON COMMIT` w DDL i `ROLLBACK SEGMENT` się
nie liczą; tło pomarańczowe. Obie funkcje mają przełącznik w Preferencjach › Edytor.

### D137 · 2026-10-24 — Edycja szablonów i foldery
Edycja szablonu wbudowanego zapisuje szablon użytkownika o tej samej ścieżce (zastępuje wbudowany; usunięcie przywraca
wbudowany). Zmiana nazwy albo folderu zapisuje nowy plik i usuwa stary. Foldery użytkownika to katalogi w `Templates`
(także puste); zmiana nazwy folderu nie nadpisuje istniejącego, usunięcie folderu usuwa tylko szablony użytkownika.

### D138 · 2026-10-24 — Migawka odzyskiwania przed wykonaniem jako opcja (zmienia D91)
D91 pominęło migawkę przy każdym wykonaniu. Jest teraz opcją (domyślnie wyłączoną) w Preferencjach › Narzędzia:
migawka przed F8, kompilacją i wykonaniem okna testu, najwyżej jedna na 5 sekund — seria wykonań nie spowalnia pracy,
a awaria w trakcie długiego polecenia nie traci niezapisanych okien.

### D139 · 2026-10-24 — Wysokość wierszy siatki i ukrycie edytora (zmienia D109)
„Align › wysokość” ustawia liczbę linii tekstu na wiersz siatki (1–10 albo wg treści z pierwszych 500 wierszy);
wartości wieloliniowe są wtedy zawijane zamiast znaku ⏎. „Ukryj edytor” chowa edytor okna SQL (same wyniki).
„Adjust Window width” nie ma odpowiednika — wyniki są w karcie jednego okna głównego (D15).

### D140 · 2026-10-24 — Własne kolory czcionek jako opcja (zmienia D112)
Edytor, siatka wyników i Object Browser mogą mieć własny kolor tekstu i tła (Preferencje › Edytor › Kolory czcionek).
Domyślnie — i po „Systemowe” — obowiązują kolory motywu systemu dla trybu jasnego i ciemnego; własny kolor działa w obu
trybach (wybór użytkownika). Kolor składni (słowa kluczowe, literały, komentarze) zostaje z motywu Pelikana; tło edytora
jest bazą odcienia koloru połączenia (PD-CONN-005).

### D141 · 2026-10-24 — Walidacja adnotacji utPLSQL przy kompilacji
Specyfikacja z `--%suite` albo `--%test` dostaje ostrzeżenia kompilacji: nieznana adnotacja, procedura z listy
`--%beforeall/afterall/beforeeach/aftereach/beforetest/aftertest(…)` nieobecna w specyfikacji (nazwy `pakiet.procedura`
pomijane — mogą być w innym pakiecie), `--%test` bez `--%suite` (utPLSQL nie uruchomi pakietu), niesparowane
`--%context`/`--%endcontext`.
### D142 · 2026-10-24 — Edytory obiektów: zadanie przez DBMS_SCHEDULER, kolejki AQ, łącza bez hasła w podglądzie
Edytor „Zadanie” tworzy i zmienia zadania DBMS_SCHEDULER (folder Object Browsera to zadania Schedulera; DBMS_JOB jest
przestarzały i od 19c działa na Schedulerze) — wspólny kod z oknem Schedulera (`Scheduler.createSQL/alterSQL`).
Kolejka AQ w jednym formularzu z opcją utworzenia tabeli kolejki (CREATE_QUEUE_TABLE + CREATE_QUEUE + START_QUEUE),
zmiany przez ALTER_QUEUE i START/STOP_QUEUE tylko dla zmienionych kierunków. Hasło łącza bazy danych jak hasło
użytkownika: maskowane w podglądzie, nigdzie nie zapisywane; zmiana użytkownika lub bazy łącza wymaga hasła (DROP +
CREATE), bez hasła edytor pokazuje powód i nie generuje DDL. Widok w edytorze formularza zdejmuje z tekstu słownika
klauzule WITH READ ONLY / CHECK OPTION (są polami). Pola tekstowe zamieniają na wielkie litery tylko nazwy obiektów.

### D143 · 2026-10-24 — Dymek debugera bez wywołań DBMS_DEBUG
Wartość pod myszą pochodzi z już wczytanych zmiennych i obserwowanych zatrzymanego debugera (także pola rekordów i
globalne pakietu bez kwalifikatora). Dymek powstaje synchronicznie, a GET_VALUE w trakcie ruchu myszy mnożyłby
wywołania w sesji nadzorującej; nazwy z dwukropkiem są i tak pomijane (D133).

### D144 · 2026-10-24 — Listy informacji debugowania, statystyki, profiler, HTP, wiele obiektów
Listy NEVER/ALWAYS (Preferencje › Oracle › Debuger) przyjmują `user@baza` albo `[SCHEMAT.]OBIEKT` z `*` i `?`; NEVER
wygrywa. Statystyki: kolumna „Suma” sumuje różnice wszystkich wykonań okna; wybór statystyk w Preferencjach › Okno SQL
(puste — wszystkie niezerowe), eksport CSV. Profiler: historia przebiegów z tabel PLSQL_PROFILER_RUNS/DBMSHP_RUNS,
jednostka czasu i próg udziału w preferencjach, drzewo HPROF z DBMSHP_PARENT_CHILD_INFO (rekurencja przerwana).
HTP Output: przełącznik w karcie Wyjście okna testu — OWA.INIT_CGI_ENV + HTP.INIT przed blokiem, OWA.GET_PAGE po nim
(bez inicjalizacji HTP.P zgłasza ORA-06502). Wiele obiektów w Object Browserze: Cmd+C kopiuje nazwy po przecinku,
menu akcji wspólnych (DDL, rekompilacja, usuwanie po jednym potwierdzeniu, błędy nie przerywają pozostałych).
Query Builder: podzapytania w FROM i JOIN jako widoki wbudowane z kolumnami z opisu wyniku (`select * … where 1 = 0`).

### D145 · 2026-10-24 — Okna narzędzi: HSplitView zamiast NavigationSplitView, stopki pod podziałem
Zrzuty w tle pokazały trzy błędy układu w oknach SwiftUI hostowanych w AppKit: `NavigationSplitView` dokłada pasek
narzędzi okna i treść szczegółów wchodzi pod tytuł (DBMS Scheduler, Panel DBA — przyciski i nagłówki tabel schowane),
`safeAreaInset` nie działa z `HSplitView` (stopka Narzędzi użytkownika na liście), a w pionowym `NSStackView` widok
przewijany bez wysokości własnej zapada się do zera (płótno diagramu — puste okno od Etapu 6). Zasada: w oknach
narzędzi `HSplitView` z listą po lewej, stopki jako ostatni element `VStack`, układ AppKit z jawnymi więzami zamiast
stosu, gdy jeden z widoków ma wypełnić resztę. Tak samo poprawione okna planu (panel SwiftUI wyśrodkowany w NSHostingView — rama na całą wysokość, pasek w dwóch wierszach) i raportu (NSStackView). W trybie skryptu zrzutów okna dialogowe nie są pokazywane — pytanie trafia do dziennika jako „Anuluj”, żeby nic nie aktywowało aplikacji. Okno instrukcji zostaje przy `NavigationSplitView` (pasek z przyciskiem
panelu jest tam potrzebny, treść WebKit nie wchodzi pod tytuł).

### D146 · 2026-10-24 — Podkreślenia analizy kodu w atrybutach tekstu, nie renderowania
Zrzut w tle pokazał, że podkreślenia analizy kodu (DG-RES-001, DG-INSP-001) nigdy nie były widoczne: TextKit 2 nie
rysuje `underlineStyle` z atrybutów renderowania `NSTextLayoutManager`. Podkreślenia są teraz atrybutami
`NSTextStorage` (zmiana atrybutów nie zmienia tekstu, nie trafia do historii cofania i nie wywołuje obsługi edycji);
kolorowanie składni nadpisuje edytowaną linię, a analiza po zmianie nakłada je ponownie. Test logiki analizy przechodził
od początku — błąd był tylko w rysowaniu, stąd zrzuty w tle jako stała część weryfikacji okien. Ten sam przebieg naprawił
nagłówek panelu agenta schowany pod paskiem narzędzi okna (przypięcie do `safeAreaLayoutGuide`).
Ten sam przebieg pokazał, że kursor ustawiony z modelu (Idź do linii, nawigacja po błędach, agent) nie odświeżał
pozycji na pasku, numeru bieżącej linii na marginesie ani wyróżnień par i wystąpień — wspólna aktualizacja jest teraz
wywoływana także po synchronizacji zaznaczenia z modelu. Hak skryptu zrzutów ma krok `debug.select` (tylko Debug).


### D147 · 2026-10-24 — Odczyt potoków procesów ograniczony w czasie po ich zakończeniu
Testy Stop na CI zawieszały się sporadycznie (nazwa testu widoczna dopiero po zmianie logów na `script`). Klient `ssh`
z ControlMaster przekazuje swoje stdio procesowi głównemu, więc po zabiciu klienta koniec zapisu potoku może trzymać
master aż do zamknięcia zdalnej sesji, a `read` bez limitu czekał bez końca — mimo limitu czasu i Stop. `Spawn.run`
i `Spawn.stream` czytają przez `poll` (200 ms) i po zakończeniu procesu lokalnego dają 3 s na dociągnięcie danych,
potem kończą odczyt. Test regresji: potomek w tle trzymający stdout 30 s nie wydłuża `run`/`stream` ponad kilka sekund.

### D148 · 2026-10-24 — Kroki pomocnicze skryptu zrzutów: plik, preferencje, widok planu
Notatnik z wykresem, historia lokalna pliku i widoki planu (diagram, flame graph) nie dają się pokazać samymi komendami
bez okien dialogowych. Hak skryptu zrzutów (tylko Debug) ma kroki `debug.openFile` {path}, `debug.preferences` {pane}
i `debug.planMode` {mode}; `@ROOT@` w scenariuszu zastępuje `scripts/screenshots.sh` (bez ścieżek domowych w repozytorium).
Pliki wejściowe scenariuszy leżą w `scripts/screenshots/fixtures/`. Okno historii lokalnej wybiera od razu najnowszą
wersję (wcześniej prawy panel był pusty do pierwszego kliknięcia).

### D149 · 2026-10-24 — Okno zgody agenta w zrzucie; pusta ostatnia linia w TextKit 2
Okno zgody w aplikacji jest arkuszem na oknie głównym, przed którym Pelikan pokazuje panel agenta i podskakuje ikoną
w Docku — w zrzucie w tle to by przeszkadzało właścicielowi. Krok `debug.approval` (tylko Debug) liczy prawdziwy
podgląd skutków (`Workspace.preview`, ten sam co dla agenta) i pokazuje ten sam `ApprovalView` w osobnym oknie
w tle. Plan DBMS_XPLAN w oknie zgody przewija się w poziomie (zawijanie łamało tabelę planu); podsumowanie
bez formy „polecenie/a”. Zrzut edytora pokazał, że numer pustej ostatniej linii (po końcowym „\n”) i podświetlenie
bieżącej linii na końcu pliku były o linię za nisko: TextKit 2 dokłada tę linię do ostatniego fragmentu tekstu jako
pusty fragment linii, więc pozycja to jego `typographicBounds`, nie dół ramki fragmentu.

### D150 · 2026-10-24 — Raport z grupami w jednej tabeli
Zrzut raportu z kolumną Break pokazał osobną tabelę na każdą grupę (różne szerokości kolumn) i wiersz „Razem” jako
krótką tabelę pod spodem, niewyrównaną z kolumnami. Układ tabelaryczny bez nowej strony po grupie renderuje teraz
jedną tabelę: wiersz grupy, nagłówki kolumn i suma grupy dla każdej grupy, „Razem” na końcu. Z nową stroną po grupie
zostaje tabela na grupę (`.group` z `break-after: page`), a „Razem” trafia do tabeli ostatniej grupy. Brak separatora
tysięcy w „3000,00” przy „19 925,00” to reguła polskiego CLDR (liczby czterocyfrowe bez grupowania), nie błąd.

### D151 · 2026-10-24 — Pobieranie hurtowe z paczką dobraną do wiersza; próba na dużej bazie właściciela
Właściciel udostępnił połączenie przez Oracle Wallet do kopii swojej bazy (Oracle 19.3, przez sieć z opóźnieniem
~50 ms). Sonda tylko do odczytu (poza repozytorium, `SET TRANSACTION READ ONLY`, bez kompilacji i DML, kod źródłowy
tylko w pamięci; do repozytorium i raportu trafiają wyłącznie liczby) sprawdziła Pelikana na dużym schemacie:
metadane Object Browsera (23 tys. tabel w 4 s, 48 tys. synonimów w 6,3 s), lekser, konspekt, zwijanie i inspekcję
kodu oraz formater na 3000 jednostkach PL/SQL (34 MB) — formater bez odmów i idempotentny, wszystko razem kilka sekund.
Wąskim gardłem okazało się pobieranie: stała paczka 500 wierszy = jedna podróż sieciowa na 500 wierszy, ~7,5 tys. w/s.
`ExecuteOptions.bulk` (queryAll, eksport tabel i do pliku, transfer danych, porównanie danych) ustawia paczkę po
wykonaniu, przed definicją zmiennych (później ODPI-C nie pozwala jej powiększyć — DPI-1015): do 10 000 wierszy i ~16 MB
buforów według szerokości wiersza. Na tej bazie 300 tys. wierszy: 38,1 s → 7,9 s. Siatka okna SQL zostaje przy paczce
z opcji połączenia — duża paczka opóźniłaby pierwsze wiersze wolnego zapytania.

### D152 · 2026-10-24 — Program z innego schematu: właściciel w nagłówku; analiza nazw hurtowo i bez fałszywych alarmów
Sonda na dużej bazie właściciela (D151) wykazała, że źródło programu z innego schematu dostawało nagłówek
`CREATE OR REPLACE PACKAGE BODY nazwa` bez właściciela — kompilacja z okna programu utworzyłaby kopię w schemacie sesji.
`MetadataProvider.source` dodaje właściciela, gdy różni się od bieżącego schematu sesji (`ProgramCompiler.withOwner`;
własne obiekty bez zmian). Analiza nazw (podkreślenia w edytorze):
- nazwy bez schematu rozwiązywane w schemacie właściciela z nagłówka programu, potem synonimy publiczne;
- kolumny: obiekt w schemacie → synonim prywatny → publiczny (wcześniej synonim publiczny wygrywał z własną tabelą);
- słownik `DBA_*`, gdy sesja może go czytać (uprawnienia sesji nie dają fałszywych „nieznanych tabel”);
- zapytania hurtowe (listy IN po 900 nazw) zamiast jednego zapytania na nazwę: pakiet 13,5 tys. linii 34 s → 1,8 s;
- bez fałszywych alarmów: tabela o nazwie słowa kluczowego (`schemat.groups`), ten sam alias w kilku podzapytaniach
  (kolumna poprawna, gdy ma ją którakolwiek relacja aliasu), alias widoku wbudowanego, alias równy nazwie schematu
  (`schemat.tabela` w FROM to relacja), CTE poza początkiem polecenia (`INSERT … WITH … SELECT`).
Na 40 największych poprawnych (VALID) ciałach pakietów (279 tys. linii): 478 zgłoszeń → 1, czas 40 s → 16,6 s. Wzorce
odtworzone syntetycznie w testach jednostkowych i na bazie testowej (żadnych danych z bazy właściciela w repozytorium).

### D153 · 2026-10-24 — Pierwsze wydanie beta jako zwykłe wydanie z „beta” w tytule
Właściciel poprosił o pierwsze wydanie testowe. Kanał aktualizacji Sparkle to `releases/latest/download/appcast.xml`,
a GitHub nie zalicza wydań oznaczonych „pre-release” do `latest` — testerzy bety nie dostaliby kolejnych wersji (bez
wydania stabilnego `latest` zwraca 404). Dlatego `make beta-release` tworzy zwykły szkic wydania z tytułem
„Pelikan X.Y.Z beta”, notatkami z `docs/BETA.md` (co testować, znane ograniczenia, zgłaszanie błędów bez haseł i danych)
i listą zmian. Osobny kanał beta w Sparkle (`sparkle:channel`) — dopiero, gdy pojawią się wydania stabilne.
Publikacja szkicu jak dotąd: właściciel (`gh release edit vX.Y.Z --draft=false`). README opisuje teraz produkt dla
testerów (funkcje, instalacja, bezpieczeństwo, budowanie) zamiast stanu budowy.

### D154 · 2026-10-24 — Instrukcja: zrzuty w docs/manual/img jako data:, tabele, rozdziały bez tłumaczenia po polsku
Instrukcja na beta dostała 15 rozdziałów (wcześniej 10). Zrzuty z `docs/screenshots` (83 pliki, ~15 MB) nie trafiają do
pakietu aplikacji, a okno pomocy ładuje HTML bez `baseURL` i z CSP `default-src 'none'` — odwołanie do pliku i tak by się
nie wyświetliło. Dlatego wybrane 19 zrzutów (~4,5 MB, PNG 1400 px jak w docs/screenshots — ostre na Retinie przy szerokości
strony 760 pt; zmniejszenie do 1120 px oszczędzało ~1 MB kosztem czytelności) leży w `docs/manual/img` pod opisowymi
nazwami i jest wspólne dla wszystkich języków. Rozdział odwołuje się do nich zwykłym Markdownem `![opis](../img/plik.png)`
— działa to też na GitHubie. `UserManual` osadza obrazek jako `data:` (CSP strony `img-src data:`) tylko wtedy, gdy plik
jest PNG/JPEG, ma ≤ 4 MB i leży wewnątrz katalogu instrukcji (ścieżka bez schematu, bez `/` na początku, po rozwinięciu
dowiązań); inaczej pokazuje sam opis. WKWebView nie dostaje dostępu do plików. Podzbiór Markdownu dostał tabele z wierszem
nagłówka (`\|` w komórce) — potrzebne do skrótów i macierzy uprawnień. Zrzuty pokazujące nazwę konta albo hosta (np. lista
sesji z OSUSER/MACHINE) nie trafiły do instrukcji. Test pilnuje, że każdy obrazek z rozdziałów istnieje, a każdy plik w
`img` jest używany (bez balastu w pakiecie). Rozdziały przenumerowane (nowe: 05-obiekty, 08-utplsql, 10-wydajnosc,
14-bezpieczenstwo, 15-problemy) także w en/de/es/uk; tłumaczenia to osobny krok, więc loader bierze rozdział, którego nie ma
w katalogu języka, z polskiego (zamiast go gubić), a test wymaga tylko, żeby tłumaczenia nie miały rozdziałów spoza
polskiej instrukcji. Po przetłumaczeniu można przywrócić wymóg kompletu.
Uzupełnienie: tłumaczenia en/de/es/uk mają komplet 15 rozdziałów (etykiety menu i okien z String Catalog, nie własne),
więc test znów wymaga kompletu; zapas po polsku w loaderze zostaje na wypadek nowego rozdziału.

### D155 · 2026-10-24 — Rozbieżności macierzy i kodu znalezione przy pisaniu instrukcji
Subagent piszący instrukcję (D154) porównał opisy z kodem i znalazł miejsca, w których macierz obiecywała więcej, niż
dawał interfejs. Poprawione w kodzie: „Sesja › Zmień hasło…” działa (OCIPasswordChange przez ODPI-C — hasło nie trafia
do tekstu SQL ani historii; nowe hasło w Pęku kluczy, gdy połączenie je zapisuje; test na bazie), „Widok › Przeglądarka
obiektów” przełącza lewą kolumnę, przełączniki w Preferencjach dla opcji Query By Example i potwierdzania zmian na
produkcji, menu kontekstowe Przeglądarki obiektów z testami utPLSQL, informacją debugowania, odświeżeniem widoku
zmaterializowanego, testem łącza, uruchomieniem zadania, kolejkami, porównaniem i „Dodaj do folderu” (pozycje
pokazywane tylko dla pasujących typów), debugowanie wyszarzone na sterowniku thin (deklaracja JDWP usunięta też z
Instant Client — D106). Poprawione w opisach: edycja wyniku wymaga ROWID, lewe karty to połączenia, obiekty, okna,
szablony i pliki, słowniczek — foldery Przeglądarki obiektów są po polsku.
### D156 · 2026-10-24 — Workspace Manager w bazie testowej
Obraz Oracle Free 26ai (23.26.3) nie ma zainstalowanego Workspace Managera (brak WMSYS i DBMS_WM), ale ma jego skrypty
w `ORACLE_HOME/rdbms/admin`. `scripts/testdb.sh owm` uruchamia `owminst.plb` w PDB testowej (ok. 40 s, raz), nadaje
użytkownikowi testowemu WM_ADMIN_ROLE i tworzy przestrzeń DEV_PELIKAN_WS jego własnym wywołaniem — `GrantSystemPriv`
jako SYS kończy się ORA-06598 (pakiet WMSYS z prawami wywołującego). Test PD-CONN-009 łączy się definicją połączenia
z przestrzenią i sprawdza `DBMS_WM.GetWorkspace`; bez instalacji OWM test nie ma czego sprawdzić i kończy się od razu.
Krok jest tani, więc CI wykonuje go po `seed`.

### D157 · 2026-10-24 — ORDS na żywo tylko w testach
ORDS (publiczne `ords-latest.zip`, bez konta) jest pobierany do `.testdb/` i uruchamiany samodzielnie w kontenerze
z JRE (`eclipse-temurin:21-jre`) w sieci Docker bazy testowej; schemat ORDS instalowany w PDB testowej, konfiguracja
w wolumenie Dockera, hasła SYS i ORDS_PUBLIC_USER przez stdin, HTTP tylko na 127.0.0.1 (`scripts/testdb.sh ords-up`,
`ords-down`). ORDS nie trafia do Pelikana. Test na żywym serwerze wykonał skrypty komend i wykrył błąd: widok
USER_ORDS_ENABLED_OBJECTS ma kolumnę TYPE, nie OBJECT_TYPE — lista obiektów AutoREST kończyła się ORA-00904.
ORDS buforuje metadane kilka sekund, więc test HTTP czeka na oczekiwany status (do 20 s). Do CI nie dodajemy
(pobranie 200 MB i obraz JRE w każdym przebiegu); test bez `PELIKAN_TESTDB_ORDS_URL` jest pomijany.

### D158 · 2026-10-24 — LDAP: alias rozwiązuje Pelikan, nie adapter Instant Client
Próba z serwerem OpenLDAP 2.6 (`scripts/testdb.sh ldap-up`: kontener Alpine, własny minimalny schemat
`orclNetService`/`orclNetDescString` z OID-ami z gałęzi dokumentacyjnej, odczyt anonimowy, bez haseł) pokazała, że
`sqlplus` z Instant Client rozwiązuje alias przez LDAP, ale ten sam klient w procesie Pelikana — nie. Przyczyna:
`libclntsh.dylib` jest konsolidowany z płaską przestrzenią nazw, a w każdym procesie z AppKit jest już załadowany
systemowy LDAP.framework. Część wywołań `ldap_*` adaptera trafia do biblioteki systemowej: wiązanie idzie jako LDAPv2
(OpenLDAP 2.5+ odrzuca: „historical protocol version requested”), a po wymuszeniu v3 proces kończył się asercją
`LDAP_VALID(ld)` w `ldap_first_entry` — przy serwerze przyjmującym LDAPv2 (np. starsze OID/AD) groziło to awarią
aplikacji. Potwierdzone `sqlplus` z `DYLD_INSERT_LIBRARIES` na LDAP.framework (ten sam błąd).
Na macOS Pelikan rozwiązuje więc bare alias sam, zanim przekaże go klientowi: konfiguracja z `ldap.ora` i
`sqlnet.ora` (z IFILE) w katalogu połączenia, katalogu Oracle Net Pelikana albo TNS_ADMIN; metody w kolejności
NAMES.DIRECTORY_PATH (domyślnie `tnsnames, ezconnect, ldap`) — tnsnames.ora, potem LDAP (LDAPv3, wiązanie anonimowe,
zapytanie bazowe o `cn=alias,cn=OracleContext,<DEFAULT_ADMIN_CONTEXT>`, wyłącznie przez LDAP.framework). Klient dostaje
gotowy deskryptor, więc jego adapter LDAP nie jest używany. Alias nieznaleziony nigdzie — ORA-12154 od Pelikana
(nie oddajemy go klientowi, by nie wejść w adapter LDAP); tak samo nazwa hosta bez portu i usługi przy aktywnym LDAP.
Nie obsługujemy wiązania portfelem (NAMES.LDAP_AUTHENTICATE_BIND), LDAPS ani NAMES.DEFAULT_DOMAIN; połączenie przez
portfel SEPS (`/@alias`) przekazuje alias dosłownie. Na Linuksie (tylko testy CI) zostaje adapter klienta — bez próby.

### D159 · 2026-10-24 — Kerberos: KDC w kontenerze, na macOS blokada zamiast awarii
`scripts/testdb.sh kdc-up` uruchamia KDC MIT (Alpine, realm PELIKAN.TEST, klucze losowe, główne hasło tylko w pliku
stash w kontenerze), dodaje principal usługi `oracle/<nazwa hosta kontenera bazy>` (klient Oracle prosi o bilet dla
nazwy hosta serwera, nie hosta z deskryptora — `oracle/localhost` nie wystarczał), kopiuje tablicę kluczy do kontenera
bazy i tworzy użytkownika `DEV_KRB IDENTIFIED EXTERNALLY AS
'dev_krb@PELIKAN.TEST'` (bez zmiany OS_AUTHENT_PREFIX i restartu). Bilety (TGT i bilety usługi) powstają przez
`kinit -k` w KDC i trafiają do `.testdb/kerberos/ccache` — klient nie musi łączyć się z KDC. Blok KERBEROS5 w sqlnet.ora
serwera jest dopisywany tylko na czas testu (`kdc-linux`, usuwany pułapką EXIT): ten plik czytają też procesy serwera
jako klient — łącze bazy danych do siebie (test PD-OB-019) i sqlplus w kontenerze kończyły się ORA-12641; narzędzia
skryptu używają w tym czasie `/opt/oracle/client-net` bez Kerberos.
Wynik: `sqlplus` z Instant Client dla macOS loguje się jako DEV_KRB, ale ten sam klient w procesie Pelikana (i każdym
procesie z AppKit) kończy się SIGABRT (ORA-24550) — także przy logowaniu hasłem, gdy sqlnet.ora włącza KERBEROS5.
Przyczyna jak w D158: `libclntsh.dylib` z płaską przestrzenią nazw i systemowy Kerberos.framework (ładowany przez
AppKit) eksportujący te same funkcje `krb5_*`; potwierdzone `sqlplus` z `DYLD_INSERT_LIBRARIES` na Kerberos.framework.
W procesie aplikacji nie da się tego obejść (framework jest załadowany przed `libclntsh`); wymagałoby to osobnego
procesu pomocniczego bez AppKit dla sesji OCI. Do tego czasu Pelikan na macOS przed połączeniem sprawdza
SQLNET.AUTHENTICATION_SERVICES (z IFILE) w katalogu Oracle Net i zgłasza czytelny błąd zamiast awarii aplikacji.
Ta sama ścieżka Pelikana (ODPISession, SessionManager, `/` bez hasła) działa z Instant Client dla Linuksa:
`scripts/testdb.sh kdc-linux` uruchamia test w kontenerze `swift:6.3-noble` w sieci bazy testowej (Basic Light
arm64/x64, konfiguracja w `.linux-build/.testdb`, CI=1 dla hosta kontenera). Wiersz PD-CONN-014 zostaje ⚠️, bo
aplikacja jest na macOS. Do CI nie dodajemy (konfiguracja Kerberos dotyczyłaby całego procesu testów bazy).

### D160 · 2026-10-24 — Okno zgody agenta: „Zezwól” i „Odmów”; spójność katalogu i instrukcji
Tłumaczenia instrukcji (D154) pokazały, że przyciski okna zgody agenta używały wspólnych kluczy „Zatwierdź”/„Odrzuć”,
które w katalogu znaczą COMMIT i „Discard/Verwerfen” — w oknie zgody mylące (zgoda na operację to nie zatwierdzenie
transakcji, a DML agenta i tak czeka na osobną zgodę na COMMIT). Okno ma teraz własne „Zezwól”/„Odmów” (Allow/Deny).
Poprawione też: komunikat o braku Instant Client wskazuje kartę Ogólne definicji połączenia (tam jest Sterownik),
katalog — de „Ansicht” zamiast „View”, en „Debug”, jednolite „Explain Plan Window”; instrukcja we wszystkich językach
— zmiana hasła z menu, aktualne ograniczenia (ORDS, Workspace Manager i LDAP sprawdzone — D156–D158; Kerberos na
macOS — D159).

### D161 · 2026-10-24 — Kerberos na macOS odłożony; pierwsza beta opublikowana
Właściciel odłożył proces pomocniczy dla połączeń Kerberos na macOS jako ewentualny plan na przyszłość: sam Kerberosa
nie używa, a proces pomocniczy oznacza przeniesienie całej komunikacji z bazą przez IPC. PD-CONN-014 zostaje ⚠️ z
czytelnym błędem z D159; wrócimy do tematu, gdy tester zgłosi potrzebę. Właściciel opublikował też Pelikan 7.9.0 beta
jako pierwsze publiczne wydanie i polecił usunąć starsze szkice wydań (1.9.0–7.7.0); tagi zostały w repozytorium.

### D162 · 2026-10-24 — Bez ścieżek budowania w binarce; nazwy usług macOS przetłumaczone
Próba opublikowanej bety 7.9.0 (pobranej z GitHuba) potwierdziła podpis aplikacji, wersję, zawartość DMG i PKG oraz
podpis EdDSA archiwum aktualizacji (zmieniony plik odrzucany). Wykryła za to w pliku wykonywalnym 384 ścieżki budowania
z katalogiem domowym (pełne przeszukanie bajtów: kilka tysięcy) — z makra `__FILE__` w kodzie C BoringSSL i z tablicy
symboli debugowania (STABS ze ścieżkami plików .o i źródeł), która zostaje w kompilacji Release bez instalacji.
`scripts/build-installer.sh` buduje z `-ffile-prefix-map` dla C (ustawienie z wiersza poleceń xcodebuild obejmuje cele
pakietów), usuwa symbole debugowania z naszych plików wykonywalnych (`strip -S -x`; aplikacja 66 → 35 MB, DMG 29 →
22 MB), `scripts/signing.sh` podpisuje też rozszerzenia z PlugIns (z dotychczasowymi uprawnieniami, piaskownica Quick
Look zostaje), a wydanie przerywa się, gdy jakikolwiek plik w aplikacji zawiera katalog repozytorium albo domowy.
Swift bez mapy prefiksów: `-file-prefix-map` psuje jawne moduły Xcode. Ta poprawka obejmie następne wydanie; 7.9.0
zostaje, bo ścieżki ujawniają tylko układ katalogów budującego (bez haseł i danych).
Nazwy w menu Usługi były tylko po polsku. Klucze ServicesMenu.strings muszą zawierać nazwę aplikacji po rozwinięciu
(„Pelikan: …”), a nazwa ma być tylko w Brand.xcconfig — dlatego plik generuje faza skryptu przy budowaniu
(`scripts/services-menu.py`) z tłumaczeń w String Catalog; `scripts/l10n.py` dopisuje nazwy usług z Info.plist do
katalogu, więc `check --strict` pilnuje kompletu. Usługa „Otwórz w SQL Window” nazywa się teraz „Otwórz w oknie SQL”,
jak polecenie w aplikacji.

### D163 · 2026-10-24 — Przegląd bezpieczeństwa: poprawki API agenta, linku pelikan:// i kluczy SSH
Przegląd (subagent, tylko odczyt kodu) potwierdził w kodzie 3 wysokie, 3 średnie i 4 niskie problemy; wszystkie są
poprawione:
- **H1:** połączenie narzędzia bez aliasu było ustalane osobno przy zgodzie i przy wykonaniu, a agent mógł w trakcie
  zgody przełączyć aktywne okno (`navigate_to`). Bramka przypina teraz połączenie kluczem wewnętrznym `__connectionID`
  (agent go nie poda, bo klucze `__` są usuwane), a protokół `AgentInvocationGate.authorize` zwraca argumenty do
  wykonania.
- **H2:** link `pelikan://open?connection=…&commandfile=…` łączył się z zapisanym hasłem i wykonywał skrypt w oknie
  poleceń (SPOOL bez pytania mógł dopisać polecenia do plików startowych powłoki). Link przyjmuje tylko otwieranie,
  a nieznane klucze dają ostrzeżenie. Argumenty procesu (`commandfile=` z wiersza poleceń) działają jak dotąd, bo
  podaje je sam użytkownik.
- **H3:** blok PL/SQL, `CALL`, polecenia systemowe i nierozpoznane mogły zatwierdzić DML agenta bez osobnej zgody na
  COMMIT. Wszystko poza zapytaniem, DML i kontrolą sesji (`mayCommit`) jest odrzucane przy niezatwierdzonym DML,
  a podgląd oznacza PL/SQL jako nieodwracalne. `ALTER SESSION DISABLE COMMIT IN PROCEDURE` odrzucone: blokuje też
  ROLLBACK w kodzie (utPLSQL), a transakcji autonomicznych i tak nie zatrzymuje.
- **M1:** `install_utplsql` zostaje (wymaga go PROMPT §7), ale podgląd w oknie zgody mówi wprost, że skrypty wykonuje
  okno poleceń na koncie użytkownika, a nie agenta, z uprawnieniami SYSDBA/DBA. Działa tylko dla połączeń dev/test.
- **M2:** przełączenie połączenia na produkcję wyłącza zmiany agenta; włączenie z powrotem to świadoma decyzja.
- **M3:** narzędzia edytora agenta (odczyt, wstawianie, zamiana, przejście) odrzucają okno poleceń.
- **L1:** agent dostaje przy błędzie łączenia tylko alias i kod błędu (bez deskryptora, hosta i wyjścia ssh).
- **L2:** gniazda serwera agentów mają FD_CLOEXEC, więc nie przechodzą do CLI agenta uruchamianego przez forkpty.
- **L3:** cele SSH Pro\*C miały `StrictHostKeyChecking=accept-new`, czyli przy pierwszym kontakcie hasło mógł dostać
  podstawiony serwer. Teraz jest `yes`; test celu pokazuje odcisk klucza (`ssh-keyscan`) do potwierdzenia, zanim zapisze
  klucz, a nieznany serwer daje osobny błąd `hostKeyUnknown`.
- **L4:** plik śladu `PELIKAN_MCP_TRACE` powstaje z prawami 0600.

Testy: link z `commandfile`, PL/SQL i CALL po DML agenta, nieznany klucz serwera na lokalnym sshd.
### D164 · 2026-10-25 — Narzędzia na dużej bazie: wyszukiwanie, diagram ER, eksport DDL, dokumentacja schematu
Druga próba tylko do odczytu na kopii dużej bazy właściciela (D151) objęła narzędzia, których pierwsza nie mierzyła.
Przeglądarka sesji (178 sesji, 166 ms) i porównanie obiektów działały poprawnie. Cztery narzędzia były za wolne, bo
każde zapytanie do słownika takiej bazy kosztuje sekundy niezależnie od liczby wierszy:
- **Znajdź obiekty bazy** (schemat z 860 tys. linii PL/SQL): 31–85 s → 1,8–2,8 s. REGEXP_LIKE po ALL_SOURCE kosztuje
  ~38 s, a INSTR ~1,3 s. Warunek `instr … and regexp_like …` nie pomagał, bo przy zmiennych wiązanych optymalizator
  liczył najpierw REGEXP_LIKE. Kolejność wymusza CASE (gałęzie WHEN sprawdzane po kolei). Tekst dosłowny: najpierw
  INSTR, potem REGEXP_LIKE dla całych słów; wyrażenie regularne — bez zmian. Definicje tabel: 58 → 16 s.
- **Diagram ER**: 60 tabel 47 → 3,8 s, 378 tabel 263 → 4,7 s. Kolumny, klucze główne i obce idą paczkami po 500 tabel
  (nowe metody źródła metadanych z domyślną implementacją dla atrap) zamiast dwóch zapytań na tabelę z podzapytaniem
  na kolumnę.
- **Eksport DDL** (a z nim porównanie obiektów): 1985 → 212 ms na obiekt. GET_DEPENDENT_DDL('OBJECT_GRANT') kosztował
  ~1,8 s na obiekt, także bez uprawnień. Lista obiektów z uprawnieniami pochodzi teraz z DBA_TAB_PRIVS (bez dostępu —
  ALL_TAB_PRIVS), raz na schemat, a indeksy, wyzwalacze i ciała nie są o uprawnienia pytane.
- **Dokumentacja schematu** (1826 obiektów): ponad 20 min → 14,7 s. Komentarze, kolumny, ograniczenia, indeksy,
  parametry programów i sekwencje pobierane są kilkoma zapytaniami na schemat zamiast czterech na tabelę.
Porównanie próbki 150 obiektów ze sobą dało w sondzie 234 „tylko w celu”: to obiekty spoza próbki, nie błąd.

### D165 · 2026-10-25 — Diagram ER dużego schematu, definicje tabel w wyszukiwaniu; beta 8.4.0, stare tagi usunięte
Trzecia próba tylko do odczytu (D151) mierzyła osobno zapytania i obliczenia po stronie klienta:
- **Diagram ER, 2000 tabel**: 98 → 6,6 s. Zapytania zajmowały 7 s, resztę zabierało `Diagram.addObject`. Dla każdej
  tabeli szukał wolnego miejsca, sprawdzając wszystkie wcześniejsze — koszt rósł z kwadratem liczby tabel, a układ
  warstwowy i tak przestawiał potem wszystko. Diagram ze schematu dodaje teraz obiekty naraz bez szukania miejsca
  (`addObjectsForLayout`), a układ znajduje elementy przez słownik zamiast przeszukiwania listy. Pojedyncze dodawanie
  (przeciąganie z przeglądarki obiektów) dalej szuka wolnego miejsca.
- **Znajdź obiekty — definicje tabel**: 16 → 4,9 s (przed D164: 58 s). Półzłączenie
  `(owner, table_name) in (select … from all_tables)` w gałęziach kolumn i komentarzy kosztowało ~5 s na gałąź przy
  0,4 s bez niego. Kolumny i komentarze widoków odpadają teraz po stronie klienta, po jednym zapytaniu o tabele
  przeszukiwanych schematów, wykonywanym tylko wtedy, gdy są trafienia. Wiersze widoków liczą się do limitu trafień
  przed odfiltrowaniem; przy domyślnym limicie 10 000 trafień rzadko ma to znaczenie.
- Właściciel opublikował drugą betę **8.4.0** (poprawki D162–D164) i polecił usunąć stare tagi v1.9.0–v7.7.0. Zostały
  tagi opublikowanych wydań: v7.9.0 i v8.4.0.

### D166 · 2026-10-25 — Bez ostrzeżeń kompilatora i CI
- CI: `actions/checkout@v7` (Node 24) zamiast v4 — GitHub wycofuje Node 20. Zadanie macOS na obrazie `xcode-27`
  (macOS 27, Xcode 27, wersja próbna) zamiast `macos-latest` z Xcode 26, który nie obsługuje celu macOS 27.
- Kompilacja aplikacji, pakietu i testów na macOS i Linuksie bez ostrzeżeń: `any NSDraggingInfo`, `Range(NSRange)` zamiast
  `toRange()`, zbędne `try`/`public`/`nonisolated(unsafe)`, `_ =` dla wyników `createFile`/`parse()` (na Linuksie bez
  `@discardableResult`), usunięty nieosiągalny kontroler dokumentu „inny niż SQL” (wszystkie rodzaje mają własne okna).
- Testy przypisywały `ws.ui = TestUI()`, a `Workspace.ui` jest słabą referencją — obiekt znikał od razu i 27 testów
  działało bez UI. Teraz trzymają referencję; test filtrów Object Browsera sprawdza przy tym okno wyboru filtru.
- Instalator buduje bez dSYM: po mapie prefiksów (D162) dsymutil nie znajdował modułów .pcm, a symbole i tak usuwa strip.

### D167 · 2026-10-25 — Przegląd aktualności zależności i narzędzi
Stan na 2026-10-25 (porównanie z najnowszymi wydaniami w repozytoriach źródłowych):
- Podniesione: swift-crypto 4.5.2 → 5.0.3 (zakres `3.0.0..<6.0.0`, jak w OracleNIO; 5.0 wydane 2026-09-16),
  swift-collections 1.7.4, SwiftTerm 1.99.1, Sparkle 2.10.1 (m.in. poprawka przedwczesnej instalacji aktualizacji ze
  ścieżki w NFC), Swift w CI Linux 6.3 → 6.4.
- Aktualne: ODPI-C 26.0.0, utPLSQL 3.2.3, swift-sdk MCP 0.12.1, SwiftNIO 2.104.0 i pozostałe zależności OracleNIO,
  Instant Client 23.26.2 (najnowszy dla macOS arm64) i 23.26.4 w CI Linux, XcodeGen 2.46.0, `actions/checkout@v7`.
- OracleNIO zostaje na commicie 7cda9e0 (po 1.0.0-rc.4, D20): na main są dwa późniejsze commity wydajnościowe
  z 2026-10-24 bez wydania — poczekają na wydanie albo dłuższą próbę.
- xcodebuild dostaje jawny cel `platform=macOS,arch=arm64` (aplikacja jest tylko arm64) — bez ostrzeżenia
  o wielu pasujących celach.

### D168 · 2026-10-25 — Dogłębny przegląd kodu całości (7 obszarów) i poprawki
Przegląd tylko do odczytu całego kodu (ok. 67 tys. linii aplikacji i pakietu) w siedmiu obszarach, potem poprawki
z weryfikacją każdego zgłoszenia. Ok. 130 zgłoszeń; prawie wszystkie potwierdzone i naprawione, z testami.
Najważniejsze:
- **Agent AI:** `agent.compile` wykonuje dokładnie polecenia z okna zgody (przypięte pod kluczem wewnętrznym, jak
  połączenie w D163) — wcześniej agent mógł podmienić tekst okna w czasie oczekiwania na zgodę; komendy edycji agenta
  nie działają w Oknie poleceń ani w oknie tylko do odczytu i trafiają do „Cofnij sesję agenta”; `sql.historyBack/Forward`
  poza listą komend agenta; argumenty spoza schematu narzędzia usuwane; walidacja stanu menu obowiązuje przy
  `run_command`; hasła w dzienniku i panelu agenta ukrywane; wywołania na sesji agenta szeregowane (równoległe
  zapytanie nie wycofa zatwierdzonego DML).
- **Transakcje:** sterownik thin robi ROLLBACK przed wylogowaniem (logoff Oracle zatwierdza transakcję), CONNECT /
  DISCONNECT w Oknie poleceń pytają o COMMIT/ROLLBACK, zamknięcie aplikacji nie gubi nieudanego COMMIT, okno dialogowe
  z dwoma „Anuluj” (zamknięcie okna bez zapisu) poprawione; zamknięcie okna w trakcie zwykłego wykonania jest odmawiane
  z komunikatem (nie przerywa wykonania), w trakcie debugowania — zatrzymuje debuger.
- **Strażnik zmian:** komendy obiektów (odświeżenie MV, uruchomienie zadania, kosz, ccflags, kompilacja próbna) i
  zadania lokalne bez COMMIT przechodzą przez strażnika; `WITH FUNCTION` traktowane jak zmieniające.
- **Dane:** porównanie i przenoszenie danych wiążą LOB/RAW zamiast literału (wcześniej BLOB > 2000 B zapisywał się
  jako NULL); wartości nieprzenoszalne (obcięte, obiekty, BFILE) przerywają operację z błędem przed zmianą w bazie;
  import CSV z CRLF, uszkodzony xlsx, separator wieloznakowy i słowa zastrzeżone w nagłówkach bez awarii.
- **ODPI `RETURNING INTO`:** wartości DML … RETURNING czytane przez `dpiVar_getReturnedData` — wcześniej ROWID
  wstawionego w siatce wiersza wychodził NULL, więc jego usunięcie albo odświeżenie przed ponownym zapytaniem nic nie
  robiło w bazie. Wykryła to nowa kontrola liczby zmienionych wierszy przy zapisie siatki (UPDATE/DELETE po ROWID bez
  skutku = wiersz zmieniony przez inną sesję).
- **Edytory obiektów:** klucz obcy do innego schematu, kolumny identity (ALWAYS, licznik) przy Recreate, nazwy z małymi
  literami, kolejność DROP w ALTER, cytowanie kolumn indeksów.
- **SSH:** do known_hosts trafiają dokładnie klucze, których odciski potwierdził użytkownik (bez drugiego połączenia
  accept-new). Klucze odczytuje `ssh` z opcjami sesji do pliku tymczasowego, bez logowania — `ssh-keyscan` nie przyjmuje
  algorytmów starych serwerów (AIX: diffie-hellman-group14-sha1, ssh-rsa) i nie odczytałby ich klucza;
  zerwane połączenie wdrożenia (kod 255) to błąd, nie Stop; dwa równoległe otwarcia tunelu nie uruchamiają dwóch ssh.
- **Bezpieczeństwo pozostałe:** okno raportu i druk HTML bez JavaScriptu, z CSP i blokadą nawigacji (dodatkowy CSS
  z cudzego pliku .rep nie wstrzyknie skryptu); hasła z CONNECT/IDENTIFIED BY poza historiami i maskowane w echu/SPOOL;
  pliki historii, konsol i makr 0600; nazwy plików eksportu DDL bez `/` i `..`.
- Martwy kod i pozostałości usunięte (m.in. mechanizm komend „zapowiedzianych”, `describeOnly`, nieużywane ustawienia
  `allowMultipleConnections` i `autoCommitPostedRecords` — stare pliki ustawień nadal się wczytują); ustawienia bez
  kontrolki dostały kontrolki w Preferencjach; wyszukiwarka Preferencji znajduje etykiety Stepper i z interpolacją.

Świadomie bez zmian:
- Komunikaty sterowników (PelikanDB/ODPI/Thin) po polsku bez L10n — warstwa sterownika nie zależy od katalogu tekstów;
  do przeniesienia przy typowanych błędach sterownika.
- Thin: limit czasu wywołania (`callTimeoutMs`) nie działa, tak jak przerwanie — OracleNIO tego nie udostępnia.
- Tunel SSH bazy (`SSHTunnelManager`) nadal przez `Foundation.Process` (Workspace nie zależy od PelikanRemote, D61).
- Nazwa aplikacji w tekstach interfejsu zostaje literałem; identyfikatory techniczne biorą ją z Brand.xcconfig.
- Pusta nazwa połączenia zadania lokalnego = połączenie główne (wcześniej: aktywnego okna).
- Styl raportu zapisywany stałym identyfikatorem; stare pliki z polską nazwą stylu wczytują się.
- Przełączniki SET w Command Window bez osobnych komend rejestru; dwie metody druku HTML w UIServices; wspólna pętla
  pobierania raportów — refaktoryzacja poza zakresem przeglądu. Entitlements Quick Look bez zmian (do sprawdzenia przy
  notaryzacji).

### D169 · 2026-10-26 — Drugie przejście przeglądu kodu
Drugie przejście objęło pliki, które w pierwszym (D168) przejrzano tylko pobieżnie, oraz sam kod poprawek z D168.
Zależności sprawdzone ponownie — bez zmian względem D167. Ok. 60 zgłoszeń, wszystkie potwierdzone i naprawione, z testami:
- **Formater (D24):** cztery przypadki, w których zmieniał działanie kodu — wcięcie doklejane wewnątrz wielolinijkowego
  literału przy formatowaniu zaznaczenia, `/` dzielenia brany za terminator, sklejanie poleceń SQL*Plus (SET, PROMPT,
  DEFINE) z następnymi liniami, zmiana wielkości liter w kodzie MLE (JavaScript) i JAVA SOURCE. Weryfikacja wyniku
  porównuje teraz także granice poleceń skryptu i dokładny tekst poleceń SQL*Plus; przy niezgodności formater odmawia.
  Do tego CASE w wyrażeniu, REFERENCING … AS w wyzwalaczu, kolejne metody TYPE BODY, COMPOUND TRIGGER w konspekcie.
- **Refaktoryzacje:** odmawiają zamiast zmieniać znaczenie (przypisanie → inicjalizacja tylko dla pierwszej instrukcji
  bez zależności); zmiana nazwy zmiennej lokalnej tylko w zakresie jej deklaracji; IN OUT dla całej listy INTO; stała
  lokalna w wyzwalaczu bez DECLARE; kodowanie plików projektu (D55) w refaktoryzacji i wyszukiwaniu.
- **Test Manager** w trybie jednej/dwóch sesji wycofywał i zamykał sesję główną (zmiany innych okien przepadały) — każdy
  test ma teraz własną sesję; AutoCommit okna testu nie zatwierdza testów Test Managera.
- **Debuger:** sprzątanie (DEBUG_OFF) po każdym błędzie startu i kroku; Stop w trakcie wykonania; przywrócenie
  `plsql_optimize_level` po debugowaniu (wcześniej obiekty kompilowane później w tej sesji dostawały poziom 1); dane
  ze stanu programu w kawałkach bezpiecznych bajtowo (polskie znaki); wartości zmiennych według typu.
- **Regresje z D168:** przenoszenie danych sprawdza rozmiar LOB przed TRUNCATE/DELETE (inaczej tabela mogła zostać pusta);
  dziennik agenta maskuje tylko hasło zamiast ukrywać cały tekst ze słowem PASSWORD; odczyt potoku HOST w osobnym
  wątku (zamknięcie uchwytu w trakcie odczytu groziło awarią); stan „rozłączone” okna Command Window w dokumencie (COMMIT/F10
  i pasek stanu nie traktują go jak połączonego z głównym); kolejka poleceń Command Window bez przełączania kart.
- **Spójność:** jeden widok HTML bez JavaScriptu i nawigacji w aplikacji, jeden nagłówek CSP w pakiecie, maskowanie
  `IDENTIFIED BY VALUES '…'`, usunięte martwe gałęzie ORA-24344.
- **Budowanie:** wersje pakietów aplikacji (Sparkle, SwiftTerm i ich zależności) przypięte w
  `Pelikan.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Bez tego pliku xcodebuild dopisywał je do
  `Packages/PelikanKit/Package.resolved` przy każdym budowaniu (zmiana w drzewie roboczym, wersje bez przypięcia w repo).

Korekta D168: identyfikatory techniczne w domenie ustawień aplikacji (autozapis okien `Pelikan.*`, `PelikanMainWindow`,
`PelikanAppliedLanguage`) zostają literałami — zmiana kasowałaby zapamiętane położenia okien użytkowników; z Brand.xcconfig
bierze nazwę moduł sesji i okno dziennika agentów.
Rozmiar elementu `SYS.DBMS_DEBUG_VC2COLL` potwierdzony na bazie testowej: 1000 bajtów — dawne kawałki po 4000 znaków
w debugerze nie mieściły się nawet przy samym ASCII.

### D170 · 2026-10-26 — Dziennik aplikacji
Właściciel poprosił o „sensowny log dla aplikacji”. Wcześniej były tylko trzy wywołania `NSLog`.
- **Moduł `PelikanLog`** bez zależności (działa też na Linuksie): `Log.<obszar>` (app, connection, sql, command, agent,
  ssh, proc, update, tools, debugger, tests, keychain) z poziomami debug/info/notice/error/fault. Treść wpisu to
  `LogMessage` z interpolacją jak `os.Logger`: tekst domyślnie prywatny, liczby i wartości logiczne jawne, inne typy
  wymagają `privacy:`; `\(error)` daje jawny kod (ORA-00942, `CommandError.notAvailable`, domena i kod NSError)
  i prywatny komunikat. Treść jest budowana tylko, gdy poziom jest włączony.
- **Ujścia:** plik `~/Library/Logs/<nazwa>/<nazwa>.log` (katalog 0700, pliki 0600, rotacja 5 × 2 MB, zapis na osobnej
  kolejce) i dziennik systemowy macOS (podsystem = bundle id). Bez konfiguracji (biblioteka, testy) wpisy nigdzie nie
  trafiają; testy dodają własne ujście diagnostyczne (`MemoryLogSink(everything: true)`) zamiast zmieniać globalne
  ustawienia, więc mogą działać równolegle.
- **Prywatność:** nigdy hasła, treść poleceń SQL, wartości zmiennych ani dane z bazy — wpisy SQL mają tylko rodzaj
  polecenia, czas i liczbę wierszy. Nazwy połączeń, serwerów i katalogów domyślnie jako skrót HMAC-SHA256 z losowym
  kluczem instalacji (`PelikanLogKey` w domenie ustawień aplikacji) — ta sama nazwa ma ten sam skrót, ale skrótu nie da
  się odwrócić słownikiem nazw. `LogRedactor` maskuje hasła w typowych zapisach i katalog domowy także w wartościach
  jawnych (druga linia obrony). Jawne nazwy — opcja w Preferencjach, domyślnie wyłączona.
- **Ustawienia:** Preferencje › Ogólne › Dziennik aplikacji — *Ostrzeżenia i błędy* / *Zdarzenia (zalecane)* /
  *Szczegóły — diagnostyka* i jawne nazwy. **Pomoc › Dziennik aplikacji** otwiera plik w Konsoli; **Pomoc › Eksportuj
  dziennik…** zapisuje pliki z opisem środowiska (wersja, system, sterowniki, liczba połączeń — bez nazw). Obie komendy
  bez dostępu agenta.
- **Co trafia do dziennika:** start (wersja, system, język) i zamknięcie; łączenie (czas, sterownik, rodzaj sesji,
  kod błędu, ponowne pytanie o hasło, wygasłe hasło), rozłączenie, utrata połączenia, zamykanie bezczynnych sesji;
  komendy (debug: każda; notice: zakończone błędem); okno SQL i okno poleceń (debug: każde polecenie; info: podsumowanie
  i błędy); zadania w tle (start, wynik, czas); debuger (start, koniec, przerwanie; ślad DBMS_DEBUG na poziomie
  Szczegóły zamiast dawnego pliku `PELIKAN_DEBUG_TRACE`); Test Manager i utPLSQL (podsumowania, instalator); tunele SSH
  i połączenia SSH Pro*C; wdrożenia Pro*C; serwer i sesje agentów, wywołania narzędzi, odmowy i zgody (szczegóły zostają
  w osobnym dzienniku agentów JSONL); Pęk kluczy (zapis, błędy z kodem OSStatus); aktualizacje Sparkle; komunikaty
  błędów pokazane użytkownikowi; `PELIKAN_STALL_LOG` przez dziennik zamiast `NSLog`.
- Wpisy po polsku (język źródłowy projektu), bez tłumaczeń — to tekst techniczny, nie interfejs.

### D171 · 2026-10-26 — Wstążka i „Szukaj czynności” zamiast szukania w menu

Właściciel: setki funkcji dostępne tylko z menu i skrótów to „ergonomiczna porażka” — ma być szybko, bez dodatkowych
kliknięć i bez klawiszologii. Dotychczasowe zastąpienie wstążek wzorca menu macOS (PD-UI-005) zostaje, a nad dokumentami
dochodzi **wstążka** (PD-UI-012) jako akcesorium paska tytułu okna głównego:
- karty stałe Start, Edycja, Obiekty, Debugowanie i testy, Narzędzia, Raporty, Widok; karty kontekstowe (Wynik, Program,
  Okno poleceń, Plan, Diagram, Raport, Notatnik) widoczne tylko przy oknie swojego rodzaju, w kolorze znacznika okna;
- wybór karty zapamiętany dla każdego rodzaju okna; pierwszy raz: program → Program, test → Debugowanie i testy,
  plan/diagram/raport/notatnik → ich karta, SQL i okno poleceń → Start (najczęstsze: wykonanie, COMMIT/ROLLBACK);
- częste czynności — duże przyciski, pozostałe małe po trzy w kolumnie, rzadsze w listach rozwijanych grup; listy mogą
  mieć wzorzec `prefiks.*` (formaty kopiowania, raporty z menu — także dodane przez użytkownika);
- **każda komenda z menu jest na wstążce** — test pokrycia z jawną listą wyjątków (karta okna, ostatnie pliki,
  przeciąganie obiektu, komendy pomocnicze okien); nowa komenda bez miejsca na wstążce czerwieni test;
- pole **Szukaj czynności…** zawsze widoczne obok kart (klik i pisanie, bez skrótu): dopasowanie bez wielkości liter i
  polskich znaków, po początkach słów, słowach kluczowych (synonimy, nazwy funkcji wzorca po angielsku) i angielskich
  tytułach z katalogu tłumaczeń; wyniki pokazują miejsce na wstążce, skrót i dostępność; ta sama wyszukiwarka w palecie
  komend (⇧⌘P);
- podpowiedź przycisku: opis i skrót (nauka skrótów przy okazji); prawy klik — pasek szybkiego dostępu;
- zwijanie do samych kart (dwuklik karty, strzałka, komenda) i ukrywanie — Widok › Wstążka, Preferencje › Ogólne;
- układ wstążki jest w kodzie (`RibbonModel`), bez edytora; dostosowanie zostaje dla paska narzędzi i szybkiego dostępu.
Ikony z symboli SF (bez grafik wzorca); test sprawdza, że każdy symbol istnieje w systemie.

### D172 · 2026-10-26 — Logo aplikacji

Właściciel poprosił o graficzne logo. Pelikan nie miał ikony (systemowa ikona ogólna). Własny rysunek, bez grafik
wzorca i znaków towarowych Oracle: biały pelikan z żółtym dziobem i pomarańczowym workiem na niebieskim tle z falami,
obok walec bazy danych (narzędzie do baz). Kształt i margines według siatki ikon macOS (824 pt w polu 1024, cień).
Rysunek jest kodem (`scripts/icon/make-icon.swift`, CoreGraphics) — generuje PNG 16–1024 px do
`App/Resources/Assets.xcassets/AppIcon.appiconset`; zmiana logo = zmiana skryptu i ponowne uruchomienie. Ten sam obraz
(256 px) w `docs/logo.png` dla README.

### D173 · 2026-10-26 — Zgłaszanie problemów na GitHubie

Właściciel: gdy wyskoczy błąd, pytanie, czy wysłać zgłoszenie, które trafia na GitHuba. Zgłoszenie to nowe Issue w
repozytorium z `PELIKAN_REPOSITORY` (Brand.xcconfig → Info.plist `PelikanRepository`). Pelikan **niczego nie wysyła
sam**: otwiera stronę `…/issues/new` z wypełnionym tytułem i treścią, a użytkownik wysyła ją ze swojego konta GitHub —
bez tokenów, serwera pośredniczącego i zbierania danych w tle (repozytorium jest publiczne, a token w aplikacji
pozwalałby każdemu pisać w imieniu właściciela).
- Wejścia: Pomoc › Zgłoś problem… (i wstążka), przycisk „Zgłoś problem…” w każdym komunikacie błędu, pytanie po
  nieoczekiwanym zamknięciu (znacznik `.running` w katalogu danych usuwany przy czystym zamknięciu; „Nie pytaj
  więcej” jak inne pytania). Bez pytań w przebiegu zrzutów (`PELIKAN_UI_SCRIPT`).
- Treść: opis użytkownika, komunikat błędu albo opis awarii z najnowszego raportu macOS (`DiagnosticReports/<nazwa>-….ips`
  nie starszego niż start poprzedniej sesji: wyjątek, sygnał, przyczyna, stos wątku z awarią — tylko nazwy modułów
  i symboli, bez ścieżek), opis środowiska (jak w eksporcie dziennika) i 80 ostatnich wpisów dziennika (nazwy ukryte,
  chyba że użytkownik je włączył). Całość przez `LogRedactor` (hasła, ścieżka domowa).
- Okno z ostrzeżeniem, że zgłoszenie jest publiczne, przełącznikami części i podglądem dokładnej treści; treść zawsze
  w schowku. Adres dłuższy niż ok. 7500 znaków: dziennik skracany od najstarszych wpisów, komunikat o wklejeniu
  pełnej treści ze schowka.

### D174 · 2026-10-26 — Precyzyjne ustawienia formatera z podglądem każdej opcji

Właściciel: precyzyjne ustawianie formatowania to kluczowe ułatwienie; podgląd ma pokazywać zmianę każdej opcji, a opcje
mają objąć to, co mają formatery (szczególnie wyrównanie i wielkość liter). Do dotychczasowych reguł doszło 20
(z ustawieniami domyślnymi wynik bez zmian — stare testy przechodzą bez modyfikacji):
- **Klauzule i łamanie linii:** słowa klauzul do lewej z elementami w kolumnie (jak dotąd), do prawej („rzeka”: słowa
  kończą się w kolumnie SELECT) albo w osobnej linii z elementami wciętymi; AND/OR na początku albo końcu linii; warunek
  JOIN … ON w nowej linii albo w linii JOIN; THEN w nowej linii; wyrażenie CASE w jednej linii albo WHEN/ELSE/END w
  osobnych liniach (w SQL i PL/SQL; AND w warunku CASE nie łamie już linii WHERE).
- **Wyrównanie w kolumnach** — osobny przebieg po gotowych liniach (`BeautifierAligner`), który dodaje wyłącznie
  spacje przed wybranymi tokenami: deklaracje (typ, `:=`/DEFAULT), parametry (tryb, typ, DEFAULT; także z przecinkiem na
  początku linii), parametry nazwane `=>`, kolejne przypisania `:=`, aliasy w SELECT i FROM, `=` w UPDATE … SET,
  komentarze na końcu kolejnych linii. Pomija linie skopiowane bez zmian (SQL*Plus, Java/JavaScript, regiony bez
  formatowania) i linie z wieloliniowym literałem lub komentarzem.
- **Odstępy:** wokół operatorów (bez spacji tylko tam, gdzie tokeny się nie skleją — `a- -1`, nie `a--1`; `:=` i `=>`
  zawsze ze spacjami), po przecinku, wewnątrz nawiasów. **Puste linie:** najwięcej n z rzędu, pusta linia przed
  podprogramem.
- **Wielkość liter grup słów:** typy danych (domyślnie jak słowa kluczowe), funkcje wbudowane przed „(” i pakiety
  dostarczane z bazą przed „.” (domyślnie jak identyfikatory). Listy w `SQLWords`. Literały, identyfikatory w
  cudzysłowie i komentarze — nigdy.
- Znaczniki regionu bez formatowania także `-- @formatter:off/on` (SQL Developer, Trivadis).
- **Preferencje › Formater:** grupy opcji; po prawej przykład opcji wskazanej kursorem albo ostatnio zmienionej
  („Teraz” / „Po zmianie tej opcji”, `BeautifierExamples`) i podgląd pakietu z podświetleniem linii zmienionych ostatnią
  zmianą. Test pilnuje, że **każda** opcja zmienia swój przykład i kod podglądu (przy ustawieniach domyślnych i przy
  „ciężkich”), a każda właściwość `BeautifierOptions` poza formatowaniem automatycznym ma przykład.
- Bezpieczeństwo bez zmian: `Beautifier.verify` porównuje tokeny; test formatuje korpus przy każdej opcji osobno, przy
  narastającej kombinacji wszystkich i sprawdza idempotencję. Wydajność z wszystkimi wyrównaniami: pakiet 50 000 linii
  w ok. 3 s w kompilacji testowej (tokeny linii w pamięci podręcznej).

### D175 · 2026-10-26 — Filtr nazw przeglądarki obiektów: fragment nazwy

Właściciel woli `%nazwa%` zamiast `nazwa%`. Tekst filtra bez `%` szuka teraz w dowolnym miejscu nazwy (`emp` → `%EMP%`);
wzorzec z `%` działa jak wpisany (`EMP%` — tylko początek). Dawne zachowanie (dopisywanie `%` na końcu) zostaje jako
**Preferencje › Object Browser › Filtr nazw bez %** (`browserFilterContains`, domyślnie „zawiera”). LIKE z `%` na początku
nie korzysta z indeksu słownika; zapytanie i tak jest zawężone do właściciela i typu obiektu.

### D176 · 2026-10-26 — Okna przywracane po ponownym uruchomieniu, także niezapisane i bez pliku

Właściciel: okna z tekstem bez pliku mają po zamknięciu i ponownym otwarciu aplikacji wrócić w stanie sprzed
zamknięcia (nadal bez pliku), a aplikacja ma się otwierać z tymi samymi oknami. Mechanizm już był — autozapis workseta
przy zakończeniu aplikacji (domyślnie włączony, UG 15) zapisuje okna z niezapisanym tekstem bez pytania o zapis i
przywraca je przy starcie — ale pomijał okna planu, diagramu, notatnika i raportu, a konsole połączeń wracały jako
zwykłe okna SQL. Teraz workset zapisuje wszystkie rodzaje okien (diagram, notatnik i raport — model JSON, gdy okno nie
ma pliku albo ma zmiany; plan — zapytanie; okno testu — także obserwowane wyrażenia), konsola wraca jako konsola
(tekst z magazynu konsol), a aktywne okno jest liczone ze wszystkich. Okno bez pliku wraca bez pliku i z oznaczeniem
zmiany, więc ⌘S pyta o nazwę, a zamknięcie okna — o zapis. Przełącznik doszedł do **Preferencje › Ogólne › Pliki**
(wcześniej tylko **Plik › Workset › Autozapis workseta**). Zamknięcie pojedynczego okna nadal pyta o zapis jak dotąd.
Sprawdzone na aplikacji w tle: okna otwarte skryptem, zakończenie zwykłym „Zakończ” (`NSRunningApplication.terminate`),
ponowne uruchomienie — te same cztery okna, z tekstem i tym samym aktywnym.

### D177 · 2026-10-26 — Czytelne czcionki i okna o zmiennym rozmiarze

Właściciel: czcionki interfejsu wyglądają źle, a okna bez zmiany rozmiaru (np. Preferencje) są kłopotliwe.
- **Czcionki:** interfejs używał wielu bardzo małych rozmiarów — `caption`/`caption2`/`footnote` (10 pt, ok. 170 miejsc),
  9–10,5 pt w AppKit i 10–11 pt w podglądach kodu — w różnych kombinacjach. Teraz najmniejszy tekst ma 11 pt
  (`subheadline`, `smallSystemFontSize`), kod w podglądach i wynikach 12 pt (jak siatka), wstążka: podpisy 12 pt, karty
  13 pt, podpisy grup 11 pt; edytor bez zmian (SF Mono 13, ustawienie użytkownika).
- **Wstążka:** rząd przycisków ma stałą wysokość — podpisy grup w jednej linii; bez paska przewijania, który przy
  ustawieniu macOS „pokazuj paski przewijania: zawsze” zasłaniał podpisy grup (szeroką kartę przewija gest albo kółko).
- **Okna:** Preferencje dostały zmianę rozmiaru, minimalizację i zapamiętaną ramkę; okna i arkusze SwiftUI ze stałym
  rozmiarem (logowanie, edytor połączenia, Znajdź i zamień, sesje, arkusze agenta, scheduler, DBA, narzędzia siatki)
  mają rozmiar minimalny i początkowy zamiast stałego (`windowSize(width:height:)`); panel Znajdź i zamień i paleta komend
  też dają się powiększać. Wyjątek: lista podpowiedzi edytora (dopasowana do treści).

### D178 · 2026-10-26 — Konfigurowalne czcionki interfejsu, edytora, siatki i Object Browsera

Właściciel: konfiguracja wielkości czcionek elementów interfejsu i samej czcionki (krój, styl) jest pożądana. W
Preferencjach osobno dla czterech obszarów: krój (rodziny zainstalowane w systemie; edytor — o stałej szerokości),
styl (cienka, zwykła, średnio gruba, półgruba, gruba) i wielkość:
- **interfejs** (Ogólne › Czcionka interfejsu; domyślnie SF Pro 13 pt): etykiety, listy połączeń i okien, wstążka,
  karty okien, pasek stanu, okna narzędzi, arkusze i Preferencje. Tekst pomocniczy jest o 2 pt mniejszy, podpisy wstążki
  i kart — o 1 pt. W SwiftUI domyślna czcionka korzeni okien i style `.ui`, `.uiSecondary`, `.uiHeadline` w miejsce
  `.subheadline`/`.headline`; w AppKit `InterfaceFonts` (obserwowany — zmiana odświeża widoki na żywo, także wysokość
  wierszy list). Menu i tytuły okien rysuje macOS — tych czcionek aplikacja nie zmienia;
- **edytor** (dotąd krój z krótkiej listy i wielkość) — dowolny krój o stałej szerokości i styl;
- **siatka wyników** (dotąd tylko wielkość) — krój (domyślnie systemowa o stałej szerokości) i styl;
- **Object Browser** (dotąd tylko wielkość) — krój i styl; bez własnych — jak interfejs (o 1 pt mniejsza).
Krój zapisany w ustawieniach, którego nie ma w systemie (np. ustawienia przeniesione z innego Maca), zostaje w wyborze
z dopiskiem „niezainstalowana” i zastępuje go czcionka systemowa. Skrypt zrzutów ma krok `debug.settings` (ustawienia
z argumentów) — zrzut z krojem Avenir Next 14 pt potwierdza zmianę wstążki, kart, list, paska stanu i Preferencji.

### D179 · 2026-10-26 — Lewa kolumna i wstążka bez efektu przezroczystości

Właściciel: czcionki w drzewie obiektów są „nierówne, poszarpane”, ładne, gdy aplikacja jest nieaktywna, a koszmarne
po aktywacji. Przyczyna: lewa kolumna (pasek boczny) i wstążka (akcesorium paska tytułu) leżały na półprzezroczystym
tle `NSVisualEffectView`; w aktywnym oknie tekst na nim jest rysowany trybem vibrancy (mieszanie z tłem bez zwykłego
wygładzania), co na monitorach bez Retina daje kanciaste, nierówne litery. W nieaktywnym oknie tło staje się jednolite i
tekst wygląda dobrze. Sprawdzone zrzutem okna przeniesionego na monitor 1× (krok skryptu `debug.moveToScreen`, usunięty w D182): z
wymuszonym efektem litery kanciaste, bez — gładkie. Teraz lewa kolumna i wstążka mają własne tło
(`SolidBackgroundView` — efekt w stałym stanie „nieaktywnym”, materiał paska bocznego i paska tytułu, jasny i ciemny
tryb bez zmian w kolorach), więc tekst jest zawsze rysowany zwykłym trybem. Antyaliasing i skalowanie były poprawne:
drzewo używa czcionki systemowej bez przekształceń.

### D180 · 2026-10-26 — Lewy panel jako zwykły panel okna, bez „płynnego szkła”

Po D179 wstążka była poprawna, ale cały lewy panel nadal miał w aktywnym oknie poszarpane litery na monitorach bez
Retina. Hierarchia widoków (zrzut przodków etykiety w działającej aplikacji): pasek boczny `NSSplitViewItem` w
zachowaniu `.sidebar` leży w macOS 26+ w `NSGlassEffectView` (Liquid Glass), który przetwarza całą zawartość panelu —
tło z D179 było wewnątrz szkła i nie pomagało. Lewy panel jest teraz zwykłym elementem podziału okna (bez szkła;
priorytet utrzymania szerokości jak pasek boczny, zwijanie bez zmian); tekst jest rysowany zwykłym trybem. Skutek
uboczny: wstążka biegnie przez całą szerokość okna, a lewy panel zaczyna się pod nią — układ jak w PL/SQL Developerze.

### D181 · 2026-10-26 — Ciało pakietu/typu razem ze specyfikacją, wcięcia drzewek, widoczny znacznik zwijania

Uwagi właściciela:
- **Pakiety i typy w jednym oknie:** pakiet otwierany z folderu „Pakiety” miał już specyfikację i ciało na dwóch
  kartach okna programu, ale ciało otwierane z „Ciał pakietów” albo „Ciał typów” otwierało się samo. Teraz Edytuj na
  ciele otwiera parę (jedno okno, karta ciała aktywna — kursor na początku drugiej jednostki, także po automatycznym
  formatowaniu). Ciało jest dołączane tylko, gdy istnieje: typ bez metod, kolekcja i pakiet bez ciała mają jedną kartę
  (test na bazie: typ `AS OBJECT` bez ciała — jedna jednostka).
- **Wcięcia drzewek:** zawartość kodu, przeglądarka obiektów i lista połączeń miały styl listy paska bocznego macOS,
  który prawie nie wcina dzieci (ok. 10 pt). Teraz styl zwykły z wcięciem 16 pt na poziom.
- **Znacznik zwijania kodu:** znak „▸/▾” małą czcionką numerów i bladym kolorem był niemal niewidoczny. Teraz symbol
  strzałki (do 12 pt, pogrubiony, kolor tekstu pomocniczego; zwinięty — kolor akcentu), margines szerszy o 6 pt, obszar
  kliknięcia 16 pt.

### D182 · 2026-10-27 — Trzecia runda przeglądu kodu: stos, ostrzeżenia, spójność i poprawki

Właściciel poprosił o kolejną rundę dogłębnego przeglądu z podziałem na subagentów: najpierw recenzenci (tylko odczyt),
potem poprawiający. Ośmiu recenzentów: aktualność stosu i zależności, ostrzeżenia budowania i testów (także CI),
zmiany D170–D181, aplikacja (dwie części), PelikanWorkspace (dwie części), pozostałe moduły i skrypty. Ok. 150
zgłoszeń, bez krytycznych; dziewięciu poprawiających w osobnych gałęziach, scalonych w jeden PR. Pominięte: 1
(ostrzeżenia Xcode w akcji wstępnej schematu — kosmetyka z ryzykiem dla numeru wersji), częściowe: kilka (niżej).

- **Stos:** wszystkie zależności SPM, ODPI-C, utPLSQL, Instant Client, XcodeGen i akcje CI w najnowszych wersjach (jak
  D167). Budowanie aplikacji i pakietu (debug, release, strict concurrency) bez ostrzeżeń; jedyne ostrzeżenie było na
  Linuksie (ProblemReport) — poprawione, a CI ma bramkę zatrzymującą na każdym ostrzeżeniu kompilatora w pakiecie.
  Włączone cechy Swift `InferIsolatedConformances`, `ImmutableWeakCaptures`, `MemberImportVisibility`;
  `NonisolatedNonsendingByDefault` odłożone (przeniosłoby ok. 460 funkcji `nonisolated async` na wątek główny —
  wymaga audytu z `@concurrent`). swift-tools 6.3, Xcode w CI przypięty (27.1), token CI tylko do odczytu, sumy SHA-256
  pobrań, środowisko testowe na Alpine 3.24 i Swift 6.4. Sparkle wymaga podpisanego kanału i weryfikuje aktualizację
  przed rozpakowaniem (generate_appcast podpisuje kanał sam). Dependabot — nie (otwierałby PR-y samodzielnie).
- **Testy SSH:** zawieszanie w `TestSSHD.deinit` (`waitUntilExit` na wątku puli) było przyczyną czerwonych przebiegów CI;
  serwery testowe kończą się teraz z limitem czasu, `make test` uruchamia testy jak CI, a skrypt testów SSH nie dotyka
  procesów testów innych projektów.
- **Worksety (D176):** okna workseta nieotwartego przy starcie (`noloaddesktop`, `workset=`) nie są nadpisywane
  autozapisem, pliki z Findera otwierane przy starcie czekają na przywrócenie workseta; zmiana workseta zamyka okna
  drogą Zamknij (transakcja, wykonanie, debuger; Anuluj przerywa); format pliku (kodowanie, BOM, CRLF) w worksecie;
  nazwy bez rozróżniania wielkości liter. Nieczytelne pliki danych (połączenia, worksety, cele SSH, historia wdrożeń) są
  odkładane jako `<plik>.bad-<data>` z komunikatem zamiast cichego nadpisania.
- **Sesje i transakcje:** flaga „transakcja otwarta” odczytywana z sesji po oknie testu, debugerze i notatniku; utrata
  sesji zeruje ją tylko w oknach tej sesji; polecenia z niejawnym COMMIT w sesji kompilacji; test linku bazy w osobnej
  sesji. Tunel SSH: host i użytkownik walidowane jak w Pro*C, cel po `--` (wcześniej `-oProxyCommand=…` w polu hosta
  uruchamiał polecenie), hasło SSH z Touch ID (D56). „Zakończ sesję okna” zabija parę SID+SERIAL# z chwili połączenia,
  Kill i akcje przeglądarki sesji przez strażnika zmian. Okno jest „wykonujące” od F8, przed pytaniami i łączeniem.
- **Agent AI i prywatność:** połączenia tymczasowe z CONNECT w Oknie poleceń (także AS SYSDBA) poza zasięgiem agenta;
  raport, źródło przenoszenia i eksport zadania lokalnego wykonują tylko zapytanie, sprawdzane przed wykonaniem.
  Dziennik (D170): przełącznik odsłania tylko nazwy (`.hash`), nigdy treści komunikatów; zgłoszenie usterki (D173)
  pokazuje komunikat błędu do edycji albo pominięcia. Raport pokrycia utPLSQL w oknie aplikacji bez JavaScriptu
  i zasobów z sieci (eksport do pliku dla przeglądarki — świadomie z zasobami utPLSQL).
- **Dane:** format własny i Kopiowanie schematu zachowują strefę TIMESTAMP WITH TIME ZONE, wartości nieprzenoszalne
  przerywają z błędem (zasada D168); kolumny wirtualne, INVISIBLE i identity ALWAYS obsłużone w eksporcie, imporcie,
  porównaniu i przenoszeniu; Recreate table sprawdza liczbę wierszy kopii przed DROP; import z „Utwórz” wykonuje tylko
  DDL tej tabeli, w schemacie docelowym; nazwy w cudzysłowie bez zmiany wielkości liter; JAVA SOURCE z poprawnym
  nagłówkiem; filtr `%nazwa%` (D175) we wszystkich folderach; zapis okna zachowuje dowiązanie i uprawnienia.
- **Sterowniki:** thin czytał CLOB tylko do ok. 32 600 znaków bez znacznika obcięcia (OracleNIO przesuwa pozycję
  w bajtach, a CLOB liczy znaki) — teraz jednym żądaniem do limitu w znakach; thin bez OOB (oracle-nio #124: 19c z OOB
  bez FastAuth zrywał połączenie; przerwania thin i tak nie ma); TSTZ ze strefą nazwaną jako UTC z oznaczeniem (tablica
  regionów Oracle nie jest dostępna — częściowo). ODPI: kursory zagnieżdżone `CURSOR(…)` bez ORA-01000. Podział skryptu
  w Command Window liniowy (8000 poleceń: 7,2 s → 0,26 s). Most MCP i serwer agenta nie gubią odpowiedzi po EOF.
- **Edytor i interfejs:** okno programu dzieli tekst na jednostki raz na zmianę (wcześniej przy każdym rysowaniu
  marginesu); Znajdź i zamień, To-Do, historia i komendy edycji odmawiają w oknie tylko do odczytu i w trakcie
  wykonania; pola kodu bez „inteligentnych” cudzysłowów (`'abc'` → `‘abc’` dawało ORA-00911). Wysokości wierszy drzew,
  list i wstążki z czcionki (D178), pozostałe listy bez vibrancy (D179), jedna czcionka kodu w podglądach; paleta
  komend i „Szukaj czynności” z tymi samymi kandydatami, bez wykonywania niedostępnych; czynności dostępne tylko
  z jednego miejsca interfejsu są komendami rejestru. Okna narzędzi ustalają połączenie przy otwarciu i je pokazują.

Częściowo / świadomie bez zmian: sortowanie siatki kliknięciem nagłówka nie jest komendą; etykiety kanwy Query
Buildera stałe jak w diagramie; File Browser listuje katalogi synchronicznie; przeglądarka różnic nie przewija sama do
zmiany w linii; wspólny pasek stanu okien SQL/Program/Test — refaktoryzacja poza zakresem; ORDS i XcodeGen w CI bez
przypięcia wersji (brak wersjonowanych adresów).

### D183 · 2026-10-27 — Dokowanie narzędzi w panelach okna głównego (zmienia D112)
Właściciel poprosił o prawdziwe dokowanie okien narzędzi (dotąd każde otwierało się w osobnym oknie), preferowane po
prawej. Okno główne ma dwa panele narzędzi w zagnieżdżonych podziałach — prawy obok obszaru dokumentów i dolny pod
nim — żeby zapamiętany układ kolumn (lewa kolumna, panel agenta) się nie zmienił; rozmiar paneli jest zapamiętany.
Wszystkie narzędzia z `ToolWindowController.show` (ok. 70) oraz Large Data Editor, informacje o obiekcie i dziennik
agentów otwierają się domyślnie w prawym panelu, każde w karcie. Karta przechodzi do drugiego panelu przeciągnięciem,
a upuszczona poza panelami — do osobnego okna w miejscu upuszczenia; to samo robią menu karty i przyciski nagłówka
panelu, a okno narzędzia wraca do panelu przyciskiem na pasku tytułu. Każda czynność jest komendą
(`view.toolDockRight|Bottom`, `view.dockToolRight|Bottom`, `view.floatTool`, `view.closeTool`, `view.toolDockAutoHide`;
agent — brak dostępu), miejsce przeniesionego narzędzia jest zapamiętane dla jego rodzaju (`toolDock` w ustawieniach,
klucze jednorazowe `diff-…`, `table-…` dzielą miejsce rodzaju). W Preferencjach: miejsce nowych narzędzi (prawy
panel, dolny panel albo osobne okna jak przed D183), autoukrywanie (fokus w edytorze chowa panele) i przywrócenie
miejsc domyślnych. Zgoda na operację agenta domyślnie zostaje w osobnym oknie. Zwinięty panel z narzędziami pokazuje
na pasku stanu przycisk z liczbą narzędzi; ⌘W z fokusem w panelu zamyka narzędzie, nie okno dokumentu.

- **Przenoszenie bez utraty stanu:** widok narzędzia (SwiftUI albo AppKit) przechodzi między panelem a oknem ten sam,
  więc `@State` zostaje. SwiftUI wywołuje jednak przy tym onDisappear/onAppear i przerywa `.task`: przerwanie
  wyszukiwania, zatrzymanie monitora zdarzeń i testu obciążenia przeszły na `onToolClose` (tylko przy zamknięciu
  narzędzia), wczytanie zależne od połączenia — na `toolTask(id:)` (raz dla wartości), a wypełnienie pól na starcie —
  na `onFirstAppear`. Karty panelu przełączają się ukrywaniem widoków (bez zdarzeń cyklu życia).
- **Rozmiar:** w panelu widok SwiftUI zgłasza tylko minimum; mniejszy panel przewija zawartość, a otwarcie narzędzia
  poszerza panel do jego minimum (najwyżej 60% obszaru). Wypełnienie ma priorytet niższy niż podział okna — inaczej
  minimum narzędzia rozpychało panel.
- **Skróty:** SwiftUI obsługuje `keyboardShortcut` (Enter — przycisk domyślny, Esc — Anuluj) poza hierarchią widoków,
  w całym oknie: Enter w drzewie obiektów wykonywał przycisk domyślny narzędzia z panelu (sprawdzone w osobnym
  procesie). Okno główne na czas obsługi skrótu ukrywa narzędzia paneli bez fokusu — skrót działa tylko w narzędziu,
  w którym jest kursor, i nie przejmuje skrótów menu.
- **Instrukcja:** `NavigationSplitView` dokłada elementy do paska narzędzi okna i w panelu okna głównego zapętlał układ
  (zawieszenie przy otwarciu instrukcji) — zastąpiony `HSplitView`, jak w innych narzędziach. Dodatek paska tytułu
  okna narzędzia jest w kontenerze o stałej ramce (AppKit nie pozwala przesuwać widoku dodatku).

Karty lewej kolumny (połączenia, obiekty, okna, szablony, pliki) zostają w niej; otwarte narzędzia nie są
przywracane po ponownym uruchomieniu (jak dotąd okna narzędzi). Zrzuty w tle: `60-dokowanie`, `61-dokowanie-powrot`;
istniejące scenariusze narzędzi pokazują je teraz w panelu okna głównego.

### D184 · 2026-10-27 — Koniec bety: wydanie 1.0.0 i numeracja semantyczna
Właściciel zdecydował o wyjściu z bety bez etapu RC: stan po dokowaniu narzędzi (D183) to 1.0.0, a przeglądarka
obiektów w stylu DBeavera (połączenia w drzewie) wejdzie jako 1.1.0; 1.0.0 publikowane od razu po scaleniu (słowo
właściciela). Dotychczasowa reguła (pierwsza cyfra co 10 scalonych PR) dała 10.x bez znaczenia, więc od scalenia
PR #102 numer jest semantyczny i dalej automatyczny: tytuł PR `feat…` podnosi środkową cyfrę, pozostałe — ostatnią,
`typ!:`/„BREAKING CHANGE” — główną (tylko na słowo właściciela); commity po scaleniu nie zmieniają numeru. Stara
reguła zostaje dla historii sprzed #102. Bezpieczeństwo przejścia 10.5.0 → 1.0.0: Sparkle porównuje numer kompilacji
(liczba commitów, rośnie), a instalator `.pkg` ma wyłączone `BundleIsVersionChecked` (inaczej mógłby pominąć
„starszą” aplikację); znaczniki v7.9.0–v10.5.0 nie kolidują z v1.x. `scripts/version-test.sh` (w CI) sprawdza regułę
na tymczasowym repozytorium. Notatki wydań stabilnych: `docs/NOWOSCI.md`; `docs/BETA.md` zostaje jako historia bet.

### D185 · 2026-10-27 — Przeglądarka obiektów z wieloma połączeniami (jak w DBeaverze)
Właściciel poprosił, żeby Object Browser pokazywał wszystkie uruchomione połączenia, znikające po rozłączeniu, z
wyróżnionym połączeniem głównym, które jest domyślne tylko wtedy, gdy kontekst wywołania nie wskazuje innego.
`SessionManager.openConnections` to otwarte połączenia w kolejności połączenia: od pierwszej sesji poza agentem AI
(sesja agenta nie dodaje połączenia do drzewa użytkownika) albo ustawienia jako główne do rozłączenia; zamknięcie
bezczynnej i utrata sesji go nie usuwają. Drzewo: gałąź na połączenie (główne pierwsze, ★, pogrubione, „główne”,
kolor połączenia), pod nią foldery, Ostatnie i foldery użytkownika; wybór użytkownika osobno dla każdej gałęzi (lista
nad drzewem dotyczy gałęzi zaznaczonego wiersza), filtr — wspólny. Zaznaczenie zapisuje połączenie gałęzi
(`Workspace.selectedObjectConnection`); zaznaczenie wielu obiektów obejmuje jedno połączenie.

Połączenie komendy obiektu (`CommandContext.objectConnection`): argument `connection`; obiekt wskazany nazwą
(`object`, `objects`) — połączenie aktywnego okna (okno poleceń przekazuje swoje połączenie jawnie); bez argumentów —
gałąź zaznaczonego obiektu; dopiero potem główne. Wszystkie `ob.*` mają parametr `connection`; „Porównaj z obiektem
w innej bazie” zachowuje swój `connection` (druga baza, nazwą), a obiekt bierze z kontekstu. Okno otwarte dla obiektu
innego połączenia niż główne jest do niego przypięte (`Workspace.bind`, zostaje w worksecie); dla głównego — jak dotąd.
Przeciągnięcie obiektu niesie połączenie gałęzi (czwarta część schowka; stary format trzech części działa). Nowe
obiekty („Nowa tabela…”, prosty edytor), wyszukiwanie obiektów i kompilacja niepoprawnych — połączenie aktywnego okna.
Poprawione przy okazji: „Wczytaj ponownie z bazy” czytał źródło z połączenia głównego zamiast okna; generator kodu
brał alias połączenia głównego. Pierwsze zbudowanie drzewa po wczytaniu widoku (synchronicznie z loadView kolumna
zostawała wąska i nazwy były obcinane). Komendy połączeń przyjmują też nazwę definicji (skrypty, scenariusze zrzutów).

### D186 · 2026-10-27 — Eksport i import połączeń z hasłami (wyjątek od „hasła tylko w Pęku kluczy”)
Właściciel poprosił o eksport i import połączeń wraz z zapisanymi hasłami, z wyborem haseł zaszyfrowanych albo jawnych,
eksport po dodatkowym uwierzytelnieniu, plik importu usuwany po imporcie. Wariant jawny łamie zasadę z PROMPT
(„hasła tylko w Pęku kluczy, nigdy w plikach”) — zgłoszone właścicielowi; potwierdził go wprost: po latach hasło może
nie być zapisane nigdzie poza Pelikanem, a bywa potrzebne do konfiguracji innego narzędzia.

Komenda `connection.exportWithPasswords` (Sesja › Połączenia, wstążka; agent — brak dostępu, wywołanie przez agenta
odrzucone także w kodzie): wybór trybu (argument `mode` albo pytanie), dla jawnego osobne ostrzeżenie, zawsze
uwierzytelnienie właściciela Maca (`authenticateOwner` — Touch ID albo hasło, niezależnie od ustawienia z D56),
fraza tylko z okna z polami NSSecureTextField (z powtórzeniem, min. 8 znaków), plik 0600. Format: zwykły eksport
definicji (starszy import wczyta same definicje) + sekcja `secrets` — `plain` (hasło bazy i tunelu SSH dla
identyfikatora definicji z pliku) albo `encrypted`: AES-256-GCM, klucz PBKDF2-HMAC-SHA256 (600 000 iteracji, sól 16
bajtów; CommonCrypto na macOS, implementacja w Swifcie z HMAC na Linuksie, zgodna z wektorami RFC 7914). Import
(`connection.import`): plik z hasłami — fraza dla zaszyfrowanego (zła fraza: nic nie zaimportowano, plik zostaje),
hasła do Pęku kluczy pod nowymi identyfikatorami (konflikt id — nowe id, jak dotąd), definicja z hasłem bazy dostaje
„zapisz hasło”; po udanym imporcie plik z hasłami jest usuwany (`removeItem`, bez Kosza — kopia w Koszu zostawiałaby
hasła); plik bez haseł zostaje jak dotąd. Dziennik — tylko liczby definicji i haseł. Ograniczenie: usunięcie pliku
na dysku SSD nie gwarantuje zamazania danych — instrukcja i ostrzeżenie każą trzymać plik w bezpiecznym miejscu.

### D187 · 2026-10-27 — Przeglądarka obiektów: obiekty własne, dostępne i publiczne
Właściciel zgłosił, że w przeglądarce brakuje wielu łączy bazy danych, katalogów Oracle i synonimów — obiektów
dostępnych w schemacie, choć jego właścicielem nie jest. Przyczyna: tryb *Bieżący użytkownik* filtrował każdy folder po
właścicielu = schemat (publiczne łącza i synonimy mają właściciela PUBLIC, obiekty nadane — inny schemat), a katalogi
(właściciel SYS) zawsze pochodziły z ALL_DIRECTORIES, także przy widokach DBA. Zakres folderu (`ObjectScope`):
*Bieżący użytkownik* — własne obiekty, publiczne łącza bazy i publiczne synonimy obiektów aplikacji (cel spoza schematów
utrzymywanych przez Oracle: ALL_USERS.ORACLE_MAINTAINED od 12c, na 11g lista schematów — bez ~8600 synonimów SYS);
nowy *Dostępne obiekty* — widoki ALL_* bez filtra właściciela (własne, nadane, publiczne; synonimy publiczne jak wyżej);
*Wszyscy użytkownicy* i wybrany schemat — jak dotąd, z widokami DBA, gdy dostępne, także katalogi (DBA_DIRECTORIES).
Obiekty spoza własnego schematu mają w drzewie właściciela przed nazwą. Publiczne synonymy aplikacji pobiera osobne
zapytanie do ALL_SYNONYMS: połączone z ALL_OBJECTS (`object_name in (…)`) trwało na bazie testowej 77 s, osobno —
setne części sekundy; filtr nazw je obejmuje, filtr stanu, źródła i filtr nazwany — nie. Preferencja **Po połączeniu
pokazuj** (Object Browser) wybiera tryb startowy gałęzi; domyślnie *Bieżący użytkownik*. Test na bazie: drugi schemat
z tabelą nadaną i nienadaną, publiczny synonim, publiczne łącze, katalog z uprawnieniem; limit czasu folderów.

### D188 · 2026-10-27 — Łącza bazy danych z *_DB_LINKS
Po 1.2.2 właściciel zgłosił, że łączy bazy dalej brakuje. Łącza są teraz czytane z widoków wskazanych przez Oracle
(Database Reference 19c, ALL_DB_LINKS / DBA_DB_LINKS), nie z ALL_OBJECTS. Prywatne łącze może używać i widzieć w
ALL_DB_LINKS tylko jego właściciel (Administrator's Guide 19c, 31.2.7), więc łącza schematu aplikacji, gdy łączysz się
innym użytkownikiem, są tylko w DBA_DB_LINKS: tryb *Wszyscy użytkownicy* i wybrany schemat sięgają po DBA_DB_LINKS
(i DBA_DIRECTORIES), gdy da się je czytać — także bez SELECT ANY DICTIONARY / SELECT_CATALOG_ROLE, przy nadanym SELECT
na sam widok (sprawdzane zapytaniem, wynik pamiętany do odświeżenia). *Bieżący użytkownik* i *Dostępne obiekty*
pokazują łącza własne i publiczne. Baza testowa: użytkownik testowy ma SELECT na DBA_DB_LINKS (`testdb.sh`), test
z prywatnym łączem schematu SYSTEM.
ALL_OBJECTS nie musi zawierać publicznych łączy bazy — źródłem łączy są widoki *_DB_LINKS. Folder Katalogi (obiekty
bez właściciela schematu) czyta DBA_DIRECTORIES we wszystkich trybach, gdy da się go czytać; ALL_DIRECTORIES pokazuje
tylko katalogi z nadanym uprawnieniem.


### D189 · 2026-10-28 — Czwarta runda przeglądu kodu: połączenie narzędzi, sesje wspólne, zgodność słownika, Hardened Runtime

Właściciel poprosił o kolejną rundę dogłębnego przeglądu (stos, ostrzeżenia, spójność, pozostałości) z podziałem na
subagentów: ośmiu recenzentów tylko do odczytu (stos i zależności, ostrzeżenia budowania i testów, zmiany D183–D188,
aplikacja ×2, PelikanWorkspace ×2, pozostałe moduły, skrypty i dokumentacja), potem dwunastu poprawiających w osobnych
gałęziach scalonych w jeden PR. 153 zgłoszenia (11 wysokich, 52 średnie, 90 niskich). Przed poprawkami: stos aktualny
poza łatkami swift-collections 1.7.5 i swift-png 4.5.2 (podniesione), budowanie aplikacji i pakietu bez ostrzeżeń,
`xcodebuild analyze` tylko znane miejsca ODPI-C, testy zielone (618 jednostkowych, 49 SSH, 240 na bazie).

- **Połączenie narzędzi (D185):** Znajdź obiekty i Kompiluj niepoprawne pracowały na połączeniu głównym, a trafienia
  otwierały na połączeniu aktywnego okna (możliwy obiekt o tej samej nazwie z innej bazy). Narzędzia ustalają połączenie
  przy otwarciu, pokazują je z wyborem (także Test Manager i Test Explorer), a `Workspace.openObject` przyjmuje połączenie
  pochodzenia obiektu (narzędzia, utPLSQL, debuger, projekt, użycia). Komendy `utplsql.*` mają parametr `connection`,
  ponowienie nieudanych — połączenie ostatniego przebiegu. Narzędzie wywołane dla innego argumentu (QBE, Filtr kolumn,
  wdrożenie Pro*C) zastępuje otwarte zamiast je przywołać; przeniesienie narzędzia (D183) nie ponawia zapytań; Esc
  w trakcie przeciągania nie odłącza narzędzia; auto-odświeżanie wstrzymane, gdy narzędzie jest niewidoczne. Zgoda na
  operację agenta to arkusz — okno `approval` w D183 to podgląd ze scenariusza zrzutów.
- **Sesje wspólne:** w trybach Dwie sesje i Jedna sesja CONNECT/DISCONNECT w Oknie poleceń zamykały sesję główną
  (wycofanie zmian innych okien) — okno teraz tylko się odpina, a sesję zamyka tylko w trybie Wiele sesji. Debuger
  czyta źródła i typy przez sesję nadzorującą (wcześniej czekał na sesję główną zajętą debugowanym blokiem); sesja
  nadzorująca ma limit oczekiwania 5 s (blok z błędem kompilacji kończy debugowanie po ok. 5 s zamiast godziny);
  debugowanie zostaje dostępne w trybie Jedna sesja. Utrata połączenia zeruje „transakcja otwarta” we wszystkich oknach
  tej sesji (serwer już wycofał). Rozłączenie i wylogowanie odmawiają, gdy okno połączenia wykonuje polecenie (wcześniej
  sesja była zamykana pod wykonaniem); zamykanie bezczynnych sesji sprawdza bezczynność ponownie po zapytaniu.
- **Słownik i edytory obiektów:** edytor tabeli czytał `ALL_TAB_COLS.DATA_DEFAULT_VC` (dopiero od 23ai — ORA-00904 na
  19c i starszych), widoku `ALL_VIEWS.TEXT_VC` (obcięte do 4000 znaków, zapis odtwarzał widok z obciętym zapytaniem).
  Teraz kolumny LONG (`DATA_DEFAULT`, `SEARCH_CONDITION`, `TEXT`) na każdej wersji, wariant 11g bez kolumn 12c; tekst
  krótszy niż `TEXT_LENGTH` wyłącza edycję; zmiana nazwy widoku najpierw tworzy nowy. Wyzwalacze i indeksy innego
  schematu niż tabela — w schemacie właściciela. Prywatne łącze innego schematu (DBA_DB_LINKS, D188) można oglądać,
  ale nie usunąć ani przetestować (wcześniej trafiało się we własne łącze o tej samej nazwie); filtr nazwany i filtry
  stanu/źródła nie dotyczą łączy ani katalogów; pamiętany jest tylko brak uprawnień do widoku DBA_. Prefiks właściciela
  pomijany dla własnego schematu we wszystkich trybach; filtr domyślny gałęzi pochodzi z połączenia głównego. DDL zadań
  Schedulera i kolejek przez typy PROCOBJ/AQ_QUEUE; „DDL zaznaczonych” nie powtarza ciała pakietu przy specyfikacji.
  Drzewo przeglądarki zachowuje rozwinięcie i zaznaczenie po odświeżeniu.
- **Agent AI:** narzędzia edytora agenta odmawiają okien połączeń ukrytych przed agentem (tekst z `IDENTIFIED BY`
  trafiał do agenta), `get_editor` zakrywa hasła; maskowanie kolumn odrzuca obejścia (`*` w argumencie funkcji,
  DBMS_XMLGEN/DBMS_SQL/XMLQUERY/XMLTABLE, CURSOR, nazwa maskowanej kolumny w literale — pozostałe obejścia opisane
  w SECURITY.md). Wynik narzędzia ponad ok. 2 MB jest przycinany ze znacznikiem `result_truncated`, ramka ponad 4 MB
  zastępowana błędem JSON-RPC, most kończy się kodem 1 z komunikatem (wcześniej ciche `exit(0)`); limit „Największy
  wynik” 50 → 1,5 MB. „Cofnij sesję agenta” zamyka okna drogą Zamknij i nie kasuje konfliktów z historii. Deklarowane
  poziomy dostępu agenta zwykłych komend (96 komend spoza `agent.*` i `AgentPolicy.appCommands`) ustawione na Brak —
  zgodnie z D33 i tak nie były osiągalne; test pilnuje spójności rejestru. Import preferencji pyta, gdy zmienia
  ustawienia uruchamiające programy lub ładujące biblioteki; link `pelikan://` otwiera tylko istniejący workset.
- **Eksport haseł (D186):** plik 0600 od utworzenia (O_EXCL, potem zmiana nazwy); na dysku bez praw POSIX plik jawny
  jest usuwany z błędem, zaszyfrowany zostaje z ostrzeżeniem. Pusta fraza lub uszkodzona sól — komunikat zamiast
  awarii (`precondition` w PBKDF2). Definicje połączeń są uwierzytelnione razem z hasłami (AAD = SHA-256 definicji,
  pole `authenticatesDefinitions`; starsze pliki czytelne), limit iteracji przy otwieraniu 2 000 000, liczenie poza
  wątkiem głównym. Import wycofuje zapisane hasła i definicje po błędzie (bez duplikatów przy ponowieniu); eksport
  bierze hasło wpisane w tej sesji. Pęk kluczy: aktualizacja wpisu zamiast usunięcia i dodania.
- **Dane i skrypty:** narzędzia danych po błędzie lub przerwaniu wycofują niezatwierdzone wiersze i przywracają
  wyzwalacze i klucze (wcześniej następne narzędzie zatwierdzało pół importu; ALTER identity commitował go od razu).
  Zasada nazw: nazwy ze słownika przechodzą bez zmian, normalizowane są tylko wpisane (`ResultExporter.dictionaryName`,
  uzupełnia D182). Kopiowanie schematu przesyła wiersze porcjami po 5000; eksport do pliku ponad 500 MB kończy się
  błędem (strumieniowy zapis wymaga wyboru pliku przed eksportem — później). TIMESTAMP WITH LOCAL TIME ZONE w UTC.
  `@plik`, `@@`, START, GET, FORMAT FILE i BEAUTIFY w Oknie poleceń dekodują i zapisują plik jak edytor (BOM,
  Windows-1250, kodowanie projektu, CRLF). Siatka: przy sortowaniu/filtrze porównania, „Kolumna do plików” i zapytania
  powiązane brały inne wiersze niż zaznaczone.
- **Git w przeglądarce plików:** automatyczne odczyty (`status`, `log`, `show`, `rev-parse`) nie wykonują poleceń
  z konfiguracji obcego repozytorium (`core.fsmonitor`, hooki, `log.showSignature`/`gpg.program`, lokalne filtry
  clean/smudge, textconv, submoduły); `add`/`commit` z woli użytkownika — jak git w terminalu. Skutek uboczny: plik
  z filtrem tylko lokalnym może chwilowo wyglądać na zmieniony.
- **Sterowniki:** `$X{…}` z nieznaną funkcją zostaje błędem zamiast zawsze prawdziwego `0 = 0` (`DELETE … WHERE`
  usuwał wszystko); DBMS_OUTPUT czytany w całości z jawnym znacznikiem obcięcia; CREATE MLE ENV dzielony jak DDL;
  maski dat z literałami w cudzysłowie (`"T"`), JSON z datą w ISO 8601; nieczytelny BFILE pokazuje błąd w komórce;
  ODPI nie dodaje referencji do wyników niejawnych (wyciek); EZConnect/hostname przed LDAP w NAMES.DIRECTORY_PATH
  zostawia nazwę klientowi. **Thin (OracleNIO):** odpowiedź LOB z liczbą znaków ≥ 65 536 kończyła proces
  (`preconditionFailure` w `readSB8`, błąd sprzed tej rundy) — odczyt CLOB w thin ograniczony do 65 535 znaków ze
  znacznikiem obcięcia (zawęża D182 dla thin); kolumny INTERVAL YEAR TO MONTH i BFILE kończą proces w dekoderze
  wierszy OracleNIO (`fatalError` „not implemented”) zanim wartość dotrze do Pelikana — bez obejścia po naszej stronie,
  do zgłoszenia w oracle-nio; VECTOR obsłużony; możliwość JSON wyłączona (dekodowanie stratne); parametry EZConnect
  Plus (`?…`) pomijane w nazwie usługi.
- **Aplikacja:** zamknięcie okna głównego = zakończenie aplikacji (z pytaniami o zapis i transakcje); kliknięcie
  w Docku przywraca okno. Czynności dostępne dotąd tylko z interfejsu są komendami (komórki notatnika, elementy
  projektu, snippety, makra, panel debugera, kanwa diagramu, kolejność Code Contents); czynności na wskazanym elemencie
  mają `inMenu: false` i argument; gest na kanwie zmienia dokument jedną komendą na końcu. Komendy panelu agenta są na
  wstążce (Narzędzia › Agent AI) i w wyszukiwarce. Preferencja „przypinaj nowe okna do połączenia” zaczęła działać.
  Wykonanie SQL w sesji debugowanej to komenda `debug.executeInTarget` przez strażnika zmian.
- **Podpis i budowanie:** Hardened Runtime włączony (także przy podpisie ad hoc — jawne `--options=runtime`), jedyne
  uprawnienie `com.apple.security.cs.disable-library-validation` (Instant Client przez `dlopen`), bez
  `allow-dyld-environment-variables`; CI sprawdza flagę. `ENABLE_USER_SCRIPT_SANDBOXING` włączone. ODPI-C bez
  `-Wno-everything` (czysty przy `-Wall -Wextra`). Bramka ostrzeżeń CI obejmuje też `App/` i `ld: warning`; aplikacja
  w konfiguracji Release budowana w CI tylko po scaleniu na main (w PR dodawałaby ok. 10 min); `cancel-in-progress`
  tylko dla PR; `actions/checkout` przypięty do SHA bez `persist-credentials`; Swift na Linuksie przypięty do 6.4.1;
  shellcheck w CI. Stare `FileHandle.seekToEndOfFile()`/`write(_:)` (wyjątek ObjC przy pełnym dysku) zastąpione wszędzie.
- **Wersje (D184):** główna cyfra rośnie tylko przy `typ!:` albo tytule zaczynającym się od `BREAKING CHANGE:`
  (wcześniej także przy słowach w środku tytułu); `version.sh` jednym `git log` (3,3 → 0,6 s).
- **Baza testowa:** `make testdb` czekał na „READY” z poprzedniego startu i padał na SIGPIPE przy dużym dzienniku;
  `seed` kończył się sukcesem mimo nieudanego logowania; Workspace Manager instalowany tylko w PDB (FREEPDB1 po
  restarcie w trybie RESTRICTED) — teraz w CDB$ROOT i PDB; `up` uruchamia też kontener SSH, a testy tunelu bez serwera
  są pomijane. Hasło kontenera przez `--env-file`.

Częściowo / świadomie bez zmian: wyszarzanie pozycji menu dla obcego łącza (wymaga synchronicznej wiedzy o użytkowniku
sesji); eksport danych strumieniowo do pliku; zamknięcie okna z niezatwierdzonymi zmianami siatki bez pytania (szersza
luka); ostrzeżenie o utracie uprawnień przy zmianie nazwy widoku; parser `ls -la` i `scp(download:)` zostają jako
PC-SSH-004/002; upuszczenie narzędzia w oknie głównym poza panelami nadal je odłącza (D183); Xcode 27.2 w CI i 27.1
lokalnie oraz odtworzenie lokalnego kontenera bazy z przypiętego obrazu (`testdb.sh reset`) — do decyzji właściciela.

### D190 · 2026-10-28 — Kolejność alfabetyczna połączeń, kopia i przenoszenie połączeń, foldery DBA i DBMS (zmienia D185)

Właściciel poprosił: foldery i połączenia na liście połączeń alfabetycznie, kopia połączenia pod inną nazwą,
przenoszenie połączeń między folderami myszą, połączenia w zakładce Obiekty też alfabetycznie, a w Obiektach na końcu
folderów DBA i DBMS z obiektami `DBA_…` i `DBMS_…`, do których użytkownik ma uprawnienia.

- **Kolejność:** `ConnectionStore.subfolders(of:)` i `connections(in:)` zwracają foldery i połączenia alfabetycznie
  (`localizedStandardCompare` — bez wielkości liter, liczby naturalnie: „baza 2” przed „Baza 10”), także połączenia
  dopasowane regułą folderu; folder „Ostatnie” zostaje w kolejności użycia. Gałęzie Object Browsera alfabetycznie tą
  samą regułą (`ConnectionStore.alphabetical`) — **zmiana D185** („główne pierwsze”): połączenie główne nie jest już
  przesuwane na początek, wyróżniają je nadal ★, pogrubienie i dopisek „główne”.
- **Kopia:** komenda `connection.duplicate` (Sesja › Połączenia, wstążka, menu kontekstowe „Kopiuj pod inną nazwą…”;
  agent — Brak): pyta o nazwę (domyślnie „<nazwa> (kopia)”), kopia w tym samym folderze z nowym identyfikatorem, bez
  historii użycia i bez łączenia przy starcie; nazwa musi być unikalna (bez wielkości liter — komendy i parametry
  startowe wskazują połączenie nazwą); zapisane hasło bazy i hasło SSH tunelu kopiowane w Pęku kluczy pod nowe konto,
  hasło tylko z tej sesji — tylko do pamięci (jak oryginał). Każdy błąd wycofuje kopię z jej hasłami. Połączenia
  tymczasowego (CONNECT w oknie poleceń) nie da się skopiować ani przenieść — czytelny błąd.
- **Przenoszenie:** komenda `connection.moveToFolder` (argumenty `connection` i `folder` — id albo nazwa, bez folderu —
  poziom główny; `inMenu: false`), wywoływana przez przeciągnięcie połączenia na folder albo wolne miejsce listy
  (upuszczenie na połączenie albo jego okno — do folderu połączenia; „Ostatnie” nie jest celem) i przez podmenu „Przenieś do folderu”
  (dostęp z klawiatury i VoiceOver). Przeciągane są tylko połączenia, nie foldery.
- **Foldery DBA i DBMS** (na końcu gałęzi każdego połączenia, po folderach typów): `MetadataProvider.systemObjects`
  czyta ALL_OBJECTS z nazwą `DBA\_%` / `DBMS\_%` (podkreślenie dosłownie), wszyscy właściciele — ALL_OBJECTS pokazuje
  obiekt innego schematu tylko z uprawnieniem (wprost, przez rolę, PUBLIC), więc lista odpowiada uprawnieniom.
  Pominięte synonimy (publiczne synonimy `DBA_…` i `DBMS_…` widzi każdy, także bez uprawnień do obiektu — sprawdzone
  na użytkowniku agenta testów: synonim DBA_USERS widoczny, widok nie), ciała pakietów i typów oraz klasy Java.
  Tylko typy znane przeglądarce. Obiekty schematu SYS bez przedrostka „SYS.”; filtr pola jak w folderach typów (nazwy,
  `status=`, `source=`, daty), filtr nazwany — nie. Wynik w pamięci podręcznej do odświeżenia. Użytkownik z samym
  SELECT ANY DICTIONARY widzi widoki DBA_ w ALL_OBJECTS (sprawdzone na 26ai) — folder nie jest pusty.
- **Obiekty schematów Oracle** (przegląd kodu przed scaleniem): foldery DBA i DBMS stawiają pakiety SYS pod ręką
  w każdym trybie, a np. „Dodaj informację debugowania” na `SYS.DBMS_OUTPUT` wykonywała się bez pytania i mogła
  unieważnić obiekty w całej bazie. `Workspace.confirmOracleMaintained`: rekompilacja (także zaznaczonych), DEBUG,
  DROP (także zaznaczonych), zmiana nazwy obiektu i elementu, włączanie/wyłączanie, flagi kompilacji warunkowej
  oraz kompilacja okna programu z jednostką schematu utrzymywanego przez Oracle (SYS, XDB, GSMADMIN_INTERNAL… — lista
  11g i nowszych wersji; jednostka bez właściciela w nagłówku — bieżący schemat sesji, więc także SYS zalogowany jako
  SYS) — zawsze osobne pytanie z domyślnym **Anuluj**, niezależnie od preferencji potwierdzania; bez interfejsu
  (skrypt) — odmowa. Typy globalne (katalogi, użytkownicy, role, profile) pomijane — katalog ma zawsze właściciela
  SYS. Domyślna nazwa kopii połączenia — pierwsza wolna („… (kopia)”, „… (kopia 2)”…).

### D191 · 2026-10-28 — Zgłoszenia #111–#114, przyciski wstążki bez argumentów, „Rekord” na karcie Wynik

Właściciel zgłosił, że „Rekord” na karcie Wynik nic nie robi, i poprosił o rozwiązanie zgłoszeń z GitHuba (#111–#114,
wszystkie z bazy 19.3). Wspólna przyczyna #111, #112 i „Rekordu”: przycisk wstążki wywołuje komendę bez argumentów,
a część komend wymagała argumentu (podawanego przez panel, agenta albo skrypt) albo tylko zwracała dane.

- **Rekord:** `grid.recordView` zwracała dane rekordu bez zmiany widoku. Nowa `grid.toggleRecordView` przełącza stan
  karty wyniku (`ResultTab.showsRecord`); przycisk w pasku siatki i „Rekord” na wstążce wywołują ją, widok idzie za
  stanem. `grid.recordView` zostaje komendą danych bez zmiany widoku (agent, skrypty, komentarze kolumn dla widoku)
  poza menu, ze skutkiem „brak” — nie nagrywa się w makrach.
- **Komendy wstążki bez argumentów (#111 „Wstaw snippet”, #112 „Wstaw szablon” i 20 kolejnych):** wywołane przez
  użytkownika bez argumentu pytają (lista z etykietami, pole tekstowe, wybór pliku lub katalogu) albo biorą
  zaznaczenie — przeglądarka plików udostępnia zaznaczony plik i pokazaną lokalizację (`FileBrowser.selectedURL`,
  `currentLocationID`, synchronizowane z panelem w obie strony), ale tylko gdy panel jest naprawdę widoczny
  (`FileBrowser.isPaneVisible` — zwinięta lewa kolumna jest ukryta, a nie odpięta); gdy nie ma czego wybrać — odmowa
  z komunikatem, co zrobić. Przeniesienie do Kosza elementu z zaznaczenia pyta zawsze (pełna ścieżka), także przy
  wyłączonym potwierdzeniu. Błąd argumentu bez argumentu dostaje tylko agent; skrypty interfejsu i makra działają jako
  użytkownik i pytają jak przycisk. Argumenty wybrane w oknie komenda zwraca w `CommandResult.resolvedArguments`,
  a makro nagrywa je zamiast pustych — odtworzenie nie otwiera okna ponownie. Lista wyboru ma etykiety bez powtórzeń
  (dopisek „(2)”). Test `RibbonArgumentTests` wywołuje każdą komendę wstążki z jakimikolwiek parametrami (wymaganymi
  albo nie) bez argumentów i zawodzi, gdy kończy się błędem argumentu bez pytania — parametry opcjonalne z wartością
  domyślną przechodzą same (komenda bierze domyślną albo odmawia z komunikatem); lista `askWhenMissing` pilnuje, żeby
  komendy już poprawione zostały na wstążce.
- **AWR, ASH, ADDM (#113, #114):** ORA-00904 „DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_HTML: invalid identifier” to brak
  uprawnienia EXECUTE do pakietu (Oracle odpowiada w SQL „invalid identifier”, nie ORA-01031 — sprawdzone na bazie).
  Prawidłowe użycie: EXECUTE do SYS.DBMS_WORKLOAD_REPOSITORY (raport ADDM — DBMS_ADDM), zwykle przez rolę DBA,
  i licencja Oracle Diagnostics Pack. Pelikan sprawdza uprawnienie przed raportem (pakiet SYS jest w ALL_OBJECTS tylko
  z uprawnieniem) — w komendach AWR i ADDM przed odczytem migawek (bez uprawnienia DBA_HIST_SNAPSHOT dawałby
  ORA-00942) — i podaje komunikat z poleceniem GRANT (nazwa użytkownika spoza `A–Z 0–9 _ $ #` w cudzysłowach). ADDM
  sprawdza najpierw DBMS_WORKLOAD_REPOSITORY: DBMS_ADDM bywa nadany PUBLIC (baza testowa 23ai), więc sam nie mówi nic
  o dostępie do migawek. Uprawnienie do pakietu bez dostępu do słownika (np. tylko rola OEM_MONITOR) — komunikat
  z GRANT SELECT_CATALOG_ROLE zamiast ORA-00942.
- **Autotrace:** polecenie ze zmiennymi wiązanymi (`:nazwa`, także zmienne PL/SQL zamienione przy zaznaczeniu
  w oknie programu) kończyło się ORA-01008 (dziennik z #113). Autotrace pyta o zmienne jak okno SQL (wartości
  zapamiętane w oknie) i wykonuje polecenie z wiązaniem; przy wyłączonym podstawianiu okna `&` zostaje w tekście bez
  pytania, a o zmienne wiązane pyta zawsze.

### D192 · 2026-10-28 — Okno programu: karty jednostek pokazują jedną jednostkę, nawigacja i bogatsza Zawartość kodu

Zgłoszenie właściciela: specyfikacja i ciało pakietu są w jednym oknie mimo kart u góry, klik karty nic nie daje,
a struktura pakietu z lewej nie nawiguje i jest uboższa niż w innych programach.

- **Przyczyna braku nawigacji** (ustalona w działającej aplikacji Debug — zrzuty i dziennik kolejności obserwatorów):
  (1) karty i Zawartość kodu ustawiały tylko kursor w jednym długim tekście; w małym pakiecie (EMP_API) cel był już
  na ekranie, więc nic się nie zmieniało, a aktywnej karty nie było; (2) skok do miejsca poza ekranem często w ogóle
  nie przewijał edytora: zaznaczenie z modelu stosowały dwa obserwatory śledzące `Document.selectedRange` —
  `syncFromModel` (zaznaczenie i przewinięcie) oraz `applyAdditionalSelections` (dodatkowe kursory, także zaznaczenie
  główne, bez przewinięcia i z wyłączonym powiadomieniem widoku). Kolejność ich wywołania nie jest stała; gdy pierwszy
  był drugi, `syncFromModel` zastawał zaznaczenie już ustawione i nie przewijał, a pasek pozycji pokazywał stare
  „1:1”. Teraz bez dodatkowych kursorów zaznaczenie główne stosuje tylko `syncFromModel`. (3) TextKit 2 szacuje
  położenie nieułożonego tekstu — po zmianie ukrytych akapitów `scrollRangeToVisible` trafia obok celu; przewinięcie
  (`scrollToSelection`) sprawdza ramkę fragmentu po układzie widocznego obszaru i poprawia położenie (do czterech
  razy, bez układu całego tekstu).
- **Karty:** dokument zostaje jeden (zapis, F8 — wszystkie jednostki, worksety, historia lokalna, agent bez zmian).
  Tekst dzieli się na rozłączne odcinki pełnych linii (`ProgramUnitTabs`): kończący `/` należy do jednostki przed
  nim, puste linie i komentarz przed `CREATE` — do następnej. Edytor ukrywa odcinki innych kart tym samym
  mechanizmem co zwijanie (`FoldingContentDelegate` pomija akapity, zakresy zwinięć i kart scalone). Karta aktywna to
  zawsze karta odcinka z kursorem (`Document.activeUnitTab`) — dlatego każde przejście z modelu w inne miejsce tekstu
  przełącza kartę samo: komunikat kompilacji, Zawartość kodu, Znajdź następne/poprzednie, Przejdź do deklaracji, Idź do
  linii, zakładki, linia debugera (zatrzymanie w innej jednostce), Wstecz/Naprzód, Search Bar, agent
  (`replace_range`, przejście do linii — linie dokumentu), Cofnij/Ponów zmiany w innej jednostce. Punkty przerwania
  stawia się kliknięciem w margines widocznej karty. Kursor i zaznaczenie z klawiatury i myszy zostają na karcie
  (strzałki, ⌘A, ⇧⌘↓ przycinane do odcinka, przycięcie przewija do kursora), a edycja z klawiatury nie usuwa znaku
  nowej linii oddzielającego następną kartę. Karta aktywna: wciśnięta i pogrubiona (w aktywnym oknie — kolor akcentu);
  w Zawartości kodu pogrubiony jej korzeń. Okno z jedną jednostką — bez zmian.
- **Komendy** (agent: Brak, jak pozostałe `prog.*`): `prog.selectUnit` (argument `unit`: numer od 1, nazwa, „nazwa
  body” albo tytuł karty; bez argumentu — wybór z listy jak w D191, makro nagrywa wybór), `prog.nextUnit` /
  `prog.previousUnit` (w kółko). Skróty: wzorzec nie ma domyślnych (docs/research/keys.md) — ⌃⇟/⌃⇞ w profilu PL/SQL
  Developer (jak przełączanie kart w programach Windows) i ⌥⌘] / ⌥⌘[ w obu profilach (MacBook bez klawiszy stron);
  bez kolizji w rejestrze. Klik karty wywołuje `prog.selectUnit`; przejście na kartę wraca kursorem w miejsce, w którym
  był na niej ostatnio (pierwszy raz — linia nagłówka jednostki) i zapisuje skok w historii nawigacji. Wstążka:
  karta kontekstowa **Program**, grupa **Jednostki** (Pokaż jednostkę, Poprzednia, Następna).
- **Numery linii:** na karcie jednostki margines, pasek pozycji, lista komunikatów kompilacji i **Idź do linii**
  liczą linie jednostki jak Oracle — linia 1 to linia słowa typu (`PACKAGE BODY …`, `ProgramUnit.sourceLine`, D189),
  tak jak ALL_SOURCE i ALL_ERRORS oraz jak w oknie programu wzorca (każda jednostka ma własny edytor numerowany od 1).
  Linie przed słowem typu (komentarz nagłówka, `CREATE OR REPLACE` w osobnej linii) są bez numeru („–” na pasku).
  Idź do linii poza końcem jednostki zostaje na jej ostatniej linii. Okno bez kart — linie dokumentu jak dotąd.
  Agent (także `edit.gotoLine` wywołane przez agenta) i komendy z pozycją w tekście (offsety, `executionLine`,
  punkty przerwania) dalej działają na liniach dokumentu. Wydruk i lista To-Do (także `edit.todoToggle` z numerem
  linii) też — drukowany jest cały tekst okna, wszystkie jednostki, z numeracją dokumentu.
- **Wyszukiwanie:** Znajdź następne/poprzednie przeszukuje cały dokument i przełącza kartę na trafienie w innej
  jednostce (Pelikan nie ma osobnych edytorów kart; zakres „cały tekst” zamiast „bieżąca karta” — mniej klikania przy
  szukaniu użycia w specyfikacji i ciele). **Zamień wszystko** działa na całym dokumencie (wszystkie jednostki),
  z opcją „W zaznaczeniu” — tylko w zaznaczeniu; liczba zamian w komunikacie; jedno Cofnij.
- **Zawartość kodu:** pojedynczy klik i Enter przenoszą kursor do nazwy elementu i fokus do edytora (z przełączeniem
  karty); strzałki w drzewie przesuwają kursor bez zmiany fokusu; śledzenie kursora jak dotąd. Treść: osobno
  specyfikacja i ciało pakietu i typu; podprogramy z parametrami i typem zwracanym (pełny nagłówek z trybami i typami
  w podpowiedzi), przeciążenia, podprogramy zagnieżdżone; typy wg rodzaju (rekord, tabela, VARRAY, REF CURSOR,
  podtyp — ikona i dopisek), kursory z parametrami i RETURN, zmienne, stałe, wyjątki, pragmy (EXCEPTION_INIT,
  AUTONOMOUS_TRANSACTION…); typ obiektowy — atrybuty z typami i metody (MEMBER, STATIC, CONSTRUCTOR … RETURN SELF AS
  RESULT). Elementy ciała niezadeklarowane w specyfikacji z tego samego tekstu są prywatne (pochylone, przygaszone,
  „prywatny” w podpowiedzi); przeciążenia dopasowane po nazwach parametrów. Pole filtru nad drzewem (nazwy, bez
  wielkości liter; zostają przodkowie pasujących, drzewo rozwinięte; ↓ — do drzewa, Esc — czyści), menu: Rozwiń
  wszystko, Zwiń wszystko; sortowanie bez zmian.
- **Wydajność:** parsowanie jak dotąd w tle; przy pisaniu granice kart i ukryte zakresy przesuwane bez ponownego
  układu całości. Przełączenie karty wymaga ponownego układu odcinka nowej karty (jak „Zwiń wszystko”): w pakiecie
  60 000 linii 0,5–1 s na przełączenie (Debug). Przy okazji: inspekcja nieużywanych deklaracji przeglądała wszystkie
  tokeny dla każdej deklaracji (pakiet 60 000 linii z 5 000 funkcji blokował główny wątek na minuty) — teraz indeks
  pozycji słów i wyszukiwanie binarne.
- **Poprawki po przeglądzie kodu:** wstawienie dokładnie na granicy kart należy do karty późniejszej (kursor na
  początku karty stoi na granicy — Enter, wklejenie, To-Do w pierwszej kolumnie zostają na karcie); ostatnia karta
  zawsze do końca tekstu. Zmiana obejmująca granicę (Zamień wszystko, formatowanie całości, Przywróć, historia
  lokalna, cofnięcie takich zmian) dzieli tekst na karty od razu, bez czekania na analizę w tle. Po analizie w tle,
  która zmieniła kartę (okno otwarte na linii, debuger, usunięcie jednostki), edytor przewija do kursora. Komendy
  edycji użytkownika i makr nie zmieniają tekstu poza kartą z kursorem (`Document.unitEditBounds` liczone z modelu
  w chwili wywołania, nie z widoku — makro może zmienić kartę i od razu edytować; np. „Usuń następne słowo” na końcu
  karty odmawia, „Powiel linię” w ostatniej linii karty jest dozwolone, a edytor wstawia kopię przed kończącym
  znakiem nowej linii, więc zostaje na tej karcie; kolejne linie z samym „/” należą do jednostki przed nimi; agent
  działa na dokumencie bez tego ograniczenia; okno z jedną jednostką — bez dzielenia tekstu przy komendzie), dodatkowe kursory nie trafiają do ukrytej jednostki, a Usuń jednostkę
  bez argumentu usuwa jednostkę karty z kursorem. Walidacja menu i wstążki komend kart korzysta z liczby kart z
  ostatniego podziału (`Document.unitTabCount`), bez dzielenia tekstu przy każdym znaku (R4-01); pozycja słowa typu
  liczona w tekście jednostki, nie w całym dokumencie. Numery linii listy komunikatów liczone raz na listę. ⌘A
  i przeciąganie myszą nie przewijają na koniec karty. Code Contents: stan rozwinięcia z rodzajem węzła
  (specyfikacja i ciało osobno), rozwinięcie sprzed filtra przywracane, filtr z opóźnieniem 180 ms, sortowanie nie
  zmienia kolejności parametrów; prywatne przeciążenie (jedna wersja w specyfikacji, dwie w ciele) zostaje
  prywatne; pragmy nie trafiają do podpowiedzi kodu ani do „Przejdź do deklaracji”.
- **Podzielony edytor:** bez dodatkowych kursorów zaznaczenie główne stosuje tylko `syncFromModel`, który pomija
  panel, gdy pisze się w drugim (`peerActive`) — pasywny panel podziału (okna SQL, programu, testu) nie przesuwa
  kursora za aktywnym, tak jak dotąd przy wpisywaniu tekstu.
- **Wstawienie na granicy i rysowanie (czwarte przejście przeglądu):** wstawienie z modelu w granicy kart edytor
  stosuje o znak wcześniej tylko dla tekstu dopisanego na końcu widocznej karty, gdy kursor po zmianie jest wewnątrz
  wstawki (Powiel linię) — To-Do w pierwszej linii ciała albo komentarz agenta przed CREATE zostają na karcie
  późniejszej. Po zmianie tekstu z modelu edytor przewija do kursora tylko, gdy kursor był widoczny albo zmiana go
  obejmuje (edycja agenta gdzie indziej, Zamień wszystko, formatowanie nie odrywają od czytanego miejsca). Tekst
  wpisany za kończącym „/” specyfikacji należy — jak w SQL*Plus — do następnego polecenia i skleja się z ciałem, które
  przestaje być rozpoznawane jako jednostka: karty znikają i widać cały tekst (edytor, komendy, kompilacja i punkty
  przerwania widzą wtedy ten sam podział), a wracają po poprawieniu tekstu (świadome zachowanie; wcześniejsze
  zachowywanie kart przy takim tekście dawało rozbieżność edytora z modelem). „Usuń jednostkę” z argumentem
  „nazwa body” usuwa tylko ciało — bez ciała w tekście odmawia, zamiast usuwać specyfikację. Znane ograniczenie: po
  zniknięciu kart (odsłonięcie całego tekstu) linie poniżej dotychczasowej wysokości widoku bywają puste do
  przewinięcia albo kliknięcia (TextKit 2 nie powiększa od razu widoku tekstu). Po zmianie ukrytego tekstu i po zmianie tekstu
  z komendy edytor układa obszar widoku jeszcze raz w następnym obiegu pętli — dolne linie (numery w marginesie bez
  tekstu) były puste do kliknięcia. Odtworzone w oknie programu z kartami (zmiana kart, dopisanie tekstu z komendy
  i z klawiatury za „/”); w oknie bez kart przy pisaniu z klawiatury nie występowało.
- **Pliki jednostek bez „/” (wymaganie właściciela):** „W repozytoriach specyfikację i body zapisujemy w osobnych
  plikach i bez znaku / na końcu” — „/” psuje proces wdrożenia. Okno programu rozpoznaje jednostki po nagłówkach
  `CREATE [OR REPLACE] [EDITIONABLE|NONEDITIONABLE] PACKAGE|PACKAGE BODY|TYPE|TYPE BODY|PROCEDURE|FUNCTION|TRIGGER|
  LIBRARY|JAVA SOURCE|MLE MODULE …` na początku linii (lekser — nie w komentarzu ani literale; `ProgramCompiler.
  programStatements`), z „/” i bez; „/” w osobnej linii, jeśli jest, należy do jednostki przed nim (podział jak
  w SQL*Plus). Dotyczy kart, Code Contents, kompilacji F8 (każda jednostka osobnym poleceniem), numeracji linii
  i błędów ALL_ERRORS, debugera i punktów przerwania, Dodaj/Usuń jednostkę, porównania z bazą, historii lokalnej.
  Tekst za kończącym „/” nie skleja już jednostek — wycofanie `keepingTabs` zostaje.
  Bez „/” domyślnie: tekst z bazy w oknie programu (Edytuj, Wczytaj ponownie z bazy, Dodaj źródło do edytora,
  otwarcie z debugera, agent otwierający obiekt, szkielet testu utPLSQL, import modułu MLE) — jednostki rozdzielone
  pustą linią; szablony jednostek programów bez „/”; Dodaj jednostkę zachowuje konwencję pliku (okno z „/” — nowa
  jednostka z „/”, bez — bez). **Zapis nigdy nie dopisuje „/”** (dotąd dopisywał kończący „/”, UG 4.2) — tekst okna
  zapisywany bez zmian, plik z „/” zapisuje się tak, jak jest (bez cichego usuwania). Preferencja „Kończ jednostki okna
  programu znakiem /” (Preferencje › Oracle, domyślnie wyłączona) przywraca „/” w tekście z bazy i w nowych jednostkach.
  Bez zmian (tam „/” wykonuje blok): okno SQL, okno poleceń, okno testu, Duplikuj obiekt (skrypt w oknie SQL),
  skrypt wdrożenia koszyka, kopia schematu, eksport obiektów do plików (DBMS_METADATA z SQLTERMINATOR — następny PR
  razem z osobnymi plikami specyfikacji i ciała).
- **Źródło dla agenta i szkielet testu:** `agent.source` i szkielet testu utPLSQL (okno programu i narzędzie agenta)
  stosują tę samą preferencję co okno programu — domyślnie bez „/” (agent może zapisać źródło do pliku w repozytorium).
- **Szóste przejście przeglądu:** szablon jednostek wstawiany do okna SQL, poleceń albo testu (i do okna programu
  z konwencją „/”) dostaje „/” po każdej jednostce — tam „/” kończy blok PL/SQL; w oknie programu bez „/”. Podział na
  jednostki to jedno przejście po tokenach polecenia (pliki z setkami jednostek bez „/”). Treść źródła Java i modułu
  MLE nie jest leksowana jak PL/SQL — następny nagłówek CREATE szukany tekstowo. `GRANT`, `REVOKE` i `SHOW ERRORS` na
  początku linii za jednostką bez „/” nie doklejają się do niej (nie są wykonywane przy F8 — jak dotąd polecenia
  inne niż CREATE); inne polecenia SQL*Plus (`EXIT`, `SET`, `PROMPT` — także słowa PL/SQL) za jednostką bez „/”
  trafiają do jej tekstu (w konwencji właściciela nie występują). Opis narzędzia `agent.source`: źródło bez „/”, do
  wykonania jako skrypt SQL*Plus każdą jednostkę trzeba zakończyć „/” albo kompilować osobno.
- **Java i MLE bez „/”:** źródło kończy się przed komentarzami PL/SQL i pustymi liniami poprzedzającymi następną
  jednostkę. Ograniczenie: w źródle Java/MLE bez „/” linia zaczynająca się od `CREATE …` z nagłówkiem jednostki (np.
  w literale szablonowym JavaScript albo bloku tekstowym Javy) jest traktowana jako nagłówek następnej jednostki —
  takie jednostki kończ „/”.



### D193 · 2026-10-29 — Plan wykonania: rozwinięcie i zwinięcie wszystkich gałęzi drzewa planu

Zgłoszenie właściciela: w drzewie Explain Plan brakuje przycisku do rozwinięcia albo zwinięcia wszystkich gałęzi.

- Komendy `plan.expandAll` „Rozwiń wszystkie gałęzie” i `plan.collapseAll` „Zwiń wszystkie gałęzie” (agent: Brak,
  skutek: stan interfejsu, PD-OPT-001) działają na aktywnym oknie planu, gdy plan ma gałęzie (plan jednokrokowy —
  wyłączone). Strzałki nad drzewem obok wyboru widoku (aktywne w widoku Drzewo), grupa „Drzewo” na karcie
  kontekstowej „Plan” wstążki, menu Narzędzia › Plan. Osobne teksty zamiast „Rozwiń wszystko”/„Zwiń wszystko” —
  te klucze należą do zwijania kodu edytora (en „Fold all”). Wzorzec nie ma dla tego skrótów — bez skrótów.
- Stan rozwinięcia w modelu okna (`Document.planExpanded`, zbiór PLAN_TABLE.ID gałęzi), a nie w widoku: drzewo to
  `Table` z `DisclosureTableRow` sterowanym tym zbiorem (`Table(children:)` nie daje dostępu do rozwinięcia). Wybór
  widoku (Drzewo/Diagram/Flame graph/Tekst) jest stanem widoku, więc komendy ze wstążki i menu zmieniają rozwinięcie
  także przy innym widoku — widać je po powrocie do Drzewa.
- Nowy plan rozwinięty w całości (jak we wzorcu): pierwszy plan okna i plan innego polecenia (`ExplainPlanResult.sql`,
  tekst bez wskazówki celu) dostają wszystkie gałęzie. Ponowne wyznaczenie planu tego samego polecenia (także z innym
  celem optymalizatora) zachowuje rozwinięcie użytkownika, przycięte do gałęzi nowego planu. Zwiń wszystkie gałęzie
  czyści zbiór — widoczny zostaje sam korzeń (SELECT STATEMENT).
- Krok zaznaczony nawigacją w kolejności wykonania albo w Diagramie/Flame graph (po powrocie do Drzewa) rozwija swoich
  przodków (`Document.revealPlanLine`), a tabela przewija się do niego.
- Ograniczenie: rozwinięcie całego poddrzewa ⌥-kliknięciem trójkąta (⌥→) to zachowanie NSOutlineView pod tabelą
  SwiftUI; przy rozwinięciu sterowanym bindingiem SwiftUI może nie przenieść go na podgałęzie (API nie daje do tego
  dostępu, a sprawdzenie wymaga sterowania interfejsem — nie sprawdzone). Całe drzewo rozwija przycisk „Rozwiń
  wszystkie gałęzie”.
- Inne widoki planu nie są drzewami: Autotrace (plan rzeczywisty) i porównanie planów to płaskie tabele z wcięciem,
  SQL Monitor — lista i raport HTML; komendy ich nie dotyczą.

### D194 · 2026-10-29 — Specyfikacja i ciało w osobnych plikach (okno programu z dwoma plikami, eksport bez „/”)

Wymaganie właściciela: „W repozytoriach specyfikację i body zawsze zapisujemy w osobnych plikach i bez znaku / na
końcu. W skryptach owszem używamy, ale nie w plikach DDL.” Okno programu (D192) rozpoznawało jednostki bez „/”, ale
miało jeden plik — specyfikacja i ciało trafiały do jednego pliku.

- **Powiązanie okno → pliki:** `Document.unitFiles` — lista plików jednostek (`UnitFile`: część spec/body, ścieżka,
  własny format pliku — kodowanie, BOM, końce linii — zakończenie treści i treść z ostatniego odczytu/zapisu). Pusta —
  okno z jednym plikiem jak dotąd. Dokument zostaje jeden (karty, F8, debuger, historia, agent bez zmian); `fileURL`
  to wtedy plik specyfikacji — klucz stanu okna, historii lokalnej (cały tekst okna, jak dotąd) i workseta; tytuł
  „nazwa.pks + .pkb”. Wybrano listę plików przy dokumencie zamiast dwóch dokumentów albo osobnych edytorów: reszta
  aplikacji widzi jeden tekst, a podział na pliki to jedna czysta funkcja.
- **Podział tekstu:** treść pliku = odcinek karty jednostki (`ProgramUnitTabs`, D192). Tekst okna z plików to
  specyfikacja bez końcowych białych znaków + pusta linia + ciało (`SpecBodyFiles.join`); zapis zdejmuje tę pustą
  linię z początku karty ciała i przywraca zakończenie pliku. Niezmienione okno daje pliki bajt w bajt — otwarcie
  pary sprawdza ten obieg i przy niezgodności (np. komentarz za `END` specyfikacji) otwiera plik sam. Polecenia
  `GRANT`/`REVOKE`/`SHOW ERRORS` między jednostkami należą teraz do karty jednostki przed nimi (zmiana D192: dotąd
  trafiały na kartę następnej) — plik specyfikacji z uprawnieniami zachowuje je przy zapisie.
- **Zapisz:** każda jednostka do swojego pliku, w jego formacie, tylko gdy jej tekst się zmienił (drugi plik
  nietknięty); bez dopisywania „/” — tekst karty jak w oknie (plik z „/” zapisuje się z nim, bez cichego usuwania, jak
  w D192). Znak spoza kodowania któregokolwiek pliku blokuje zapis obu. Okno pary, które przestało być dokładnie
  specyfikacją i ciałem jednego pakietu/typu (usunięte ciało, dodana procedura), nie zapisuje się — komunikat
  wskazuje **Zapisz jako jeden plik…**. **Kodowanie pliku…** zmienia oba pliki.
- **Zapisz jako… i pierwsze Zapisz nowego okna** ze specyfikacją i ciałem: okno zapisu z nazwą `nazwa.pks`
  (rozszerzenie specyfikacji z Preferencji), ciało obok jako `nazwa.pkb`; istniejący plik ciała spoza okna — pytanie
  „Zastąpić?”. Okno z innym plikiem (np. `.pck`) ⌘S zapisuje jak dotąd do tego pliku. Nowa komenda
  `file.saveAsSingleFile` „Zapisz jako jeden plik…” (agent: Brak, wstążka Start › Plik › Więcej) zapisuje całe okno
  w jednym pliku i zdejmuje powiązanie z parą. Okno z jedną jednostką albo innymi jednostkami — bez zmian.
- **Otwieranie:** `x.pks`/`x.pkb` (`x.tps`/`x.tpb`) z plikiem pary obok otwiera obie jednostki w jednym oknie na karcie
  otwartego pliku — Plik › Otwórz, ostatnie pliki, Przeglądarka plików, Finder, przeciągnięcie, projekt; wielkość
  liter rozszerzenia jak w otwieranym pliku. Ponowne otwarcie któregoś z plików aktywuje okno i jego kartę. Para
  tylko, gdy w plikach jest dokładnie specyfikacja i ciało tego samego obiektu, a drugi plik nie jest już otwarty
  w innym oknie (jeden plik w dwóch oknach rozjechałby się przy zapisie). Preferencja **Otwieraj parę
  specyfikacja/ciało w jednym oknie** (domyślnie włączona).
- **Worksety i odzyskiwanie:** `WorksetDocument.unitFiles` (pole opcjonalne — starsze worksety bez zmian): ścieżki,
  części, formaty i zakończenia. Okno bez zmian wraca jako para z plików (niezależnie od preferencji), ze zmianami —
  tekst z workseta, powiązanie i formaty z workseta, treść zapisana z dysku. Migawka odzyskiwania to ten sam workset.
- **Pozostałe miejsca:** Przeglądarka plików (otwarte i zmienione — oba pliki), zmiana nazwy i usunięcie pliku albo
  katalogu (powiązanie przeniesione albo zdjęte), stan Git i **Porównaj z HEAD** (plik karty z kursorem, treść karty),
  użycia i refaktoryzacja (oba pliki jako otwarte), skok do linii pliku z wyników i projektu (linia pliku ciała
  przeliczona na linię okna), edycja w programie zewnętrznym (plik tymczasowy z całym tekstem, jak okno bez pliku),
  blokada kompilacji pliku tylko do odczytu (którykolwiek z pary).
- **Preferencje › Ogólne › Specyfikacja i ciało w osobnych plikach:** otwieranie pary i rozszerzenia specyfikacji
  i ciała pakietu (`pks`/`pkb`) i typu (`tps`/`tpb`) — bez kropki, małymi literami; pliki z nimi otwierają się jako
  okno programu.
- **Eksport obiektów użytkownika (PD-TOOL-007):** „plik na obiekt” zapisuje specyfikację i ciało osobno z
  rozszerzeniami z Preferencji (dotąd `.spc`/`.bdy`); **Specyfikacja i ciało w jednym pliku** (`.pck`/`.typ`) domyślnie
  wyłączona, a takie pliki mają „/” jak w PL/SQL Developerze. Jednostki PL/SQL w osobnych plikach na obiekt bez „/” —
  nowa opcja **Kończ jednostki znakiem /** (domyślnie wyłączona). DBMS_METADATA dalej z SQLTERMINATOR (tabele i inne
  DDL zachowują „;”); „/” zdejmowany za jednostką, gdy za nią nic nie ma; `ALTER TRIGGER … ENABLE` (wyzwalacz i tak
  powstaje włączony) jest pomijane, a `… DISABLE` zastępuje klauzula `DISABLE` w `CREATE TRIGGER` (11g+, przed
  `WHEN (…)` albo treścią wyzwalacza) — plik bez „/” i bez ALTER. Gdy za jednostką jest inne polecenie (np. `ALTER
  TYPE` ewolucji typu), „/” zostaje, a okno eksportu wymienia takie pliki. Bez zmian, z „/”: tryb „jeden plik” (skrypt
  SQL*Plus), skrypt wdrożenia koszyka, kopia schematu, porównanie schematów, eksport w oknie poleceń, Duplikuj obiekt,
  okno testu, ORDS. Testy na bazie: EMP_API → `emp_api.pks`/`emp_api.pkb` bez linii „/”, otwarte jako para
  i skompilowane F8 — oba VALID; wyłączony wyzwalacz → plik z `DISABLE`, wykonany ponownie daje wyzwalacz DISABLED.
- **Uprawnienia (decyzja właściciela: „GRANT'y zawsze w osobnych plikach”):** w trybie „plik na obiekt” pliki DDL
  (`.pks`, `.pkb`, `.tps`, `.tpb`, `.sql`, `.trg`…) zawierają wyłącznie CREATE; uprawnienia obiektu trafiają do
  osobnego pliku `nazwa.grants.sql` obok (polecenia GRANT zakończone „;”) albo są pomijane (opcja **Uprawnienia
  w plikach na obiekt**: w osobnym pliku — domyślnie — albo pomiń). Jeden plik (skrypt) — uprawnienia za obiektem jak
  dotąd. W oknie programu `GRANT` stojące w pliku specyfikacji (dopisane ręcznie) to tekst użytkownika: należy do
  karty specyfikacji i zapisuje się z nią bez zmian — Pelikan nie usuwa ani nie przenosi go po cichu.
- **Nagłówek z datą:** w plikach na obiekt domyślnie bez komentarza „-- Wygenerowane przez Pelikana — data” (data
  zmieniałaby każdy plik w repozytorium przy każdym eksporcie) — opcja **Nagłówek z datą eksportu**; jeden plik —
  z nagłówkiem jak dotąd.
- **Nazwy plików eksportu:** nazwa bazowa nadawana obiektowi (właściciel + nazwa) wspólna dla wszystkich jego plików.
  Przy eksporcie obiektów kilku schematów zawsze z przedrostkiem schematu w nazwie każdego pliku (`s2.pkg.pks`,
  `s2.pkg.pkb`, `s2.pkg.grants.sql`) — specyfikacja jednego schematu nie trafia w parę z ciałem innego; eksport jednego
  schematu — bez przedrostka jak dotąd. Inny obiekt o tej samej nazwie bazowej
  („Foo” i „FOO”) dostaje przyrostek `_2` we wszystkich swoich plikach. Kolejność eksportu: typ, właściciel, nazwa.
- **Poprawki po przeglądzie (zapis i otwieranie):** Zapisz jako z nazwą `.pck`, bez rozszerzenia albo `.pkb` pyta raz
  o wszystkie istniejące pliki pary spoza okna (plik wybrany w oknie zapisu potwierdza okno zapisu), zamiast nadpisać
  specyfikację bez pytania. Rozszerzenia z Preferencji: cztery różne, z liter, cyfr i „_”, inne niż rozszerzenia
  skryptów, testów, raportów i plików `.pck`/`.typ`; rozszerzenia specyfikacji różne od rozszerzeń ciała; pakiet
  i typ mogą mieć wspólne (np. `.spc`/`.bdy`), ale tylko oba naraz — wspólna specyfikacja z różnymi ciałami dawałaby
  niejednoznaczny plik pary — inaczej używane są domyślne (Preferencje pokazują ostrzeżenie), a zapis
  odmawia, gdy plik specyfikacji i ciała to ten sam plik. Przed zapisem każdy plik pary musi zawierać dokładnie
  jedną jednostkę o tym samym tekście co w oknie (dwie jednostki w jednej linii dzielą kartę w środku polecenia) —
  inaczej odmowa z komunikatem. Plik pary, który ten zapis zapisze (jego jednostka zmieniła się w oknie), a zmienił się
  na dysku od otwarcia albo zapisu (inny program, `git checkout`) — pytanie „Zapisz mimo to / Anuluj”; zmianę wykrywa
  skrót bajtów pliku z otwarcia albo zapisu (`UnitFile.savedHash`, FNV-1a), bez dekodowania — pliki jednobajtowe bez
  fałszywych alarmów, a po **Kodowanie pliku…** (oba pliki oznaczone do zapisu, `needsRewrite`) sprawdzenie nadal
  działa. Worksety zapisują skrót (pole opcjonalne `hash`) — okno ze zmianami przywrócone z workseta pyta, gdy plik
  zmienił się na dysku po zapisie workseta; starsze worksety bez skrótu — bez sprawdzania. Plik
  zmieniony na dysku, którego jednostka w oknie się nie zmieniła, nie jest zapisywany ani nie wywołuje pytania; jego
  treść zapisana zostaje dawna (świadomie — przyjęcie treści z dysku sprawiłoby, że następny zapis po cichu nadpisałby
  zmianę z repozytorium starą kartą okna), więc gdy jednostka zmieni się później, zapis zapyta wtedy. Treść zapisana
  każdego pliku aktualizowana od razu po jego zapisie; nieudane Zapisz jako usuwa tylko pliki, których przed zapisem nie
  było wcale (sprawdzenie bez podążania za dowiązaniem — wiszące dowiązanie zostaje). Nowy plik pary przy Zapisz jako dostaje format dotychczasowego pliku
  tej samej części. Okno z samą specyfikacją albo samym ciałem proponuje rozszerzenie `.pks`/`.pkb` (`.tps`/`.tpb`).
  Plik pary szukany po rzeczywistej nazwie z katalogu (APFS bez rozróżniania wielkości liter), nieczytelny plik pary —
  otwarcie samego pliku; jednostki i karty z otwarcia trafiają do pamięci okna. Klauzula `DISABLE` wyzwalacza w eksporcie
  stawiana także przed etykietą bloku (`<<etykieta>>`). Pasek okna (stan repozytorium) bierze
  plik karty widocznej z pamięci kart (`Document.shownUnitTab`/`shownFileURL`) — bez dzielenia tekstu przy każdym
  znaku (R4-01). Przeglądarka plików oznacza jako zmieniony tylko plik, którego jednostka się zmieniła. **git add** bez
  argumentu w oknie pary dodaje oba pliki; pulpit projektu, **Dodaj plik okna do projektu**, zmienna `#file` narzędzi
  użytkownika (plik karty z kursorem) i scalanie workseta nieotwartego przy starcie uwzględniają oba pliki; treść
  zapisana plików z workseta czytana w kodowaniu projektu. `GRANT` sam w linii i `GRANT …; -- komentarz` należą do
  karty jednostki przed nimi. Nowe ustawienia w zestawach preferencji (sekcja Ogólne).
- **Ograniczenia:** komentarz za `END` specyfikacji w pliku `.pks` (bez pustej linii przed ciałem) przeniósłby się przy
  zapisie do ciała — taki plik otwiera się sam, bez pary. Para w oknie ma tę samą nazwę bazową plików przy Zapisz jako;
  zmiana nazwy jednego pliku w Przeglądarce plików zachowuje powiązanie z inną nazwą. Workset z oknem pary otwarty
  w starszej wersji Pelikana nie zna pola `unitFiles` — okno wraca z całym tekstem i plikiem specyfikacji, a zapis
  zapisałby obie jednostki do pliku specyfikacji. Pasek stanu repozytorium dla zmienionego okna pary pokazuje „zmieniony”
  także dla niezmienionego pliku karty (stan liczony z całego okna — bez dzielenia tekstu przy każdym znaku).

### D195 · 2026-10-29 — Polskie nazewnictwo interfejsu: macOS, IDE i Oracle (glosariusz)

Prośba właściciela: „Co w explain plan oznacza «Wyjaśnij»? Nie ma to być «Odśwież»?” oraz przegląd polskich nazw
pod kątem nomenklatury aplikacji macOS i narzędzi programistycznych — zmiany umiarkowane, tylko tam, gdzie polski
użytkownik oczekuje innego słowa.

- **Zasady** (szczegóły, źródła i tabela terminów: [`docs/research/glosariusz.md`](research/glosariusz.md)): czynności
  w trybie rozkazującym (rzeczownik tylko przy przełącznikach i nazwach narzędzi), wielokropek tylko przed oknem
  z pytaniem, ta sama czynność tą samą nazwą w menu, na wstążce, w palecie, na przyciskach i w instrukcji; panele
  Pelikana po polsku jak w menu Widok (Przeglądarka obiektów, Przeglądarka plików, Zawartość kodu, okno SQL, konsola
  SQL*Plus); nazwy własne narzędzi wzorca (Explain Plan, Code Assistant, Query Builder, Query By Example, Large Data
  Editor, SQL Monitor…) bez tłumaczenia; słowa SQL w nawiasie przy polskiej czynności.
- **Okno planu:** przycisk „Wyjaśnij” (kalka „Explain”) i etykieta wstążki „Wyznacz plan” → **Odśwież plan** — liczy
  plan ponownie dla tekstu okna (pierwszy plan liczy otwarcie okna z okna SQL).
- **Ustawienia zamiast Preferencji:** od macOS 13 menu aplikacji ma „Ustawienia…” (⌘,) — Pelikan już tak je nazywał,
  ale okno, podmenu Narzędzia, zestawy, eksport/import i opisy mówiły „Preferencje”. Teraz wszędzie **Ustawienia**
  (Zestawy ustawień, Eksportuj ustawienia…, „w Ustawieniach › Oracle”), także w instrukcji pl; nazwa pliku
  `13-preferencje.md` i identyfikatory w kodzie bez zmian.
- **Debuger:** Krok do / Krok przez / Wyjdź z podprogramu (było Wejdź / Przejdź / Wyjdź — „Wyjdź” myli się
  z zamknięciem, „Przejdź” z przejściem do miejsca), Przełącz punkt przerwania.
- **Spójność terminów Oracle:** Post w siatce → **Zapisz zmiany w bazie (Post)** („Zatwierdź” zarezerwowane dla
  COMMIT); „Zabij sesję” → **Zakończ sesję (Kill)** jak „Zakończ sesję okna (Kill)”; INVALID — zawsze
  **nieprawidłowe** (było też „niepoprawne”).
- **Decyzje właściciela po przeglądzie tabeli zmian:** duże przyciski transakcji na wstążce zostają nazwami SQL
  **COMMIT** / **ROLLBACK** (w menu dalej „Zatwierdź (COMMIT)” / „Wycofaj (ROLLBACK)”); raport predefiniowany
  i nagłówek dokumentacji schematu zostają **Ograniczenia** (folder w Przeglądarce obiektów — „Więzy”).
  „Okno poleceń” (Command Window) → **Konsola SQL*Plus** wszędzie (menu Plik › Nowy, wstążka, tytuły okien i komend,
  opisy, instrukcja) — nazwa mówi, czym okno jest; także po angielsku (*SQL*Plus Console*), niemiecku, hiszpańsku
  i ukraińsku (tłumaczenia i instrukcje poprawione, bo zmienił się sens nazwy). Punkt załamania linii relacji na
  diagramie → **punkt zgięcia**. Po angielsku *Preferences* → *Settings* wszędzie (okno, menu, opisy, „in Settings ›
  …”, instrukcja en; zestawy — *Settings sets*). Dawne nazwy są słowami kluczowymi wyszukiwania komend. Tytuł okna
  wyznacza nazwy plików zrzutów, więc zrzuty konsoli i ustawień dostaną nowe nazwy przy następnym przebiegu.
- **Po przeglądzie gałęzi:** es *Ajustes* i uk *Налаштування* wszędzie (okno, podmenu, opisy, instrukcje — jak macOS),
  en zestawy *Settings presets*, en *Toggle Breakpoint* i *Step Into / Step Over / Step Out*; klucz „Przejdź”
  (Zawartość kodu, menu jednostek) ma tłumaczenia „przejdź do”, nie debugera; przyciski przeglądarki sesji
  i pytanie o zakończenie używają tytułu komendy „Zakończ sesję (Kill)”. Nazwy sekcji w parametrze `sections`
  komend `prefs.export` / `prefs.import` (makra, skrypty, agent) są przetłumaczone na język interfejsu —
  `PreferenceSets.sectionNames` przyjmuje też klucz polski, synonimy zapisane przy definicji sekcji (angielska i dawna
  nazwa, np. „SQL Window”, „Object Browser”) i tłumaczenie każdej nazwy na wszystkie języki interfejsu (makro nagrane
  po niemiecku działa po polsku), bez względu na wielkość liter; nieznana nazwa to błąd nieprawidłowego argumentu
  z listą znanych sekcji (wcześniej po cichu nic nie eksportowała). Sekcja okna SQL to teraz „Okno SQL” (była „SQL
  Window”). Po angielsku zestawy ustawień to konsekwentnie *presets* (karta *Presets*, *Settings Presets…*).
- **Do zrobienia po następnym przebiegu zrzutów** (po scaleniu zrzutów ukrytych): nowe nazwy plików od tytułów okien
  (Konsola SQL*Plus, Ustawienia) — poprawić odnośniki w docs/FEATURES.md (wiersze ok. 218, 355, 400, 495), usunąć
  stare pliki zrzutów i odświeżyć obrazki instrukcji.
- **IDE:** Fragmenty kodu (snippety), Wyodrębnij (Wydziel), Przełącz komentarz linii, Zamień na wielkie/małe litery,
  Przejdź do pierwszego znaku linii, Pokaż podpowiedzi kodu, Kompiluj projekt / Kompiluj zmienione (Buduj / Make),
  Duplikuj połączenie…, Filtruj wyrażeniem… / Filtruj kolumny…; macOS: Powtórz (było „Ponów” — w angielskim
  interfejsie pokazywało „Retry” przy ⇧⌘Z), Zminimalizuj, dwukrotne kliknięcie; Pro*C: kopia robocza, kopia
  zapasowa; diagram: punkt zgięcia.
- **Technicznie:** klucz = polskie zdanie, więc tłumaczenia en/de/es/uk przeniesiono na nowe klucze bez zmian;
  poprawiono tylko te, którym zmienił się sens (Odśwież plan, Powtórz, Ustawienia). Dawne polskie tytuły komend są
  słowami kluczowymi wyszukiwania czynności (`CommandSearch.keywords`), więc „wyjaśnij”, „zabij”, „snippet”, „buduj”
  czy „preferencje” dalej znajdują komendę. Teksty dziennika i komunikaty SP2-/ORA- bez zmian.
- **Pozostawione** (z powodem w glosariuszu): Workset, żargon zdalnego buildu Pro*C (build, binarka, remote, commit),
  Zadokuj, Autoukrywanie, Rekompiluj, To-Do, Znaki specjalne, Status linii, nazwy narzędzi wzorca.

### D196 · 2026-10-29 — Zrzuty bez okien na ekranie (zmienia D113)
Właściciel pracuje przy komputerze, a okna przebiegu zrzutów (D113) pojawiały się na kilka sekund na jego monitorach;
`screencapture` nie działa też w piaskownicy agentów. Teraz w trybie skryptu (`PELIKAN_UI_SCRIPT`, tylko Debug) okna są
niewidoczne od pierwszej klatki: haki Objective-C (`App/Sources/UIScriptWindows.m`) na inicjalizatorze `NSWindow`
i każdej drodze wystawienia okna (`orderWindow`, `orderFront`, `makeKeyAndOrderFront`, `orderFrontRegardless`,
`setIsVisible`, arkusze, okna potomne) ustawiają alfę 0, `ignoresMouseEvents`, brak cienia i animacji; `setAlphaValue`
zawsze daje 0, a `activate`, `activateIgnoringOtherApps` i `requestUserAttention` nic nie robią. Polityka aktywacji
`.accessory`, a skrypt uruchamia klon APFS aplikacji z `LSUIElement` (nowy podpis ad hoc z tymi samymi uprawnieniami,
po przebiegu wyrejestrowany i usunięty) — bez ikony w Docku także w pierwszych chwilach po `open -g -n` (sama polityka
w kodzie przychodzi po starcie: ok. 0,5 s typu „Foreground”). Okna pozostają „widoczne” dla AppKit (`isVisible`,
układ, rysowanie), więc `open -j` (ukryta aplikacja) odrzucone — ukryte okna nie są rysowane ani listowane.
Zrzut robi aplikacja: po ostatnim kroku (`PELIKAN_SNAPSHOT=<katalog>/<scenariusz>`) albo krokiem `debug.snapshotWindows`
(`prefix`) rysuje ramkę każdego okna (`contentView.superview` — pasek tytułu, pasek narzędzi, wstążka, SwiftUI, TextKit 2)
przez `cacheDisplay(in:to:)` do mapy bitowej co najmniej 2×, dokleja treść WKWebView z `takeSnapshot`, zapisuje
`<scenariusz>-<tytuł>.png` (nazwy jak dotąd), znacznik `.done` i kończy pracę. Porównanie: `CALayer.render(in:)` gubi
tła przycisków paska narzędzi (szkło), `CGWindowListCreateImage` jest wycofane w SDK i mogłoby wywołać pytanie
o nagrywanie ekranu, ScreenCaptureKit wymaga tego uprawnienia — odrzucone. Sprawdzone strażnikiem odczytującym listę
okien co 20 ms (alfa okien procesu zawsze 0, typ aplikacji zawsze UIElement) na scenariuszach 01, 07, 11, 17, 19, 28, 49
i 65: obraz zgodny z dawnymi zrzutami, a WKWebView (instrukcja) wreszcie z treścią. Ograniczenia: zaznaczony segment
`NSTabViewController` (szkło Liquid Glass, warstwy portalowe) wychodzi bez etykiety, rogi okna są proste (bez
przezroczystych zaokrągleń); w takich przypadkach `scripts/screenshots.sh --screen` — dawny sposób z widocznymi oknami
(`PELIKAN_UI_SCRIPT_VISIBLE=1`).
Skrypt zawsze buduje aplikację (przyrostowo) i przerywa, gdy klon nie ma haków ukrywania (stara binarka pokazałaby
okna); każdy przebieg ma własny katalog `mktemp` (klon, dane — równoległe przebiegi w worktree agentów się nie mieszają),
sprzątany w `trap` razem z niewidocznymi instancjami (sesje w bazie testowej); katalogi przebiegów przerwanych bez
sprzątania (właściciel z `owner.pid` już nie działa) są usuwane przy następnym starcie. Scenariusz bez żadnego zrzutu
kończy skrypt błędem; okna modalne i arkusze w trybie skryptu trafiają do dziennika `.log`, a zrzut treści WKWebView ma
limit 5 s. Klon jest bez rozszerzeń (`PlugIns`, Quick Look nie rejestruje się drugi raz).

### D197 · 2026-10-29 — Pliki zmienione przez inny program: wykrywanie przy aktywacji i wczytanie ponowne

Właściciel: jak w PL/SQL Developerze — otwarcie pliku go nie blokuje, a gdy plik zmieni inny program (agent, git,
edytor), Pelikan to wykrywa i pyta.

- **Bez blokad:** okna czytają plik raz (`Data(contentsOf:)`) i nie trzymają deskryptora ani blokady; zapis jest
  atomowy (plik tymczasowy i podmiana, `writeKeepingFile` — przez dowiązanie zapisywany jest plik docelowy,
  uprawnienia zostają). Inne programy mogą plik czytać, zmieniać i usuwać w każdej chwili.
- **Stan pliku:** przy otwarciu, zapisie i wczytaniu ponownym okno zapamiętuje dla każdego pliku (okno pary — dla
  `.pks` i `.pkb` osobno) datę modyfikacji, rozmiar i skrót bajtów (`Document.diskStamps`, `FileStamp`). Sprawdzenie
  czyta plik tylko, gdy zmieniła się data albo rozmiar; ten sam skrót (np. `touch`, `git checkout` bez zmiany treści)
  uaktualnia stan bez pytania. Dowiązanie — stan pliku docelowego; wiszące dowiązanie (cel usunięty) to plik usunięty.
  Na woluminie nielokalnym (SMB, NFS — `volumeIsLocalKey`) treść jest porównywana zawsze, bo daty bywają zaokrąglane
  albo z innego zegara.
- **Kiedy:** przy aktywacji okna z plikiem, karty pliku w oknie pary i aplikacji (okno na wierzchu). Jedno sprawdzenie
  naraz i jedno pytanie naraz (zmiany kilku plików okna po kolei), pytania tylko dla aktywowanego okna — inne okna
  zapytają, gdy się je aktywuje. Nie w trakcie zapisu okna (także okna wyboru nazwy), nie w trybie skryptu
  (`PELIKAN_UI_SCRIPT`), nie bez interfejsu. Zmiana z edytora zewnętrznego (PD-EDIT-028) jest wczytywana jak dotąd
  i nie pyta drugi raz.
- **Okno bez zmian:** „Plik „…” został zmieniony przez inny program. Wczytać go ponownie?” — **Wczytaj ponownie** /
  **Zostaw**; preferencja **Wczytuj bez pytania pliki zmienione na zewnątrz, gdy okno nie ma zmian** (domyślnie
  wyłączona). **Okno ze zmianami** (w oknie pary — karta tego pliku): ostrzeżenie „Okno ma niezapisane zmiany” —
  **Wczytaj ponownie (utracisz zmiany)** / **Zachowaj moje zmiany**. „Zostaw” i „Zachowaj” zapamiętują nowy stan dysku
  jako znany (bez pytania do następnej zmiany), ale nie treść zapisaną okna — późniejsze ⌘S ostrzega „Pliki zmieniły
  się na dysku… Zapisz mimo to / Anuluj” (dla wszystkich okien z plikiem, nie tylko par: `Document.savedFileHash`).
  Ostrzeżenie przy zapisie najpierw porównuje datę i rozmiar ze znanym stanem (gdy to stan zapisu), skrót liczy tylko
  przy różnicy, odczyt i skrót poza wątkiem głównym. Z wyłączoną preferencją **Wykrywaj zmiany plików na dysku** — bez
  ostrzeżenia; w trybie skryptu i bez interfejsu zapis odbywa się (bez cichego anulowania), a nadpisanie zmiany z dysku
  trafia do dziennika. Tekst sprzed wczytania ponownego zawsze trafia do historii lokalnej (także okno bez zmian
  i wczytanie bez pytania). Pytania nie mają dodatkowego przycisku „Anuluj”: Esc wybiera bezpieczną odpowiedź
  (**Zostaw**, **Zachowaj moje zmiany**; przy pliku usuniętym domyślny jest **Zachowaj w oknie**) —
  `UIServices.ask(_:message:buttons:escapeButton:)`. Nieudane wczytanie (np. plik nie do odczytu, para o innym
  podziale) — także w trybie bez pytania — zapamiętuje stan dysku jako znany (bez pytania przy każdej aktywacji),
  a błąd pokazuje użytkownikowi i zapisuje w dzienniku.
- **Plik usunięty albo przeniesiony:** „Plik „…” nie istnieje na dysku” — **Zachowaj w oknie** (okno oznaczone jako
  zmienione, zapis utworzy plik ponownie; bez ponownego pytania) albo **Zamknij okno** (okno ze zmianami — zwykłe
  pytanie o zapis).
- **Para `.pks`/`.pkb`:** wczytywany jest tylko zmieniony plik (jego karta), druga karta zostaje bez zmian, także
  niezapisana; kursor zostaje w tym samym miejscu karty, karty i Zawartość kodu odświeżają się z tekstu. Wczytanie
  sprawdza obieg jak otwarcie pary — podział nowego tekstu na karty musi dać te same pliki, każdy z jedną jednostką
  swojej karty; inaczej (np. komentarz za `END` specyfikacji przeszedłby do karty ciała) odmowa z komunikatem „otwórz
  go osobno”.
- **Wczytanie ponowne** okna z jednym plikiem odtwarza je jak otwarcie (kodowanie, BOM, końce linii; okno testu `.tst`
  ze zmiennymi, raport, diagram, notatnik); kursor na tej samej pozycji, jeśli się mieści.
- **Komenda `file.reload`** „Wczytaj ponownie z dysku” (menu Plik, wstążka Start › Plik › Więcej; agent: Za zgodą,
  skutek: tekst edytora; na liście komend aplikacji dla agenta) — okno pary: oba pliki. Okno ze zmianami: użytkownik
  potwierdza utratę zmian, agent dostaje odmowę.
- **Preferencje › Ogólne › Pliki:** **Wykrywaj zmiany plików na dysku** (domyślnie włączona) i wczytywanie bez
  pytania; obie w zestawach preferencji (sekcja Ogólne).
- **Worksety:** okno ze zmianami zapisuje skrót pliku z otwarcia albo zapisu (pole opcjonalne `fileHash`, para —
  `hash` każdego pliku) — po przywróceniu zmiana pliku z czasu, gdy Pelikan był zamknięty, jest wykrywana przy
  aktywacji i przy zapisie. Okno bez zmian i tak czyta plik ponownie przy przywróceniu.
- **Dziennik:** `Log.files` — wykrycie zmiany, usunięcia i wczytanie ponowne, nazwa pliku `privacy: .hash`, bez
  treści.
- **Ograniczenia:** brak obserwacji systemu plików w tle (FSEvents) — zmiana jest wykrywana dopiero przy aktywacji
  okna, karty albo aplikacji (jak we wzorcu); zmiana pliku okna w tle, gdy Pelikan jest aktywny i okno na wierzchu,
  zostanie zauważona przy następnej aktywacji (np. przełączeniu okna albo aplikacji) albo przez **Wczytaj ponownie
  z dysku**. Pliki w iCloud Drive (i innych dostawcach plików): synchronizacja może zmieniać datę bez zmiany treści
  (bez pytania — porównanie skrótu), a plik usunięty z dysku lokalnego przez „Optymalizuj miejsce” (zastąpiony
  symbolem zastępczym) bywa widziany jako usunięty albo jest pobierany przy odczycie — Pelikan nie odróżnia tych stanów
  od zwykłej zmiany pliku.
