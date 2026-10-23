# Zadanie: zdalny build Pro*C w Pelikanie (backend SSH przejęty z BiFold)

## Kontekst

- **Pelikan** (IDE typu PL/SQL Developer dla macOS) dostaje obsługę Pro*C: edycja lokalna,
  build zdalny przez SSH na AIX 6.1 (ksh88, stary OpenSSH, `scp` bez SFTP).
- **BiFold** (`github.com/andrzejoles/Bifold`, publiczne, ten sam autor) ma sprawdzoną na AIX 6.1
  warstwę SSH/SCP w `Packages/BifoldKit/Sources/BifoldCore/Remote/`.
- **Decyzja: bez wspólnej biblioteki.** Kod z BiFold jest jednorazowo kopiowany do Pelikana i od tej
  chwili rozwija się w Pelikanie niezależnie, pod potrzeby IDE. BiFold nie jest zmieniany.
- **Środowisko docelowe:** AIX 6.1, kompilator IBM XL C/C++ for AIX V12.1 (`xlc`), Pro*C zainstalowany
  i skonfigurowany na serwerze (Pelikan nie przekazuje do builda żadnych haseł Oracle).
- **Źródła w gicie** (zdalne repo na GitLab). Obecny przepływ: merge na GitLab, potem `git pull` na AIX.
  Pelikan wpisuje się w ten przepływ — źródeł na serwer nie wgrywa przez `scp`.
- Pelikan i BiFold działają na tym samym sprzęcie i systemie (macOS 27).

## Faza 1: przejęcie kodu z BiFold

**Źródło:** repo BiFold, commit `a1ee643` (główny `main` na 2026-10-20). W nagłówku każdego
skopiowanego pliku komentarz: `// Pochodzi z BiFold (Remote/SSH.swift @ a1ee643), dalej rozwijany w Pelikanie.`
— tylko informacyjnie, bez obowiązku synchronizacji.

**Do skopiowania (sprawdzone na AIX 6.1):**

| Element | Plik w BiFold | Dlaczego warto |
|---|---|---|
| `Spawn` — `posix_spawn` z argumentami jako bajty | `Remote/SSH.swift` | Omija NFD z `Foundation.Process` (polskie nazwy na AIX). Anulowanie, pauza, timeout. |
| `NameEncoding` (UTF-8 / ISO-8859-2) | `Remote/SSH.swift` | Kodowanie nazw i tekstu poleceń. |
| `SSHSession` | `Remote/SSH.swift` | ControlMaster/ControlPersist, stare algorytmy filtrowane przez `ssh -Q`, hasło przez FIFO + askpass (nigdy w argumentach/env), `accept-new` + known_hosts, `explain()` błędów negocjacji, `scp -O` z poprawnym escapowaniem, `shellQuote`. |
| `KeychainStore` | `Remote/Connections.swift` | Sekrety w Pęku kluczy. |
| Katalog gniazd (limit `sun_path` 104 B) | `BifoldWorkspace/Remote/RemoteManager.swift` (`socketDirectory()`) | Bez tego długa ścieżka do ControlPath psuje połączenie. |
| Parser `ls -la` (AIX/Linux/BSD) | `Remote/ScpFS.swift` (`parseListing`, `parseMode`) | Przyda się przy sprawdzaniu plików na serwerze; przepisać na własny typ wyniku Pelikana. |
| Uruchamianie lokalnego `sshd` w testach | `Tests/BifoldWorkspaceTests/ScpTests.swift` | Wzorzec testów integracyjnych bez dotykania `~/.ssh`. |

**Nie kopiować:** `ScpFS` (poza parserem), `RemoteFS`, `Rclone`, `RemoteConnection` (model pod rclone
i panele plików), `RemoteManager`, terminal SwiftTerm, warstwę VFS.

**Dostosowanie przy kopiowaniu:**
- Zależności od `BifoldCore` (`VFSError`, `RemoteError`, `L10n.tr`, `expandTilde`, `runBlocking`) zastąpić
  odpowiednikami Pelikana albo własnym typem błędu SSH z przypadkami strukturalnymi
  (`negotiationFailed`, `permissionDenied`, `hostKeyChanged`, `timeout`, `cancelled`, `io`, `invalidName`,
  `unencodable`). Teksty dla użytkownika tworzy warstwa UI Pelikana, zgodnie z jego zasadami lokalizacji.
- Platforma zgodna (oba projekty: macOS 27, Swift 6.2, tryb języka 6) — kod przenosi się bez zmian w tym zakresie.
- Testy z lokalnym `sshd` przenieść i uruchomić w Pelikanie przed rozbudową — punkt odniesienia, że kopia działa.

## Rozbudowa pod potrzeby IDE (w Pelikanie)

Braki skopiowanego kodu, które trzeba uzupełnić:

