# Pelikan — architektura

Wymagania: [`PROMPT.md`](PROMPT.md). Decyzje: [`DECISIONS.md`](DECISIONS.md), ADR: [`adr/`](adr/). Bezpieczeństwo:
[`SECURITY.md`](SECURITY.md). Macierz funkcji: [`FEATURES.md`](FEATURES.md).

## 1. Układ repozytorium

```
Pelikan/
├── project.yml                 # definicja projektu Xcode (XcodeGen) — źródło prawdy
├── Makefile                    # build, test, test-unit, test-ssh, test-integration, testdb, installer…
├── Config/                     # Brand.xcconfig (NAZWA APLIKACJI I BUNDLE ID — jedyne miejsce), uprawnienia podpisu
├── App/                        # cel Pelikan.app (AppKit; SwiftUI w preferencjach i prostych oknach), QuickLook/
├── Packages/PelikanKit/        # cała logika jako pakiet SPM, testowalny bez interfejsu
│   ├── Sources/
│   │   ├── PelikanLog/         # dziennik aplikacji z prywatnością wartości (D170), bez zależności
│   │   ├── PelikanSQL/         # lekser, dzielenie skryptów, klasyfikacja poleceń, zmienne (& :), formater
│   │   ├── PelikanDB/          # protokół DatabaseSession, wartości, błędy, Oracle Net (tnsnames, LDAP, sqlnet.ora)
│   │   ├── CODPI/              # ODPI-C 26.0 (C, dołączone źródła)
│   │   ├── PelikanODPI/        # sterownik Instant Client (thick)
│   │   ├── PelikanThin/        # sterownik OracleNIO (thin)
│   │   ├── PelikanWorkspace/   # model stanu i komendy: Model, Commands, Connections, SQL, Editor, Metadata
│   │   │                       # (MetadataProvider), Debug (DebuggerEngine), UtPLSQL, Agent (baza agenta), Tools…
│   │   ├── PelikanAgent/       # serwer gniazda, polityka uprawnień, katalog narzędzi MCP (tylko macOS)
│   │   ├── PelikanBridgeKit/   # most stdio ↔ gniazdo Unix
│   │   ├── pelikan-mcp/        # plik wykonywalny mostu
│   │   ├── PelikanRemote/      # SSH przez systemowe ssh/scp (ControlMaster, askpass przez FIFO; tylko macOS)
│   │   └── PelikanProC/        # cele SSH i wdrożenia Pro*C (build na serwerze, repozytorium, kopie)
│   └── Tests/                  # Swift Testing; PelikanDBTests łączą się tylko z bazą testową, SSH — z lokalnym sshd
├── scripts/                    # version.sh, testdb.sh, l10n.py, screenshots.sh, signing.sh, release.sh, status.py…
└── docs/                       # dokumentacja, instrukcja (docs/manual), zrzuty, raport postępów
```

Zależności między modułami (wg Package.swift i project.yml; `PelikanLog` używają prawie wszystkie — pominięty):

| Moduł | Zależy od |
|---|---|
| Pelikan.app | PelikanWorkspace, PelikanODPI, PelikanThin, PelikanAgent, PelikanProC, PelikanRemote, SwiftTerm, Sparkle; osadza pelikan-mcp i PelikanQuickLook |
| PelikanWorkspace | PelikanDB, PelikanSQL |
| PelikanDB | — |
| PelikanODPI | PelikanDB, CODPI |
| PelikanThin | PelikanDB, PelikanSQL, OracleNIO, NIOCore |
| PelikanRemote | — |
| PelikanAgent | PelikanWorkspace, PelikanBridgeKit, swift-sdk MCP |
| PelikanProC | PelikanWorkspace, PelikanRemote |
| pelikan-mcp | PelikanBridgeKit |
| PelikanQuickLook (rozszerzenie) | PelikanSQL |

`PelikanLog`, `PelikanSQL`, `PelikanDB`, sterowniki i `PelikanWorkspace` nie importują AppKit i budują się na Linuksie
(CI z bazą Oracle); `PelikanAgent` i `PelikanRemote` są w `#if canImport(Darwin)`, w `PelikanProC` — tylko części z SSH.
Interfejs dostaje usługi przez protokół `UIServices` (pytania, okna wyboru, edytory obiektów), który w testach
implementują atrapy.

## 2. Warstwa bazy (PelikanDB)

- `DatabaseSession` (protokół, `Sendable`): `execute(sql, binds, options) → ExecutionResult`, `fetch(resultSet,
  maxRows) → RowBatch`, `closeResultSet`, `commit`, `rollback`, `breakExecution()` (z dowolnego wątku), `ping`,
  `setTags` (MODULE/ACTION/CLIENT_INFO), `close`, `info` (`SessionInfo`: sterownik, wersje, `DriverCapabilities`,
  schemat). Wartości: `OracleValue` (NUMBER jako tekst — pełna precyzja), `ColumnInfo`, `BindVariable` (IN/OUT/IN OUT,
  REF CURSOR, LOB), błędy `OracleError` (kod, komunikat, pozycja, ostrzeżenie, utrata połączenia, anulowanie).
- `ConnectionTarget` (zapisywane: użytkownik, connect string, rola, proxy, external auth, portfel, katalog TNS, edition)
  jest oddzielone od `Credentials` (tylko w pamięci, `description` ukrywa treść, nie `Codable`).
