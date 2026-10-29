import Foundation

/// File Browser (UG 22), Git (UG 17), worksety (UG 15) i układ okna (UG 23.10). Operacje na plikach i repozytorium
/// są tylko dla użytkownika (agent — Brak): ścieżki lokalne mogą ujawniać katalog domowy, a agent ma własne narzędzia.
@MainActor
enum FileCommands {
    static let pathParam = CommandParameter("path", .string, L10n.tr("Ścieżka pliku albo katalogu"))

    /// Okna pliku albo plików z wnętrza katalogu (jak przy zmianie nazwy) zostają oknami bez pliku ze zmianą do zapisu.
    static func detachDocuments(under u: URL, in ws: Workspace) {
        for d in ws.documents {
            // Okno pary (D194): dowolny z jego plików.
            guard d.fileURLs.contains(where: { $0 == u || $0.path.hasPrefix(u.path + "/") }) else { continue }
            d.fileURL = nil
            d.unitFiles = []
            d.diskStamps = [:]
            d.savedFileHash = nil
            d.isModified = true
        }
    }

    static func url(_ ctx: CommandContext, _ key: String = "path") -> URL? {
        guard let p = ctx.arguments.string(key), !p.isEmpty else { return nil }
        return URL(fileURLWithPath: (p as NSString).expandingTildeInPath).standardizedFileURL
    }

    /// Plik z argumentu albo plik aktywnego okna.
    static func fileOrActive(_ ctx: CommandContext) throws -> URL {
        if let u = url(ctx) { return u }
        // Okno pary (D194): plik karty z kursorem.
        guard let u = ctx.workspace.activeDocument?.activeFileURL else { throw CommandError.notAvailable(L10n.tr("Aktywne okno nie ma pliku")) }
        return u
    }

    static func repository(for u: URL) async throws -> GitRepository {
        guard let repo = await Task.detached(operation: { GitRepository.discover(for: u) }).value else {
            throw CommandError.notAvailable(L10n.tr("\(u.lastPathComponent) nie leży w repozytorium Git"))
        }
        return repo
    }

    static func hasActiveFile(_ ws: Workspace) -> Bool { ws.activeDocument?.fileURL != nil }