1. **Strumieniowanie wyjścia.** `Spawn.run` zbiera całe stdout/stderr i oddaje po zakończeniu procesu.
   Dodać `Spawn.stream(...) -> AsyncThrowingStream<SpawnEvent, Error>` (`.stdout(Data)`, `.stderr(Data)`,
   `.exit(Int32)`). Dekoder tekstu z buforem resztek (UTF-8 może rozciąć znak między porcjami).
2. **Stdin.** Teraz zawsze `/dev/null`. Opcja `stdin: .null | .data(Data) | .file(path)` (`cat > plik`, `ksh -s`).
3. **Pty i Stop.** `SSHSession.run` nie używa pty, więc anulowanie kończy tylko lokalny `ssh`, a `make` na
   serwerze działa dalej. `stream(command:, tty:)` z `-tt`: zamknięcie `ssh` → SIGHUP dla grupy procesów
   na serwerze; normalizacja `\r\n` → `\n`. Zapas: skrypt wypisuje `@@PID $$`, Stop wysyła osobnym
   połączeniem `kill -TERM -<pid>`, po 5 s `kill -KILL`.
4. **Timeout.** Domyślne 120 s w `SSHSession.run` jest za krótkie na build: `nil` = bez limitu, plus
   opcjonalny limit czasu bez wyjścia.
5. **Środowisko zdalne.** Nieinteraktywny ksh88 nie czyta `.profile` (brak `ORACLE_HOME`, `LIBPATH`, `PATH`).
   Prolog `NAZWA='wartość'; export NAZWA;` (dwa kroki — bezpieczne w ksh88) z konfiguracji celu.
6. **Kodowanie treści plików** — dotyczy edytora, nie transferu (źródła idą przez git). Edytor Pelikana
   otwiera i zapisuje `.pc`/`.h`/makefile w kodowaniu ustawionym dla projektu (to samo, w którym pliki są
   w repo; ustalić na podstawie istniejących plików). Przy zapisie sprawdzenie niekodowalnych znaków
   (linia, kolumna, znak) — ISO-8859-2 nie ma m.in. cudzysłowów „ ”. Plik nie może się po cichu
   przekodować na UTF-8 przy pierwszej edycji.

Testy rozbudowy na lokalnym `sshd`: kolejność porcji strumienia i kod wyjścia, stdin, Stop z pty (proces
zdalny znika), ISO-8859-2 w nazwach i wyjściu, parser `ls -la` z próbkami z AIX.

## Faza 2: funkcje Pelikana

### Menedżer połączeń SSH
Własne okno w stylu menedżera połączeń Oracle w Pelikanie (drzewo z folderami, dodaj/edytuj/duplikuj/usuń,
eksport/import bez sekretów). Model `PelikanSSHTarget`:
- nazwa, folder, host, port, użytkownik, plik klucza / agent / hasło SSH (Keychain),
- `legacyAlgorithms`, kodowanie nazw i wyjścia konsoli, ścieżka do ksh (domyślnie `/usr/bin/ksh`),
- środowisko: `ORACLE_HOME`, `LIBPATH`, `PATH`, dowolne dodatkowe zmienne,
- **katalog bazowy** (wymagany) — zawiera foldery `src` i `bin`; Pelikan wylicza `<baza>/src` i `<baza>/bin`,
  z możliwością nadpisania nazw tylko w ustawieniach zaawansowanych,
- **katalog backupów** (wymagany) — osobne pole, może leżeć gdziekolwiek; podpowiedź `<baza>/backup`,
- git na serwerze: katalog working copy (domyślnie `<baza>/src` — patrz otwarte pytania), gałąź
  (domyślnie `MASTER`), nazwa remote (domyślnie `origin`),
- katalog roboczy Pelikana (blokada, skrypty uruchomieniowe): `<backupy>/.pelikan` — **zawsze poza working
  copy**, inaczej pliki Pelikana pojawiłyby się w `git status` i blokowały wdrożenie,
- komenda builda: domyślnie `make` (ewentualne argumenty w konfiguracji); Pelikan nie wywołuje kompilatora
  ani `proc` bezpośrednio — całą logikę budowania ma makefile,
- środowisko: **UAT** albo **PROD** (kolor w drzewie połączeń, w konsoli i w tytule okna; PROD = dodatkowe
  potwierdzenie z wpisaniem nazwy celu).

Typowo dwa połączenia na projekt: UAT i produkcja, oba na gałęzi `MASTER`. Nazwy gałęzi w gicie są wrażliwe
na wielkość liter — Pelikan porównuje je dokładnie.

