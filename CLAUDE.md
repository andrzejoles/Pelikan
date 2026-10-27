# Pelikan — wskazówki dla sesji Claude Code

Natywne IDE dla Oracle PL/SQL na macOS (Swift 6, AppKit), odpowiednik PL/SQL Developer 17 z utPLSQL i API dla agentów AI.
Wymagania: `docs/PROMPT.md`, plan: `docs/PLAN.md`, macierz funkcji: `docs/FEATURES.md`, architektura:
`docs/ARCHITECTURE.md`, bezpieczeństwo: `docs/SECURITY.md`, decyzje: `docs/DECISIONS.md`, ADR: `docs/adr/`,
zachowania wzorca: `docs/research/behaviour.md`. **Na początku każdej sesji przeczytaj PLAN, status.json i ostatnie
decyzje, zanim cokolwiek zmienisz.**

## Zasady (decyzje właściciela)
- Praca autonomiczna (D1): pytania zastępuje wpis w DECISIONS; zatrzymanie tylko w sytuacjach z PROMPT §13
  (blokada w raporcie: `scripts/status.py block "…" "…"`).
- **Raport postępów** po każdym zadaniu, commicie, blokadzie i co ≤ 30 min: `scripts/status.py done|task|next|tests…`
  (generuje `docs/progress/index.html` i `~/Pelikan-raport/index.html`). Właściciel patrzy na raport — aktualizuj go.
- Wersja z historii gita (`scripts/version.sh`, D184): od 1.0.0 tytuł scalonego PR `feat…` podnosi środkową cyfrę,
  inne — ostatnią; `typ!:` (główna cyfra) tylko na słowo właściciela. Nowości wydania: sekcja w `docs/NOWOSCI.md`.
  Zmiany na `main` tylko przez PR scalane „Merge pull request”
  (`gh pr merge --merge --delete-branch`), nigdy squash/rebase, nigdy push na `main`. CI czerwone — naprawiać.
- Commity: konwencjonalne prefiksy po angielsku + identyfikator z macierzy, np. `feat(sqlwin): … (PD-SQLW-004)`;
  stopka `Co-Authored-By` z promptu systemowego. Tożsamość gita lokalnie: adres noreply (D3).
- Autor wszędzie: „Andrzej Oleś w kooperacji z Claude AI”. Nazwa i bundle id tylko w `Config/Brand.xcconfig`.
- Każda czynność jest komendą w rejestrze (menu, skróty, paleta, agent), z poziomem dostępu agenta i opisem skutków.
- Hasła tylko w Pęku kluczy — nigdy w plikach, logach, argumentach procesów, zmiennych środowiskowych, raporcie.
  Repozytorium publiczne: przed commitem nic z `~/Library`, kluczy, haseł, adresów baz, ścieżek domowych.
- Testy łączą się tylko z lokalną bazą testową (`scripts/testdb.sh`, `.testdb/env`); nigdy z bazami właściciela.
  Nazwy połączeń i aliasy TNS dla lokalnych baz testowych zawsze z przedrostkiem `dev_` (np. `dev_test`, `dev_pelikan_seps`).
- Teksty interfejsu po polsku (klucz = polskie zdanie) przez `L10n.tr("…")` (literał; `\(…)` → `%@`), tłumaczenia en/de/es/uk
  w String Catalog. Po dodaniu tekstów: `scripts/l10n.py extract` i przetłumacz nowe teksty (CI: `scripts/l10n.py check --strict` — komplet en/de/es/uk); `export`/`import`.
- Funkcja zrobiona = test (✅) lub zrzut ekranu (👁) i aktualizacja stanu wiersza w `docs/FEATURES.md`.
- Dziennik aplikacji (D170): `Log.<obszar>.info("… \(wartość)")` z `PelikanLog`; tekst w interpolacji jest prywatny
  (nazwy połączeń, serwerów, katalogów — `privacy: .hash`; stałe techniczne — `.public`). Nigdy haseł, treści SQL,
  wartości zmiennych ani danych z bazy. Testy wpisów: `Log.addSink(MemoryLogSink(everything: true))`, bez `Log.configure`.

## Polecenia
```sh
make testdb                 # baza testowa (Colima musi działać: colima start)
make test                   # wszystkie testy pakietu (integracyjne wymagają bazy)
make test-unit              # bez bazy i bez SSH
make test-ssh               # SSH na lokalnym sshd i Pro*C, z limitem czasu (jak CI)
make generate build run     # aplikacja (XcodeGen + xcodebuild)
scripts/status.py done "…"  # wpis do raportu + regeneracja
scripts/testdb.sh sql TEST <<< "select 1 from dual;"   # sqlplus w kontenerze
```

## Pułapki
- `scripts/testdb.sh`: `set -o pipefail` + `tr </dev/urandom | head` zabija skrypt po cichu (SIGPIPE) — losowanie przez
  `openssl rand`. `docker cp` tworzy pliki jako root — `chown` przed użyciem przez oracle.
- `DBMS_SESSION.SLEEP` nie reaguje na Break do końca uśpienia (tak samo w SQL*Plus) — testy przerwania na długim zapytaniu.
- Komunikaty SourceKit „No such module”/„Cannot find type” w edytorze to nieaktualny indeks — liczy się `swift build`.
- Runner CI macOS to obraz `xcode-27` (macOS 27, Xcode 27 — wersja próbna GitHuba, D166); przy kłopotach z kolejką
  wrócić do `macos-latest` (Xcode 26: ostrzeżenia o celu macOS 27, testy przechodzą). CI Linux: Swift 6.4 (swiftly).
- Testy na bazie dzielą schemat testowy — uruchamiać szeregowo (`swift test --no-parallel --filter PelikanDBTests`, tak robi
  `make test` i CI); równoległe zestawy kolidują (np. kompilacja niepoprawnych obiektów).
- Debuger: po `DBMS_DEBUG.DEBUG_ON` każde wywołanie PL/SQL w sesji docelowej czeka na debuger — DBMS_OUTPUT włączać
  przed `DEBUG_ON`, a `DEBUG_OFF` obsłużyć z sesji nadzorującej (ADR 0006, `DebuggerEngine.cleanUp`).
- Instant Client lokalnie: `~/Downloads/instantclient_23_26` (wykrywany automatycznie); w CI Linux: `/opt/oracle/instantclient`.
- Zrzuty w tle: `scripts/screenshots.sh [scenariusz]` (scenariusze w `scripts/screenshots/*.json`, D113). Aplikacja Debug
  nie może czytać `~/Downloads` (pytanie macOS o dostęp przerywa właścicielowi) — skrypt używa kopii w `.testdb/instantclient`.
  Scenariusz musi podać wszystkie argumenty komend: brakujący argument otwiera okno dialogowe, które aktywuje aplikację.
  Pliki zrzutów nazywane są od tytułu okna (`NN-scenariusz-tytul.png`), bo kolejność okien między przebiegami się zmienia.
