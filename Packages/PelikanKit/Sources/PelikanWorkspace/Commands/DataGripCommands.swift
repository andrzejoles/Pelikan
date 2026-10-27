import Foundation
import PelikanDB
import PelikanSQL

/// Komendy Etapu 7 z analizy DataGrip: analiza kodu (nieznane nazwy, inspekcje), Find Usages, refaktoryzacja z podglądem,
/// historia lokalna, konsole połączeń, zmiany oczekujące w siatce (DG-RES-001, DG-INSP-001, DG-USE-001, DG-REF-001,
/// DG-HIST-001, DG-CONS-001, DG-GRID-001).
@MainActor
enum DataGripCommands {
    static func editor(_ ws: Workspace) -> Document? { Stage7Commands.editor(ws) }

    static func diagnosticsJSON(_ list: [EditorDiagnostic], text: String) -> JSONValue {
        .array(list.map { d -> JSONValue in
            var o: [String: JSONValue] = ["code": .string(d.code), "severity": .string(d.severity.rawValue), "message": .string(d.message)]
            o["line"] = .int(Int64(d.line(in: text)))
            o["start"] = .int(Int64(d.range.lowerBound))
            o["end"] = .int(Int64(d.range.upperBound))
            return .object(o)
        })
    }

    /// Następny albo poprzedni problem względem kursora (z zawijaniem).
    static func moveToProblem(_ ws: Workspace, forward: Bool) -> CommandResult {
        guard let doc = editor(ws), let list = ws.diagnostics[doc.id], !list.isEmpty else { return .ok }
        let pos = doc.selectedRange.lowerBound
        let d = forward ? list.first { $0.range.lowerBound > pos } ?? list.first! : list.last { $0.range.lowerBound < pos } ?? list.last!
        doc.selectedRange = d.range
        return CommandResult(message: d.message)
    }

    /// Obiekt (właściciel, nazwa) i kolumna z argumentów albo identyfikatora pod kursorem: `NAZWA`, `WŁAŚCICIEL.NAZWA`,
    /// `ALIAS.KOLUMNA` (alias z polecenia pod kursorem), `WŁAŚCICIEL.TABELA.KOLUMNA`.
    static func target(_ ctx: CommandContext) throws -> (owner: String?, name: String, column: String?) {
        let doc = editor(ctx.workspace)
        var spec = ctx.arguments.string("name")
        if spec == nil, let doc { spec = BuiltinCommands.identifier(at: doc.selectedRange.lowerBound, in: doc.text)?.0 }
        guard let spec, !spec.isEmpty else { throw CommandError.missingArgument("name") }
        let parts = spec.split(separator: ".").map { $0.hasPrefix("\"") ? String($0.dropFirst().dropLast()) : $0.uppercased() }
        var column = ctx.arguments.string("column")?.uppercased()
        if column == nil, parts.count == 2, let doc,
           let r = NameResolver.relation(qualifier: parts[0], at: doc.selectedRange.lowerBound, in: doc.text) {
            return (r.owner, r.name, parts[1])
        }
        if parts.count >= 3 { column = column ?? parts[2] }
        return parts.count >= 2 ? (parts[0], parts[1], column) : (nil, parts[0], column)
    }

    /// Pliki projektu (do Find Usages i refaktoryzacji).
    static func projectFiles(_ ws: Workspace) -> [URL] {
        guard let p = ws.project, let u = ws.projectURL else { return [] }
        return p.items.filter { $0.kind == .file }.compactMap { ProjectEngine.url(of: $0, projectURL: u) }
    }

    static func editorDocuments(_ ws: Workspace) -> [Document] { ws.documents.filter { [.sql, .program, .test, .command].contains($0.kind) } }