Przycisk **Testuj**: łączy się i pokazuje `uname -a`, `oslevel -s`, wersję serwera SSH (z logu negocjacji),
`make`, `git --version`, gałąź i czystość working copy (`git status --porcelain`),
`compress`/`gzip`; sprawdza, czy `<baza>`, `<baza>/src`, `<baza>/bin` i katalog backupów istnieją i są
zapisywalne (backupy można utworzyć z potwierdzeniem).

### Integracja z gitem (lokalnie)
Pelikan nie zastępuje klienta gita ani GitLaba — korzysta z lokalnego `git` w katalogu projektu:
- pasek stanu: bieżąca gałąź, niezacommitowane zmiany, commity niewypchnięte na GitLab,
- widok „gdzie co jest”: commit `origin/<gałąź>` (po `git fetch`) i commit wdrożony na każdym celu
  (z historii wdrożeń i z `git rev-parse HEAD` na serwerze),
- ostrzeżenie przed wdrożeniem, gdy lokalne zmiany nie są jeszcze na GitLab (wdrożenie i tak bierze
  stan z GitLaba, nie z Maca).

### Pipeline „Wdrożenie” (po merge na GitLab; każdy krok = sekcja w konsoli)
1. **Podsumowanie przed startem:** cel, commit obecny na serwerze → commit `origin/<gałąź>`, lista commitów
   i zmienionych plików między nimi (lokalnie, z `git log`/`git diff --stat`). PROD wymaga potwierdzenia.
   Na PROD Pelikan dodatkowo pokazuje, czy ten sam commit jest już wdrożony na UAT (ostrzeżenie, jeśli nie).
2. **Blokada:** `mkdir <backupy>/.pelikan/.lock` (atomowe na każdym systemie); w środku plik z użytkownikiem, hostem
   Maca i czasem. Istniejąca blokada → kto ją trzyma; ręczne zdjęcie tylko z potwierdzeniem.
3. **Kontrola working copy na serwerze:** właściwa gałąź i `git status --porcelain` puste. Zmiany wprowadzone
   ręcznie na serwerze → przerwanie z listą plików i diffem; Pelikan niczego nie nadpisuje ani nie czyści.
4. **Pobranie zmian:** zapis `HEAD` przed, `git pull --ff-only` (nigdy merge na serwerze), zapis `HEAD` po.
   Brak fast-forward → przerwanie z komunikatem.
5. **Backup binarki:** kopia `<baza>/bin/nazwa` do katalogu backupów jako `nazwa.YYYYmmddHHMMSS.<krótki-commit>`,
   retencja ostatnich N (konfigurowalne). Źródeł nie archiwizujemy — ich historią jest git.
6. **Build:** `make` w `<baza>/src`, przez skrypt ksh88 zapisany do `<backupy>/.pelikan/run-<id>.ksh`
   i uruchomiony przez `ssh -tt`; strumień do konsoli, kod wyjścia `make` decyduje o sukcesie.
7. **Instalacja do bin:** `cp` do `<baza>/bin/nazwa.new`, zachowanie praw, `mv nazwa nazwa.prev`,
   `mv nazwa.new nazwa`. Przy błędzie builda `bin` pozostaje nietknięty.
8. **Zdjęcie blokady, zapis historii:** kto, kiedy, cel, commit przed/po, nazwa binarki, wynik, pełny log.

**Gdy build się nie powiedzie:** binarka bez zmian; working copy zostaje na nowym commicie (zgodnym z GitLab).
Konsola pokazuje błędy; poprawka idzie normalną drogą (commit → merge → ponowne wdrożenie). Opcjonalnie,
z potwierdzeniem: powrót working copy do commita sprzed `pull`.

**Rollback:** binarka z `.prev` lub z wybranego backupu (pipeline z konsolą). Źródła wycofuje się przez revert
na GitLab i ponowne wdrożenie; Pelikan może to podpowiedzieć, ale nie robi `reset`/`checkout` na serwerze
bez wyraźnej decyzji.

### Build próbny (opcjonalny, przed commitem)
Szybka kontrola, czy lokalne, niezacommitowane zmiany kompilują się na AIX — bez dotykania repo i `bin`
na serwerze:
- tylko na połączeniu UAT (dla PROD opcja niedostępna),
- osobny katalog na serwerze per użytkownik (np. `~/.pelikan/sandbox/<projekt>`) z własnym klonem repo,
- przed buildem: `git fetch` i `checkout` commita, na którym bazują lokalne zmiany, potem `scp -O`
  zmienionych i nowych plików z `git status` na Macu,
- build tą samą komendą, wynik tylko w konsoli; nic nie trafia do `bin`.

