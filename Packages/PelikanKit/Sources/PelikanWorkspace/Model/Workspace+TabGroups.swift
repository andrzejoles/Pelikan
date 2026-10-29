import Foundation
import PelikanLog

/// Stan grup kart wybrany przez użytkownika (D200): grupy ręczne (kolejność utworzenia), przydziały okien i tryb
/// „wszystkie karty”.
public struct TabGroupState: Sendable, Hashable {
    public var manualGroups: [ManualTabGroup] = []
    public var assignments: [DocumentID: UUID] = [:]
    /// Pasek kart pokazuje karty wszystkich grup (kapsułka „Wszystkie”).
    public var showAll = false
    public init() {}
}

extension Workspace {
    // MARK: Grupy

    /// Dane wejściowe kaskady z bieżących okien, projektu, repozytoriów i połączeń.
    func tabGroupInput() -> TabGroupInput {
        var projectFiles: Set<String> = []
        if let project, let projectURL {
            for item in project.items where item.kind == .file {
                if let u = ProjectEngine.url(of: item, projectURL: projectURL) { projectFiles.insert(u.standardizedFileURL.path) }
            }
        }
        var labels: [UUID: TabGroupConnectionLabel] = [:]
        var repos: [String: RepositoryGroupInfo] = [:]
        var unknown = false
        let items = documents.map { d -> TabGroupItem in
            let files = d.fileURLs.map { $0.standardizedFileURL.path }
            for f in files {
                let dir = (f as NSString).deletingLastPathComponent
                if let r = repositoryInfo(forDirectory: dir) { repos[f] = r }
                if tabRepositories[dir] == nil, !tabRepositoryDirectories.contains(dir) { unknown = true }
            }
            let c = effectiveConnection(of: d)
            if let c, labels[c] == nil, let def = connections.connection(c) {
                labels[c] = TabGroupConnectionLabel(name: def.displayName, detail: def.environment == .other ? nil : def.environment.shortName)
            }
            return TabGroupItem(id: d.id, kind: d.kind, files: files, connection: c, manualGroup: tabGroupState.assignments[d.id])
        }
        // Katalog jeszcze niesprawdzony (nowe okno, zapis pod nową nazwą) — sprawdzenie w tle, grupy uaktualnią się same.
        if unknown { scheduleTabRepositoryRefresh(full: false) }
        return TabGroupInput(items: items, manualGroups: tabGroupState.manualGroups, projectName: project?.name,
                             projectFiles: projectFiles, repositories: repos, connections: labels)
    }

    /// Grupy kart w kolejności kapsułek (D200) z kolorami palety. Przydział kolorów i tryb histerezy uaktualniają się
    /// przy wyliczeniu (powtórne wyliczenie z tym samym stanem daje ten sam wynik).
    public var tabGroups: [TabGroup] {
        var groups = TabGrouping.groups(tabGroupInput(), mode: &tabGroupingMode)
        // Kolejność pierwszego okna — kolory przydzielane połączeniom w kolejności otwarcia.
        var keys: [String] = []
        var seen = Set<String>()
        for d in documents {
            if let c = effectiveConnection(of: d), seen.insert(TabColorPalette.connectionKey(c)).inserted { keys.append(TabColorPalette.connectionKey(c)) }
        }
        for g in groups { if let k = g.colorKey, seen.insert(k).inserted { keys.append(k) } }
        tabPalette.sync(keys)
        for i in groups.indices { groups[i].colorIndex = groups[i].colorKey.flatMap(tabPalette.index(for:)) }
        return groups
    }

    /// Kolor palety połączenia okna (tło karty); nil — okno bez połączenia (neutralne tło).
    public func paletteIndex(for doc: Document) -> Int? {
        guard let c = effectiveConnection(of: doc) else { return nil }
        if let i = tabPalette.index(for: TabColorPalette.connectionKey(c)) { return i }
        _ = tabGroups
        return tabPalette.index(for: TabColorPalette.connectionKey(c))
    }

    /// Grupa okna.
    public func tabGroup(of id: DocumentID, in groups: [TabGroup]? = nil) -> TabGroup? {
        (groups ?? tabGroups).first { $0.documents.contains(id) }
    }