- Oracle Net: tnsnames.ora, sqlnet.ora i nazewnictwo katalogowe (LDAP — D158) czyta Pelikan.
- Sterownik ODPI: sesja na własnej szeregowej kolejce GCD (wywołania OCI blokują), `breakExecution` poza kolejką
  (OCIBreak, tryb THREADED), pobieranie tablicowe (fetch array 500), LOB do limitu (1 MB) z pełną długością.

Słownik i debuger leżą w `PelikanWorkspace`, bo korzystają z modelu połączeń i sesji:
- `MetadataProvider` (`PelikanWorkspace/Metadata`): zapytania słownika odporne na wersję (ALL_/DBA_, brak kolumn na
  starszych wersjach → zapytanie alternatywne), cache w pamięci per połączenie, unieważnianie po kompilacji/DDL.
- `DebuggerEngine` (`PelikanWorkspace/Debug`, ADR 0006): DBMS_DEBUG — sesja docelowa i sesja nadzorująca. Debuger
  DBMS_DEBUG_JDWP pominięty (D106).

## 3. Model stanu aplikacji (PelikanWorkspace)

`@MainActor @Observable final class Workspace` — jedno źródło prawdy dla interfejsu i API agenta:

```
Workspace
├── connections: ConnectionStore      # definicje (foldery, kolory, środowisko dev/test/prod, sterownik, opcje agenta)
├── sessions: SessionManager           # sesje bazy: główna, per okno (multi/dual/single), kompilacji, agenta;
│                                      # openConnections — otwarte połączenia w drzewie Object Browsera (D185)
├── documents: [Document]              # okna: SQL, Program, Test, Command, Explain Plan, Report, Diagram, Notebook
├── activeDocumentID
├── history: [HistoryEntry]            # Recall Statement (bez poleceń z hasłami)
├── settings: Settings                 # preferencje, zestawy preferencji, skróty
├── registry: CommandRegistry, keymap: Keymap
├── breakpoints, utplsqlHistory, project…
└── tasks: WorkspaceTaskCenter         # długie operacje w tle (postęp, przerwanie)

Document (wspólny dla rodzajów DocumentKind): id, kind, text, selectedRange, fileURL, isModified, isCompileStale,
          isExecuting, transactionOpen, connectionID (przypięte/nieprzypięte), sessionPurpose, results: [ResultTab],
          output (DBMS_OUTPUT), programUnits (karty okna programu)
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
Menu, wstążka, skróty (`Keymap`), paleta komend i API agenta wywołują `Workspace.invoke(id, args, invoker)` — jedną
funkcję. `docs/SKROTY.md` generuje test z rejestru.

## 5. Agent AI — przepływ wywołania

Jak w Bifoldzie (ARCHITECTURE §7–8): `AgentLauncher` uruchamia CLI w terminalu SwiftTerm z tokenem 256 bit w środowisku
i konfiguracją MCP tylko dla sesji; CLI uruchamia `pelikan-mcp` (stdio), most łączy się z gniazdem Unix
(`~/Library/Application Support/Pelikan/run/agent.sock`, 0600 w katalogu 0700), `AgentServer` weryfikuje UID, drzewo
procesów i token, `ToolCatalog` mapuje narzędzia MCP na komendy rejestru, `AgentPolicy` liczy poziom efektywny
min(komenda, sesja, połączenie/środowisko), a `AgentController` (bramka `AgentInvocationGate`) prosi interfejs
(`ApprovalPresenter` — w aplikacji `AgentUIController`) o okno zgody z podglądem.
Specyfika bazy (`PelikanWorkspace/Agent`, testy także na Linuksie): agent ma własną sesję bazy
(`Workspace.agentDatabaseSession`, MODULE `Pelikan agent`, ACTION = narzędzie), odczyt w `SET TRANSACTION READ ONLY`
z limitami, klasyfikacja poleceń (`StatementClassifier`) przed wykonaniem, DML niezatwierdzone do osobnej zgody
(`AgentChanges`), historia DDL obiektów przed zmianą (`undoAgentSession`), dane z bazy jako `untrusted_content`.
Narzędzia MCP to komendy `agent.*` z rejestru; `run_command` widzi tylko komendy z `AgentPolicy.appCommands`.

## 6. Interfejs (Pelikan.app)

ADR 0005: jedno okno główne ze wstążką, lewą kolumną z kartami (Połączenia, Obiekty, Okna, Szablony, Pliki), obszarem
dokumentów z własnym paskiem kart i panelem agenta. Object Browser pokazuje na najwyższym poziomie wszystkie otwarte
połączenia (D185). Pozostałe narzędzia (To-Do, projekt, historia schowka, narzędzia DBA…) otwierają się domyślnie jako
karty w panelach narzędzi po prawej i na dole okna głównego, z przeciąganiem między panelami i do osobnych okien
(`ToolDockManager`, D183). Edytor — ADR 0003 (TextKit 2), siatka — ADR 0004 (NSTableView). Preferencje i proste
okna — SwiftUI.

## 7. Dane aplikacji

`~/Library/Application Support/Pelikan/`: `connections.json` (bez haseł), `settings.json`, `keymap.json`,
`history/` (Recall Statement), `journal/`, `agent-logs/`, `run/` (gniazdo agenta), `worksets/`. Hasła — Pęk kluczy
(usługa `local.aoles.pelikan.connection`, konto = id połączenia). Testy wstrzykują katalog danych (`PELIKAN_DATA_DIR`,
`Workspace(persists: false)`) i nigdy nie dotykają prawdziwych danych.
