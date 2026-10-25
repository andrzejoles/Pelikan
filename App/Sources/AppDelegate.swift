import AppKit
import PelikanAgent
import PelikanDB
import PelikanODPI
import PelikanProC
import PelikanRemote
import PelikanThin
import Sparkle
import PelikanSQL
import PelikanWorkspace
import SwiftUI
import WebKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, UIServices {
    let workspace: Workspace
    private var mainWindow: MainWindowController?
    private var menuBuilder: MenuBuilder?
    private var palette: CommandPalette?
    private let prompts = ConnectionPrompts()
    private var connectionCheck: Timer?
    /// Okresowy zapis konsol połączeń (DG-CONS-001) i migawki okien do odzyskiwania (PD-FILE-001).
    private var consoleSave: Timer?
    private var recoverySave: Timer?
    private var keyMonitor: Any?
    /// Aktualizacje Sparkle (kanał releases/latest/download/appcast.xml, podpis EdDSA). W kompilacji Debug wyłączone.
    #if DEBUG
    let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    #else
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    #endif
    /// Usługi macOS (MAC-SVC-001).
    private var services: ServicesProvider?
    /// Agenci AI: panel, okno zgody, serwer gniazda (PROMPT §7).
    private var agentUI: AgentUIController?
    private var menuToken: ObservationToken?
    private var appearanceToken: ObservationToken?
    /// Katalog Oracle Net zarządzany przez aplikację (D53) — także dla sterownika z katalogiem wskazanym później.
    private var oracleNetDirectory: String?

    override init() {
        // Katalog danych: ~/Library/Application Support/<nazwa>; PELIKAN_DATA_DIR nadpisuje (testy interfejsu).
        let env = ProcessInfo.processInfo.environment
        let name = Bundle.main.object(forInfoDictionaryKey: "PelikanAppName") as? String ?? "Pelikan"
        let dir = env["PELIKAN_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        // Usługa w Pęku kluczy z bundle id (nazwa marki tylko w Config/Brand.xcconfig).
        let keychainService = (Bundle.main.bundleIdentifier ?? name) + ".connection"
        workspace = Workspace(dataDirectory: dir, secrets: KeychainSecretStore(service: keychainService))
        super.init()
        // Katalog Oracle Net zarządzany przez Pelikana: portfel magazynu haseł i IFILE do konfiguracji użytkownika (D53).
        do {
            oracleNetDirectory = try OracleNet.prepareManagedDirectory(dir.appendingPathComponent("oracle-net", isDirectory: true),
                                                                       userDirectory: workspace.settings.oracleNetDirectory,
                                                                       walletDirectory: workspace.settings.walletDirectory)
        } catch {
            NSLog("Katalog Oracle Net niedostępny: %@", error.localizedDescription)
        }
        workspace.sessions.setDriver(ODPIDriver(libraryDirectory: workspace.settings.instantClientDirectory, configDirectory: oracleNetDirectory))
        workspace.sessions.setDriver(ThinDriver())
    }

    /// Diagnostyka (PELIKAN_STALL_LOG=1): przerwy głównego wątku > 100 ms w dzienniku (PD-PROG-018 — pisanie bez opóźnień).
    private var stallTimer: Timer?
    private var lastTick = Date()

    private func startStallLog() {
        guard ProcessInfo.processInfo.environment["PELIKAN_STALL_LOG"] == "1" else { return }
        lastTick = Date()
        stallTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let gap = Date().timeIntervalSince(self.lastTick)
                if gap > 0.1 { NSLog("PELIKAN_STALL %.0f ms", gap * 1000) }
                self.lastTick = Date()
            }
        }
        RunLoop.main.add(stallTimer!, forMode: .common)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        startStallLog()
        workspace.ui = self
        consoleSave = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.workspace.persistConsoles() }
        }
        workspace.sessions.prompter = prompts
        // Zadania lokalne według harmonogramu (DB-TASK-001) — tylko gdy są zdefiniowane.
        if !workspace.localTasks.definitions.isEmpty { workspace.localTasks.start(workspace) }
        let builder = MenuBuilder(workspace: workspace)
        NSApp.mainMenu = builder.build()
        menuBuilder = builder
        // Wygląd z Preferencji (jak system / jasny / ciemny).
        appearanceToken = trackChanges { [weak self] in
            guard let self else { return }
            switch self.workspace.settings.appearance {
            case .system: NSApp.appearance = nil
            case .light: NSApp.appearance = NSAppearance(named: .aqua)
            case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
        // Zmiana profilu albo własnych skrótów (Preferencje › Klawiatura) — menu z nowymi skrótami.
        menuToken = trackChanges { [weak self] in
            guard let self else { return }
            _ = self.workspace.keymap.bindings.count
            NSApp.mainMenu = self.menuBuilder?.build()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak builder] event in
            nonisolated(unsafe) let e = event   // monitor lokalny działa na wątku głównym
            let handled = MainActor.assumeIsolated { builder?.handleKeyDown(e) == true }
            return handled ? nil : event
        }
        let window = MainWindowController(workspace: workspace)
        window.showWindow(nil)
        mainWindow = window
        prompts.window = window.window
        if let agents = AgentUIController(workspace: workspace) {
            agents.mainWindow = window
            window.installAgentPane(agents.pane)
            agentUI = agents
        }
        let provider = ServicesProvider(workspace: workspace)
        NSApp.servicesProvider = provider
        services = provider
        NSUpdateDynamicServices()
        // Parametry startowe (PD-CLI-001), np. `open -a Pelikan --args connection=Dev editobject=APP.PKG`.
        let startup = StartupOptions.parse(Array(ProcessInfo.processInfo.arguments.dropFirst()))
        // Workset i układ okna z poprzedniego uruchomienia (UG 15, UG 23.10).
        if workspace.settings.worksetAutosave, !startup.noLoadDesktop, startup.workset == nil, workspace.documents.isEmpty,
           let saved = try? workspace.worksets.load(workspace.worksets.current), !saved.documents.isEmpty {
            workspace.applyWorkset(saved)
        }
        if workspace.settings.autosaveLayout, let layout = workspace.worksets.loadLayout() { window.apply(layout) }
        // Pierwsze okno SQL jak we wzorcu po zalogowaniu (bez połączenia do Etapu 1).
        if workspace.documents.isEmpty {
            workspace.perform("file.new.sql")
        }
        // Przebieg zrzutów: aplikacja jest zamykana sygnałem — bez pytania o odzyskanie okien po „awarii”.
        if Self.uiScriptURL == nil { startRecovery() }
        // Przebieg zrzutów w tle (D30): bez aktywacji aplikacji — okna nie zabierają fokusu użytkownikowi.
        if Self.uiScriptURL == nil { NSApp.activate() }
        startConnectionCheck()
        if let script = Self.uiScriptURL {
            runUIScript(script)
            return
        }
        if !startup.isEmpty || !startup.warnings.isEmpty {
            runStartup(startup)
            if startup.connection != nil { return }
        }
        // Jak we wzorcu: okno logowania przy starcie (można anulować), chyba że są połączenia „Połącz przy starcie”.
        let auto = workspace.connections.connections.filter(\.connectOnStartup)
        if let first = auto.first {
            workspace.perform("connection.connectAsMain", CommandArguments(["connection": .string(first.id.uuidString)]))
        } else {
            showLogon()
        }
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updater.checkForUpdates(sender)
    }

    @objc func showPreferences(_ sender: Any?) {
        PreferencesWindowController.show(workspace: workspace)
    }

    func customizeToolbar() {
        mainWindow?.toolbarController?.customize()
    }

    func showPreferenceSets() {
        PreferencesWindowController.show(workspace: workspace, pane: "PreferenceSetsPane")
    }

    /// Pliki otwierane z Findera, Docka albo `open -a` (typy z Info.plist) i URL schematu Pelikana (PD-CLI-001).
    func application(_ application: NSApplication, open urls: [URL]) {
        let scheme = Bundle.main.object(forInfoDictionaryKey: "PelikanURLScheme") as? String ?? ""
        var files: [URL] = []
        for url in urls {
            if !url.isFileURL, !scheme.isEmpty, url.scheme?.lowercased() == scheme.lowercased() {
                runStartup(StartupOptions.parse(url: url, scheme: scheme))
                continue
            }
            if url.isFileURL { files.append(url) }
        }
        // Katalog (upuszczony albo otwarty) — wszystkie skrypty w nim (PD-FILE-004).
        for url in FileOpening.files(from: files) {
            do { try workspace.openFile(url) } catch { showError(error.localizedDescription) }
        }
    }

    private func runStartup(_ options: StartupOptions) {
        Task { @MainActor in
            let messages = await workspace.applyStartup(options)
            if !messages.isEmpty { showError(messages.joined(separator: "\n")) }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if workspace.settings.autosaveLayout, let l = mainWindow?.layout { workspace.worksets.saveLayout(l) }
        // Autozapis workseta: niezapisane okna przetrwają w worksecie — bez pytania o zapis (UG 15).
        let worksetSaved = workspace.settings.worksetAutosave && (try? workspace.saveCurrentWorkset()) != nil
        let modified = worksetSaved ? [] : workspace.documents.filter { $0.isModified && $0.consoleConnectionID == nil && ($0.fileURL != nil || (workspace.settings.confirmSaveNewWindows && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) }
        if modified.isEmpty && !workspace.documents.contains(where: \.transactionOpen) { return .terminateNow }
        Task { @MainActor in
            NSApp.reply(toApplicationShouldTerminate: await confirmTermination(closing: modified))
        }
        return .terminateLater
    }

    /// Niezapisane okna: pytanie jak przy zamykaniu każdego okna (Zapisz / Nie zapisuj / Anuluj); potem otwarte transakcje
    /// pozostałych okien. Nieudany COMMIT/ROLLBACK pokazuje błąd i anuluje zamknięcie aplikacji.
    private func confirmTermination(closing modified: [PelikanWorkspace.Document]) async -> Bool {
        do {
            for d in modified where workspace.documents.contains(where: { $0.id == d.id }) {
                workspace.activate(d.id)
                try await workspace.invoke("file.close")
            }
        } catch CommandError.cancelledByUser {
            return false
        } catch {
            showError(error.localizedDescription)
            return false
        }
        let open = workspace.documents.filter(\.transactionOpen)
        guard !open.isEmpty else { return true }
        let answer = await ask(L10n.tr("Niezatwierdzone zmiany"),
                               message: L10n.tr("Okna z otwartą transakcją: \(open.map(\.fullTitle).joined(separator: ", ")). Co zrobić przed zamknięciem?"),
                               buttons: [L10n.tr("Zatwierdź (COMMIT)"), L10n.tr("Wycofaj (ROLLBACK)")])
        guard let answer else { return false }
        do {
            try await workspace.endTransactions(of: open, commit: answer == 0)
        } catch {
            showError(error.localizedDescription)
            return false
        }
        await workspace.sessions.disconnectAll()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Procesy ssh tuneli i połączenia główne celów Pro*C kończą się razem z aplikacją.
    func applicationWillTerminate(_ notification: Notification) {
        workspace.persistConsoles()
        // Czyste zamknięcie: bez migawki do odzyskania (PD-FILE-001).
        workspace.recovery.end()
        agentUI?.stop()
        workspace.sessions.tunnels.closeAll()
        procDeployModel?.disconnectAll()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Powrót do Pelikana: okna edytowane programem zewnętrznym dostają nową treść (PD-EDIT-028).
    func applicationDidBecomeActive(_ notification: Notification) {
        workspace.checkExternalEdits()
    }

    /// Odzyskiwanie po awarii (PD-FILE-001): okna z poprzedniego, nieczysto zakończonego uruchomienia i okresowa migawka.
    private func startRecovery() {
        if let previous = workspace.recovery.begin() {
            workspace.pendingRecovery = previous
            Task { @MainActor in
                let answer = await workspace.askSuppressible(.restoreRecovery, title: L10n.tr("Pelikan nie został poprawnie zamknięty"),
                                                             message: L10n.tr("Odzyskać okna z niezapisanymi zmianami (\(previous.documents.count))?"),
                                                             buttons: [L10n.tr("Odzyskaj"), L10n.tr("Odrzuć")])
                if answer == 0 {
                    workspace.perform("file.restoreRecovery")
                } else if answer == 1 {
                    workspace.pendingRecovery = nil
                    workspace.recovery.discardPrevious()
                }
            }
        }
        scheduleRecoverySave()
    }

    private func scheduleRecoverySave() {
        recoverySave?.invalidate()
        let interval = TimeInterval(max(15, workspace.settings.recoveryIntervalSeconds))
        recoverySave = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.workspace.saveRecoverySnapshot()
                if TimeInterval(max(15, self.workspace.settings.recoveryIntervalSeconds)) != interval { self.scheduleRecoverySave() }
            }
        }
    }

    // MARK: UIServices

    func showCompletion(_ result: CompletionResult, for document: PelikanWorkspace.Document) {
        NotificationCenter.default.post(name: CodeEditorView.showCompletionNotification, object: document, userInfo: ["result": result])
    }

    func showFindObjects(_ criteria: DatabaseSearchCriteria) {
        ToolWindowController.show(key: "findObjects", title: L10n.tr("Znajdź obiekty bazy"), size: NSSize(width: 760, height: 520)) {
            FindObjectsView(workspace: workspace, criteria: criteria)
        }
    }

    func showObjectBrowser() {
        mainWindow?.sidebarController.select(pane: SidebarViewController.objectBrowserPane)
    }

    func showFileBrowser() {
        mainWindow?.sidebarController.select(pane: SidebarViewController.fileBrowserPane)
    }

    func chooseDirectory() async -> URL? {
        if Self.scriptSkipsDialog("chooseDirectory") { return nil }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard let window = mainWindow?.window else { return panel.runModal() == .OK ? panel.url : nil }
        return await panel.beginSheetModal(for: window) == .OK ? panel.url : nil
    }

    /// Cele SSH zdalnego builda Pro*C: plik w katalogu danych bez sekretów, sekrety w Pęku kluczy (`<bundle id>.ssh`).
    private lazy var sshTargets: SSHTargetManagerModel = {
        let bundle = Bundle.main.bundleIdentifier ?? (Bundle.main.object(forInfoDictionaryKey: "PelikanAppName") as? String ?? "Pelikan")
        let dir = workspace.dataDirectory
        let store = SSHTargetStore(fileURL: dir?.appendingPathComponent(SSHTargetStore.fileName),
                                   secrets: KeychainSecretStore(service: SSHTargetStore.keychainService(bundleIdentifier: bundle)))
        let preferred = (dir ?? FileManager.default.temporaryDirectory).appendingPathComponent("run", isDirectory: true)
        let run = (try? SocketDirectory.make(preferred: preferred)) ?? FileManager.default.temporaryDirectory
        return SSHTargetManagerModel(store: store, workspace: workspace, runDirectory: run)
    }()

    /// Wdrożenia Pro*C (konsola, historia) na celach z menedżera celów SSH.
    private var procDeployModel: ProCDeployModel?
    private var procDeploy: ProCDeployModel {
        if let procDeployModel { return procDeployModel }
        let model = ProCDeployModel(store: sshTargets.store, workspace: workspace, runDirectory: sshTargets.runDirectory)
        procDeployModel = model
        return model
    }

    func showProCDeploy(_ action: ProCDeployAction) {
        let model = procDeploy
        switch action {
        case .deploy(let name): ProCDeployWindows.showStart(model, target: name)
        case .rollback(let name): ProCDeployWindows.showRollback(model, target: name)
        case .history: ProCDeployWindows.showHistory(model)
        case .console: ProCDeployWindows.showConsole(model)
        case .stop: model.center.selected?.stop()
        case .gitStatus: ProCDeployWindows.showGitStatus(model)
        case .releaseLock(let name):
            guard let t = model.target(named: name) ?? model.center.selected?.target ?? model.store.targets.first else { return }
            Task {
                if let m = await model.releaseLock(t, info: model.center.selected?.target.id == t.id ? model.center.selected?.progress.lockInfo ?? [] : []) {
                    let a = NSAlert()
                    a.messageText = m
                    a.runModal()
                }
            }
        }
    }

    func showSSHTargets(_ action: SSHTargetAction) {
        let model = sshTargets
        switch action {
        case .manage, .test:
            ToolWindowController.show(key: "sshTargets", title: L10n.tr("Cele SSH"), size: NSSize(width: 900, height: 640)) {
                SSHTargetManagerView(model: model)
            }
            if case .test(let name) = action {
                if let name { model.select(name: name) }
                Task { await model.test() }
            }
        case .export:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = SSHTargetStore.fileName
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do { try model.store.exportData().write(to: url, options: .atomic) } catch { NSAlert(error: error).runModal() }
        case .import:
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do { try model.store.importData(Data(contentsOf: url)) } catch { NSAlert(error: error).runModal() }
        }
    }

    func currentLayout() -> WindowLayout? { mainWindow?.layout }

    func applyLayout(_ layout: WindowLayout) { mainWindow?.apply(layout) }

    func showDiff(left: String, right: String, leftTitle: String, rightTitle: String) {
        showDiff(left: left, right: right, leftTitle: leftTitle, rightTitle: rightTitle, reload: nil)
    }

    func showDiff(left: String, right: String, leftTitle: String, rightTitle: String, reload: DiffReload?) {
        ToolWindowController.show(key: "diff-\(UUID().uuidString)", title: L10n.tr("Różnice: \(leftTitle) ↔ \(rightTitle)"),
                                  size: NSSize(width: 1100, height: 680)) {
            DiffViewer(left: left, right: right, leftTitle: leftTitle, rightTitle: rightTitle, reload: reload)
        }
    }

    func showTemplateWindow() {
        ToolWindowController.show(key: "templates", title: L10n.tr("Szablony"), size: NSSize(width: 320, height: 560)) {
            TemplatePane(workspace: workspace)
        }
    }

    func showSearchBar() {
        ToolWindowController.show(key: "searchBar", title: L10n.tr("Szukaj w edytorach i plikach"), size: NSSize(width: 760, height: 480)) {
            SearchBarView(workspace: workspace)
        }
    }

    func showUsages(title: String, hits: [UsageHit]) {
        ToolWindowController.close(key: "usages")
        ToolWindowController.show(key: "usages", title: L10n.tr("Użycia: \(title)"), size: NSSize(width: 820, height: 420)) {
            UsagesView(workspace: workspace, title: title, hits: hits)
        }
    }

    func showSearchResults(query: String, hits: [UsageHit]) {
        ToolWindowController.close(key: "usages")
        ToolWindowController.show(key: "usages", title: L10n.tr("Wyniki wyszukiwania „\(query)”"), size: NSSize(width: 820, height: 420)) {
            UsagesView(workspace: workspace, title: query, hits: hits,
                       summary: hits.isEmpty ? L10n.tr("Brak wyników „\(query)”") : L10n.tr("Trafień „\(query)”: \(hits.count)"))
        }
    }

    func confirmRefactoring(_ plan: RefactoringPlan) async -> Bool {
        guard let window = mainWindow?.window else { return false }
        return await withCheckedContinuation { cont in
            var sheet: NSWindow?
            var finished = false
            let view = RefactoringPreviewView(plan: plan) { apply in
                guard !finished else { return }
                finished = true
                if let sheet { window.endSheet(sheet) }
                sheet = nil  // zrywa cykl okno → widok → domknięcie → okno
                cont.resume(returning: apply)
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            sheet = w
            window.beginSheet(w)
        }
    }

    func showLocalHistory(document: PelikanWorkspace.Document) {
        ToolWindowController.close(key: "localHistory")
        ToolWindowController.show(key: "localHistory", title: L10n.tr("Historia lokalna — \(document.title)"), size: NSSize(width: 820, height: 480)) {
            LocalHistoryView(workspace: workspace, document: document)
        }
    }

    func showProblems(document: PelikanWorkspace.Document) {
        ToolWindowController.close(key: "problems")
        ToolWindowController.show(key: "problems", title: L10n.tr("Problemy — \(document.title)"), size: NSSize(width: 640, height: 320)) {
            ProblemsView(workspace: workspace, document: document)
        }
    }

    func showTableEditor(_ definition: TableDefinition, original: TableDefinition?, connectionID: UUID) {
        let title = original == nil ? L10n.tr("Nowa tabela") : L10n.tr("Tabela \(definition.owner).\(definition.name)")
        ToolWindowController.show(key: "table-\(definition.owner).\(original?.name ?? UUID().uuidString)", title: title,
                                  size: NSSize(width: 980, height: 560)) {
            TableEditorView(workspace: workspace, connectionID: connectionID, definition: definition, original: original)
        }
    }

    func showObjectEditor(_ editor: SimpleObjectEditor, connectionID: UUID) {
        let name = editor.original?["name"]
        let title = name.map { "\(editor.title) \($0)" } ?? L10n.tr("Nowy obiekt: \(editor.title.lowercased())")
        ToolWindowController.show(key: "table-\(editor.kind.rawValue)-\(name ?? UUID().uuidString)", title: title, size: NSSize(width: 780, height: 460)) {
            SimpleObjectEditorView(workspace: workspace, connectionID: connectionID, editor: editor)
        }
    }

    func showDebugger(_ debugger: DebuggerEngine, document: PelikanWorkspace.Document) {
        ToolWindowController.show(key: "debugger-\(document.id)", title: L10n.tr("Debuger — \(document.title)"), size: NSSize(width: 640, height: 380)) {
            DebuggerPanel(workspace: workspace, debugger: debugger, document: document)
        }
        // Fokus zostaje w oknie głównym — kroki skrótami (⌃N, ⌃O, ⌃T, ⌃R) jak w edytorze.
        mainWindow?.window?.makeKeyAndOrderFront(nil)
    }

    func showBreakpoints() {
        ToolWindowController.show(key: "breakpoints", title: L10n.tr("Punkty przerwania"), size: NSSize(width: 640, height: 360)) {
            BreakpointsView(workspace: workspace)
        }
    }

    func showMacroLibrary() {
        ToolWindowController.show(key: "macroLibrary", title: L10n.tr("Biblioteka makr"), size: NSSize(width: 480, height: 420)) {
            MacroLibraryView(workspace: workspace)
        }
    }

    func showClipboardHistory() {
        ToolWindowController.show(key: "clipboardHistory", title: L10n.tr("Historia schowka"), size: NSSize(width: 520, height: 520)) {
            ClipboardHistoryView(workspace: workspace)
        }
    }

    func showTodoItems() {
        ToolWindowController.show(key: "todoItems", title: L10n.tr("Zadania To-Do"), size: NSSize(width: 640, height: 420)) {
            TodoItemsView(workspace: workspace)
        }
    }

    func clipboardText() -> String? { NSPasteboard.general.string(forType: .string) }

    func exportDiagram(_ doc: PelikanWorkspace.Document, format: String) {
        DiagramOutput.export(doc, format: format, workspace: workspace)
    }

    func copyDiagramImage(_ doc: PelikanWorkspace.Document) {
        DiagramOutput.copy(doc)
    }

    func printDiagram(_ doc: PelikanWorkspace.Document) {
        DiagramOutput.print(doc)
    }

    func showQueryBuilder(sql: String?, connectionID: UUID?) {
        let target = workspace.activeDocument.flatMap { [.sql, .program, .test].contains($0.kind) ? $0.id : nil }
        ToolWindowController.close(key: "queryBuilder")
        ToolWindowController.show(key: "queryBuilder", title: L10n.tr("Query Builder"), size: NSSize(width: 1000, height: 720)) {
            QueryBuilderView(workspace: workspace, connectionID: connectionID, targetDocument: target, initialSQL: sql)
        }
    }

    func showStage7Tool(_ tool: Stage7Tool) { Stage7ToolWindows.show(tool, workspace: workspace) }

    func showDataTransfer(_ tool: DataTransferTool) {
        switch tool {
        case .exportTables:
            ToolWindowController.show(key: "exportTables", title: L10n.tr("Eksport tabel"), size: NSSize(width: 760, height: 600)) { ExportTablesView(workspace: workspace) }
        case .importTables:
            ToolWindowController.show(key: "importTables", title: L10n.tr("Import tabel"), size: NSSize(width: 720, height: 560)) { ImportTablesView(workspace: workspace) }
        case .textImporter:
            ToolWindowController.show(key: "textImporter", title: L10n.tr("Import tekstu"), size: NSSize(width: 900, height: 680)) { ImporterView(workspace: workspace, excel: false) }
        case .excelImporter:
            ToolWindowController.show(key: "excelImporter", title: L10n.tr("Import z Excela"), size: NSSize(width: 900, height: 680)) { ImporterView(workspace: workspace, excel: true) }
        case .dataGenerator:
            ToolWindowController.show(key: "dataGenerator", title: L10n.tr("Generator danych"), size: NSSize(width: 900, height: 640)) { DataGeneratorView(workspace: workspace) }
        case .compareTableData:
            ToolWindowController.show(key: "compareTableData", title: L10n.tr("Porównanie danych tabel"), size: NSSize(width: 900, height: 580)) { CompareTableDataView(workspace: workspace) }
        }
    }

    func showExportObjects() {
        ToolWindowController.show(key: "exportObjects", title: L10n.tr("Eksport obiektów użytkownika"), size: NSSize(width: 680, height: 620)) {
            ExportObjectsView(workspace: workspace)
        }
    }

    func showCompareObjects() {
        ToolWindowController.show(key: "compareObjects", title: L10n.tr("Porównanie obiektów użytkowników"), size: NSSize(width: 980, height: 620)) {
            CompareObjectsView(workspace: workspace)
        }
    }

    func showScheduler() {
        ToolWindowController.show(key: "scheduler", title: L10n.tr("DBMS Scheduler"), size: NSSize(width: 1000, height: 640)) {
            SchedulerView(workspace: workspace)
        }
    }

    func showGraph(document: PelikanWorkspace.Document, tab: ResultTab) {
        // Każdy wykres w osobnym oknie (kilka wykresów z różnych wyników naraz).
        ToolWindowController.show(key: "graph-\(tab.id.uuidString)", title: L10n.tr("Wykres – \(tab.title)"), size: NSSize(width: 980, height: 600)) {
            GraphView(workspace: workspace, document: document, tab: tab)
        }
    }

    func showToolOutput(title: String, text: String, status: Int32) {
        ToolWindowController.close(key: "toolOutput")
        ToolWindowController.show(key: "toolOutput", title: title, size: NSSize(width: 640, height: 400)) {
            ToolOutputView(text: text, status: status)
        }
    }

    func showUserToolsSettings() {
        ToolWindowController.show(key: "userTools", title: L10n.tr("Narzędzia użytkownika"), size: NSSize(width: 760, height: 480)) {
            UserToolsView(workspace: workspace)
        }
    }

    func showSessionBrowser() {
        ToolWindowController.show(key: "sessions", title: L10n.tr("Sesje"), size: NSSize(width: 1000, height: 640)) {
            SessionBrowserView(workspace: workspace)
        }
    }

    func showGridTool(_ request: GridToolRequest) {
        switch request {
        case let .linkedQueries(links, values, connection):
            ToolWindowController.close(key: "linkedQueries")
            ToolWindowController.show(key: "linkedQueries", title: L10n.tr("Zapytania powiązane"), size: NSSize(width: 520, height: 360)) {
                LinkedQueriesView(workspace: workspace, links: links, values: values, connection: connection)
            }
        case let .compareRecords(comparison):
            ToolWindowController.close(key: "compareRecords")
            ToolWindowController.show(key: "compareRecords", title: L10n.tr("Porównanie rekordów"), size: NSSize(width: 700, height: 440)) {
                CompareRecordsView(comparison: comparison)
            }
        case let .compareResults(left, right):
            ToolWindowController.close(key: "compareResults")
            ToolWindowController.show(key: "compareResults", title: L10n.tr("Porównanie wyników"), size: NSSize(width: 1000, height: 540)) {
                CompareResultsView(left: left, right: right)
            }
        case let .columnToFiles(tab):
            ToolWindowController.close(key: "columnToFiles")
            ToolWindowController.show(key: "columnToFiles", title: L10n.tr("Kolumna do plików"), size: NSSize(width: 540, height: 200)) {
                ColumnToFilesView(tab: tab)
            }
        case let .groupCounts(tab, column, counts):
            ToolWindowController.close(key: "groupCounts")
            ToolWindowController.show(key: "groupCounts", title: L10n.tr("Grupowanie"), size: NSSize(width: 420, height: 420)) {
                GroupCountsView(workspace: workspace, tab: tab, column: column, counts: counts)
            }
        }
    }

    func showSnippets() {
        ToolWindowController.show(key: "snippets", title: L10n.tr("Snippety"), size: NSSize(width: 420, height: 520)) {
            SnippetsView(workspace: workspace)
        }
    }

    func showEventMonitor() {
        ToolWindowController.show(key: "eventMonitor", title: L10n.tr("Monitor zdarzeń"), size: NSSize(width: 680, height: 420)) {
            EventMonitorView(workspace: workspace)
        }
    }

    func showLoadTester() {
        ToolWindowController.show(key: "loadTester", title: L10n.tr("Test obciążenia"), size: NSSize(width: 980, height: 620)) {
            LoadTesterView(workspace: workspace)
        }
    }

    func showProject() {
        ToolWindowController.show(key: "project", title: L10n.tr("Projekt"), size: NSSize(width: 640, height: 640)) {
            ProjectView(workspace: workspace)
        }
    }

    func showAutotrace(_ result: AutotraceResult, sql: String) {
        ToolWindowController.close(key: "autotrace")
        ToolWindowController.show(key: "autotrace", title: L10n.tr("Autotrace"), size: NSSize(width: 960, height: 560)) {
            AutotraceView(result: result, sql: sql)
        }
    }

    func showPlanComparison(_ comparison: PlanComparison, leftTitle: String, rightTitle: String) {
        ToolWindowController.close(key: "planCompare")
        ToolWindowController.show(key: "planCompare", title: L10n.tr("Porównanie planów"), size: NSSize(width: 1000, height: 520)) {
            PlanComparisonView(comparison: comparison, leftTitle: leftTitle, rightTitle: rightTitle)
        }
    }

    func showDBAPanel() {
        ToolWindowController.show(key: "dba", title: L10n.tr("Panel DBA"), size: NSSize(width: 1040, height: 640)) {
            DBAPanelView(workspace: workspace)
        }
    }

    func showInstanceViewer() {
        ToolWindowController.show(key: "instanceViewer", title: L10n.tr("Instance Viewer"), size: NSSize(width: 960, height: 660)) {
            InstanceViewerView(workspace: workspace)
        }
    }

    func showTaskMonitor() {
        ToolWindowController.show(key: "taskMonitor", title: L10n.tr("Zadania w tle"), size: NSSize(width: 760, height: 380)) {
            TaskMonitorView(workspace: workspace)
        }
    }

    func showSchemaDoc() {
        ToolWindowController.show(key: "schemaDoc", title: L10n.tr("Dokumentacja schematu"), size: NSSize(width: 560, height: 220)) {
            SchemaDocView(workspace: workspace)
        }
    }

    func showHTMLReport(title: String, html: String) {
        let key = "html-" + UUID().uuidString
        ToolWindowController.show(key: key, title: title, size: NSSize(width: 960, height: 680)) { HTMLReportView(title: title, html: html) }
    }

    func showDualityViews() {
        ToolWindowController.show(key: "dualityViews", title: L10n.tr("Widoki dualności JSON"), size: NSSize(width: 860, height: 520)) { DualityViewsView(workspace: workspace) }
    }

    func showMLEModules() {
        ToolWindowController.show(key: "mleModules", title: L10n.tr("Moduły i środowiska MLE"), size: NSSize(width: 680, height: 420)) { MLEModulesView(workspace: workspace) }
    }

    func showSpatialPreview(title: String, wkt: [String]) {
        ToolWindowController.show(key: "spatial-" + UUID().uuidString, title: L10n.tr("Podgląd przestrzenny: \(title)"), size: NSSize(width: 640, height: 520)) { SpatialPreviewView(wkt: wkt) }
    }

    func showUserManual() {
        ToolWindowController.show(key: "userManual", title: L10n.tr("Instrukcja Pelikana"), size: NSSize(width: 900, height: 640)) { UserManualView(workspace: workspace) }
    }

    /// Druk okna (PD-SQLW-016): HTML z `PrintLayout` jako tekst sformatowany, podział na strony przez NSTextView.
    func printHTML(title: String, html: String) {
        guard let text = NSAttributedString(html: Data(html.utf8), documentAttributes: nil) else { return }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        view.textStorage?.setAttributedString(text)
        view.isVerticallyResizable = true
        view.sizeToFit()
        let op = NSPrintOperation(view: view, printInfo: info)
        op.jobTitle = title
        if let window = mainWindow?.window {
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            op.run()
        }
    }

    /// Koniec długiego wykonania (PD-SQLW-015): dźwięk, a gdy Pelikan jest w tle — podskok ikony w Docku.
    func notifyExecutionFinished(title: String, elapsed: String, success: Bool) {
        NSSound(named: success ? "Glass" : "Basso")?.play()
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
    }

    func showQueryByExample(_ tab: ResultTab) {
        ToolWindowController.show(key: "qbe", title: L10n.tr("Query By Example"), size: NSSize(width: 480, height: 420)) {
            QueryByExampleView(workspace: workspace, tab: tab) { ToolWindowController.close(key: "qbe") }
        }
    }

    func showColumnFilter(_ tab: ResultTab) {
        ToolWindowController.show(key: "columnFilter", title: L10n.tr("Filtr kolumn"), size: NSSize(width: 500, height: 300)) {
            ColumnFilterView(workspace: workspace, tab: tab) { ToolWindowController.close(key: "columnFilter") }
        }
    }

    /// Lista wartości kolumny (PD-GRID-022): wybór w okienku z listą rozwijaną.
    func chooseValue(_ title: String, values: [String]) async -> String? {
        if Self.scriptSkipsDialog(title) { return nil }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = L10n.tr("Wybierz wartość")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        popup.addItems(withTitles: values)
        alert.accessoryView = popup
        alert.addButton(withTitle: L10n.tr("Wybierz"))
        alert.addButton(withTitle: L10n.tr("Anuluj"))
        return alert.runModal() == .alertFirstButtonReturn ? popup.titleOfSelectedItem : nil
    }

    /// Kalendarz przy edycji daty (PD-GRID-005): graficzny wybór dnia, z czasem — pole godziny.
    func chooseDate(_ title: String, initial: OracleTimestamp?, withTime: Bool) async -> OracleTimestamp? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let start = initial.flatMap { t in
            cal.date(from: DateComponents(year: Int(t.year), month: Int(t.month), day: Int(t.day), hour: Int(t.hour), minute: Int(t.minute),
                                          second: Int(t.second)))
        } ?? Date()
        let picker = NSDatePicker()
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = .yearMonthDay
        picker.timeZone = cal.timeZone
        picker.calendar = cal
        picker.dateValue = start
        picker.sizeToFit()
        let time = NSDatePicker()
        time.datePickerStyle = .textFieldAndStepper
        time.datePickerElements = .hourMinuteSecond
        time.timeZone = cal.timeZone
        time.calendar = cal
        time.dateValue = start
        time.sizeToFit()
        let stack = NSStackView(views: withTime ? [picker, time] : [picker])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: max(picker.frame.width, 200), height: picker.frame.height + (withTime ? time.frame.height + 8 : 0))
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = L10n.tr("Wybierz datę")
        alert.accessoryView = stack
        alert.addButton(withTitle: L10n.tr("Wybierz"))
        alert.addButton(withTitle: L10n.tr("Anuluj"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let d = cal.dateComponents([.year, .month, .day], from: picker.dateValue)
        let h = cal.dateComponents([.hour, .minute, .second], from: time.dateValue)
        return OracleTimestamp(year: Int16(d.year ?? 2000), month: UInt8(d.month ?? 1), day: UInt8(d.day ?? 1),
                               hour: UInt8(withTime ? h.hour ?? 0 : 0), minute: UInt8(withTime ? h.minute ?? 0 : 0),
                               second: UInt8(withTime ? h.second ?? 0 : 0))
    }

    /// Edytor szablonu (PD-TPL-003): folder (lista albo nowy), nazwa i tekst ze składnią szablonów.
    func editTemplate(_ template: CodeTemplate, folders: [String]) async -> CodeTemplate? {
        let folder = NSComboBox(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        folder.addItems(withObjectValues: folders)
        folder.stringValue = template.folder
        folder.setAccessibilityLabel(L10n.tr("Folder szablonu"))
        let name = NSTextField(string: template.name)
        name.placeholderString = L10n.tr("Nazwa szablonu")
        name.setAccessibilityLabel(L10n.tr("Nazwa szablonu"))
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 260))
        text.string = template.text
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isRichText = false
        text.setAccessibilityLabel(L10n.tr("Tekst szablonu"))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 260))
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let hint = NSTextField(wrappingLabelWithString: L10n.tr("Zmienne: [Nazwa], [Nazwa=domyślna], lista [Nazwa=*a,b,c]; kursor: [#]; nawias dosłownie: [[; wbudowane: $OSUSER $DBUSER $DATE $TIME."))
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        let row = NSStackView(views: [folder, name])
        let stack = NSStackView(views: [row, scroll, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 520, height: 330)
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalToConstant: 520), scroll.heightAnchor.constraint(equalToConstant: 260),
                                     name.widthAnchor.constraint(equalToConstant: 250), hint.widthAnchor.constraint(equalToConstant: 520)])
        let alert = NSAlert()
        alert.messageText = template.name.isEmpty ? L10n.tr("Nowy szablon") : L10n.tr("Edytuj szablon")
        alert.accessoryView = stack
        alert.addButton(withTitle: L10n.tr("Zapisz"))
        alert.addButton(withTitle: L10n.tr("Anuluj"))
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return CodeTemplate(folder: folder.stringValue.trimmingCharacters(in: .whitespaces), name: name.stringValue.trimmingCharacters(in: .whitespaces),
                            text: text.string)
    }

    func showSQLMonitor() {
        ToolWindowController.show(key: "sqlMonitor", title: L10n.tr("SQL Monitor"), size: NSSize(width: 940, height: 480)) { SQLMonitorView(workspace: workspace) }
    }

    func showTestManager() {
        ToolWindowController.show(key: "testManager", title: L10n.tr("Test Manager"), size: NSSize(width: 900, height: 600)) {
            TestManagerView(workspace: workspace)
        }
    }

    func showTestExplorer() {
        ToolWindowController.show(key: "testExplorer", title: L10n.tr("Eksplorator testów"), size: NSSize(width: 460, height: 560)) {
            TestExplorerView(workspace: workspace)
        }
    }

    func showUtplsqlResults(_ run: UtplsqlRun) {
        // Jedno okno wyników — nowy przebieg zastępuje zawartość.
        ToolWindowController.close(key: "utplsql")
        ToolWindowController.show(key: "utplsql", title: L10n.tr("Wyniki utPLSQL"), size: NSSize(width: 900, height: 560)) {
            UtplsqlResultsView(workspace: workspace, run: run)
        }
    }

    func showCompileInvalid() {
        ToolWindowController.show(key: "compileInvalid", title: L10n.tr("Kompiluj niepoprawne obiekty"), size: NSSize(width: 680, height: 460)) {
            CompileInvalidView(workspace: workspace)
        }
    }

    func showError(_ message: String) {
        if Self.scriptSkipsDialog(message) { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("Nie udało się wykonać polecenia")
        alert.informativeText = message
        if let window = mainWindow?.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    func showCommandPalette() {
        if palette == nil { palette = CommandPalette(workspace: workspace) }
        palette?.show(relativeTo: mainWindow?.window)
    }

    /// Sprawdzanie połączeń co n s (UG 23.1 „Check connection”); utracone — komunikat o wycofanej transakcji.
    private func startConnectionCheck() {
        let interval = TimeInterval(max(15, workspace.settings.checkConnectionIntervalSeconds))
        connectionCheck = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Bezczynne sesje okien bez transakcji (Preferencje › Oracle, PD-CONN-026).
                await self.workspace.sessions.closeIdleSessions(olderThan: self.workspace.settings.closeIdleSessionsMinutes)
                // Okna programu: obiekty zmienione w bazie przez innych od wczytania (PD-PROG-011) — ostrzeżenie na pasku stanu.
                await self.workspace.checkProgramWindowChanges()
                let lost = await self.workspace.sessions.checkConnections()
                guard !lost.isEmpty else { return }
                let names = Set(lost.compactMap { self.workspace.connections.connection($0.connectionID)?.displayName })
                for d in self.workspace.documents where d.transactionOpen && lost.contains(where: { $0.connectionID == self.workspace.effectiveConnection(of: d) }) {
                    d.transactionOpen = false
                }
                self.showError(L10n.tr("Połączenie utracone: \(names.sorted().joined(separator: ", ")). Niezatwierdzone zmiany zostały wycofane przez serwer. Kolejne polecenie połączy się ponownie."))
            }
        }
    }

    func showConnectionEditor(connectionID: UUID?) {
        ConnectionEditorPresenter.present(workspace: workspace, connectionID: connectionID, in: mainWindow?.window)
    }

    func showLogon() {
        guard let window = mainWindow?.window else { return }
        var sheet: NSWindow?
        let view = LogonView(workspace: workspace) { [weak self] in
            if let sheet { window.endSheet(sheet) }
            sheet = nil  // zrywa cykl okno → widok → domknięcie → okno
            self?.mainWindow?.documentArea.focusActiveDocument()
        }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet = w
        window.beginSheet(w)
    }

    func askVariables(_ requests: [VariableRequest], document: PelikanWorkspace.Document) async -> [String: VariableValue]? {
        if Self.scriptSkipsDialog("askVariables") { return nil }
        return await presentVariables(requests, document: document, title: L10n.tr("Zmienne"), submit: L10n.tr("Wykonaj"), legend: true)
    }

    func askTemplateValues(_ requests: [VariableRequest], document: PelikanWorkspace.Document) async -> [String: VariableValue]? {
        if Self.scriptSkipsDialog("askTemplateValues") { return nil }
        return await presentVariables(requests, document: document, title: L10n.tr("Zmienne szablonu"), submit: L10n.tr("Wstaw"), legend: false)
    }

    private func presentVariables(_ requests: [VariableRequest], document: PelikanWorkspace.Document, title: String, submit: String,
                                  legend: Bool) async -> [String: VariableValue]? {
        guard let window = mainWindow?.window else { return nil }
        let model = VariablesModel(requests: requests, workspace: workspace, document: document)
        return await withCheckedContinuation { cont in
            var sheet: NSWindow?
            var finished = false
            let view = VariablesView(model: model, title: title, submitTitle: submit, showLegend: legend) { values in
                guard !finished else { return }
                finished = true
                if let sheet { window.endSheet(sheet) }
                sheet = nil  // zrywa cykl okno → widok → domknięcie → okno
                self.mainWindow?.documentArea.focusActiveDocument()
                cont.resume(returning: values)
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            sheet = w
            window.beginSheet(w)
        }
    }

    func printHTML(_ html: String, title: String) {
        _ = HTMLPrinter(html: html, title: title)
    }

    func copyToClipboard(_ text: String, html: String?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        if let html { pb.setString(html, forType: .html) }
        workspace.recordClipboard(text)
    }

    func saveFile(suggestedName: String, fileExtension: String, data: Data) async -> Bool {
        if Self.scriptSkipsDialog("saveFile") { return false }
        guard let window = mainWindow?.window else { return false }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName.replacingOccurrences(of: "/", with: "-") + "." + fileExtension
        panel.allowedContentTypes = [UTType(filenameExtension: fileExtension) ?? .data]
        panel.canCreateDirectories = true
        let response = await panel.beginSheetModal(for: window)
        guard response == .OK, let url = panel.url else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    func askText(_ title: String, message: String, defaultValue: String) async -> String? {
        if Self.scriptSkipsDialog(title) { return nil }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.tr("OK"))
        alert.addButton(withTitle: L10n.tr("Anuluj"))
        alert.window.initialFirstResponder = field
        guard let window = mainWindow?.window else { return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil }
        let r = await alert.beginSheetModal(for: window)
        mainWindow?.documentArea.focusActiveDocument()
        return r == .alertFirstButtonReturn ? field.stringValue : nil
    }

    private var findPanel: NSPanel?
    func showFindReplace() {
        if findPanel == nil {
            let p = NSPanel(contentViewController: NSHostingController(rootView: FindReplaceView(model: FindReplaceModel(workspace: workspace))))
            p.title = L10n.tr("Znajdź i zamień")
            p.styleMask = [.titled, .closable, .utilityWindow, .nonactivatingPanel]
            p.isFloatingPanel = true
            p.hidesOnDeactivate = true
            if let f = mainWindow?.window?.frame { p.setFrameTopLeftPoint(NSPoint(x: f.maxX - 600, y: f.maxY - 80)) }
            findPanel = p
        }
        findPanel?.makeKeyAndOrderFront(nil)
    }

    func showObjectInfo(title: String, columns: [String], rows: [[String]]) {
        ObjectInfoWindowController.show(title: title, columns: columns, rows: rows)
    }

    /// Ekran pomocy przy braku Instant Client (PD-CONN-029): pobranie od Oracle, wskazanie katalogu, sterownik thin.
    func showClientMissingHelp(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = L10n.tr("Brak Oracle Instant Client")
        alert.informativeText = message + "\n\n" + L10n.tr("Licencja Oracle nie pozwala dołączyć Instant Client do Pelikana. Bez niego możesz użyć sterownika „thin” (Definicja połączenia › Ogólne › Sterownik) — z ograniczeniami: bez TCPS/wallet, Kerberos i przerwania wykonania.")
        alert.addButton(withTitle: L10n.tr("Wskaż katalog…"))
        alert.addButton(withTitle: L10n.tr("Otwórz stronę Oracle"))
        alert.addButton(withTitle: L10n.tr("Zamknij"))
        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard let self else { return }
            switch r {
            case .alertFirstButtonReturn:
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.message = L10n.tr("Wybierz katalog z biblioteką libclntsh.dylib")
                if panel.runModal() == .OK, let url = panel.url {
                    self.workspace.settings.instantClientDirectory = url.path
                    self.workspace.sessions.setDriver(ODPIDriver(libraryDirectory: url.path, configDirectory: self.oracleNetDirectory))
                    if case .failure(let e) = ODPIDriver(libraryDirectory: url.path).availability() { self.showError(e.localizedDescription) }
                }
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(URL(string: "https://www.oracle.com/database/technologies/instant-client/macos-arm64-downloads.html")!)
            default: break
            }
        }
        if let window = mainWindow?.window, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    func showRecallStatement() {
        guard let window = mainWindow?.window else { return }
        var sheet: NSWindow?
        let view = RecallStatementView(workspace: workspace) { [weak self] in
            if let sheet { window.endSheet(sheet) }
            sheet = nil  // zrywa cykl okno → widok → domknięcie → okno
            self?.mainWindow?.documentArea.focusActiveDocument()
        }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet = w
        window.beginSheet(w)
    }

    /// Klucz katalogu startowego dla rodzaju okna (PD-PREF-006).
    static func startDirectoryKey(_ kind: DocumentKind?) -> String {
        switch kind {
        case .program: "program"
        case .test: "test"
        case .report: "report"
        default: "sql"
        }
    }

    /// Skrypt przebiegu zrzutów (tylko kompilacja Debug): JSON [{"command": id, "args": {…}, "delay": s}], wykonywany
    /// po starcie zamiast okna logowania; na końcu plik `PELIKAN_UI_SCRIPT.done`. Bez klawiszy, kliknięć i aktywacji.
    static var uiScriptURL: URL? {
        #if DEBUG
        ProcessInfo.processInfo.environment["PELIKAN_UI_SCRIPT"].map { URL(fileURLWithPath: $0) }
        #else
        nil
        #endif
    }

    /// Tryb skryptu zrzutów: okna dialogowe nie są pokazywane (mogłyby aktywować aplikację w trakcie pracy właściciela,
    /// D30) — pytanie trafia do dziennika skryptu i jest traktowane jak „Anuluj”.
    static func scriptSkipsDialog(_ what: String) -> Bool {
        guard let script = uiScriptURL else { return false }
        let line = "\(ISO8601DateFormatter().string(from: Date())) pominięto okno dialogowe: \(what)\n"
        if let h = FileHandle(forWritingAtPath: script.path + ".log") {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        }
        return true
    }

    private func runUIScript(_ url: URL) {
        struct Step: Decodable { var command: String; var args: [String: PelikanWorkspace.JSONValue]?; var delay: Double? }
        let steps = (try? JSONDecoder().decode([Step].self, from: Data(contentsOf: url))) ?? []
        let logURL = url.appendingPathExtension("log")
        func log(_ s: String) {
            let line = Data((ISO8601DateFormatter().string(from: Date()) + " " + s + "\n").utf8)
            if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line); try? h.close() } else { try? line.write(to: logURL) }
        }
        log("start: kroki \(steps.count), okna \(workspace.documents.count)")
        Task { @MainActor in
            // Połączenie „przy starcie” (portfel bazy testowej) przed krokami skryptu.
            if let first = workspace.connections.connections.first(where: \.connectOnStartup) {
                log("łączenie \(first.displayName)")
                do { _ = try await workspace.invoke("connection.connectAsMain", CommandArguments(["connection": .string(first.id.uuidString)])); log("połączono") }
                catch { log("połączenie: \(error.localizedDescription)") }
            }
            for s in steps {
                // Zaznaczenie w aktywnym oknie (kursor dla wyróżnień, zakres dla „Oznacz kolorem”) — bez klawiszy i myszy.
                if s.command == "debug.select", let doc = workspace.activeDocument {
                    let from = s.args?["from"].flatMap { if case .int(let v) = $0 { Int(v) } else { nil } } ?? 0
                    let to = s.args?["to"].flatMap { if case .int(let v) = $0 { Int(v) } else { nil } } ?? from
                    doc.selectedRange = from..<max(from, to)
                    // Dodatkowe kursory / zaznaczenie kolumnowe: "extra": [[od, do], …].
                    if case .array(let list)? = s.args?["extra"] {
                        doc.additionalSelections = list.compactMap { item -> Range<Int>? in
                            guard case .array(let p) = item, p.count == 2, case .int(let a) = p[0], case .int(let b) = p[1] else { return nil }
                            return Int(a)..<Int(max(a, b))
                        }
                    }
                    log("ok debug.select \(from)..<\(to)")
                    try? await Task.sleep(for: .seconds(s.delay ?? 1))
                    continue
                }
                // Otwarcie pliku (np. notatnika z wykresem) bez panelu wyboru.
                if s.command == "debug.openFile", case .string(let path)? = s.args?["path"] {
                    do { _ = try workspace.openFile(URL(fileURLWithPath: path)); log("ok debug.openFile") }
                    catch { log("debug.openFile: \(error.localizedDescription)") }
                    try? await Task.sleep(for: .seconds(s.delay ?? 1))
                    continue
                }
                // Okno preferencji na wskazanym panelu (np. "BrowserPane").
                if s.command == "debug.preferences" {
                    let pane = s.args?["pane"].flatMap { if case .string(let v) = $0 { v } else { nil } }
                    PreferencesWindowController.show(workspace: workspace, pane: pane)
                    log("ok debug.preferences")
                    try? await Task.sleep(for: .seconds(s.delay ?? 1))
                    continue
                }
                // Okno zgody z prawdziwym podglądem skutków komendy agenta — w osobnym oknie w tle (bez arkusza,
                // panelu agenta i podskakującej ikony w Docku).
                if s.command == "debug.approval", case .string(let id)? = s.args?["command"] {
                    let args = CommandArguments(s.args?["args"].flatMap { if case .object(let o) = $0 { o } else { nil } } ?? [:])
                    do {
                        let cmd = CommandID(rawValue: id)
                        let preview = try await workspace.preview(cmd, args, invoker: .agent(sessionID: "debug", agentName: "Claude"))
                        let request = ApprovalRequest(sessionID: "debug", agentName: "Claude", command: cmd,
                                                      title: workspace.registry.command(cmd)?.descriptor.title ?? id, preview: preview, arguments: args,
                                                      connection: (try? workspace.agentConnection(alias: nil))?.agentAlias)
                        ToolWindowController.show(key: "approval", title: L10n.tr("Zgoda na operację agenta"), size: NSSize(width: 640, height: 480)) {
                            ApprovalView(request: request) { _ in ToolWindowController.close(key: "approval") }
                        }
                        log("ok debug.approval")
                    } catch { log("debug.approval: \(error.localizedDescription)") }
                    try? await Task.sleep(for: .seconds(s.delay ?? 1))
                    continue
                }
                // Widok planu wykonania otwieranego w następnych krokach: 0 drzewo, 1 diagram, 2 flame graph, 3 tekst.
                if s.command == "debug.planMode", case .int(let m)? = s.args?["mode"] {
                    PlanPanel.initialMode = Int(m)
                    log("ok debug.planMode")
                    continue
                }
                // Zrzut treści WKWebView w procesie (WebKit nie rysuje okien w tle w `screencapture`).
                if s.command == "debug.snapshotWebViews", case .string(let dir)? = s.args?["directory"] {
                    await snapshotWebViews(into: URL(fileURLWithPath: dir))
                    log("ok snapshotWebViews")
                    continue
                }
                do {
                    let r = try await workspace.invoke(CommandID(rawValue: s.command), CommandArguments(s.args ?? [:]))
                    log("ok \(s.command)" + (r.message.map { ": \($0)" } ?? ""))
                }
                catch { log("\(s.command): \(error.localizedDescription)") }
                try? await Task.sleep(for: .seconds(s.delay ?? 1))
            }
            try? Data().write(to: url.appendingPathExtension("done"))
        }
    }

    private func snapshotWebViews(into dir: URL) async {
        func webViews(_ v: NSView) -> [WKWebView] { (v as? WKWebView).map { [$0] } ?? v.subviews.flatMap(webViews) }
        var i = 0
        for w in NSApp.windows where w.isVisible {
            for wv in webViews(w.contentView ?? NSView()) {
                guard let image = try? await wv.takeSnapshot(configuration: nil), let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                i += 1
                try? png.write(to: dir.appendingPathComponent("web-\(w.title.replacingOccurrences(of: "/", with: "-"))-\(i).png"))
            }
        }
    }

    func chooseFilesToOpen() async -> [URL] {
        if Self.scriptSkipsDialog("chooseFilesToOpen") { return [] }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = ["sql", "pck", "pks", "pkb", "spc", "bdy", "fnc", "prc", "trg", "typ", "tps", "tpb", "tst", "txt"]
            .compactMap { UTType(filenameExtension: $0) }
        panel.allowsOtherFileTypes = true
        panel.directoryURL = workspace.startDirectory(for: Self.startDirectoryKey(workspace.activeDocument?.kind))
        guard let window = mainWindow?.window else { return panel.runModal() == .OK ? panel.urls : [] }
        return await panel.beginSheetModal(for: window) == .OK ? panel.urls : []
    }

    func chooseSaveURL(suggestedName: String, fileExtension: String) async -> URL? {
        if Self.scriptSkipsDialog("chooseSaveURL") { return nil }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName.replacingOccurrences(of: "/", with: "-") + "." + fileExtension
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.directoryURL = workspace.startDirectory(for: Self.startDirectoryKey(workspace.activeDocument?.kind))
        guard let window = mainWindow?.window else { return panel.runModal() == .OK ? panel.url : nil }
        return await panel.beginSheetModal(for: window) == .OK ? panel.url : nil
    }

    func showLargeDataEditor(_ model: LargeDataModel) {
        LargeDataEditorController.show(model, workspace: workspace, relativeTo: mainWindow?.window)
    }

    func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Plik w wskazanej aplikacji (nazwa, ścieżka `.app` albo identyfikator pakietu) albo w skojarzonej.
    func openInApplication(_ file: URL, application: String?) {
        guard let name = application, let app = Self.applicationURL(name) else {
            if let application { showError(L10n.tr("Nie znaleziono aplikacji „\(application)” — plik otwarty programem skojarzonym")) }
            NSWorkspace.shared.open(file)
            return
        }
        NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static func applicationURL(_ name: String) -> URL? {
        let n = (name as NSString).expandingTildeInPath
        if n.hasSuffix(".app"), FileManager.default.fileExists(atPath: n) { return URL(fileURLWithPath: n) }
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: n) { return u }
        let file = n.hasSuffix(".app") ? (n as NSString).lastPathComponent : n + ".app"
        for dir in ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications", "/Applications/Utilities"] {
            let p = (dir as NSString).appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        }
        return nil
    }

    func askWithSuppression(_ title: String, message: String, buttons: [String]) async -> (Int?, Bool) {
        if Self.scriptSkipsDialog(title) { return (nil, false) }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for b in buttons { alert.addButton(withTitle: b) }
        alert.addButton(withTitle: L10n.tr("Anuluj"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L10n.tr("Nie pytaj więcej")
        let response = alert.runModal()
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return (index < buttons.count ? index : nil, alert.suppressionButton?.state == .on)
    }

    func ask(_ title: String, message: String, buttons: [String]) async -> Int? {
        if Self.scriptSkipsDialog(title) { return nil }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for b in buttons { alert.addButton(withTitle: b) }
        // Wywołujący często sami podają „Anuluj” (wtedy zwracany jest jego indeks) — bez drugiego takiego przycisku.
        let cancel = L10n.tr("Anuluj")
        if !buttons.contains(cancel) { alert.addButton(withTitle: cancel) }
        let response = alert.runModal()
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return index < buttons.count ? index : nil
    }
}