    /// Bieżąca grupa: grupa aktywnego okna (okno spoza grupy aktywowane skądkolwiek przełącza grupę samo).
    public var currentTabGroup: TabGroup? {
        guard let id = activeDocumentID else { return nil }
        return tabGroup(of: id)
    }

    /// Okna na pasku kart: bieżącej grupy albo wszystkie (tryb „wszystkie karty” albo jedna grupa).
    public var visibleTabDocuments: [DocumentID] {
        if tabGroupState.showAll { return documents.map(\.id) }
        let groups = tabGroups
        guard groups.count > 1, let id = activeDocumentID, let g = tabGroup(of: id, in: groups) else { return documents.map(\.id) }
        return g.documents
    }

    /// Kolejność ⌃Tab: okna grup jedna po drugiej (kolejność kapsułek), w trybie „wszystkie karty” — kolejność okien.
    var tabCycleOrder: [DocumentID] {
        if tabGroupState.showAll { return documents.map(\.id) }
        let groups = tabGroups
        return groups.count > 1 ? groups.flatMap(\.documents) : documents.map(\.id)
    }

    /// Ostatnio używane okno z listy (kolejność aktywacji), inaczej pierwsze.
    func mostRecent(_ ids: [DocumentID]) -> DocumentID? {
        ids.max { (activationTicks[$0] ?? 0, -(ids.firstIndex(of: $0) ?? 0)) < (activationTicks[$1] ?? 0, -(ids.firstIndex(of: $1) ?? 0)) }
    }

    /// Pokazuje grupę: aktywuje jej ostatnio używane okno i wyłącza tryb „wszystkie karty”.
    @discardableResult
    public func showTabGroup(_ id: String) -> Bool {
        guard let g = tabGroups.first(where: { $0.id == id }), let doc = mostRecent(g.documents) else { return false }
        tabGroupState.showAll = false
        activate(doc)
        return true
    }

    /// Następna / poprzednia grupa (cyklicznie).
    public func cycleTabGroups(forward: Bool) {
        let groups = tabGroups
        guard groups.count > 1 else { return }
        let i = activeDocumentID.flatMap { id in groups.firstIndex { $0.documents.contains(id) } } ?? 0
        let j = (i + (forward ? 1 : groups.count - 1)) % groups.count
        showTabGroup(groups[j].id)
    }

    /// Grupa ze wskazania: identyfikator, numer od 1 albo nazwa (bez względu na wielkość liter; także „nazwa · szczegół”).
    public func tabGroup(matching spec: String) -> TabGroup? {
        let groups = tabGroups
        let s = spec.trimmingCharacters(in: .whitespaces)
        if let g = groups.first(where: { $0.id == s }) { return g }
        if let n = Int(s), groups.indices.contains(n - 1) { return groups[n - 1] }
        // „nazwa · szczegół” przed samą nazwą: dwa repozytoria o tej samej nazwie (worktree, gałęzie) są rozróżnialne.
        if let g = groups.first(where: { $0.qualifiedName.caseInsensitiveCompare(s) == .orderedSame }) { return g }
        return groups.first { $0.name.caseInsensitiveCompare(s) == .orderedSame }
    }

    /// Następne okno po zamknięciu aktywnego: z prawej w tej samej grupie, inaczej z lewej; grupa bez innych okien —
    /// ostatnio używane okno.
    func nextAfterClosing(_ id: DocumentID) -> DocumentID? {
        let groups = tabGroups
        if !tabGroupState.showAll, let g = tabGroup(of: id, in: groups), let i = g.documents.firstIndex(of: id), g.documents.count > 1 {
            return i + 1 < g.documents.count ? g.documents[i + 1] : g.documents[i - 1]
        }
        guard !tabGroupState.showAll, groups.count > 1 else { return nil }
        return mostRecent(documents.map(\.id).filter { $0 != id })
    }

    // MARK: Grupy ręczne