### Skrypty po stronie serwera (ksh88, AIX 6.1)
Szablony w zasobach Pelikana, z podstawianiem wyłącznie przez `shellQuote`. Zakazane: `set -o pipefail`,
`local`, tablice asocjacyjne, `${v//a/b}`, `sed -i`, `stat`, `mktemp`, `md5sum`/`sha256sum`, `date +%s`,
`tar -z`, `xargs -0`, GNU-owe opcje `find`. Komendy gita tylko w formie dostępnej w wersji z serwera
(sprawdzić `git --version`; np. `git -C` wymaga 1.8.5 — bezpieczniej `cd`). Kod wyjścia sprawdzany po każdej
komendzie (`|| exit N`), bez polegania na potokach. Każdy krok wypisuje znaczniki `@@STEP nazwa` /
`@@END nazwa kod`, które konsola zamienia na sekcje i statusy. Komendy parsowane (`git status`, `ls`) z
`LC_ALL=C`; build w lokalizacji z konfiguracji celu.

Szablony muszą być przetestowane na prawdziwym AIX 6.1 (ksh93 na macOS nie jest wiarygodnym testem);
w repo zestaw fixture'ów z rzeczywistym wyjściem.

### Konsola
- Panel dolny; sekcje kroków ze statusem i czasem; przewijanie z „przyklejeniem” do końca.
- Dekodowanie wg kodowania celu; filtr: wszystko / tylko błędy i ostrzeżenia.
- Błędy klikalne → plik i linia w lokalnym projekcie (ścieżka względna wobec repo na serwerze = względna
  wobec repo na Macu).
- **Stop** = zakończenie `ssh -tt` (SIGHUP po stronie serwera) + zapasowe `kill` po znaczniku `@@PID`;
  po zatrzymaniu zawsze zdjęcie blokady.
- Zapis i ponowne otwarcie logów z historii wdrożeń.

### Parsery błędów
Pelikan uruchamia tylko `make`; parsery służą wyłącznie do rozpoznawania komunikatów w wyjściu `make`,
żeby błędy w konsoli były klikalne. Sukces lub porażkę builda wyznacza kod wyjścia `make`, nie parser.
W wyjściu pojawiają się dwa rodzaje komunikatów:
- **Pro*C** (`PCC-S-…`, `PCC-W-…` z informacją o linii i pliku `.pc`),
- **IBM XL C/C++ V12.1** — format `"plik", line L.C: 1506-NNN (S) treść`, ważność `(I)`, `(W)`, `(E)`, `(S)`,
  `(U)`. Parser musi działać także z `-qsrcmsg` (kompilator dokleja wtedy linię źródła i znacznik kolumny).

Przy `LINES=YES` w `proc` wygenerowany `.c` zawiera dyrektywy `#line`, więc `xlc` powinien raportować
od razu plik `.pc` i jego linie — **sprawdzić na serwerze**; jeśli nie, mapowanie po `#line` w Pelikanie.
Formaty budować na próbkach zebranych z naszego AIX-a, nie z pamięci — próbki jako fixture'y testów.

## Zasady
- Sekrety SSH tylko w Keychain; nigdy w argumentach procesów, zmiennych środowiskowych, plikach ani logach.
- Procesy SSH/SCP/git zdalny wyłącznie przez `Spawn` (posix_spawn), nigdy przez `Foundation.Process`.
- Na serwerze Pelikan nie nadpisuje zmian w working copy, nie robi merge ani `reset` bez wyraźnej decyzji
  użytkownika.
- Jeśli repo Pelikana jest publiczne: przed commitem nic z `~/.ssh`, kluczy, nazw prawdziwych hostów,
  ścieżek domowych.

## Kryteria akceptacji
- Testy przeniesione z BiFold przechodzą w Pelikanie przed rozpoczęciem rozbudowy.
- Na AIX 6.1 pełny cykl: kontrola working copy → `git pull --ff-only` → backup binarki → `make` →
  instalacja do `bin` → rollback z `.prev`, z konsolą na żywo i działającym Stop.
- Ręczna zmiana pliku w working copy na serwerze zatrzymuje wdrożenie przed `pull`.
- Błędy `proc` i `xlc` są klikalne i prowadzą do właściwej linii w lokalnym `.pc`.
- Zapis pliku z „” przy kodowaniu ISO-8859-2 jest blokowany z dokładnym wskazaniem miejsca.

## Otwarte pytania
1. Wersja gita na AIX (`git --version`) — wpływa na dostępne opcje w skryptach.
2. Gdzie na serwerze jest korzeń repo gita: `<baza>/src` czy `<baza>` (wtedy `bin` jest w repo albo
   w `.gitignore` — to wpływa na kontrolę czystości working copy)?
3. Skąd Pelikan wie, które pliki z builda trafiają do `bin` — jedna binarka na projekt, lista w konfiguracji,
   czy cel `install` w makefile?
4. W jakim kodowaniu są pliki w repo (UTF-8 czy ISO-8859-2)?
5. Czy build próbny jest potrzebny w pierwszej wersji, czy później?
