import Foundation
import PelikanDB

/// Plik punktów przerwania (PD-DBG-008): punkty jednostek, punkty bloków okien testu zapisanych w plikach (ścieżka
/// zamiast identyfikatora okna) i kody błędów, przy których debuger się zatrzymuje.
public struct BreakpointFile: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var breakpoint: Breakpoint
        /// Plik okna testu dla punktu w bloku testu (okno bez pliku — punkt pomijany przy zapisie).
        public var testFile: String?
    }
    public var format = "pelikan-breakpoints"
    public var version = 1
    public var entries: [Entry]
    public var errorCodes: [Int]
}

extension Workspace {
    /// Punkty i kody błędów jako plik JSON (identyfikatory punktów nie są zapisywane — przy wczytaniu nowe).
    public func exportBreakpoints() throws -> Data {
        var entries: [BreakpointFile.Entry] = []
        for bp in breakpoints {
            if let d = bp.document {
                guard let url = documents.first(where: { $0.id.raw == d })?.fileURL else { continue }
                entries.append(.init(breakpoint: bp, testFile: url.path))
            } else {
                entries.append(.init(breakpoint: bp, testFile: nil))
            }
        }
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(BreakpointFile(entries: entries, errorCodes: errorBreakpoints))
    }

    /// Warunki punktów przerwania w pliku (bez pustych) — do potwierdzenia przed wczytaniem: warunek jest wykonywany
    /// jako SQL w sesji nadzorującej debugera (WS2-21).
    public static func breakpointConditions(in data: Data) -> [String] {
        guard let f = try? JSONDecoder().decode(BreakpointFile.self, from: data) else { return [] }
        return f.entries.compactMap { $0.breakpoint.condition?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Wczytuje punkty (`replace` — zamiast bieżących, inaczej dopisuje bez duplikatów); punkty bloku testu trafiają do
    /// otwartego okna z tym plikiem. `keepConditions: false` — bez warunków (plik z niezaufanego źródła). Zwraca liczbę
    /// dodanych punktów.
    @discardableResult
    public func importBreakpoints(_ data: Data, replace: Bool, keepConditions: Bool = true) throws -> Int {
        guard let f = try? JSONDecoder().decode(BreakpointFile.self, from: data), f.format == "pelikan-breakpoints" else {
            throw CommandError.invalidArgument("file", L10n.tr("To nie jest plik punktów przerwania Pelikana"))
        }
        if replace { breakpoints.removeAll() }
        var added = 0
        for e in f.entries {
            var bp = e.breakpoint
            bp.id = UUID()
            if !keepConditions { bp.condition = nil }
            if let path = e.testFile {
                guard let doc = documents.first(where: { $0.fileURL?.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path }) else { continue }
                bp.document = doc.id.raw
            }
            let duplicate = breakpoints.contains { $0.document == bp.document && $0.unit == bp.unit && $0.type == bp.type && $0.line == bp.line && $0.owner == bp.owner }
            if duplicate { continue }
            breakpoints.append(bp)
            added += 1
        }
        errorBreakpoints = replace ? f.errorCodes : Array(Set(errorBreakpoints + f.errorCodes)).sorted()
        return added
    }

    /// Informacja debugowania przy kompilacji (PD-DBG-011): lista NEVER wygrywa, potem ALWAYS, potem preferencja.
    /// Wpis listy to `user@baza` (połączenie, `*` i `?`) albo `[SCHEMAT.]OBIEKT` (wzorzec nazwy obiektu).
    public func addsDebugInfo(object: DBObject, connectionID: UUID?) -> Bool {
        func matches(_ entry: String) -> Bool {
            let e = entry.trimmingCharacters(in: .whitespaces)
            guard !e.isEmpty else { return false }
            if e.contains("@") {
                guard let id = connectionID, let c = connections.connection(id) else { return false }
                return Wildcard.matches(user: c.target.driverUserName, database: c.target.connectString, pattern: e)
                    || Wildcard.matches(user: c.target.driverUserName, database: c.name, pattern: e)
            }
            return e.contains(".") ? Wildcard.matches("\(object.owner).\(object.name)", pattern: e) : Wildcard.matches(object.name, pattern: e)
        }
        if settings.debugInfoNever.contains(where: matches) { return false }
        if settings.debugInfoAlways.contains(where: matches) { return true }
        return settings.debugInfoOnCompile
    }

    /// Wartość zmiennej pod kursorem myszy (PD-DBG-005) z wczytanych zmiennych i obserwowanych zatrzymanego debugera —
    /// bez wywołań DBMS_DEBUG (dymek musi powstać od razu; nazw z dwukropkiem i tak nie da się odczytać, D133).
    public func debugHoverText(_ word: String) -> String? {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !w.isEmpty, !DebuggerEngine.isUnsupportedName(w) else { return nil }
        for d in debuggers.values where d.state == .paused {
            if let v = Self.findVariable(w, in: d.variables + d.watchValues) {
                let shown = v.value.count > 400 ? String(v.value.prefix(400)) + "…" : v.value
                var text = "\(v.path) = \(shown)"
                if let c = v.children, !c.isEmpty {
                    text += "\n" + c.prefix(20).map { "  \($0.name) = \($0.value)" }.joined(separator: "\n") + (c.count > 20 ? "\n  …" : "")
                }
                return text
            }
        }
        return nil
    }

    nonisolated static func findVariable(_ path: String, in vars: [DebugVariable]) -> DebugVariable? {
        for v in vars {
            if v.path.lowercased() == path || (v.path.hasPrefix("#") && v.name.lowercased() == path) { return v }
            if let c = v.children, let f = findVariable(path, in: c) { return f }
        }
        // Zmienna globalna pakietu pod nazwą bez kwalifikatora.
        for v in vars where v.path.hasPrefix("#") {
            if let f = v.children?.first(where: { $0.name.lowercased() == path }) { return f }
        }
        return nil
    }
}

/// Słowo pod myszą dla dymka debugera: identyfikator z kropkami (`r.ename`, `pkg.g_x`), bez dwukropka zmiennej wiązanej.
public enum DebugHover {
    public static func word(in text: String, at offset: Int) -> String? {
        let ns = text as NSString
        guard offset >= 0, offset < ns.length else { return nil }
        func isWord(_ c: unichar) -> Bool {
            guard let s = Unicode.Scalar(c) else { return false }
            return CharacterSet.alphanumerics.contains(s) || c == 0x5F || c == 0x24 || c == 0x23 || c == 0x2E   // _ $ # .
        }
        guard isWord(ns.character(at: offset)), ns.character(at: offset) != 0x2E else { return nil }
        var a = offset, b = offset
        while a > 0, isWord(ns.character(at: a - 1)) { a -= 1 }
        // Do końca członu pod myszą (dalsze człony ścieżki nie należą do wskazanej zmiennej).
        while b + 1 < ns.length, isWord(ns.character(at: b + 1)), ns.character(at: b + 1) != 0x2E { b += 1 }
        if a > 0, ns.character(at: a - 1) == 0x3A { return nil }   // :zmienna
        let w = ns.substring(with: NSRange(location: a, length: b - a + 1)).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return w.isEmpty ? nil : w
    }
}

/// Komendy pliku punktów przerwania (PD-DBG-008) i eksportu statystyk (PD-OPT-004).
enum DebugP2Commands {
    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "stats.export", title: L10n.tr("Eksportuj statystyki…"), category: .tools,
                                      parameters: [CommandParameter("file", .string, L10n.tr("Ścieżka pliku .csv"))],
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Zapisuje statystyki aktywnego okna (ostatnie wykonanie i suma) do pliku CSV."), feature: "PD-OPT-004"),
                    validate: { $0.activeDocument?.statisticTotals.isEmpty == false }) { ctx in
                guard let d = ctx.workspace.activeDocument, !d.statisticTotals.isEmpty else { throw CommandError.notAvailable(L10n.tr("Brak statystyk w aktywnym oknie")) }
                var url = ctx.arguments.string("file").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                if url == nil { url = await ctx.ui?.chooseSaveURL(suggestedName: L10n.tr("statystyki"), fileExtension: "csv") }
                guard let url else { throw CommandError.cancelledByUser }
                let rows = Profiler.rows(last: d.statistics, totals: d.statisticTotals, selected: ctx.workspace.settings.selectedStatistics)
                try Profiler.csv(rows).write(to: url, atomically: true, encoding: .utf8)
                return CommandResult(message: L10n.tr("Zapisano statystyki: \(rows.count)"), value: .int(Int64(rows.count)))
            },
            Command(CommandDescriptor(id: "debug.saveBreakpoints", title: L10n.tr("Zapisz punkty przerwania…"), category: .debug,
                                      parameters: [CommandParameter("file", .string, L10n.tr("Ścieżka pliku .json"))],
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Zapisuje punkty przerwania i kody błędów do pliku JSON."), feature: "PD-DBG-008")) { ctx in
                var url = ctx.arguments.string("file").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                if url == nil { url = await ctx.ui?.chooseSaveURL(suggestedName: L10n.tr("punkty-przerwania"), fileExtension: "json") }
                guard let url else { throw CommandError.cancelledByUser }
                try ctx.workspace.exportBreakpoints().write(to: url, options: .atomic)
                return CommandResult(message: L10n.tr("Zapisano punkty przerwania: \(ctx.workspace.breakpoints.count)"))
            },
            Command(CommandDescriptor(id: "debug.loadBreakpoints", title: L10n.tr("Wczytaj punkty przerwania…"), category: .debug,
                                      parameters: [CommandParameter("file", .string, L10n.tr("Ścieżka pliku .json")),
                                                   CommandParameter("replace", .boolean, L10n.tr("Zastąp bieżące punkty (domyślnie dopisz)"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Wczytuje punkty przerwania i kody błędów z pliku JSON."), feature: "PD-DBG-008")) { ctx in
                var url = ctx.arguments.string("file").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                if url == nil { url = await ctx.ui?.chooseFilesToOpen().first }
                guard let url else { throw CommandError.cancelledByUser }
                let data = try Data(contentsOf: url)
                @MainActor func load(_ keep: Bool) throws -> CommandResult {
                    let n = try ctx.workspace.importBreakpoints(data, replace: ctx.arguments.bool("replace") ?? false, keepConditions: keep)
                    return CommandResult(message: L10n.tr("Wczytano punkty przerwania: \(n)"), value: .int(Int64(n)))
                }
                // Warunki to SQL wykonywany przy zatrzymaniu (np. funkcja z autonomiczną transakcją) — pokazane do
                // potwierdzenia; bez interfejsu wczytywane bez warunków (WS2-21).
                var keep = true
                let conditions = Workspace.breakpointConditions(in: data)
                if !conditions.isEmpty {
                    guard let ui = ctx.ui else { return try load(false) }
                    let list = conditions.prefix(20).map { "• " + $0 }.joined(separator: "\n") + (conditions.count > 20 ? "\n…" : "")
                    switch await ui.ask(L10n.tr("Punkty przerwania z warunkami"),
                                        message: L10n.tr("Warunki są wykonywane jako SQL w bazie przy każdym zatrzymaniu:") + "\n" + list,
                                        buttons: [L10n.tr("Wczytaj bez warunków"), L10n.tr("Wczytaj z warunkami"), L10n.tr("Anuluj")]) {
                    case 0?: keep = false
                    case 1?: keep = true
                    default: throw CommandError.cancelledByUser
                    }
                }
                return try load(keep)
            },
            // Przyciski listy punktów przerwania (R4-18) — komendy rejestru (skróty, makra).
            Command(CommandDescriptor(id: "debug.enableAllBreakpoints", title: L10n.tr("Włącz wszystkie punkty przerwania"), category: .debug,
                                      agent: .none, effect: .uiState, summary: L10n.tr("Włącza wszystkie punkty przerwania."),
                                      inMenu: false, feature: "PD-DBG-008")) { ctx in
                for i in ctx.workspace.breakpoints.indices where !ctx.workspace.breakpoints[i].enabled { ctx.workspace.breakpoints[i].enabled = true }
                return .ok
            },
            Command(CommandDescriptor(id: "debug.disableAllBreakpoints", title: L10n.tr("Wyłącz wszystkie punkty przerwania"), category: .debug,
                                      agent: .none, effect: .uiState, summary: L10n.tr("Wyłącza wszystkie punkty przerwania (zostają na liście)."),
                                      inMenu: false, feature: "PD-DBG-008")) { ctx in
                for i in ctx.workspace.breakpoints.indices where ctx.workspace.breakpoints[i].enabled { ctx.workspace.breakpoints[i].enabled = false }
                return .ok
            },
            Command(CommandDescriptor(id: "debug.removeAllBreakpoints", title: L10n.tr("Usuń wszystkie punkty przerwania"), category: .debug,
                                      agent: .none, effect: .uiState, summary: L10n.tr("Usuwa wszystkie punkty przerwania."),
                                      inMenu: false, feature: "PD-DBG-008")) { ctx in
                ctx.workspace.breakpoints.removeAll()
                return .ok
            },
        ]
    }
}