    static func isDirectory(_ u: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Ścieżka z argumentu albo — gdy wywołuje użytkownik (wstążka, paleta) — istniejący element zaznaczony w widocznym
    /// panelu Przeglądarki plików (jak obiekty biorą zaznaczenie Object Browsera).
    static func pathOrSelection(_ ctx: CommandContext) -> URL? {
        if let u = url(ctx) { return u }
        return selection(ctx)
    }

    /// Istniejący element zaznaczony w widocznym panelu Przeglądarki plików (tylko dla użytkownika).
    static func selection(_ ctx: CommandContext) -> URL? {
        guard ctx.invoker == .user, let s = ctx.workspace.fileBrowser.visibleSelection?.standardizedFileURL,
              FileManager.default.fileExists(atPath: s.path) else { return nil }
        return s
    }

    /// Katalog z argumentu `directory`, a dla użytkownika: zaznaczony katalog (albo katalog zaznaczonego pliku),
    /// katalog pokazanej lokalizacji, a bez nich — okno wyboru katalogu.
    static func directoryOrSelection(_ ctx: CommandContext) async throws -> URL {
        if let u = url(ctx, "directory") { return u }
        guard let ui = ctx.askingUI else { throw CommandError.missingArgument("directory") }
        let fb = ctx.workspace.fileBrowser
        if let s = pathOrSelection(ctx) { return isDirectory(s) ? s : s.deletingLastPathComponent() }
        if let loc = fb.locations.first(where: { $0.id == fb.visibleLocationID }), isDirectory(loc.url) { return loc.url.standardizedFileURL }
        guard let d = await ui.chooseDirectory() else { throw CommandError.cancelledByUser }
        return d.standardizedFileURL
    }

    /// Ścieżka z argumentu albo zaznaczenie; bez obu — dla użytkownika komunikat, co zaznaczyć.
    static func requiredPath(_ ctx: CommandContext) throws -> URL {
        if let u = pathOrSelection(ctx) { return u }
        if ctx.askingUI != nil { throw CommandError.notAvailable(L10n.tr("Zaznacz plik albo katalog w Przeglądarce plików")) }
        throw CommandError.missingArgument("path")
    }

    static func command(_ id: CommandID, _ title: String, _ category: CommandCategory = .file, submenu: String? = nil,
                        params: [CommandParameter] = [], pd: [String] = [], mac: [String]? = nil, effect: CommandEffect,
                        summary: String, feature: String, validate: ValidationHandler? = nil, inMenu: Bool = true,
                        _ run: @escaping CommandHandler) -> Command {
        Command(CommandDescriptor(id: id, title: title, category: category, submenu: submenu, pd: pd, mac: mac, parameters: params,
                                  agent: .none, effect: effect, summary: summary, inMenu: inMenu, feature: feature),
                validate: validate, run: run)
    }

    static var all: [Command] { fileBrowser + git + worksets + layout }

    // MARK: File Browser

    static var fileBrowser: [Command] {
        let fb = L10n.tr("Przeglądarka plików")
        return [
            command("view.fileBrowser", L10n.tr("Przeglądarka plików"), .view, effect: .uiState,
                    summary: L10n.tr("Pokazuje Przeglądarkę plików w lewej kolumnie (lokalizacje, drzewo plików, filtr, stan Git)."),
                    feature: "PD-FB-001") { ctx in
                ctx.ui?.showFileBrowser()
                return .ok
            },
            command("fb.addLocation", L10n.tr("Dodaj lokalizację…"), submenu: fb,
                    params: [pathParam, CommandParameter("name", .string, L10n.tr("Nazwa lokalizacji")),
                             CommandParameter("filter", .string, L10n.tr("Maski plików, np. *.sql;*.pck")),
                             CommandParameter("parent", .string, L10n.tr("Identyfikator lokalizacji nadrzędnej"))],
                    effect: .settings, summary: L10n.tr("Dodaje katalog do lokalizacji Przeglądarki plików (z filtrem plików i miejscem w hierarchii)."),
                    feature: "PD-FB-001") { ctx in
                var u = url(ctx)
                if u == nil { u = await ctx.ui?.chooseDirectory() }
                guard let u else { throw CommandError.cancelledByUser }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue else {
                    throw CommandError.notAvailable(L10n.tr("Katalog nie istnieje: \(u.lastPathComponent)"))
                }
                let loc = FileLocation(name: ctx.arguments.string("name") ?? u.lastPathComponent, path: u.path,
                                       filter: ctx.arguments.string("filter") ?? "", parentID: ctx.arguments.string("parent").flatMap(UUID.init(uuidString:)))
                ctx.workspace.fileBrowser.upsert(loc)
                return CommandResult(value: .string(loc.id.uuidString))
            },
            command("fb.removeLocation", L10n.tr("Usuń lokalizację"), submenu: fb,
                    params: [CommandParameter("location", .string, L10n.tr("Identyfikator lokalizacji (bez argumentu — pokazana w panelu, po potwierdzeniu)"))],
                    effect: .settings, summary: L10n.tr("Usuwa lokalizację z Przeglądarki plików (pliki zostają; lokalizacje podrzędne przechodzą wyżej)."),
                    feature: "PD-FB-001", inMenu: false) { ctx in
                let browser = ctx.workspace.fileBrowser
                var id = ctx.arguments.string("location").flatMap(UUID.init(uuidString:))
                // Ze wstążki — lokalizacja pokazana w panelu (po potwierdzeniu), a bez niej wybór z listy lokalizacji.
                if ctx.arguments.string("location") == nil, let ui = ctx.askingUI {
                    guard !browser.locations.isEmpty else { throw CommandError.notAvailable(L10n.tr("Przeglądarka plików nie ma lokalizacji")) }
                    if let loc = browser.locations.first(where: { $0.id == browser.visibleLocationID }) {
                        guard await ui.ask(L10n.tr("Usunąć lokalizację?"),
                                           message: L10n.tr("Lokalizacja „\(loc.name)” zniknie z Przeglądarki plików; pliki zostają."),
                                           buttons: [L10n.tr("Usuń lokalizację"), L10n.tr("Anuluj")]) == 0 else { throw CommandError.cancelledByUser }
                        id = loc.id
                    } else {
                        id = try await ctx.choose(L10n.tr("Usuń lokalizację"), browser.locations.map {
                            (label: "\($0.name) — \(tildePath($0.path))", value: $0.id)
                        })
                    }
                }
                guard let id else { throw CommandError.missingArgument("location") }
                browser.remove(id)
                return .ok
            },
            command("fb.open", L10n.tr("Otwórz jako…"), submenu: fb,
                    params: [CommandParameter("path", .string, L10n.tr("Ścieżka pliku (bez argumentu — plik zaznaczony w Przeglądarce plików albo wybór pliku)")),
                             CommandParameter("kind", .string, L10n.tr("Rodzaj okna (domyślnie wg rozszerzenia)"), allowed: ["sql", "program", "test", "command"])],
                    effect: .uiState, summary: L10n.tr("Otwiera plik w oknie SQL, programu, testu albo poleceń (domyślnie wg rozszerzenia)."),
                    feature: "PD-FB-001", inMenu: false) { ctx in
                // Ścieżka albo lista ścieżek (makro nagrywa pliki wybrane w oknie).
                let given = (ctx.arguments.strings("path") ?? []).filter { !$0.isEmpty }
                    .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL }
                let files: [URL]
                if !given.isEmpty {
                    files = given
                } else if let u = selection(ctx) {
                    guard !isDirectory(u) else { throw CommandError.notAvailable(L10n.tr("Zaznacz plik w Przeglądarce plików")) }
                    files = [u]
                } else {
                    // Ze wstążki bez zaznaczenia — okno wyboru plików.
                    guard let ui = ctx.askingUI else { throw CommandError.missingArgument("path") }
                    files = await ui.chooseFilesToOpen()
                    guard !files.isEmpty else { throw CommandError.cancelledByUser }
                }
                var kind = ctx.arguments.string("kind").flatMap(DocumentKind.init(rawValue:))
                // „Otwórz jako…” ze wstążki — pytanie o rodzaj okna (menu panelu podaje ścieżkę, a rodzaj w argumencie).
                if given.isEmpty, ctx.arguments.string("kind") == nil {
                    let options: [(label: String, value: DocumentKind?)] = [
                        (L10n.tr("Wg rozszerzenia pliku"), nil), (L10n.tr("Okno SQL"), .sql), (L10n.tr("Okno programu"), .program),
                        (L10n.tr("Okno testu"), .test), (L10n.tr("Okno poleceń"), .command)]
                    kind = try await ctx.choose(L10n.tr("Otwórz jako"), options) ?? nil
                }
                var title = ""
                for f in files { title = try ctx.workspace.openFile(f, as: kind).fullTitle }
                // Pliki i rodzaj okna wybrane w oknach albo z zaznaczenia — do nagrania w makrze (odtworzenie bez pytań).
                var resolved: [String: JSONValue] = [:]
                if given.isEmpty {
                    resolved["path"] = files.count == 1 ? .string(files[0].path) : .array(files.map { .string($0.path) })
                    if let kind, ctx.arguments.string("kind") == nil { resolved["kind"] = .string(kind.rawValue) }
                }
                return CommandResult(message: title).resolving(resolved)
            },
            command("fb.rename", L10n.tr("Zmień nazwę…"), submenu: fb,
                    params: [CommandParameter("path", .string, L10n.tr("Ścieżka (bez argumentu — zaznaczenie w Przeglądarce plików)")),
                             CommandParameter("name", .string, L10n.tr("Nowa nazwa"))],
                    effect: .external, summary: L10n.tr("Zmienia nazwę pliku albo katalogu; otwarte okno pliku wskazuje nową nazwę."),
                    feature: "PD-FB-001", inMenu: false) { ctx in
                let u = try requiredPath(ctx)
                var name = ctx.arguments.string("name")
                if name == nil { name = await ctx.ui?.askText(L10n.tr("Zmień nazwę"), message: u.lastPathComponent, defaultValue: u.lastPathComponent) }
                guard let name else { throw CommandError.cancelledByUser }
                let target = try FileBrowser.rename(u, to: name)
                let moved = { (f: URL) -> URL? in
                    let f = f.standardizedFileURL
                    if f == u { return target.standardizedFileURL }
                    return f.path.hasPrefix(u.path + "/") ? URL(fileURLWithPath: target.path + f.path.dropFirst(u.path.count)) : nil
                }
                for d in ctx.workspace.documents {
                    if let f = d.fileURL, let m = moved(f) { d.fileURL = m }
                    // Stan dysku pod nową ścieżką — przeniesienie przez Pelikana to nie zmiana z zewnątrz (D197).
                    for (u, s) in d.diskStamps { if let m = moved(u) { d.diskStamps[u] = nil; d.diskStamps[m.standardizedFileURL] = s } }
                    // Okno pary (D194): także plik ciała.
                    for i in d.unitFiles.indices { if let m = moved(d.unitFiles[i].url) { d.unitFiles[i].url = m } }
                }
                if ctx.workspace.fileBrowser.selectedURL?.standardizedFileURL == u { ctx.workspace.fileBrowser.selectedURL = target }
                return CommandResult(value: .string(target.path))
            },
            command("fb.newFolder", L10n.tr("Nowy katalog…"), submenu: fb,
                    params: [CommandParameter("directory", .string, L10n.tr("Katalog nadrzędny (bez argumentu — zaznaczony w Przeglądarce plików albo wybór katalogu)")),
                             CommandParameter("name", .string, L10n.tr("Nazwa"))],
                    effect: .external, summary: L10n.tr("Tworzy katalog w Przeglądarce plików."), feature: "PD-FB-001", inMenu: false) { ctx in
                let dir = try await directoryOrSelection(ctx)
                var name = ctx.arguments.string("name")
                if name == nil { name = await ctx.ui?.askText(L10n.tr("Nowy katalog"), message: dir.lastPathComponent, defaultValue: "") }
                guard let name else { throw CommandError.cancelledByUser }
                return CommandResult(value: .string(try FileBrowser.createFolder(in: dir, name: name).path))
            },
            command("fb.newFile", L10n.tr("Nowy plik…"), submenu: fb,
                    params: [CommandParameter("directory", .string, L10n.tr("Katalog (bez argumentu — zaznaczony w Przeglądarce plików albo wybór katalogu)")),
                             CommandParameter("name", .string, L10n.tr("Nazwa pliku z rozszerzeniem"))],
                    effect: .external, summary: L10n.tr("Tworzy pusty plik i otwiera go w oknie odpowiednim dla rozszerzenia."), feature: "PD-FB-001", inMenu: false) { ctx in
                let dir = try await directoryOrSelection(ctx)
                var name = ctx.arguments.string("name")
                if name == nil { name = await ctx.ui?.askText(L10n.tr("Nowy plik"), message: dir.lastPathComponent, defaultValue: "nowy.sql") }
                guard let name else { throw CommandError.cancelledByUser }
                let f = try FileBrowser.createFile(in: dir, name: name)
                try ctx.workspace.openFile(f)
                return CommandResult(value: .string(f.path))
            },
            command("fb.trash", L10n.tr("Przenieś do Kosza"), submenu: fb,
                    params: [CommandParameter("path", .string, L10n.tr("Ścieżka (bez argumentu — zaznaczenie w Przeglądarce plików)"))],
                    effect: .external, summary: L10n.tr("Przenosi plik albo katalog do Kosza (po potwierdzeniu); otwarte okno pliku zostaje jako okno bez pliku."),
                    feature: "PD-FB-001", inMenu: false) { ctx in
                let u = try requiredPath(ctx)
                let shown = tildePath(u.path)
                if url(ctx) == nil, let ui = ctx.ui {
                    // Element z zaznaczenia panelu (wstążka, paleta) — pytanie zawsze, także przy wyłączonym potwierdzeniu:
                    // użytkownik mógł nie zauważyć, co jest zaznaczone.
                    guard await ui.ask(L10n.tr("Przenieść do Kosza?"), message: shown,
                                       buttons: [L10n.tr("Przenieś do Kosza"), L10n.tr("Anuluj")]) == 0 else {
                        throw CommandError.cancelledByUser
                    }
                } else if ctx.ui != nil {
                    guard await ctx.workspace.askSuppressible(.moveToTrash, title: L10n.tr("Przenieść do Kosza?"), message: shown,
                                                              buttons: [L10n.tr("Przenieś do Kosza")]) == 0 else {
                        throw CommandError.cancelledByUser
                    }
                }
                try FileBrowser.trash(u)
                detachDocuments(under: u, in: ctx.workspace)
                if let s = ctx.workspace.fileBrowser.selectedURL?.standardizedFileURL, s == u || s.path.hasPrefix(u.path + "/") {
                    ctx.workspace.fileBrowser.selectedURL = nil
                }
                return .ok
            },
            command("fb.showInFinder", L10n.tr("Pokaż w Finderze"), submenu: fb,
                    params: [CommandParameter("path", .string, L10n.tr("Ścieżka (domyślnie plik aktywnego okna)"))],
                    effect: .external, summary: L10n.tr("Zaznacza plik w oknie Findera."), feature: "PD-FB-001",
                    validate: { hasActiveFile($0) }) { ctx in
                let u = try fileOrActive(ctx)
                #if os(macOS)
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["-R", u.path]
                try p.run()
                #endif
                return .ok
            },
            command("fb.toggleHidden", L10n.tr("Pokaż ukryte pliki"), submenu: fb, effect: .settings,
                    summary: L10n.tr("Pokazuje albo ukrywa pliki i katalogi ukryte w Przeglądarce plików."), feature: "PD-FB-001") { ctx in
                ctx.workspace.fileBrowser.showHidden.toggle()
                return .ok
            },
            command("fb.clearFilterHistory", L10n.tr("Wyczyść historię filtra"), submenu: fb, effect: .settings,
                    summary: L10n.tr("Usuwa zapamiętane maski filtra nazw Przeglądarki plików."), feature: "PD-FB-002", inMenu: false) { ctx in
                ctx.workspace.fileBrowser.clearFilterHistory()
                return .ok
            },
        ]
    }

