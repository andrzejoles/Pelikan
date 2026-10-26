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
dokowanie paneli wymagałoby własnego menedżera układu na AppKit. Kolory tekstu i tła biorą się z motywu systemu
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
