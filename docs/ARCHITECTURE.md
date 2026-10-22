# Pelikan — architektura

Wymagania: [`PROMPT.md`](PROMPT.md). Decyzje: [`DECISIONS.md`](DECISIONS.md), ADR: [`adr/`](adr/). Bezpieczeństwo:
[`SECURITY.md`](SECURITY.md). Macierz funkcji: [`FEATURES.md`](FEATURES.md).

## 1. Układ repozytorium

```
Pelikan/
├── project.yml                 # definicja projektu Xcode (XcodeGen) — źródło prawdy
├── Makefile                    # build, test, test-integration, testdb, report…
├── Config/Brand.xcconfig       # NAZWA APLIKACJI I BUNDLE ID — jedyne miejsce
├── App/                        # cel Pelikan.app (AppKit; SwiftUI w ustawieniach i prostych oknach)
├── Packages/PelikanKit/        # cała logika jako pakiet SPM, testowalny bez interfejsu
│   ├── Sources/
│   │   ├── PelikanSQL/         # lekser, dzielenie skryptów, klasyfikacja, zmienne (& : Jasper), parser (Etap 2)
│   │   ├── PelikanDB/          # protokoły: DatabaseSession, wartości, błędy, MetadataProvider (Etap 2), Debugger (3)
│   │   ├── CODPI/              # ODPI-C 26.0 (C, dołączone źródła)
│   │   ├── PelikanODPI/        # sterownik Instant Client
│   │   ├── PelikanThin/        # sterownik OracleNIO (Etap 1)
│   │   ├── PelikanWorkspace/   # model stanu, rejestr komend, komendy, ustawienia, połączenia, historia
│   │   ├── PelikanTest/        # utPLSQL: TestRunner, eksplorator, pokrycie (Etap 4)
│   │   ├── PelikanAgent/       # polityka uprawnień, sesje agenta, serwer gniazda, narzędzia MCP (Etap 5)
│   │   ├── PelikanBridgeKit/   # most stdio ↔ gniazdo Unix (Etap 5)
│   │   └── pelikan-mcp/        # plik wykonywalny mostu (Etap 5)
│   └── Tests/                  # Swift Testing; PelikanDBTests łączą się tylko z bazą testową
├── scripts/                    # version.sh, testdb.sh, progress.py, status.py, release.sh (Etap 8)…
└── docs/
```

Zależności (strzałka = „zależy od”):

```
Pelikan.app ─► PelikanWorkspace ─► PelikanDB ─► PelikanSQL
     │               ▲   ▲
     │               │   └── PelikanODPI ─► CODPI      PelikanThin ─► OracleNIO
     ├─► PelikanAgent┘ ─► PelikanBridgeKit             pelikan-mcp ─► PelikanBridgeKit
     ├─► PelikanTest ─► PelikanDB
     └─► SwiftTerm, Sparkle
```

`PelikanSQL`, `PelikanDB`, sterowniki i `PelikanTest` nie importują AppKit i budują się na Linuksie (CI z bazą Oracle).
`PelikanWorkspace` nie importuje AppKit (testowalny bez interfejsu); interfejs dostaje usługi przez protokół `UIServices`
(pytania, okna wyboru, okno zgody), który w testach implementują atrapy.

## 2. Warstwa bazy (PelikanDB)

- `DatabaseSession` (protokół, `Sendable`): `execute(sql, binds, options) → ExecutionResult`, `fetch(resultSet,
  maxRows) → RowBatch`, `closeResultSet`, `commit`, `rollback`, `breakExecution()` (z dowolnego wątku), `ping`,
  `setTags` (MODULE/ACTION/CLIENT_INFO), `close`, `info` (`SessionInfo`: sterownik, wersje, `DriverCapabilities`,
  schemat). Wartości: `OracleValue` (NUMBER jako tekst — pełna precyzja), `ColumnInfo`, `BindVariable` (IN/OUT/IN OUT,
  REF CURSOR, LOB), błędy `OracleError` (kod, komunikat, pozycja, ostrzeżenie, utrata połączenia, anulowanie).
- `ConnectionTarget` (zapisywane: użytkownik, connect string, rola, proxy, external auth, katalog TNS, edition) jest
  oddzielone od `Credentials` (tylko w pamięci, `description` ukrywa treść, nie `Codable`).
- Sterownik ODPI: sesja na własnej szeregowej kolejce GCD (wywołania OCI blokują), `breakExecution` poza kolejką
  (OCIBreak, tryb THREADED), pobieranie tablicowe (fetch array 500), LOB do limitu (1 MB) z pełną długością.
- `MetadataProvider` (Etap 2): zapytania słownika odporne na wersję (ALL_/DBA_, brak kolumn na starszych wersjach →
  zapytanie alternatywne), cache w pamięci per połączenie, odświeżanie w tle, unieważnianie po kompilacji/DDL.
- `Debugger` (Etap 3): DBMS_DEBUG (sesja docelowa + sesja sterująca) i DBMS_DEBUG_JDWP (Pelikan jako serwer JDWP).

## 3. Model stanu aplikacji (PelikanWorkspace)

`@MainActor @Observable final class Workspace` — jedno źródło prawdy dla interfejsu i API agenta:

```
Workspace
├── connections: ConnectionStore      # definicje (foldery, kolory, środowisko dev/test/prod, sterownik, opcje agenta)
├── sessions: SessionManager           # sesje bazy: główna, per okno (multi/dual/single), kompilacji, agenta
├── documents: [Document]              # okna: SQL, Program, Test, Command, Explain Plan, Report, Diagram, Notebook…
├── activeDocumentID
├── history: StatementHistory          # Recall Statement (bez poleceń z hasłami)
├── settings: Settings                 # preferencje (zestawy preferencji w Etapie 8), skróty
├── registry: CommandRegistry, keymap: Keymap
└── journal: ActionJournal             # dziennik zmian (cofanie, „Cofnij sesję agenta”)

Document (wspólne): id, kind, title, connectionID (przypięte/nieprzypięte), fileURL, isModified, isCompiledStale,
                   transactionOpen, executing
SQLDocument: editor (EditorModel: tekst, zaznaczenie, kursor), results: [ResultTab] (ResultGridModel, pinned),
             output (DBMS_OUTPUT), statistics, variables (wartości & i :bind, Jasper)
ProgramDocument: units: [ProgramUnit] (karty), compileErrors, breakpoints
TestDocument: block, variables: [TestVariable], debugState
CommandDocument: dialog (bufor tekstu), editor, sqlplusState (SET…, DEFINE, VARIABLE, SPOOL)
```

Interfejs obserwuje model (`withObservationTracking`, D6 w Bifoldzie). Długie operacje (zapytania, kompilacja,
eksport, porównania, testy) działają w `Task` poza głównym aktorem i zawsze mają przerwanie (PROMPT §4.2 p.4).

## 4. Rejestr komend

Jak w Bifoldzie (ARCHITECTURE §4): każda czynność to `Command` z `CommandDescriptor` — identyfikator (`sql.execute`,
`sql.executeCurrent`, `session.commit`, `program.compile`, `browser.describe`…), tytuł (polski, lokalizowany),
kategoria (= menu wzorca: File, Project, Edit, Session, Debug, Tools, Reports, Configure, View, Window, Help),
skróty dla dwóch profili (`plsqlDeveloper` — F-klawisze i Ctrl wzorca z zamiennikami dla MacBooka; `macOS` — Cmd),
parametry (→ schemat narzędzia MCP), **poziom dostępu agenta** (`none/read/approval/full`), skutki
(`none/uiState/modifiesEditor/modifiesDatabase/transaction/external/settings`) i opis skutków. Komenda ma `run` i
opcjonalnie `preview` (skutki na sucho: tekst polecenia, obiekty, plan, liczba wierszy — okno zgody).
Menu, paski narzędzi, skróty (`KeyRouter`), paleta komend (Cmd+Shift+P) i API agenta wywołują
`Workspace.invoke(id, args, invoker)` — jedną funkcję. `docs/SKROTY.md` generuje test z rejestru.

## 5. Agent AI (Etap 5) — przepływ wywołania

Jak w Bifoldzie (ARCHITECTURE §7–8): `AgentLauncher` uruchamia CLI w terminalu SwiftTerm z tokenem 256 bit w środowisku
i konfiguracją MCP tylko dla sesji; CLI uruchamia `pelikan-mcp` (stdio), most łączy się z gniazdem Unix
(`~/Library/Application Support/Pelikan/run/agent.sock`, 0600 w katalogu 0700), serwer weryfikuje UID, drzewo procesów
i token, `ToolCatalog` mapuje narzędzia MCP na komendy rejestru, `AgentPolicy` liczy poziom efektywny
min(komenda, sesja, połączenie/środowisko), `ApprovalCenter` pokazuje okno zgody z podglądem.
Specyfika bazy: agent ma własną sesję bazy (`AgentSessionManager`, MODULE `Pelikan agent`, ACTION = narzędzie),
odczyt w `SET TRANSACTION READ ONLY` z limitami, klasyfikacja poleceń (`StatementClassifier`) przed wykonaniem, DML
niezatwierdzone do osobnej zgody, historia DDL obiektów przed zmianą (cofanie), dane z bazy jako `untrusted_content`.

## 6. Interfejs (Pelikan.app)

ADR 0005: jedno okno główne z lewą kolumną narzędzi (Object Browser, Connection List, Window List, Templates, File
Browser), obszarem dokumentów z własnym paskiem kart i prawym panelem (agent, Bookmarks, Search, Clipboard).
Edytor — ADR 0003 (TextKit 2), siatka — ADR 0004 (NSTableView). Ustawienia i proste okna — SwiftUI.

## 7. Dane aplikacji

`~/Library/Application Support/Pelikan/`: `connections.json` (bez haseł), `settings.json`, `keymap.json`,
`history/` (Recall Statement), `journal/`, `agent-logs/`, `run/` (gniazdo agenta), `worksets/`. Hasła — Pęk kluczy
(usługa `local.aoles.pelikan.connection`, konto = id połączenia). Testy wstrzykują katalog danych (`PELIKAN_DATA_DIR`,
`Workspace(persists: false)`) i nigdy nie dotykają prawdziwych danych.