    // MARK: Git

    static var git: [Command] {
        let sub = "Git"
        return [
            command("vcs.status", L10n.tr("Stan Git pliku"), .tools, submenu: sub, params: [pathParam], effect: .none,
                    summary: L10n.tr("Gałąź repozytorium i stan pliku (zmieniony, dodany, nieśledzony…) — domyślnie plik aktywnego okna."),
                    feature: "PD-VCS-001", validate: { hasActiveFile($0) }) { ctx in
                let u = try fileOrActive(ctx)
                let repo = try await repository(for: u)
                let status = try await Task.detached { try repo.status() }.value
                let state = status.state(of: u) ?? .unmodified
                let branch = status.branch ?? L10n.tr("(odłączony HEAD)")
                return CommandResult(message: L10n.tr("Gałąź \(branch): \(u.lastPathComponent) — \(state.displayName)"),
                                     value: .object(["branch": .string(branch), "state": .string(state.rawValue),
                                                     "ahead": .int(Int64(status.ahead)), "behind": .int(Int64(status.behind))]))
            },
            command("vcs.diff", L10n.tr("Porównaj z HEAD"), .tools, submenu: sub, params: [pathParam], effect: .uiState,
                    summary: L10n.tr("Przeglądarka różnic: wersja pliku z ostatniego zatwierdzenia (HEAD) i bieżąca (także niezapisana w oknie)."),
                    feature: "PD-VCS-001", validate: { hasActiveFile($0) }) { ctx in
                let u = try fileOrActive(ctx)
                let repo = try await repository(for: u)
                let head = try await Task.detached { try repo.headContent(of: u) }.value ?? Data()
                // Obie strony dekodowane jak przy otwieraniu pliku (BOM, ISO-8859-2/Windows-1250, kodowanie projektu — D55).
                let encoding = ctx.workspace.projectEncoding(for: u)
                let current = ctx.workspace.documents.lazy.compactMap { $0.currentText(of: u) }.first
                    ?? TextFileCodec.decode((try? Data(contentsOf: u)) ?? Data(), preferred: encoding).text
                let headText = TextFileCodec.decode(head, preferred: encoding).text
                ctx.ui?.showDiff(left: headText, right: current, leftTitle: "HEAD: \(u.lastPathComponent)", rightTitle: u.lastPathComponent)
                return CommandResult(value: .bool(headText != current))
            },
            command("vcs.add", L10n.tr("Dodaj do zatwierdzenia (git add)"), .tools, submenu: sub, params: [pathParam], effect: .external,
                    summary: L10n.tr("Dodaje plik do indeksu Git (zapisz okno wcześniej — dodawana jest zawartość pliku na dysku)."),
                    feature: "PD-VCS-001", validate: { hasActiveFile($0) }) { ctx in
                let u = try fileOrActive(ctx)
                let repo = try await repository(for: u)
                // Bez argumentu w oknie pary (D194) — oba pliki okna.
                var files = [u]
                if url(ctx) == nil, let d = ctx.workspace.activeDocument, d.unitFiles.count > 1 { files = d.fileURLs }
                try await Task.detached { [files] in try repo.add(files) }.value
                return CommandResult(message: L10n.tr("Dodano: \(files.map(\.lastPathComponent).joined(separator: ", "))"))
            },
            command("vcs.commit", L10n.tr("Zatwierdź (git commit)…"), .tools, submenu: sub,
                    params: [pathParam, CommandParameter("message", .string, L10n.tr("Komunikat zatwierdzenia"))], effect: .external,
                    summary: L10n.tr("Zatwierdza zawartość indeksu repozytorium pliku z podanym komunikatem (bez wysyłania na serwer)."),
                    feature: "PD-VCS-001", validate: { hasActiveFile($0) }) { ctx in
                let u = try fileOrActive(ctx)
                let repo = try await repository(for: u)
                var message = ctx.arguments.string("message")
                if message == nil { message = await ctx.ui?.askText(L10n.tr("Zatwierdzenie Git"), message: L10n.tr("Komunikat zatwierdzenia"), defaultValue: "") }
                guard let message else { throw CommandError.cancelledByUser }
                let hash = try await Task.detached { try repo.commit(message: message) }.value
                return CommandResult(message: L10n.tr("Zatwierdzono \(hash)"), value: .string(hash))
            },
            command("vcs.log", L10n.tr("Historia Git pliku"), .tools, submenu: sub,
                    params: [pathParam, CommandParameter("all", .boolean, L10n.tr("Historia całego repozytorium zamiast pliku"))], effect: .uiState,
                    summary: L10n.tr("Lista zatwierdzeń zmieniających plik (albo całe repozytorium): skrót, autor, data, opis."),
                    feature: "PD-VCS-001", validate: { hasActiveFile($0) }) { ctx in
                let u = try fileOrActive(ctx)
                let repo = try await repository(for: u)
                let whole = ctx.arguments.bool("all") == true
                let commits = try await Task.detached { try repo.log(limit: 200, file: whole ? nil : u) }.value
                ctx.ui?.showGitLog(commits, title: L10n.tr("Historia Git: \(whole ? repo.root.lastPathComponent : u.lastPathComponent)"))
                return CommandResult(value: .array(commits.map { .object(["hash": .string($0.hash), "author": .string($0.author), "subject": .string($0.subject)]) }))
            },
        ]
    }

