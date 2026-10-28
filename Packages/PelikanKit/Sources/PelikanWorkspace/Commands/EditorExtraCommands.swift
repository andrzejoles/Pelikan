import Foundation
import PelikanSQL

/// Komendy edytora z Etapu 8 (audyt): zakładki, znaczniki kolorów, wiele kursorów, podział edytora, rozmiar czcionki,
/// tylko do odczytu, otwarcie z połączeniem, refaktoryzacje, wyszukiwanie w edytorach i plikach.
@MainActor
enum EditorExtraCommands {
    static func editor(_ ws: Workspace) -> Document? { BuiltinCommands.editable(ws) }

    static func command(_ id: String, _ title: String, _ category: CommandCategory = .edit, submenu: String? = nil, pd: [String] = [], mac: [String]? = nil,
                        params: [CommandParameter] = [], agent: AgentAccess = .none, effect: CommandEffect = .uiState, summary: String, feature: String,
                        validate: (@MainActor (Workspace) -> Bool)? = nil, _ handler: @escaping CommandHandler) -> Command {
        Command(CommandDescriptor(id: CommandID(rawValue: id), title: title, category: category, submenu: submenu, pd: pd, mac: mac, parameters: params,
                                  agent: agent, effect: effect, summary: summary, feature: feature),
                validate: validate ?? { editor($0) != nil }, run: handler)
    }

