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