    // MARK: Worksety

    static func worksetName(_ ctx: CommandContext, title: String, defaultValue: String = "") async throws -> String {
        if let n = ctx.arguments.string("name"), !n.isEmpty { return n }
        let list = ctx.workspace.worksets.names.joined(separator: ", ")
        guard let n = await ctx.ui?.askText(title, message: list.isEmpty ? L10n.tr("Nazwa workseta") : L10n.tr("Worksety: \(list)"), defaultValue: defaultValue),
              !n.trimmingCharacters(in: .whitespaces).isEmpty else { throw CommandError.cancelledByUser }
        return n.trimmingCharacters(in: .whitespaces)
    }

    static func missingMessage(_ missing: [String]) -> String? {
        missing.isEmpty ? nil : L10n.tr("Pominięto brakujące pliki: \(missing.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))")
    }

    static var worksets: [Command] {
        let sub = L10n.tr("Workset")
        let nameParam = CommandParameter("name", .string, L10n.tr("Nazwa workseta"))
        return [
            command("workset.new", L10n.tr("Nowy workset…"), submenu: sub, params: [nameParam], effect: .uiState,
                    summary: L10n.tr("Zapisuje bieżące okna do bieżącego workseta i zaczyna nowy, pusty workset."), feature: "PD-WSET-001") { ctx in
                let name = try await worksetName(ctx, title: L10n.tr("Nowy workset"))
                guard ctx.workspace.worksets.existingName(name) == nil else { throw CommandError.notAvailable(L10n.tr("Workset „\(name)” już istnieje")) }
                try await ctx.workspace.switchWorkset(to: name)
                return CommandResult(message: name)
            },
            command("workset.open", L10n.tr("Otwórz workset…"), submenu: sub, params: [nameParam], effect: .uiState,
                    summary: L10n.tr("Zapisuje bieżące okna do bieżącego workseta i otwiera okna wskazanego (także niezapisane zmiany)."), feature: "PD-WSET-001") { ctx in
                let name = try await worksetName(ctx, title: L10n.tr("Otwórz workset"))
                guard let existing = ctx.workspace.worksets.existingName(name) else { throw CommandError.notAvailable(L10n.tr("Nie ma workseta „\(name)”")) }
                let missing = try await ctx.workspace.switchWorkset(to: existing)
                return CommandResult(message: missingMessage(missing) ?? existing)
            },
            command("workset.save", L10n.tr("Zapisz workset"), submenu: sub, effect: .settings,
                    summary: L10n.tr("Zapisuje bieżące okna (z niezapisanymi zmianami) do bieżącego workseta."), feature: "PD-WSET-001") { ctx in
                try ctx.workspace.saveCurrentWorkset()
                return CommandResult(message: ctx.workspace.worksets.current)
            },
            command("workset.revert", L10n.tr("Przywróć workset"), submenu: sub, effect: .uiState,
                    summary: L10n.tr("Odrzuca zmiany okien od ostatniego zapisu workseta i przywraca zapisany stan (po potwierdzeniu)."), feature: "PD-WSET-001") { ctx in
                let ws = ctx.workspace
                guard let saved = try ws.worksets.load(ws.worksets.current) else { throw CommandError.notAvailable(L10n.tr("Workset nie był jeszcze zapisany")) }
                if ctx.ui != nil {
                    guard await ws.askSuppressible(.revertWorkset, title: L10n.tr("Przywrócić workset „\(saved.name)”?"),
                                                   message: L10n.tr("Zmiany okien od ostatniego zapisu workseta zostaną utracone."),
                                                   buttons: [L10n.tr("Przywróć")]) == 0 else { throw CommandError.cancelledByUser }
                }
                return CommandResult(message: missingMessage(try await ws.applyWorkset(saved)) ?? saved.name)
            },
            command("workset.close", L10n.tr("Zamknij workset"), submenu: sub, effect: .uiState,
                    summary: L10n.tr("Zapisuje i zamyka bieżący workset; przechodzi do workseta domyślnego."), feature: "PD-WSET-001",
                    validate: { $0.worksets.current != WorksetStore.defaultName }) { ctx in
                let missing = try await ctx.workspace.switchWorkset(to: WorksetStore.defaultName)
                return CommandResult(message: missingMessage(missing) ?? WorksetStore.defaultName)
            },
            command("workset.compare", L10n.tr("Porównaj worksety…"), submenu: sub,
                    params: [CommandParameter("name", .string, required: true, L10n.tr("Workset do porównania")),
                             CommandParameter("with", .string, L10n.tr("Drugi workset (domyślnie bieżące okna)"))], effect: .uiState,
                    summary: L10n.tr("Porównuje okna i ich treść dwóch worksetów albo zapisanego workseta z bieżącymi oknami."), feature: "PD-WSET-001") { ctx in
                let ws = ctx.workspace
                let name = try await worksetName(ctx, title: L10n.tr("Porównaj z worksetem"))
                guard let other = try ws.worksets.load(name) else { throw CommandError.notAvailable(L10n.tr("Nie ma workseta „\(name)”")) }
                let left: Workset
                if let w = ctx.arguments.string("with"), !w.isEmpty {
                    guard let l = try ws.worksets.load(w) else { throw CommandError.notAvailable(L10n.tr("Nie ma workseta „\(w)”")) }
                    left = l
                } else {
                    left = ws.worksetSnapshot(name: L10n.tr("bieżące okna"))
                }
                return CompareCommands.show(ctx, left: left.comparisonText(), right: other.comparisonText(), leftTitle: left.name, rightTitle: other.name)
            },
            command("workset.delete", L10n.tr("Usuń workset…"), submenu: sub, params: [nameParam], effect: .settings,
                    summary: L10n.tr("Usuwa zapisany workset (okna bieżącego workseta zostają otwarte)."), feature: "PD-WSET-001") { ctx in
                let name = try await worksetName(ctx, title: L10n.tr("Usuń workset"))
                try ctx.workspace.worksets.delete(name)
                return .ok
            },
        ]
    }

