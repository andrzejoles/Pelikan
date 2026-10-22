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