    /// Tworzy grupę ręczną i przenosi do niej okno.
    /// Nazwy grup ręcznych są unikalne (bez względu na wielkość liter) — wskazanie nazwą w makrach i komendach.
    public func manualTabGroupNameTaken(_ name: String, except: UUID? = nil) -> Bool {
        tabGroupState.manualGroups.contains { $0.id != except && $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    @discardableResult
    public func moveToNewTabGroup(_ doc: DocumentID, name: String) -> ManualTabGroup {
        let g = ManualTabGroup(name: name)
        tabGroupState.manualGroups.append(g)
        moveToTabGroup(doc, group: g.id)
        Log.app.info("Nowa grupa ręczna kart")
        return g
    }

    public func moveToTabGroup(_ doc: DocumentID, group: UUID) {
        guard tabGroupState.manualGroups.contains(where: { $0.id == group }) else { return }
        tabGroupState.assignments[doc] = group
        tabGroupState.showAll = false
        pruneManualTabGroups()
    }

    /// Okno wraca do kaskady automatycznych grup.
    public func removeFromManualTabGroup(_ doc: DocumentID) {
        tabGroupState.assignments[doc] = nil
        pruneManualTabGroups()
    }

    public func renameManualTabGroup(_ group: UUID, to name: String) {
        guard let i = tabGroupState.manualGroups.firstIndex(where: { $0.id == group }) else { return }
        tabGroupState.manualGroups[i].name = name
    }

    /// Rozgrupowanie: okna grupy wracają do kaskady, grupa znika.
    public func ungroupManualTabGroup(_ group: UUID) {
        tabGroupState.assignments = tabGroupState.assignments.filter { $0.value != group }
        tabGroupState.manualGroups.removeAll { $0.id == group }
    }

    func releaseTabGroupAssignment(_ doc: DocumentID) {
        guard tabGroupState.assignments[doc] != nil else { return }
        tabGroupState.assignments[doc] = nil
        pruneManualTabGroups()
    }

    /// Grupa ręczna bez okien znika (pusta kapsułka nic nie pokazuje).
    func pruneManualTabGroups() {
        let used = Set(tabGroupState.assignments.values)
        if tabGroupState.manualGroups.contains(where: { !used.contains($0.id) }) {
            tabGroupState.manualGroups.removeAll { !used.contains($0.id) }
        }
    }

    // MARK: Repozytoria

    /// Sprawdzenie repozytoriów katalogów plików okien w tle (jedno naraz, scalane). Nowe katalogi — położenie
    /// repozytorium (`git rev-parse`); znane — tylko gałąź z pliku HEAD (bez procesu gita); `full` (aktywacja aplikacji,
    /// nie częściej niż co 30 s) — także zdalne od nowa (`git remote` raz na katalog roboczy, nie na katalog pliku).
    public func scheduleTabRepositoryRefresh(full: Bool) {
        if full, lastFullRepositoryCheck.map({ Date().timeIntervalSince($0) >= 30 }) ?? true {
            tabRepositoryRefreshFull = true
        }
        guard tabRepositoryRefresh == nil, let probe = tabRepositoryProbe else { return }
        tabRepositoryRefresh = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            let dirs = self.tabRepositoryDirectoriesInUse
            // Bez okien z plikami — nic do sprawdzania (aktywacja okna bez pliku nie uruchamia zadania w tle).
            guard !dirs.isEmpty else {
                self.tabRepositoryRefresh = nil
                return
            }
            let fullRun = self.tabRepositoryRefreshFull
            self.tabRepositoryRefreshFull = false
            if fullRun { self.lastFullRepositoryCheck = Date() }
            let known = self.tabRepositories
            let checked = self.tabRepositoryDirectories
            let result = await Task.detached {
                TabRepositoryProbe.refresh(dirs: dirs, known: known, checked: checked, full: fullRun, probe: probe)
            }.value
            var repos = self.tabRepositories
            for (dir, info) in result {
                self.tabRepositoryDirectories.insert(dir)
                repos[dir] = info
            }
            if repos != self.tabRepositories {
                self.tabRepositories = repos
                Log.files.debug("Repozytoria grup kart odświeżone: \(repos.count, privacy: .public)")
            }
            self.tabRepositoryRefresh = nil
            // W trakcie sprawdzania mogły dojść okna z nowych katalogów albo prośba o pełne odświeżenie.
            let pending = self.tabRepositoryDirectoriesInUse.subtracting(self.tabRepositoryDirectories)
            if self.tabRepositoryRefreshFull || !pending.isEmpty { self.scheduleTabRepositoryRefresh(full: false) }
        }
    }

    /// Katalogi plików otwartych okien.
    var tabRepositoryDirectoriesInUse: Set<String> {
        Set(documents.flatMap { $0.fileURLs.map { ($0.standardizedFileURL.path as NSString).deletingLastPathComponent } })
    }

    /// Repozytorium katalogu: sprawdzone albo — dla katalogu jeszcze niesprawdzonego — znane repozytorium nad nim (nowy
    /// plik w znanym repozytorium trafia do grupy repozytorium od razu, bez mignięcia w grupie połączenia).
    func repositoryInfo(forDirectory dir: String) -> RepositoryGroupInfo? {
        if let r = tabRepositories[dir] { return r }
        guard !tabRepositoryDirectories.contains(dir) else { return nil }
        return tabRepositories.values.filter { dir == $0.root || dir.hasPrefix($0.root + "/") }.max { $0.root.count < $1.root.count }
    }
}

/// Sprawdzanie repozytoriów dla grup kart (D200) — wstrzykiwane (testy: zaślepka albo nil, bez procesów gita).
public struct TabRepositoryProbe: Sendable {
    /// Położenie repozytorium katalogu (katalog roboczy, nazwa, katalog gita, gałąź); bez informacji o zdalnym.
    public var locate: @Sendable (String) -> RepositoryGroupInfo?
    /// Czy repozytorium (katalog roboczy) ma zdalne.
    public var hasRemote: @Sendable (String) -> Bool
    /// Gałąź (katalog gita, katalog roboczy).
    public var branch: @Sendable (String, String) -> String?

