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
Zakres z `zadanie-pelikan-proc-ssh.md`. Do czasu odpowiedzi właściciela (D1 — bez pytań w trakcie pracy):
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

### D-S8G-1 · 2026-10-24 — Kursor zagnieżdżony w nowej karcie wyniku
Wzorzec otwiera wynik `<Cursor>` w nowym SQL Window. Pelikan dokłada kartę wyniku w tym samym oknie: kursor jest częścią
sesji okna (zamknięcie okna zamyka kursor), a nowe okno nie miałoby polecenia do ponownego wykonania.

### D-S8G-2 · 2026-10-24 — Bez blokady przewijania kolumn i wierszy
NSTableView nie ma zamrażania kolumn ani wierszy; dwie zsynchronizowane tabele komplikowałyby edycję, sortowanie i
przenoszenie kolumn. Kolumna numerów wierszy i nagłówek zostają widoczne przy przewijaniu; filtr kolumn (PD-GRID-011)
pozwala zawęzić siatkę do potrzebnych kolumn.

### D-S8G-3 · 2026-10-24 — Wyrównanie kolumn bez wysokości wierszy i zmiany okna
„Align” ustawia szerokości (nagłówek, treść z pierwszych 500 wierszy, oba) i zapisuje szablon kolejności i szerokości
dla zapytania (klucz: tekst zapytania ze zwiniętymi odstępami), stosowany automatycznie (preferencja). Wysokość
wierszy, „Hide Editor” i „Adjust Window width” pominięte — siatka ma stałą wysokość wiersza zależną od czcionki.

### D-S8G-4 · 2026-10-24 — LOB na żądanie jako podgląd 4000 bajtów
Sterownik zawsze zwraca lokator i rozmiar LOB; przy „LOB na żądanie” siatka pobiera tylko 4000 bajtów (zamiast 1 MB),
oznaczonych jako obcięte, a Large Data Editor dociąga całość przez ROWID. Zero bajtów odebrałoby panelowi wartości
podgląd i znacznik obcięcia.

### D-S8G-5 · 2026-10-24 — Wartości zmiennych okna w worksecie zamiast .pfi
Wzorzec trzyma wartości zmiennych w pliku `.pfi` obok skryptu. Pelikan zapisuje je w stanie okna w worksecie (także dla
okien bez pliku); odświeżenie karty i automatyczne odświeżanie używają zapamiętanych wartości bez pytania (NF8).