    /// Plan zmiany nazwy: zmienna/parametr pod kursorem (lokalnie w zakresie) albo obiekt w oknach i plikach projektu
    /// z (niewykonywanym) DDL zmiany nazwy w bazie.
    static func renamePlan(_ ctx: CommandContext, newName: String) async throws -> RefactoringPlan {
        let ws = ctx.workspace
        guard let doc = editor(ws) else { throw CommandError.notAvailable(L10n.tr("Brak okna edytora")) }
        let offset = doc.selectedRange.lowerBound
        if ctx.arguments.string("name") == nil, let (word, _) = BuiltinCommands.identifier(at: offset, in: doc.text), !word.contains("."),
           let decl = PLSQLOutline.declaration(of: word, at: offset, in: PLSQLOutline.parse(doc.text)),
           [.variable, .constant, .parameter].contains(decl.kind) {
            let (after, n) = try Refactoring.renameLocal(in: doc.text, at: offset, to: newName)
            return RefactoringPlan(title: L10n.tr("Zmiana nazwy \(word) na \(newName)"),
                                   changes: [RefactoringChange(target: .document(doc.id), title: doc.fullTitle, before: doc.text, after: after, occurrences: n)])
        }
        let (owner, name, column) = try target(ctx)
        var texts: [(RefactoringChange.Target, String, String)] = editorDocuments(ws).map { (.document($0.id), $0.fullTitle, $0.text) }
        let open = Set(ws.documents.compactMap { $0.fileURL?.standardizedFileURL })
        for f in projectFiles(ws) where !open.contains(f.standardizedFileURL) {
            if let data = try? Data(contentsOf: f) { texts.append((.file(f), f.lastPathComponent, TextFileCodec.decode(data, preferred: ws.projectEncoding(for: f)).text)) }
        }
        var ddl: String?
        let changes: [RefactoringChange]
        if let column {
            // Kolumna: tylko w poleceniach odwołujących się do tabeli.
            changes = texts.compactMap { target, title, text in
                let t = SQLToken.significant(text), tab = name, col = column
                var hit = Set<Int>()
                for st in NameResolver.statements(t) where NameResolver.relations(t, st).contains(where: { $0.name == tab }) {
                    for i in st where t[i].isWord && t[i].name == col { hit.insert(i) }
                }
                let (after, n) = Refactoring.replace(text, newName: newName) { _, i in hit.contains(i) }
                return n > 0 ? RefactoringChange(target: target, title: title, before: text, after: after, occurrences: n) : nil
            }
        } else {
            changes = try Refactoring.renameObject(name, owner: owner, to: newName, texts: texts)
        }
        if let m = ws.metadata(for: ws.effectiveConnection(of: doc)),
           ws.sessions.existingSession(SessionKey(connectionID: m.connectionID, purpose: .main)) != nil,
           let o = try? await m.find(owner.map { "\($0).\(name)" } ?? name, type: column == nil ? nil : .table) {
            ddl = Refactoring.renameDDL(owner: o.owner, name: o.name, type: o.type, newName: newName, column: column)
        }
        let what = column.map { "\(name).\($0)" } ?? (owner.map { "\($0).\(name)" } ?? name)
        return RefactoringPlan(title: L10n.tr("Zmiana nazwy \(what) na \(newName)"), changes: changes, ddl: ddl)
    }

    static func newName(_ ctx: CommandContext) async throws -> String {
        if let n = ctx.arguments.string("newName") { return n }
        var current = ""
        if let doc = editor(ctx.workspace), let (w, _) = BuiltinCommands.identifier(at: doc.selectedRange.lowerBound, in: doc.text) {
            current = String(w.split(separator: ".").last ?? "")
        }
        guard let n = await ctx.ui?.askText(L10n.tr("Zmień nazwę"), message: L10n.tr("Nowa nazwa dla \(current)"), defaultValue: current),
              !n.isEmpty else { throw CommandError.cancelledByUser }
        return n
    }

    static func entry(_ ctx: CommandContext) throws -> (Document, LocalHistoryEntry) {
        let ws = ctx.workspace
        guard let doc = ws.activeDocument, let (key, _) = ws.historyKey(for: doc) else {
            throw CommandError.notAvailable(L10n.tr("Okno nie ma historii lokalnej (zapisz plik albo skompiluj obiekt)"))
        }
        let list = ws.localHistory.entries(key)
        guard let id = ctx.arguments.string("entry") else {
            guard let first = list.first else { throw CommandError.notAvailable(L10n.tr("Brak wersji w historii lokalnej")) }
            return (doc, first)
        }
        guard let e = list.first(where: { $0.id.uuidString == id }) else { throw CommandError.invalidArgument("entry", id) }
        return (doc, e)
    }