    // MARK: Układ okna

    static var layout: [Command] {
        [
            command("view.saveLayout", L10n.tr("Zapisz układ okna"), .view, effect: .settings,
                    summary: L10n.tr("Zapamiętuje położenie i rozmiar okna głównego, szerokość lewej kolumny, jej kartę i panel agenta."),
                    feature: "PD-WSET-002") { ctx in
                guard let l = ctx.ui?.currentLayout() else { throw CommandError.notAvailable(L10n.tr("Brak okna głównego")) }
                ctx.workspace.worksets.saveLayout(l)
                return .ok
            },
            command("view.restoreLayout", L10n.tr("Przywróć układ okna"), .view, effect: .uiState,
                    summary: L10n.tr("Przywraca zapisany układ okna głównego."), feature: "PD-WSET-002") { ctx in
                guard let l = ctx.workspace.worksets.loadLayout() else { throw CommandError.notAvailable(L10n.tr("Układ okna nie był zapisany")) }
                ctx.ui?.applyLayout(l)
                return .ok
            },
            command("view.autosaveLayout", L10n.tr("Autozapis układu okna"), .view, effect: .settings,
                    summary: L10n.tr("Włącza albo wyłącza zapisywanie układu okna przy zamykaniu i przywracanie przy starcie."),
                    feature: "PD-WSET-002") { ctx in
                ctx.workspace.settings.autosaveLayout.toggle()
                return CommandResult(value: .bool(ctx.workspace.settings.autosaveLayout))
            },
            command("workset.toggleAutosave", L10n.tr("Autozapis workseta"), submenu: L10n.tr("Workset"), effect: .settings,
                    summary: L10n.tr("Włącza albo wyłącza zapis bieżącego workseta przy zamykaniu aplikacji i jego przywrócenie przy starcie."),
                    feature: "PD-WSET-001") { ctx in
                ctx.workspace.settings.worksetAutosave.toggle()
                return CommandResult(value: .bool(ctx.workspace.settings.worksetAutosave))
            },
        ]
    }
}

/// Ścieżka z katalogiem domowym skróconym do „~” (`abbreviatingWithTildeInPath` nie ma w Foundation na Linuksie).
func tildePath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
    return "~" + path.dropFirst(home.count)
}