    public init(locate: @escaping @Sendable (String) -> RepositoryGroupInfo?, hasRemote: @escaping @Sendable (String) -> Bool,
                branch: @escaping @Sendable (String, String) -> String?) {
        self.locate = locate; self.hasRemote = hasRemote; self.branch = branch
    }

    public static let git = TabRepositoryProbe(
        locate: { GitRepository.location(for: URL(fileURLWithPath: $0, isDirectory: true)) },
        hasRemote: { GitRepository.hasRemote(root: URL(fileURLWithPath: $0, isDirectory: true)) },
        branch: { GitRepository.currentBranch(gitDirectory: $0, root: $1) })

    /// Jedno odświeżenie: znane repozytoria — gałąź; `git remote` najwyżej raz na katalog roboczy (katalogi jednego
    /// repozytorium dzielą wynik), poza pełnym sprawdzeniem — ze znanych wyników.
    static func refresh(dirs: Set<String>, known: [String: RepositoryGroupInfo], checked: Set<String>, full: Bool,
                        probe: TabRepositoryProbe) -> [String: RepositoryGroupInfo?] {
        var out: [String: RepositoryGroupInfo?] = [:]
        var remotes: [String: Bool] = [:]
        if !full { for r in known.values { remotes[r.root] = r.hasRemote } }
        func remote(_ root: String) -> Bool {
            if let r = remotes[root] { return r }
            let r = probe.hasRemote(root)
            remotes[root] = r
            return r
        }
        for dir in dirs.sorted() {
            if checked.contains(dir), var r = known[dir] {
                if let g = r.gitDirectory { r.branch = probe.branch(g, r.root) }
                r.hasRemote = remote(r.root)
                out[dir] = r
                continue
            }
            // Katalog spoza repozytorium sprawdzony wcześniej — ponownie tylko przy pełnym sprawdzeniu.
            if checked.contains(dir), !full { continue }
            guard var r = probe.locate(dir) else {
                out[dir] = .some(nil)
                continue
            }
            r.hasRemote = remote(r.root)
            out[dir] = r
        }
        return out
    }
}

/// Komendy grup kart (D200): następna i poprzednia grupa, pokaż grupę, karty wszystkich grup, grupy ręczne.
enum TabGroupCommands {
    static let groupParam = CommandParameter("group", .string, L10n.tr("Grupa: nazwa, numer od 1 albo identyfikator"))

    /// Nazwa grupy ręcznej już zajęta — grupy wskazuje się nazwą (makra, agent), więc bez duplikatów.
    static func duplicate(_ name: String) -> CommandError {
        CommandError.invalidArgument("name", L10n.tr("Grupa ręczna „\(name)” już istnieje"))
    }