    static func hasHistory(_ ws: Workspace) -> Bool {
        guard let doc = ws.activeDocument else { return false }
        return ws.historyKey(for: doc) != nil
    }

    static func dateText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }

    static var all: [Command] {
        let hasEditor: @MainActor (Workspace) -> Bool = { editor($0) != nil }
        let hasPending: @MainActor (Workspace) -> Bool = { GridCommands.activeGrid($0).map { !$0.1.pendingSummary.isEmpty } ?? false }
        let entryParam = CommandParameter("entry", .string, L10n.tr("Identyfikator wersji (domyślnie najnowsza)"))
        return [
            // MARK: Analiza kodu (DG-RES-001, DG-INSP-001)
            Command(CommandDescriptor(id: "edit.analyzeCode", title: L10n.tr("Analizuj kod"), category: .edit, submenu: L10n.tr("Analiza kodu"),
                                      parameters: [CommandParameter("text", .sql, L10n.tr("Tekst do analizy (domyślnie aktywne okno)"))],
                                      agent: .none, effect: .none,
                                      summary: L10n.tr("Inspekcje kodu (nieużywane zmienne i parametry, kod nieosiągalny, UPDATE/DELETE bez WHERE, niejawne konwersje) i nieznane tabele, kolumny, aliasy wg słownika połączenia; lista problemów."),
                                      feature: "DG-INSP-001")) { ctx in
                let ws = ctx.workspace
                if let text = ctx.arguments.string("text") {
                    let list = CodeInspections.inspect(text, identifierLimit: ws.settings.identifierLengthWarning)
                    return CommandResult(message: L10n.tr("Problemów: \(list.count)"), value: diagnosticsJSON(list, text: text))
                }
                guard let doc = editor(ws) else { throw CommandError.notAvailable(L10n.tr("Brak okna edytora")) }
                // Agent dostaje tylko inspekcje tekstu — słownik czyta wyłącznie przez własną sesję (narzędzia agent.*).
                let list = await ws.analyzeCode(doc, names: !ctx.invoker.isAgent)
                if !ctx.invoker.isAgent { ctx.ui?.showProblems(document: doc) }
                return CommandResult(message: L10n.tr("Problemów: \(list.count)"), value: diagnosticsJSON(list, text: doc.text))
            },
            Command(CommandDescriptor(id: "edit.toggleCodeAnalysis", title: L10n.tr("Analiza kodu w czasie pisania"), category: .edit, submenu: L10n.tr("Analiza kodu"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Włącza albo wyłącza podkreślanie nieznanych nazw i problemów inspekcji podczas pisania."),
                                      feature: "DG-RES-001")) { ctx in
                ctx.workspace.settings.liveCodeAnalysis.toggle()
                if !ctx.workspace.settings.liveCodeAnalysis { ctx.workspace.diagnostics = [:] }
                return CommandResult(message: ctx.workspace.settings.liveCodeAnalysis ? L10n.tr("Analiza kodu włączona") : L10n.tr("Analiza kodu wyłączona"))
            },
            Command(CommandDescriptor(id: "edit.nextProblem", title: L10n.tr("Następny problem"), category: .edit, submenu: L10n.tr("Analiza kodu"),
                                      mac: ["f2"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zaznacza następne podkreślone miejsce (nieznana nazwa, wynik inspekcji)."), feature: "DG-RES-001"),
                    validate: { ws in editor(ws).map { !(ws.diagnostics[$0.id] ?? []).isEmpty } ?? false }) { ctx in
                moveToProblem(ctx.workspace, forward: true)
            },
            Command(CommandDescriptor(id: "edit.previousProblem", title: L10n.tr("Poprzedni problem"), category: .edit, submenu: L10n.tr("Analiza kodu"),
                                      mac: ["shift+f2"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zaznacza poprzednie podkreślone miejsce."), feature: "DG-RES-001"),
                    validate: { ws in editor(ws).map { !(ws.diagnostics[$0.id] ?? []).isEmpty } ?? false }) { ctx in
                moveToProblem(ctx.workspace, forward: false)
            },
            Command(CommandDescriptor(id: "edit.showProblems", title: L10n.tr("Lista problemów"), category: .edit, submenu: L10n.tr("Analiza kodu"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Okno z problemami analizy kodu aktywnego okna; wybór przechodzi do miejsca w tekście."), feature: "DG-INSP-001"),
                    validate: hasEditor) { ctx in
                guard let doc = editor(ctx.workspace) else { return .ok }
                if ctx.workspace.diagnostics[doc.id] == nil { await ctx.workspace.analyzeCode(doc) }
                ctx.ui?.showProblems(document: doc)
                return .ok
            },

            // MARK: Find Usages (DG-USE-001)
            Command(CommandDescriptor(id: "edit.findUsages", title: L10n.tr("Znajdź użycia"), category: .edit, submenu: L10n.tr("Refaktoryzacja"),
                                      mac: ["alt+f7"],
                                      parameters: [CommandParameter("name", .string, L10n.tr("Obiekt (WŁAŚCICIEL.NAZWA) albo ALIAS.KOLUMNA; domyślnie nazwa pod kursorem")),
                                                   CommandParameter("column", .string, L10n.tr("Kolumna tabeli"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Użycia obiektu albo kolumny: obiekty zależne (ALL_DEPENDENCIES), linie ich kodu, PL/Scope, otwarte okna i pliki projektu. Agent ma narzędzie find_usages."),
                                      feature: "DG-USE-001"),
                    validate: hasEditor) { ctx in
                let ws = ctx.workspace
                let (owner, name, column) = try target(ctx)
                var hits: [UsageHit] = []
                let conn = editor(ws).flatMap { ws.effectiveConnection(of: $0) } ?? ws.sessions.mainConnectionID
                if let m = ws.metadata(for: conn), let o = try await m.find(owner.map { "\($0).\(name)" } ?? name) {
                    hits += try await UsageFinder.inDatabase(owner: o.owner, name: o.name, column: column, session: try await m.session())
                        .map { var h = $0; h.connection = m.connectionID; return h }
                }
                hits += await UsageFinder.inTexts(name: name, owner: owner, column: column, documents: editorDocuments(ws), files: projectFiles(ws),
                                                  encoding: ws.projectEncodingResolver())
                let title = column.map { "\(name).\($0)" } ?? (owner.map { "\($0).\(name)" } ?? name)
                ctx.ui?.showUsages(title: title, hits: hits)
                return CommandResult(message: L10n.tr("Użycia \(title): \(hits.count)"), value: .array(hits.map {
                    .object(["kind": .string($0.kind.rawValue), "title": .string($0.title), "line": .int(Int64($0.line)), "text": .string($0.text)])
                }))
            },

            // MARK: Refaktoryzacja (DG-REF-001)
            Command(CommandDescriptor(id: "edit.refactorRename", title: L10n.tr("Zmień nazwę…"), category: .edit, submenu: L10n.tr("Refaktoryzacja"),
                                      mac: ["shift+f6"],
                                      parameters: [CommandParameter("newName", .string, L10n.tr("Nowa nazwa")),
                                                   CommandParameter("name", .string, L10n.tr("Obiekt albo ALIAS.KOLUMNA (domyślnie nazwa pod kursorem)")),
                                                   CommandParameter("column", .string, L10n.tr("Kolumna tabeli"))],
                                      agent: .none, effect: .external,
                                      summary: L10n.tr("Zmienia nazwę zmiennej lub parametru w jej zakresie albo obiektu lub kolumny w oknach i plikach projektu; podgląd różnic przed zastosowaniem, DDL zmiany w bazie trafia do nowego okna bez wykonania."),
                                      feature: "DG-REF-001"),
                    validate: hasEditor,
                    preview: { ctx in
                        guard let n = ctx.arguments.string("newName") else { throw CommandError.missingArgument("newName") }
                        let plan = try await renamePlan(ctx, newName: n)
                        return EffectPreview(summary: plan.title, statements: plan.changes.flatMap { c in
                            ["-- \(c.title): \(c.occurrences)"] + c.changedLines.prefix(20).map { "\($0.line): \($0.before)  →  \($0.after)" }
                        } + (plan.ddl.map { [$0] } ?? []))
                    }) { ctx in
                let n = try await newName(ctx)
                let plan = try await renamePlan(ctx, newName: n)
                guard !plan.changes.isEmpty || plan.ddl != nil else { throw CommandError.notAvailable(L10n.tr("Brak wystąpień do zmiany")) }
                if !ctx.invoker.isAgent, let ui = ctx.ui {
                    guard await ui.confirmRefactoring(plan) else { throw CommandError.cancelledByUser }
                }
                let applied = try ctx.workspace.apply(plan)
                return CommandResult(message: L10n.tr("\(plan.title): zmienionych tekstów \(applied)"))
            },

            // MARK: Historia lokalna (DG-HIST-001)
            Command(CommandDescriptor(id: "file.localHistory", title: L10n.tr("Historia lokalna"), category: .file, submenu: L10n.tr("Historia lokalna"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Wersje pliku albo obiektu aktywnego okna (zapis, kompilacja, refaktoryzacja) z porównaniem i przywracaniem."),
                                      feature: "DG-HIST-001"),
                    validate: hasHistory) { ctx in
                guard let doc = ctx.workspace.activeDocument else { return .ok }
                ctx.ui?.showLocalHistory(document: doc)
                return .ok
            },
            Command(CommandDescriptor(id: "file.localHistoryList", title: L10n.tr("Wersje w historii lokalnej"), category: .file, submenu: L10n.tr("Historia lokalna"),
                                      agent: .none, effect: .none,
                                      summary: L10n.tr("Lista wersji aktywnego okna: identyfikator, czas, zdarzenie, długość tekstu."),
                                      inMenu: false, feature: "DG-HIST-001"),
                    validate: hasHistory) { ctx in
                let ws = ctx.workspace
                guard let doc = ws.activeDocument, let (key, _) = ws.historyKey(for: doc) else { return .ok }
                let list = ws.localHistory.entries(key)
                return CommandResult(message: L10n.tr("Wersji: \(list.count)"), value: .array(list.map {
                    .object(["id": .string($0.id.uuidString), "date": .string(dateText($0.date)), "label": .string($0.label),
                             "length": .int(Int64(($0.text as NSString).length))])
                }))
            },
            Command(CommandDescriptor(id: "file.localHistoryCheckpoint", title: L10n.tr("Zapisz wersję w historii"), category: .file, submenu: L10n.tr("Historia lokalna"),
                                      parameters: [CommandParameter("label", .string, L10n.tr("Opis wersji"))],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Dopisuje bieżący tekst okna do historii lokalnej z opisem."), feature: "DG-HIST-001"),
                    validate: hasHistory) { ctx in
                let ws = ctx.workspace
                guard let doc = ws.activeDocument else { return .ok }
                var label = ctx.arguments.string("label")
                if label == nil, let ui = ctx.ui {
                    guard let l = await ui.askText(L10n.tr("Historia lokalna"), message: L10n.tr("Opis wersji"), defaultValue: "") else { throw CommandError.cancelledByUser }
                    label = l
                }
                ws.recordHistory(doc, label: label?.isEmpty == false ? label! : L10n.tr("ręcznie"))
                return .ok
            },
            Command(CommandDescriptor(id: "file.localHistoryCompare", title: L10n.tr("Porównaj z wersją"), category: .file, submenu: L10n.tr("Historia lokalna"),
                                      parameters: [entryParam], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Różnice między wersją z historii a bieżącym tekstem okna."), inMenu: false, feature: "DG-HIST-001"),
                    validate: hasHistory) { ctx in
                let (doc, e) = try entry(ctx)
                ctx.ui?.showDiff(left: e.text, right: doc.text, leftTitle: "\(dateText(e.date)) · \(e.label)", rightTitle: L10n.tr("Bieżący tekst"))
                return .ok
            },
            Command(CommandDescriptor(id: "file.localHistoryRestore", title: L10n.tr("Przywróć wersję"), category: .file, submenu: L10n.tr("Historia lokalna"),
                                      parameters: [entryParam], agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Wstawia do okna tekst wersji z historii (bieżący tekst zostaje w historii)."), inMenu: false, feature: "DG-HIST-001"),
                    validate: hasHistory) { ctx in
                let (doc, e) = try entry(ctx)
                ctx.workspace.restore(e, in: doc)
                return CommandResult(message: L10n.tr("Przywrócono wersję z \(dateText(e.date))"))
            },

            // MARK: Konsole (DG-CONS-001)
            Command(CommandDescriptor(id: "session.console", title: L10n.tr("Konsola połączenia"), category: .session,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Okno SQL przypisane do połączenia, którego tekst jest zachowywany automatycznie między uruchomieniami."),
                                      feature: "DG-CONS-001"),
                    validate: { ws in (ws.activeDocument.flatMap { ws.effectiveConnection(of: $0) } ?? ws.sessions.mainConnectionID) != nil }) { ctx in
                let ws = ctx.workspace
                guard let c = ws.activeDocument.flatMap({ ws.effectiveConnection(of: $0) }) ?? ws.sessions.mainConnectionID else { throw CommandError.notConnected }
                ws.openConsole(connection: c)
                return .ok
            },

            // MARK: Zmiany oczekujące w siatce (DG-GRID-001)
            Command(CommandDescriptor(id: "grid.nextPendingChange", title: L10n.tr("Następna zmiana oczekująca"), category: .session, submenu: L10n.tr("Wynik"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zaznacza następny wiersz wstawiony, zmieniony albo usunięty przed zapisem."), feature: "DG-GRID-001"),
                    validate: hasPending) { ctx in
                guard let (tab, grid) = GridCommands.activeGrid(ctx.workspace), let r = grid.nextPendingRow(after: tab.selectedRows?.first) else { return .ok }
                tab.selectedRows = [r]
                tab.revealRow = r
                return CommandResult(message: grid.pendingSummary.text)
            },
            Command(CommandDescriptor(id: "grid.previousPendingChange", title: L10n.tr("Poprzednia zmiana oczekująca"), category: .session, submenu: L10n.tr("Wynik"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zaznacza poprzedni wiersz ze zmianą oczekującą."), feature: "DG-GRID-001"),
                    validate: hasPending) { ctx in
                guard let (tab, grid) = GridCommands.activeGrid(ctx.workspace),
                      let r = grid.nextPendingRow(after: tab.selectedRows?.first, forward: false) else { return .ok }
                tab.selectedRows = [r]
                tab.revealRow = r
                return CommandResult(message: grid.pendingSummary.text)
            },
            Command(CommandDescriptor(id: "grid.revertRowChanges", title: L10n.tr("Cofnij zmiany wierszy"), category: .session, submenu: L10n.tr("Wynik"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Przywraca wartości pierwotne zaznaczonych wierszy, zdejmuje oznaczenie usunięcia, usuwa wiersze wstawione."),
                                      feature: "DG-GRID-001"),
                    validate: { ws in hasPending(ws) && GridCommands.activeGrid(ws)?.0.selectedRows?.isEmpty == false }) { ctx in
                guard let (tab, grid) = GridCommands.activeGrid(ctx.workspace), let rows = tab.selectedRows else { return .ok }
                grid.revertRows(rows)
                tab.selectedRows = nil
                return CommandResult(message: grid.pendingSummary.isEmpty ? L10n.tr("Brak zmian oczekujących") : grid.pendingSummary.text)
            },
        ]
    }
}

extension RefactoringChange {
    /// Zmienione linie (zmiana nazwy nie zmienia liczby linii): numer, przed, po.
    public var changedLines: [(line: Int, before: String, after: String)] {
        let a = before.components(separatedBy: "\n"), b = after.components(separatedBy: "\n")
        guard a.count == b.count else { return [] }
        return zip(a, b).enumerated().compactMap { i, p in
            p.0 == p.1 ? nil : (i + 1, p.0.trimmingCharacters(in: .whitespaces), p.1.trimmingCharacters(in: .whitespaces))
        }
    }
}