    static func lineOf(_ offset: Int, in text: String) -> Int {
        (text as NSString).substring(to: min(offset, (text as NSString).length)).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    static func go(_ doc: Document, to offset: Int) {
        doc.selectedRange = offset..<offset
    }

    static var all: [Command] {
        let bm = L10n.tr("Zakładki")
        let colors = L10n.tr("Znaczniki kolorów")
        let refactor = L10n.tr("Refaktoryzacja")
        return [
            // MARK: Zakładki (PD-EDIT-011)
            command("edit.toggleBookmark", L10n.tr("Przełącz zakładkę"), submenu: bm, mac: ["cmd+f3"],
                    params: [CommandParameter("number", .integer, L10n.tr("Numer 0–9 (domyślnie pierwszy wolny)"))],
                    summary: L10n.tr("Ustawia albo usuwa zakładkę na linii kursora (Ctrl+K n — zakładka n)."), feature: "PD-EDIT-011") { ctx in
                guard let doc = editor(ctx.workspace) else { return .ok }
                let n = ctx.arguments.int("number").map { Int($0) }
                if let n, !(0...9).contains(n) { throw CommandError.invalidArgument("number", String(n)) }
                doc.bookmarks = Bookmarks.toggle(doc.bookmarks, number: n, at: doc.selectedRange.lowerBound, in: doc.text)
                return CommandResult(value: .array(doc.bookmarks.map { .int(Int64($0.number)) }))
            },
            command("edit.gotoBookmark", L10n.tr("Przejdź do zakładki"), submenu: bm,
                    params: [CommandParameter("number", .integer, required: true, L10n.tr("Numer 0–9"))],
                    summary: L10n.tr("Przenosi kursor do zakładki o numerze (Ctrl+Q n)."), feature: "PD-EDIT-011",
                    validate: { editor($0).map { !$0.bookmarks.isEmpty } ?? false }) { ctx in
                guard let doc = editor(ctx.workspace) else { return .ok }
                let n = Int(ctx.arguments.int("number") ?? -1)
                guard let b = doc.bookmarks.first(where: { $0.number == n }) else { throw CommandError.notAvailable(L10n.tr("Nie ma zakładki \(n)")) }
                go(doc, to: b.offset)
                return .ok
            },
            command("edit.nextBookmark", L10n.tr("Następna zakładka"), submenu: bm, mac: ["cmd+alt+f3"],
                    summary: L10n.tr("Przenosi kursor do następnej zakładki w oknie."), feature: "PD-EDIT-011",
                    validate: { editor($0).map { !$0.bookmarks.isEmpty } ?? false }) { ctx in
                guard let doc = editor(ctx.workspace), let b = Bookmarks.next(doc.bookmarks, from: doc.selectedRange.lowerBound, forward: true) else { return .ok }
                go(doc, to: b.offset)
                return .ok
            },
            command("edit.previousBookmark", L10n.tr("Poprzednia zakładka"), submenu: bm, mac: ["cmd+alt+shift+f3"],
                    summary: L10n.tr("Przenosi kursor do poprzedniej zakładki w oknie."), feature: "PD-EDIT-011",
                    validate: { editor($0).map { !$0.bookmarks.isEmpty } ?? false }) { ctx in
                guard let doc = editor(ctx.workspace), let b = Bookmarks.next(doc.bookmarks, from: doc.selectedRange.lowerBound, forward: false) else { return .ok }
                go(doc, to: b.offset)
                return .ok
            },
            command("edit.renameBookmark", L10n.tr("Nazwij zakładkę…"), submenu: bm,
                    params: [CommandParameter("number", .integer, required: true, L10n.tr("Numer 0–9")), CommandParameter("name", .string, L10n.tr("Nazwa"))],
                    summary: L10n.tr("Nadaje zakładce nazwę widoczną na liście zakładek."), feature: "PD-EDIT-011",
                    validate: { editor($0).map { !$0.bookmarks.isEmpty } ?? false }) { ctx in
                guard let doc = editor(ctx.workspace) else { return .ok }
                let n = Int(ctx.arguments.int("number") ?? -1)
                guard let i = doc.bookmarks.firstIndex(where: { $0.number == n }) else { throw CommandError.notAvailable(L10n.tr("Nie ma zakładki \(n)")) }
                var name = ctx.arguments.string("name")
                if name == nil, let ui = ctx.ui { name = await ui.askText(L10n.tr("Nazwa zakładki"), message: L10n.tr("Zakładka \(n)"), defaultValue: doc.bookmarks[i].name ?? "") }
                guard let name else { throw CommandError.cancelledByUser }
                doc.bookmarks[i].name = name.isEmpty ? nil : name
                return .ok
            },
            command("edit.bookmarkList", L10n.tr("Lista zakładek"), submenu: bm,
                    summary: L10n.tr("Zakładki wszystkich okien z numerem, nazwą i linią; wybór przenosi do zakładki."), feature: "PD-EDIT-011",
                    validate: { ws in ws.documents.contains { !$0.bookmarks.isEmpty } }) { ctx in
                let ws = ctx.workspace
                let entries = ws.documents.flatMap { d in d.bookmarks.map { (d, $0) } }
                let hits = entries.map { d, b in
                    UsageHit(kind: .document, owner: nil, name: d.title, type: nil, line: lineOf(b.offset, in: d.text),
                             text: "[\(b.number)] " + (b.name ?? ""), fileURL: nil, document: d.id, title: d.title)
                }
                ctx.ui?.showUsages(title: L10n.tr("Zakładki"), hits: hits)
                return CommandResult(value: .array(entries.map { d, b in
                    .object(["window": .string(d.title), "number": .int(Int64(b.number)), "line": .int(Int64(lineOf(b.offset, in: d.text))), "name": .string(b.name ?? "")])
                }))
            },
            command("edit.clearBookmarks", L10n.tr("Usuń zakładki okna"), submenu: bm,
                    summary: L10n.tr("Usuwa wszystkie zakładki aktywnego okna."), feature: "PD-EDIT-011",
                    validate: { editor($0).map { !$0.bookmarks.isEmpty } ?? false }) { ctx in
                editor(ctx.workspace)?.bookmarks = []
                return .ok
            },
            // MARK: Znaczniki kolorów (PD-EDIT-012)
            command("edit.colorMark", L10n.tr("Oznacz kolorem"), submenu: colors,
                    params: [CommandParameter("color", .integer, L10n.tr("Kolor 1–6 (0 — usuń znacznik z zaznaczenia)"))],
                    summary: L10n.tr("Wyróżnia zaznaczony fragment tłem w wybranym kolorze."), feature: "PD-EDIT-012",
                    validate: { editor($0).map { !$0.selectedRange.isEmpty } ?? false }) { ctx in
                guard let doc = editor(ctx.workspace) else { return .ok }
                let c = Int(ctx.arguments.int("color") ?? 1)
                guard (0...6).contains(c) else { throw CommandError.invalidArgument("color", String(c)) }
                doc.colorMarks = ColorMarks.apply(doc.colorMarks, range: doc.selectedRange, color: c)
                return .ok
            },
            command("edit.clearColorMarks", L10n.tr("Usuń znaczniki kolorów"), submenu: colors,
                    summary: L10n.tr("Usuwa wszystkie znaczniki kolorów aktywnego okna."), feature: "PD-EDIT-012",
                    validate: { editor($0).map { !$0.colorMarks.isEmpty } ?? false }) { ctx in
                editor(ctx.workspace)?.colorMarks = []
                return .ok
            },
            // MARK: Wiele kursorów (PD-EDIT-023)
            command("edit.addCursorAbove", L10n.tr("Dodaj kursor powyżej"), submenu: L10n.tr("Wiele kursorów"), pd: ["ctrl+shift+up"], mac: ["ctrl+shift+up"],
                    summary: L10n.tr("Dodaje kursor w linii powyżej (w tej samej kolumnie); pisanie trafia do wszystkich kursorów."), feature: "PD-EDIT-023") { ctx in
                guard let doc = editor(ctx.workspace) else { return .ok }
                let all = MultiCursor.addCursor(in: doc.text, ranges: [doc.selectedRange] + doc.additionalSelections, below: false)
                doc.selectedRange = all.first ?? doc.selectedRange
                doc.additionalSelections = Array(all.dropFirst())
                return .ok
            },
            command("edit.addCursorBelow", L10n.tr("Dodaj kursor poniżej"), submenu: L10n.tr("Wiele kursorów"), pd: ["ctrl+shift+down"], mac: ["ctrl+shift+down"],
                    summary: L10n.tr("Dodaje kursor w linii poniżej (w tej samej kolumnie); pisanie trafia do wszystkich kursorów."), feature: "PD-EDIT-023") { ctx in
                guard let doc = editor(ctx.workspace) else { return .ok }
                let all = MultiCursor.addCursor(in: doc.text, ranges: [doc.selectedRange] + doc.additionalSelections, below: true)
                doc.selectedRange = all.first ?? doc.selectedRange
                doc.additionalSelections = Array(all.dropFirst())
                return .ok
            },
            command("edit.singleCursor", L10n.tr("Jeden kursor"), submenu: L10n.tr("Wiele kursorów"),
                    summary: L10n.tr("Usuwa dodatkowe kursory i zaznaczenia."), feature: "PD-EDIT-023",
                    validate: { editor($0).map { !$0.additionalSelections.isEmpty } ?? false }) { ctx in
                editor(ctx.workspace)?.additionalSelections = []
                return .ok
            },
            // MARK: Podział edytora (PD-EDIT-014), rozmiar czcionki (PD-EDIT-021), tylko do odczytu (PD-FILE-003)
            command("view.splitEditor", L10n.tr("Podziel edytor"), .view,
                    summary: L10n.tr("Pokazuje albo ukrywa drugi widok tego samego tekstu pod edytorem."), feature: "PD-EDIT-014") { ctx in
                guard let doc = editor(ctx.workspace) else { return .ok }
                doc.splitEditor.toggle()
                return CommandResult(value: .bool(doc.splitEditor))
            },
            command("view.zoomIn", L10n.tr("Powiększ czcionkę edytora"), .view, pd: ["ctrl+="], mac: ["cmd+="],
                    effect: .settings, summary: L10n.tr("Zwiększa rozmiar czcionki edytorów."), feature: "PD-EDIT-021", validate: { _ in true }) { ctx in
                ctx.workspace.settings.editorFontSize = EditorZoom.next(ctx.workspace.settings.editorFontSize, step: 1)
                return CommandResult(value: .double(ctx.workspace.settings.editorFontSize))
            },
            command("view.zoomOut", L10n.tr("Pomniejsz czcionkę edytora"), .view, pd: ["ctrl+shift+-"], mac: ["cmd+-"],
                    effect: .settings, summary: L10n.tr("Zmniejsza rozmiar czcionki edytorów."), feature: "PD-EDIT-021", validate: { _ in true }) { ctx in
                ctx.workspace.settings.editorFontSize = EditorZoom.next(ctx.workspace.settings.editorFontSize, step: -1)
                return CommandResult(value: .double(ctx.workspace.settings.editorFontSize))
            },
            command("view.zoomReset", L10n.tr("Domyślny rozmiar czcionki edytora"), .view, pd: ["ctrl+0"], mac: ["cmd+0"],
                    effect: .settings, summary: L10n.tr("Przywraca domyślny rozmiar czcionki edytorów (13 pt)."), feature: "PD-EDIT-021", validate: { _ in true }) { ctx in
                ctx.workspace.settings.editorFontSize = EditorZoom.next(ctx.workspace.settings.editorFontSize, step: 0)
                return .ok
            },
            command("file.readOnly", L10n.tr("Tylko do odczytu"), .file,
                    summary: L10n.tr("Przełącza okno w tryb tylko do odczytu (tekst nie może być zmieniany w edytorze)."), feature: "PD-FILE-003") { ctx in
                guard let doc = editor(ctx.workspace) else { return .ok }
                doc.isReadOnly.toggle()
                return CommandResult(value: .bool(doc.isReadOnly))
            },
            // MARK: Otwarcie pliku z połączeniem (PD-FILE-004)
            command("file.openWithConnection", L10n.tr("Otwórz z połączeniem…"), .file,
                    params: [CommandParameter("path", .string, L10n.tr("Plik albo katalog (bez argumentu — wybór plików)")),
                             CommandParameter("connection", .string, L10n.tr("Nazwa połączenia okna (bez argumentu — wybór z listy)"))],
                    effect: .uiState, summary: L10n.tr("Otwiera plik (z katalogu — wszystkie skrypty) i przypina do okien wskazane połączenie."),
                    feature: "PD-FILE-004", validate: { _ in true }) { ctx in
                let ws = ctx.workspace
                // Ścieżka albo lista ścieżek (makro nagrywa pliki wybrane w oknie).
                var sources = ctx.arguments.strings("path")?.filter { !$0.isEmpty }.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                if sources?.isEmpty == true { sources = nil }
                var name = ctx.arguments.string("connection")
                var resolved: [String: JSONValue] = [:]
                // Ze wstążki bez argumentów — wybór plików, potem połączenia z listy.
                if let ui = ctx.askingUI, sources == nil || name == nil {
                    let defs = ws.connections.connections.sorted(by: ConnectionStore.alphabetical)
                    guard !defs.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak zdefiniowanych połączeń")) }
                    if sources == nil {
                        let chosen = await ui.chooseFilesToOpen()
                        guard !chosen.isEmpty else { throw CommandError.cancelledByUser }
                        sources = chosen
                        resolved["path"] = .array(chosen.map { .string($0.path) })
                    }
                    if name == nil {
                        // Wartość — identyfikator: dwa połączenia o tej samej nazwie da się rozróżnić („X”, „X (2)”).
                        name = try await ctx.choose(L10n.tr("Otwórz z połączeniem"), defs.map { (label: $0.displayName, value: $0.id.uuidString) })
                        if let name { resolved["connection"] = .string(name) }
                    }
                }
                guard let sources, let name else { throw CommandError.invalidArgument("path", "") }
                guard let def = UUID(uuidString: name).flatMap(ws.connections.connection)
                        ?? ws.connections.connections.first(where: { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }) else {
                    throw CommandError.invalidArgument("connection", name)
                }
                let files = FileOpening.files(from: sources)
                guard !files.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak plików do otwarcia")) }
                var opened: [String] = []
                for f in files {
                    let d = try ws.openFile(f)
                    d.connectionID = def.id
                    d.connectionPinned = true
                    opened.append(f.lastPathComponent)
                }
                return CommandResult(value: .array(opened.map { .string($0) })).resolving(resolved)
            },
            // MARK: Refaktoryzacja (PD-CA-014)
            refactoring("edit.extractLocalConstant", L10n.tr("Wydziel stałą lokalną…"), summary: L10n.tr("Zastępuje zaznaczone wyrażenie stałą zadeklarowaną w podprogramie albo bloku."),
                        typed: true) { text, sel, name, type in try CodeRefactoring.extractLocalConstant(text, selection: sel, name: name, type: type) },
            refactoring("edit.extractGlobalConstant", L10n.tr("Wydziel stałą globalną…"), summary: L10n.tr("Zastępuje zaznaczone wyrażenie stałą zadeklarowaną na początku pakietu."),
                        typed: true) { text, sel, name, type in try CodeRefactoring.extractGlobalConstant(text, selection: sel, name: name, type: type) },
            refactoring("edit.extractProcedure", L10n.tr("Wydziel procedurę…"), summary: L10n.tr("Przenosi zaznaczone instrukcje do procedury lokalnej; używane zmienne stają się parametrami."),
                        typed: false) { text, sel, name, _ in try CodeRefactoring.extractProcedure(text, selection: sel, name: name) },
            command("edit.replaceAssignmentWithInitialization", L10n.tr("Zamień przypisanie na inicjalizację"), submenu: refactor, agent: .none, effect: .modifiesEditor,
                    summary: L10n.tr("Przenosi przypisanie „zmienna := wyrażenie;” z początku ciała do deklaracji zmiennej."), feature: "PD-CA-014") { ctx in
                guard let doc = editor(ctx.workspace) else { return .ok }
                try BuiltinCommands.checkWritable(doc)
                do {
                    let e = try CodeRefactoring.replaceAssignmentWithInitialization(doc.text, at: doc.selectedRange.lowerBound)
                    doc.text = e.text
                    doc.selectedRange = e.selection
                } catch let e as RefactoringError { throw CommandError.notAvailable(e.message) }
                return .ok
            },
            // MARK: Wyszukiwanie (PD-CA-015)
            command("edit.searchBar", L10n.tr("Szukaj w edytorach i plikach…"), submenu: nil, mac: ["cmd+alt+shift+f"],
                    params: [CommandParameter("query", .string, L10n.tr("Szukany tekst")),
                             CommandParameter("scope", .string, L10n.tr("current — bieżący edytor, all — wszystkie edytory, files — pliki w katalogach")),
                             CommandParameter("directories", .string, L10n.tr("Katalogi rozdzielone ; (domyślnie lokalizacje File Browsera)")),
                             CommandParameter("caseSensitive", .boolean, L10n.tr("Wielkość liter")), CommandParameter("wholeWord", .boolean, L10n.tr("Całe słowa")),
                             CommandParameter("regex", .boolean, L10n.tr("Wyrażenie regularne"))],
                    agent: .none, effect: .none,
                    summary: L10n.tr("Szuka tekstu w bieżącym edytorze, we wszystkich edytorach albo w plikach skryptów w katalogach; lista wyników przenosi do miejsca."),
                    feature: "PD-CA-015", validate: { _ in true }) { ctx in
                let ws = ctx.workspace
                // Bez tekstu: użytkownik dostaje okno Search Bar (zakres i opcje), agent — błąd argumentu.
                guard let query = ctx.arguments.string("query"), !query.isEmpty else {
                    if !ctx.invoker.isAgent, let ui = ctx.ui { ui.showSearchBar(); return .ok }
                    throw CommandError.invalidArgument("query", "")
                }
                let scope: TextSearchScope
                switch (ctx.arguments.string("scope") ?? "all").lowercased() {
                case "current": scope = .currentEditor
                case "files":
                    let raw = ctx.arguments.string("directories")
                    let dirs = raw.map { $0.split(separator: ";").map { URL(fileURLWithPath: (String($0).trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath) } }
                        ?? ws.fileBrowser.locations.map { URL(fileURLWithPath: ($0.path as NSString).expandingTildeInPath) }
                    guard !dirs.isEmpty else { throw CommandError.notAvailable(L10n.tr("Podaj katalogi albo dodaj lokalizacje w File Browserze")) }
                    // Agent przeszukuje tylko okna (pliki użytkownika — poza jego zakresem).
                    if ctx.invoker.isAgent { throw AgentDenial.permissionDenied("wyszukiwanie w plikach jest niedostępne dla agenta") }
                    scope = .directories(dirs)
                default: scope = .allEditors
                }
                let options = TextSearchOptions(caseSensitive: ctx.arguments.bool("caseSensitive") ?? false, wholeWord: ctx.arguments.bool("wholeWord") ?? false,
                                                regex: ctx.arguments.bool("regex") ?? false)
                let hits = EditorSearch.search(query, scope: scope, options: options, in: ws)
                if !ctx.invoker.isAgent { ctx.ui?.showSearchResults(query: query, hits: hits) }
                return CommandResult(message: L10n.tr("Trafień: \(hits.count)"), value: .array(hits.map {
                    .object(["title": .string($0.title), "line": .int(Int64($0.line)), "text": .string($0.text)])
                }))
            },
        ]
    }

    /// Refaktoryzacja zaznaczenia z pytaniem o nazwę (i typ stałej, gdy nie wynika z wyrażenia).
    static func refactoring(_ id: String, _ title: String, summary: String, typed: Bool,
                            _ transform: @escaping @MainActor (String, Range<Int>, String, String?) throws -> TextEdit) -> Command {
        var params = [CommandParameter("name", .string, L10n.tr("Nazwa"))]
        if typed { params.append(CommandParameter("type", .string, L10n.tr("Typ (domyślnie z wyrażenia)"))) }
        return command(id, title, submenu: L10n.tr("Refaktoryzacja"), params: params, agent: .none, effect: .modifiesEditor, summary: summary, feature: "PD-CA-014",
                       validate: { editor($0).map { !$0.selectedRange.isEmpty } ?? false }) { ctx in
            guard let doc = editor(ctx.workspace) else { return .ok }
            try BuiltinCommands.checkWritable(doc)
            var name = ctx.arguments.string("name")
            if name == nil, let ui = ctx.ui { name = await ui.askText(title, message: L10n.tr("Nazwa"), defaultValue: "") }
            guard let name, !name.isEmpty else { throw CommandError.cancelledByUser }
            var type = ctx.arguments.string("type")
            do {
                let e: TextEdit
                do { e = try transform(doc.text, doc.selectedRange, name, type) } catch let err as RefactoringError where typed && type == nil && ctx.ui != nil {
                    // Typ nie wynika z wyrażenia — pytanie o typ i ponowna próba.
                    guard let ui = ctx.ui, let t = await ui.askText(title, message: err.message, defaultValue: "VARCHAR2(100)"), !t.isEmpty else { throw CommandError.cancelledByUser }
                    type = t
                    e = try transform(doc.text, doc.selectedRange, name, type)
                }
                doc.text = e.text
                doc.selectedRange = e.selection
            } catch let e as RefactoringError { throw CommandError.notAvailable(e.message) }
            return .ok
        }
    }
}