    @MainActor
    static func group(_ ctx: CommandContext, title: String, manualOnly: Bool = false) async throws -> TabGroup {
        let ws = ctx.workspace
        if let s = ctx.arguments.string("group") {
            guard let g = ws.tabGroup(matching: s), !manualOnly || g.kind == .manual else {
                throw CommandError.invalidArgument("group", L10n.tr("Nie ma takiej grupy kart"))
            }
            return g
        }
        let groups = ws.tabGroups.filter { !manualOnly || $0.kind == .manual }
        guard !groups.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak grup kart")) }
        guard let id = try await ctx.choose(title, groups.map { (label: $0.name + " — " + $0.caption, value: $0.id) }) else {
            throw CommandError.invalidArgument("group", L10n.tr("Podaj grupę"))
        }
        return groups.first { $0.id == id }!
    }

    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "window.nextGroup", title: L10n.tr("Następna grupa kart"), category: .window,
                                      pd: ["ctrl+cmd+]"], mac: ["ctrl+cmd+]"], agent: .full, effect: .uiState,
                                      summary: L10n.tr("Pokazuje karty następnej grupy i aktywuje jej ostatnio używane okno."), feature: "PD-UI-013"),
                    validate: { $0.tabGroups.count > 1 }) { ctx in
                ctx.workspace.cycleTabGroups(forward: true)
                return CommandResult(message: ctx.workspace.currentTabGroup?.name)
            },
            Command(CommandDescriptor(id: "window.previousGroup", title: L10n.tr("Poprzednia grupa kart"), category: .window,
                                      pd: ["ctrl+cmd+["], mac: ["ctrl+cmd+["], agent: .full, effect: .uiState,
                                      summary: L10n.tr("Pokazuje karty poprzedniej grupy i aktywuje jej ostatnio używane okno."), feature: "PD-UI-013"),
                    validate: { $0.tabGroups.count > 1 }) { ctx in
                ctx.workspace.cycleTabGroups(forward: false)
                return CommandResult(message: ctx.workspace.currentTabGroup?.name)
            },
            Command(CommandDescriptor(id: "window.showGroup", title: L10n.tr("Pokaż grupę kart…"), category: .window,
                                      parameters: [groupParam], agent: .full, effect: .uiState,
                                      summary: L10n.tr("Pokazuje karty wskazanej grupy i aktywuje jej ostatnio używane okno; bez argumentu — wybór z listy grup."),
                                      feature: "PD-UI-013"),
                    validate: { $0.tabGroups.count > 1 }) { ctx in
                let g = try await group(ctx, title: L10n.tr("Pokaż grupę kart"))
                ctx.workspace.showTabGroup(g.id)
                return CommandResult(message: g.name, value: .object(["group": .string(g.id), "windows": .int(Int64(g.documents.count))]),
                                     resolvedArguments: CommandArguments(["group": .string(g.qualifiedName)]))
            },
            Command(CommandDescriptor(id: "window.allTabs", title: L10n.tr("Karty wszystkich grup"), category: .window,
                                      parameters: [CommandParameter("visible", .boolean, L10n.tr("Pokaż karty wszystkich grup (true) albo tylko bieżącej (false); bez argumentu — przełącza"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Pasek kart pokazuje karty wszystkich grup albo tylko bieżącej grupy."), feature: "PD-UI-013"),
                    validate: { $0.tabGroups.count > 1 || $0.tabGroupState.showAll }) { ctx in
                let show = ctx.arguments.bool("visible") ?? !ctx.workspace.tabGroupState.showAll
                ctx.workspace.tabGroupState.showAll = show
                return CommandResult(value: .bool(show), resolvedArguments: CommandArguments(["visible": .bool(show)]))
            },
            Command(CommandDescriptor(id: "window.moveToGroup", title: L10n.tr("Przenieś okno do grupy…"), category: .window,
                                      parameters: [WindowListCommands.documentParam,
                                                   CommandParameter("group", .string, L10n.tr("Istniejąca grupa ręczna: nazwa albo identyfikator")),
                                                   CommandParameter("name", .string, L10n.tr("Nazwa nowej grupy ręcznej")),
                                                   CommandParameter("new", .boolean, L10n.tr("Nowa grupa — bez nazwy pyta o nią"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Przenosi okno do grupy ręcznej (istniejącej albo nowej); grupy ręczne mają pierwszeństwo przed grupami automatycznymi i są zapisywane w worksecie."),
                                      feature: "PD-UI-013"),
                    validate: { $0.activeDocument != nil }) { ctx in
                let ws = ctx.workspace
                let d = try WindowListCommands.document(ctx)
                if let name = ctx.arguments.string("name")?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                    guard !ws.manualTabGroupNameTaken(name) else { throw duplicate(name) }
                    let g = ws.moveToNewTabGroup(d.id, name: name)
                    return CommandResult(message: g.name, value: .string("manual:" + g.id.uuidString))
                }
                var target: ManualTabGroup?
                if let s = ctx.arguments.string("group") {
                    target = ws.tabGroupState.manualGroups.first {
                        $0.id.uuidString == s || "manual:" + $0.id.uuidString == s || $0.name.caseInsensitiveCompare(s) == .orderedSame
                    }
                    guard target != nil else { throw CommandError.invalidArgument("group", L10n.tr("Nie ma takiej grupy ręcznej")) }
                } else if ctx.arguments.bool("new") != true {
                    let new = UUID()
                    let options = [(label: L10n.tr("Nowa grupa…"), value: new)] + ws.tabGroupState.manualGroups.map { (label: $0.name, value: $0.id) }
                    guard let chosen = try await ctx.choose(L10n.tr("Przenieś okno do grupy"), options) else {
                        throw CommandError.invalidArgument("group", L10n.tr("Podaj grupę albo nazwę nowej grupy"))
                    }
                    if chosen == new {
                        guard let name = await ctx.ui?.askText(L10n.tr("Nowa grupa kart"), message: L10n.tr("Nazwa grupy"), defaultValue: ""),
                              !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw CommandError.cancelledByUser }
                        let n = name.trimmingCharacters(in: .whitespaces)
                        guard !ws.manualTabGroupNameTaken(n) else { throw duplicate(n) }
                        let g = ws.moveToNewTabGroup(d.id, name: n)
                        return CommandResult(message: g.name, resolvedArguments: CommandArguments(["document": .string(d.id.description), "name": .string(g.name)]))
                    }
                    target = ws.tabGroupState.manualGroups.first { $0.id == chosen }
                } else {
                    // Menu karty › Przenieś do grupy › Nowa grupa… — od razu pytanie o nazwę.
                    guard let name = await ctx.ui?.askText(L10n.tr("Nowa grupa kart"), message: L10n.tr("Nazwa grupy"), defaultValue: ""),
                          !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw CommandError.cancelledByUser }
                    let n = name.trimmingCharacters(in: .whitespaces)
                    guard !ws.manualTabGroupNameTaken(n) else { throw duplicate(n) }
                    let g = ws.moveToNewTabGroup(d.id, name: n)
                    return CommandResult(message: g.name, resolvedArguments: CommandArguments(["document": .string(d.id.description), "name": .string(g.name)]))
                }
                guard let target else { throw CommandError.cancelledByUser }
                ws.moveToTabGroup(d.id, group: target.id)
                return CommandResult(message: target.name, resolvedArguments: CommandArguments(["document": .string(d.id.description), "group": .string(target.name)]))
            },
            Command(CommandDescriptor(id: "window.removeFromGroup", title: L10n.tr("Usuń okno z grupy ręcznej"), category: .window,
                                      parameters: [WindowListCommands.documentParam], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Okno wraca do grup automatycznych (projekt, repozytorium, połączenie albo rodzaj okna)."),
                                      feature: "PD-UI-013"),
                    validate: { ws in ws.activeDocumentID.map { ws.tabGroupState.assignments[$0] != nil } ?? false }) { ctx in
                let d = try WindowListCommands.document(ctx)
                guard ctx.workspace.tabGroupState.assignments[d.id] != nil else {
                    throw CommandError.notAvailable(L10n.tr("Okno nie należy do grupy ręcznej"))
                }
                ctx.workspace.removeFromManualTabGroup(d.id)
                return .ok
            },
            Command(CommandDescriptor(id: "window.renameGroup", title: L10n.tr("Zmień nazwę grupy kart…"), category: .window,
                                      parameters: [groupParam, CommandParameter("name", .string, L10n.tr("Nowa nazwa"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zmienia nazwę grupy ręcznej."), feature: "PD-UI-013"),
                    validate: { !$0.tabGroupState.manualGroups.isEmpty }) { ctx in
                let g = try await group(ctx, title: L10n.tr("Zmień nazwę grupy kart"), manualOnly: true)
                var name = ctx.arguments.string("name")
                if name == nil {
                    guard let t = await ctx.ui?.askText(L10n.tr("Zmień nazwę grupy kart"), message: L10n.tr("Nazwa grupy"), defaultValue: g.name) else {
                        throw CommandError.cancelledByUser
                    }
                    name = t
                }
                let n = (name ?? "").trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty, let id = g.manualID else { throw CommandError.invalidArgument("name", L10n.tr("Pusta nazwa grupy")) }
                guard !ctx.workspace.manualTabGroupNameTaken(n, except: id) else { throw duplicate(n) }
                ctx.workspace.renameManualTabGroup(id, to: n)
                return CommandResult(resolvedArguments: CommandArguments(["group": .string(g.id), "name": .string(n)]))
            },
            Command(CommandDescriptor(id: "window.ungroup", title: L10n.tr("Rozgrupuj"), category: .window,
                                      parameters: [groupParam], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Usuwa grupę ręczną; jej okna wracają do grup automatycznych."), feature: "PD-UI-013"),
                    validate: { !$0.tabGroupState.manualGroups.isEmpty }) { ctx in
                let g = try await group(ctx, title: L10n.tr("Rozgrupuj"), manualOnly: true)
                if let id = g.manualID { ctx.workspace.ungroupManualTabGroup(id) }
                return CommandResult(resolvedArguments: CommandArguments(["group": .string(g.id)]))
            },
        ]
    }
}

/// Pozycja menu karty (PD-UI-004, D200): komenda z argumentami — aplikacja buduje z nich menu, test sprawdza, że każda
/// pozycja wywołuje właściwą komendę.
public struct TabMenuEntry: Sendable, Equatable {
    public var title: String
    public var command: CommandID?
    public var arguments: [String: JSONValue]
    /// Komenda działa na aktywnym oknie — najpierw aktywacja okna karty.
    public var activatesFirst: Bool
    public var submenu: [TabMenuEntry]?
    public var isSeparator: Bool { command == nil && submenu == nil }

    public static let separator = TabMenuEntry(title: "", command: nil, arguments: [:], activatesFirst: false, submenu: nil)
}

extension Workspace {
    /// Menu karty: zamykanie (okno, pozostałe, z lewej, z prawej), Przenieś do grupy › Nowa grupa… / grupy ręczne,
    /// Usuń z grupy ręcznej.
    public func tabMenuEntries(for doc: Document) -> [TabMenuEntry] {
        let d: [String: JSONValue] = ["document": .string(doc.id.description)]
        func entry(_ title: String, _ id: CommandID, _ args: [String: JSONValue] = [:], activates: Bool = false) -> TabMenuEntry {
            TabMenuEntry(title: title, command: id, arguments: args, activatesFirst: activates, submenu: nil)
        }
        var items = [entry(L10n.tr("Zamknij"), "file.closeWindow", d),
                     entry(L10n.tr("Zamknij pozostałe"), "file.closeOthers", activates: true),
                     entry(L10n.tr("Zamknij z lewej"), "file.closeLeft", activates: true),
                     entry(L10n.tr("Zamknij z prawej"), "file.closeRight", activates: true),
                     .separator]
        let assigned = tabGroupState.assignments[doc.id]
        var move = [entry(L10n.tr("Nowa grupa…"), "window.moveToGroup", d.merging(["new": .bool(true)]) { $1 })]
        let others = tabGroupState.manualGroups.filter { $0.id != assigned }
        if !others.isEmpty { move.append(.separator) }
        move += others.map { entry($0.name, "window.moveToGroup", d.merging(["group": .string($0.id.uuidString)]) { $1 }) }
        items.append(TabMenuEntry(title: L10n.tr("Przenieś do grupy"), command: nil, arguments: [:], activatesFirst: false, submenu: move))
        if assigned != nil { items.append(entry(L10n.tr("Usuń z grupy ręcznej"), "window.removeFromGroup", d)) }
        return items
    }
}
