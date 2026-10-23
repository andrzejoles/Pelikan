import Foundation
import PelikanSQL

/// Komendy wbudowane. Skróty profilu PL/SQL Developer: potwierdzone w UG 17 / na forum producenta albo oznaczone
/// „do weryfikacji” w docs/research/keys.md. Komendy zapowiedziane (`.planned`) są w menu wyszarzone do swojego etapu.
public enum BuiltinCommands {
    @MainActor
    public static var all: [Command] {
        file + edit + session + SQLCommands.all + GridCommands.all + GridToolCommands.all + Stage7Commands.all + Stage7PlanCommands.all + PackCommands.all + Stage7ToolCommands.all + DataGripCommands.all + Oracle23Commands.all + TestManagerCommands.all + ProjectCommands.all + MonitorCommands.all + ObjectCommands.all + ToolCommands.all + TemplateCommands.all + CompareCommands.all + NavigationCommands.all + EditorCommands.all + UtplsqlCommands.all + EditorToolCommands.all + ConnectionCommands.all + FileCommands.all + AgentCommands.all + AgentDatabaseCommands.all + AgentChangeCommands.all + PlanCommands.all + SessionCommands.all + SchedulerCommands.all + DiagramCommands.all + DataTransferCommands.all + UserToolCommands.all + ReportCommands.all + debug + tools + reports + view + window + help
    }

    private static func newDocument(_ kind: DocumentKind, id: String, title: String, pd: [String] = [], mac: [String]? = nil,
                                    feature: String) -> Command {
        Command(CommandDescriptor(
            id: CommandID(rawValue: id), title: title, category: .file, submenu: L10n.tr("Nowy"), pd: pd, mac: mac,
            agent: .full, effect: .uiState, summary: L10n.tr("Otwiera nowe puste okno: \(kind.displayName)."), feature: feature
        )) { ctx in
            let doc = ctx.workspace.newDocument(kind)
            return CommandResult(message: doc.fullTitle, value: .object(["document": .string(doc.id.description)]))
        }
    }

    // MARK: Plik

    /// Zamknięcie grupy okien względem bieżącego (menu karty — PD-UI-004).
    @MainActor
    static func closeMany(_ id: String, _ title: String, _ summary: String, _ which: @escaping @Sendable (Int, Int) -> Bool) -> Command {
        Command(CommandDescriptor(id: CommandID(rawValue: id), title: title, category: .file, agent: .none, effect: .uiState,
                                  summary: summary, feature: "PD-UI-004"),
                validate: { ws in
                    guard let a = ws.documents.firstIndex(where: { $0.id == ws.activeDocumentID }) else { return false }
                    return ws.documents.indices.contains { which($0, a) }
                }) { ctx in
            let ws = ctx.workspace
            guard let a = ws.documents.firstIndex(where: { $0.id == ws.activeDocumentID }) else { return .ok }
            let keep = ws.documents[a].id
            let targets = ws.documents.enumerated().filter { which($0.offset, a) }.map(\.element)
            for d in targets {
                ws.activate(d.id)
                guard try await closeDocument(d, in: ws) else { ws.activate(keep); throw CommandError.cancelledByUser }
            }
            ws.activate(keep)
            return .ok
        }
    }

    /// Zapis (z oknem wyboru nazwy dla nowego okna albo „Zapisz jako”). false — anulowano.
    @MainActor
    static func saveDocument(_ doc: Document, in ws: Workspace, askForName: Bool) async throws -> Bool {
        var url = doc.fileURL
        if askForName || url == nil {
            let (base, ext) = suggestedFileName(doc)
            guard let chosen = await ws.ui?.chooseSaveURL(suggestedName: base, fileExtension: ext) else { return false }
            url = chosen
        }
        try ws.save(doc, to: url!)
        return true
    }

    /// Proponowana nazwa pliku: z pliku, z jednostki programu (nazwa + rozszerzenie typu, UG 23.29) albo z tytułu.
    @MainActor
    static func suggestedFileName(_ doc: Document) -> (String, String) {
        if let url = doc.fileURL { return (url.deletingPathExtension().lastPathComponent, url.pathExtension) }
        if doc.kind == .program, let u = ProgramCompiler.units(in: doc.text).first {
            return (u.name.lowercased(), ObjectCommands.fileExtension(u.type))
        }
        let title = doc.customTitle ?? doc.kind.shortName
        let ext = (title as NSString).pathExtension
        return ext.isEmpty ? (title, doc.kind.defaultExtension) : ((title as NSString).deletingPathExtension, ext)
    }

    /// Zamknięcie okna (UG 23.20, PD-SQLW-024): pytanie o zapis zmian i o otwartą transakcję, zamknięcie sesji okna.
    /// false — użytkownik anulował.
    @MainActor
    static func closeDocument(_ doc: Document, in ws: Workspace) async throws -> Bool {
        let needsSave = doc.isModified && doc.consoleConnectionID == nil && (doc.fileURL != nil || (ws.settings.confirmSaveNewWindows && !doc.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        if needsSave {
            let choice = await ws.ui?.ask(L10n.tr("Zapisać zmiany w „\(doc.title)”?"), message: L10n.tr("Niezapisane zmiany zostaną utracone."),
                                          buttons: [L10n.tr("Zapisz"), L10n.tr("Nie zapisuj"), L10n.tr("Anuluj")]) ?? 1
            switch choice {
            case 0: guard try await saveDocument(doc, in: ws, askForName: doc.fileURL == nil) else { return false }
            case 1: break
            default: return false
            }
        }
        if doc.transactionOpen {
            var commit: Bool
            switch ws.settings.logoffWithOpenTransaction {
            case .commit: commit = true
            case .rollback: commit = false
            case .ask:
                let choice = await ws.ui?.ask(L10n.tr("Transakcja okna „\(doc.title)” jest otwarta"), message: L10n.tr("Zatwierdzić czy wycofać zmiany przed zamknięciem okna?"),
                                              buttons: [L10n.tr("Zatwierdź"), L10n.tr("Wycofaj"), L10n.tr("Anuluj")])
                guard let choice, choice < 2 else { return false }
                commit = choice == 0
            }
            try await ws.endTransactions(of: [doc], commit: commit)
        }
        // Sesja okna (tryb Multi) kończy się razem z oknem.
        if let c = ws.effectiveConnection(of: doc), ws.settings.sessionMode == .multi {
            await ws.sessions.close(ws.sessions.key(forDocument: doc.id, connection: c))
        }
        ws.close(doc.id)
        return true
    }

    @MainActor static var file: [Command] {
        [
            newDocument(.sql, id: "file.new.sql", title: L10n.tr("Okno SQL"), mac: ["cmd+n"], feature: "PD-SQLW-002"),
            newDocument(.program, id: "file.new.program", title: L10n.tr("Okno programu"), mac: ["cmd+shift+n"], feature: "PD-PROG-001"),
            newDocument(.test, id: "file.new.test", title: L10n.tr("Okno testu"), feature: "PD-TEST-001"),
            newDocument(.command, id: "file.new.command", title: L10n.tr("Okno poleceń"), feature: "PD-CMDW-001"),
            newDocument(.explainPlan, id: "file.new.explainPlan", title: L10n.tr("Okno planu (Explain Plan)"), feature: "PD-OPT-001"),
            newDocument(.report, id: "file.new.report", title: L10n.tr("Okno raportu"), feature: "PD-REP-002"),
            newDocument(.diagram, id: "file.new.diagram", title: L10n.tr("Okno diagramu"), feature: "PD-DIAG-001"),
            newDocument(.notebook, id: "file.new.notebook", title: L10n.tr("Notatnik SQL"), feature: "SD-NB-001"),
            Command(CommandDescriptor(id: "file.open", title: L10n.tr("Otwórz…"), category: .file, mac: ["cmd+o"],
                                      agent: .none, effect: .external, summary: L10n.tr("Otwiera plik w odpowiednim oknie."),
                                      feature: "PD-SQLW-012")) { ctx in
                let urls = await ctx.workspace.ui?.chooseFilesToOpen() ?? []
                for url in urls { try ctx.workspace.openFile(url) }
                return .ok
            },
            Command(CommandDescriptor(id: "file.reopen", title: L10n.tr("Otwórz ponownie"), category: .file,
                                      parameters: [CommandParameter("path", .string, required: true, L10n.tr("Ścieżka pliku z listy ostatnich"))],
                                      agent: .none, effect: .external, summary: L10n.tr("Otwiera plik z listy ostatnio używanych."),
                                      inMenu: false, feature: "PD-SQLW-012")) { ctx in
                guard let path = ctx.arguments.string("path"), ctx.workspace.settings.recentFiles.contains(path) else {
                    throw CommandError.invalidArgument("path", L10n.tr("plik spoza listy ostatnich"))
                }
                try ctx.workspace.openFile(URL(fileURLWithPath: path))
                return .ok
            },
            Command(CommandDescriptor(id: "file.save", title: L10n.tr("Zapisz"), category: .file, mac: ["cmd+s"],
                                      agent: .approval, effect: .external, summary: L10n.tr("Zapisuje okno do pliku."),
                                      feature: "PD-SQLW-012"),
                    validate: { $0.activeDocument != nil }) { ctx in
                guard let doc = ctx.workspace.activeDocument else { return .ok }
                let ok = try await saveDocument(doc, in: ctx.workspace, askForName: doc.fileURL == nil)
                return CommandResult(message: ok ? L10n.tr("Zapisano \(doc.title)") : nil)
            },
            Command(CommandDescriptor(id: "file.saveAs", title: L10n.tr("Zapisz jako…"), category: .file, mac: ["cmd+shift+s"],
                                      agent: .none, effect: .external, summary: L10n.tr("Zapisuje okno pod nową nazwą."),
                                      feature: "PD-SQLW-012"),
                    validate: { $0.activeDocument != nil }) { ctx in
                guard let doc = ctx.workspace.activeDocument else { return .ok }
                _ = try await saveDocument(doc, in: ctx.workspace, askForName: true)
                return .ok
            },
            Command(CommandDescriptor(id: "file.encoding", title: L10n.tr("Kodowanie pliku…"), category: .file,
                                      parameters: [CommandParameter("encoding", .string, required: true, L10n.tr("Kodowanie"), allowed: TextFileCodec.encodingNames)],
                                      agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Jawnie zmienia kodowanie, w którym okno zostanie zapisane (UTF-8, ISO-8859-2, Windows-1250); znaki spoza kodowania są wskazywane."),
                                      feature: "PC-ENC-001"),
                    validate: { $0.activeDocument != nil }) { ctx in
                guard let doc = ctx.workspace.activeDocument, let name = ctx.arguments.string("encoding"), let enc = TextFileCodec.encoding(named: name) else {
                    throw CommandError.invalidArgument("encoding", TextFileCodec.encodingNames.joined(separator: ", "))
                }
                doc.fileFormat.encoding = enc
                doc.fileFormat.hasBOM = false
                doc.isModified = true
                if let bad = TextFileCodec.firstUnencodable(doc.text, encoding: enc) {
                    return CommandResult(message: L10n.tr("Kodowanie \(name); znak „\(bad.character)” (linia \(bad.line), kolumna \(bad.column)) trzeba zmienić przed zapisem"))
                }
                return CommandResult(message: L10n.tr("Kodowanie \(name)"))
            },
            Command(CommandDescriptor(id: "file.close", title: L10n.tr("Zamknij okno"), category: .file, mac: ["cmd+w"],
                                      agent: .full, effect: .uiState, summary: L10n.tr("Zamyka bieżące okno."), feature: "PD-UI-004"),
                    validate: { $0.activeDocument != nil }) { ctx in
                guard let doc = ctx.workspace.activeDocument else { return .ok }
                guard try await closeDocument(doc, in: ctx.workspace) else { throw CommandError.cancelledByUser }
                return .ok
            },
            Command(CommandDescriptor(id: "file.closeWindow", title: L10n.tr("Zamknij wskazane okno"), category: .file,
                                      parameters: [CommandParameter("document", .string, required: true, L10n.tr("Identyfikator okna"))],
                                      agent: .full, effect: .uiState, summary: L10n.tr("Zamyka okno o podanym identyfikatorze (z pytaniami o zapis i transakcję)."),
                                      inMenu: false, feature: "PD-UI-004")) { ctx in
                guard let s = ctx.arguments.string("document"), let d = ctx.workspace.documents.first(where: { $0.id.description == s }) else {
                    throw CommandError.invalidArgument("document", L10n.tr("nieznane okno"))
                }
                guard try await closeDocument(d, in: ctx.workspace) else { throw CommandError.cancelledByUser }
                return .ok
            },
            closeMany("file.closeOthers", L10n.tr("Zamknij pozostałe okna"), L10n.tr("Zamyka wszystkie okna oprócz bieżącego.")) { i, a in i != a },
            closeMany("file.closeLeft", L10n.tr("Zamknij okna z lewej"), L10n.tr("Zamyka okna na lewo od bieżącego.")) { i, a in i < a },
            closeMany("file.closeRight", L10n.tr("Zamknij okna z prawej"), L10n.tr("Zamyka okna na prawo od bieżącego.")) { i, a in i > a },
            Command(CommandDescriptor(id: "file.closeAll", title: L10n.tr("Zamknij wszystkie okna"), category: .file,
                                      mac: ["cmd+alt+w"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zamyka wszystkie okna."), feature: "PD-UI-004"),
                    validate: { !$0.documents.isEmpty }) { ctx in
                for d in ctx.workspace.documents {
                    ctx.workspace.activate(d.id)
                    guard try await closeDocument(d, in: ctx.workspace) else { throw CommandError.cancelledByUser }
                }
                return .ok
            },
            .planned(CommandDescriptor(id: "file.print", title: L10n.tr("Drukuj…"), category: .file, mac: ["cmd+p"],
                                       agent: .none, effect: .external, summary: L10n.tr("Drukuje bieżące okno."),
                                       stage: 8, feature: "PD-SQLW-016")),
        ]
    }

    // MARK: Edycja

    /// Okno z edytorem tekstu (SQL, Command, program, test).
    @MainActor
    static func editable(_ ws: Workspace) -> Document? {
        guard let d = ws.activeDocument, [.sql, .command, .program, .test].contains(d.kind) else { return nil }
        return d
    }

    /// Komenda zmieniająca tekst edytora czystą funkcją (cofalne w edytorze — zmiana trafia przez model).
    @MainActor
    static func editCommand(_ id: String, _ title: String, pd: [String] = [], mac: [String]? = nil, summary: String, feature: String,
                            _ transform: @escaping @Sendable (String, Range<Int>) -> TextEdit) -> Command {
        Command(CommandDescriptor(id: CommandID(rawValue: id), title: title, category: .edit, submenu: L10n.tr("Zaznaczenie"), pd: pd, mac: mac,
                                  agent: .full, effect: .modifiesEditor, summary: summary, feature: feature),
                validate: { editable($0) != nil }) { ctx in
            guard let doc = editable(ctx.workspace) else { return .ok }
            let len = (doc.text as NSString).length
            let sel = min(doc.selectedRange.lowerBound, len)..<min(doc.selectedRange.upperBound, len)
            let e = transform(doc.text, sel)
            doc.text = e.text
            doc.selectedRange = e.selection
            return .ok
        }
    }

    /// Identyfikator (z kropkami: schemat.pakiet.element) obejmujący pozycję.
    static func identifier(at offset: Int, in text: String) -> (String, Range<Int>)? {
        let ns = text as NSString
        func isIdent(_ c: unichar) -> Bool {
            guard let s = Unicode.Scalar(c) else { return false }
            return CharacterSet.alphanumerics.contains(s) || c == 0x5F || c == 0x24 || c == 0x23 || c == 0x2E || c == 0x22
        }
        var a = min(offset, ns.length)
        var b = a
        while a > 0, isIdent(ns.character(at: a - 1)) { a -= 1 }
        while b < ns.length, isIdent(ns.character(at: b)) { b += 1 }
        guard b > a else { return nil }
        var w = ns.substring(with: NSRange(location: a, length: b - a))
        w = w.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return w.isEmpty ? nil : (w.replacingOccurrences(of: "\"", with: ""), a..<b)
    }

    @MainActor
    static func findNext(_ ctx: CommandContext, backwards: Bool) throws -> CommandResult {
        guard let doc = editable(ctx.workspace), let search = ctx.workspace.lastSearch else { return .ok }
        let from = backwards ? doc.selectedRange.lowerBound : doc.selectedRange.upperBound
        guard let r = try search.next(in: doc.text, from: from, backwards: backwards) else {
            return CommandResult(message: L10n.tr("Nie znaleziono „\(search.pattern)”"))
        }
        doc.selectedRange = r
        return .ok
    }

    @MainActor static var edit: [Command] {
        [
            Command(CommandDescriptor(id: "edit.find", title: L10n.tr("Znajdź i zamień…"), category: .edit, pd: ["ctrl+f"], mac: ["cmd+f"],
                                      agent: .none, effect: .uiState, summary: L10n.tr("Wyszukiwanie i zamiana w edytorze (tekst albo wyrażenie regularne)."),
                                      feature: "PD-EDIT-008"),
                    validate: { editable($0) != nil }) { ctx in
                ctx.workspace.ui?.showFindReplace()
                return .ok
            },
            Command(CommandDescriptor(id: "edit.findNext", title: L10n.tr("Znajdź następne"), category: .edit, pd: ["f3"], mac: ["cmd+g"],
                                      agent: .full, effect: .uiState, summary: L10n.tr("Zaznacza następne wystąpienie ostatnio szukanego tekstu."),
                                      feature: "PD-EDIT-008"),
                    validate: { editable($0) != nil && $0.lastSearch != nil }) { ctx in try findNext(ctx, backwards: false) },
            Command(CommandDescriptor(id: "edit.findPrevious", title: L10n.tr("Znajdź poprzednie"), category: .edit, pd: ["shift+f3"], mac: ["cmd+shift+g"],
                                      agent: .full, effect: .uiState, summary: L10n.tr("Zaznacza poprzednie wystąpienie ostatnio szukanego tekstu."),
                                      feature: "PD-EDIT-008"),
                    validate: { editable($0) != nil && $0.lastSearch != nil }) { ctx in try findNext(ctx, backwards: true) },
            Command(CommandDescriptor(id: "edit.gotoLine", title: L10n.tr("Przejdź do linii…"), category: .edit, pd: ["ctrl+g"], mac: ["cmd+l"],
                                      parameters: [CommandParameter("line", .integer, L10n.tr("Numer linii (od 1)"))],
                                      agent: .full, effect: .uiState, summary: L10n.tr("Przenosi kursor do linii."), feature: "PD-EDIT-010"),
                    validate: { editable($0) != nil }) { ctx in
                guard let doc = editable(ctx.workspace) else { return .ok }
                var line = ctx.arguments.values["line"].flatMap { v -> Int? in
                    if case .int(let i) = v { return Int(i) }
                    return v.stringValue.flatMap(Int.init)
                }
                if line == nil {
                    let current = (doc.text as NSString).substring(to: min(doc.selectedRange.lowerBound, (doc.text as NSString).length))
                        .components(separatedBy: "\n").count
                    guard let answer = await ctx.workspace.ui?.askText(L10n.tr("Przejdź do linii"), message: L10n.tr("Numer linii:"), defaultValue: String(current)) else {
                        return .ok
                    }
                    line = Int(answer.trimmingCharacters(in: .whitespaces))
                }
                guard let l = line, l > 0 else { throw CommandError.invalidArgument("line", L10n.tr("liczba od 1")) }
                let o = TextEditing.offset(ofLine: l, in: doc.text)
                doc.selectedRange = o..<o
                return .ok
            },
            Command(CommandDescriptor(id: "edit.beautify", title: L10n.tr("Formatuj kod PL/SQL"), category: .edit,
                                      mac: ["cmd+shift+f"], agent: .full, effect: .modifiesEditor,
                                      summary: L10n.tr("Formatuje całe źródło albo zaznaczone linie według reguł formatera; zmienia tylko odstępy, układ linii i wielkość liter."),
                                      feature: "PD-BEAU-002"),
                    validate: { editable($0) != nil }) { ctx in
                guard let doc = editable(ctx.workspace) else { return .ok }
                let options = ctx.workspace.settings.beautifier
                let len = (doc.text as NSString).length
                let sel = min(doc.selectedRange.lowerBound, len)..<min(doc.selectedRange.upperBound, len)
                if sel.isEmpty {
                    let f = try Beautifier.format(doc.text, options: options)
                    let caret = min(sel.lowerBound, (f as NSString).length)
                    doc.text = f
                    doc.selectedRange = caret..<caret
                } else {
                    let (f, range) = try Beautifier.format(doc.text, range: sel, options: options)
                    doc.text = f
                    doc.selectedRange = range
                }
                return CommandResult(message: L10n.tr("Sformatowano"))
            },
            Command(CommandDescriptor(id: "edit.codeAssistant", title: L10n.tr("Podpowiedź kodu"), category: .edit,
                                      pd: ["ctrl+space"], mac: ["alt+escape", "ctrl+space"], agent: .read, effect: .none,
                                      summary: L10n.tr("Lista kolumn, elementów pakietu, pól rekordu, deklaracji i obiektów pasujących do pozycji kursora."),
                                      feature: "PD-CA-001"),
                    validate: { editable($0) != nil }) { ctx in
                guard let doc = editable(ctx.workspace) else { return .ok }
                let m = ctx.workspace.metadata(for: ctx.workspace.effectiveConnection(of: doc))
                guard let r = await CodeAssistant.complete(text: doc.text, offset: doc.selectedRange.lowerBound, metadata: m) else {
                    return CommandResult(message: L10n.tr("Brak podpowiedzi"))
                }
                ctx.ui?.showCompletion(r, for: doc)
                // Agent dostaje listę (bez zmiany tekstu).
                return CommandResult(message: r.items.prefix(200).map(\.label).joined(separator: ", "))
            },
            Command(CommandDescriptor(id: "edit.refreshCodeAssistant", title: L10n.tr("Odśwież podpowiedzi kodu"), category: .edit,
                                      agent: .full, effect: .uiState,
                                      summary: L10n.tr("Czyści pamięć podręczną słownika używaną przez podpowiedzi (np. po zmianie tabel w innej sesji)."),
                                      feature: "PD-CA-009"),
                    validate: { ws in editable(ws).flatMap { ws.metadata(for: ws.effectiveConnection(of: $0)) } != nil }) { ctx in
                guard let doc = editable(ctx.workspace) else { return .ok }
                ctx.workspace.metadata(for: ctx.workspace.effectiveConnection(of: doc))?.refresh()
                return .ok
            },
            Command(CommandDescriptor(id: "edit.fold", title: L10n.tr("Zwiń blok"), category: .edit,
                                      pd: ["cmd+alt+left"], mac: ["cmd+alt+left"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zwija blok, IF, LOOP albo CASE zaczynający się w linii kursora lub najbliższy obejmujący kursor."),
                                      feature: "PD-EDIT-013"),
                    validate: { editable($0) != nil }) { ctx in
                guard let doc = editable(ctx.workspace) else { return .ok }
                let caret = doc.selectedRange.lowerBound
                let regions = CodeFolding.regions(doc.text)
                let line = TextEditing.line(containing: caret, in: doc.text)
                // Najpierw obszar zaczynający się w linii kursora, potem najmniejszy niezwinięty obejmujący kursor.
                guard let r = regions.first(where: { $0.startLine == line && !doc.foldedStarts.contains($0.start) })
                        ?? regions.filter({ $0.startLine <= line && $0.endLine >= line && !doc.foldedStarts.contains($0.start) })
                                  .max(by: { $0.startLine < $1.startLine }) else {
                    throw CommandError.notAvailable(L10n.tr("Brak bloku do zwinięcia"))
                }
                doc.foldedStarts.insert(r.start)
                // Kursor nie zostaje w ukrytym tekście.
                if r.hidden.contains(caret) { doc.selectedRange = r.start..<r.start }
                return .ok
            },
            Command(CommandDescriptor(id: "edit.unfold", title: L10n.tr("Rozwiń blok"), category: .edit,
                                      pd: ["cmd+alt+right"], mac: ["cmd+alt+right"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Rozwija zwinięty blok w linii kursora."), feature: "PD-EDIT-013"),
                    validate: { editable($0).map { !$0.foldedStarts.isEmpty } ?? false }) { ctx in
                guard let doc = editable(ctx.workspace) else { return .ok }
                let line = TextEditing.line(containing: doc.selectedRange.lowerBound, in: doc.text)
                let hit = CodeFolding.regions(doc.text).filter { doc.foldedStarts.contains($0.start) && $0.startLine <= line && $0.endLine >= line }
                guard let r = hit.max(by: { $0.startLine < $1.startLine }) else { throw CommandError.notAvailable(L10n.tr("Brak zwiniętego bloku")) }
                doc.foldedStarts.remove(r.start)
                return .ok
            },
            Command(CommandDescriptor(id: "edit.foldAll", title: L10n.tr("Zwiń wszystko"), category: .edit,
                                      pd: ["cmd+alt+shift+left"], mac: ["cmd+alt+shift+left"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zwija wszystkie bloki podprogramów i struktur sterujących."), feature: "PD-EDIT-013"),
                    validate: { editable($0) != nil }) { ctx in
                guard let doc = editable(ctx.workspace) else { return .ok }
                let regions = CodeFolding.regions(doc.text)
                doc.foldedStarts = Set(regions.map(\.start))
                if let r = regions.first(where: { $0.hidden.contains(doc.selectedRange.lowerBound) }) { doc.selectedRange = r.start..<r.start }
                return .ok
            },
            Command(CommandDescriptor(id: "edit.unfoldAll", title: L10n.tr("Rozwiń wszystko"), category: .edit,
                                      pd: ["cmd+alt+shift+right"], mac: ["cmd+alt+shift+right"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Rozwija wszystkie zwinięte bloki."), feature: "PD-EDIT-013"),
                    validate: { editable($0).map { !$0.foldedStarts.isEmpty } ?? false }) { ctx in
                editable(ctx.workspace)?.foldedStarts = []
                return .ok
            },
            Command(CommandDescriptor(id: "edit.gotoDeclaration", title: L10n.tr("Przejdź do deklaracji"), category: .edit,
                                      pd: ["ctrl+alt+d"], mac: ["ctrl+cmd+j"], agent: .full, effect: .uiState,
                                      summary: L10n.tr("Deklaracja identyfikatora pod kursorem: lokalna (zmienna, parametr, podprogram) albo obiekt bazy."),
                                      feature: "PD-CA-012"),
                    validate: { editable($0) != nil }) { ctx in
                guard let doc = editable(ctx.workspace) else { return .ok }
                guard let (word, _) = identifier(at: doc.selectedRange.lowerBound, in: doc.text) else {
                    throw CommandError.notAvailable(L10n.tr("Brak identyfikatora pod kursorem"))
                }
                let parts = word.split(separator: ".").map(String.init)
                // Lokalnie: zmienna, parametr, kursor, typ, podprogram w zarysie kodu.
                if parts.count == 1, let d = PLSQLOutline.declaration(of: word, at: doc.selectedRange.lowerBound, in: PLSQLOutline.parse(doc.text)) {
                    ctx.workspace.recordJump()
                    doc.selectedRange = d.nameOffset..<(d.nameOffset + (d.name as NSString).length)
                    return CommandResult(message: "\(d.kind.rawValue) \(d.name)")
                }
                // Obiekt bazy (pakiet, tabela…) — źródło albo DDL w nowym oknie.
                guard let m = ctx.workspace.metadata(for: ctx.workspace.effectiveConnection(of: doc)) else {
                    throw CommandError.notAvailable(L10n.tr("Nie znaleziono deklaracji „\(word)”"))
                }
                var found = try await m.find(parts.count >= 2 ? parts.prefix(2).joined(separator: ".") : word)
                if found == nil, parts.count >= 2 { found = try await m.find(parts[0]) }
                guard let o = found else {
                    throw CommandError.notAvailable(L10n.tr("Nie znaleziono deklaracji „\(word)”"))
                }
                ctx.workspace.recordJump()
                return try await ctx.workspace.invoke("ob.edit", CommandArguments(["object": .string("\(o.owner).\(o.name)"), "type": .string(o.type.rawValue)]),
                                                      invoker: ctx.invoker)
            },
            Command(CommandDescriptor(id: "edit.recallStatement", title: L10n.tr("Historia poleceń…"), category: .edit, pd: ["ctrl+e"],
                                      mac: ["cmd+shift+h"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Wstawia wcześniej wykonane polecenie (globalna historia, bez poleceń z hasłami)."), feature: "PD-EDIT-009"),
                    validate: { editable($0) != nil }) { ctx in
                ctx.workspace.ui?.showRecallStatement()
                return .ok
            },
            editCommand("edit.commentLine", L10n.tr("Komentarz linii"), pd: ["ctrl+-"], mac: ["cmd+/"],
                        summary: L10n.tr("Dodaje lub usuwa -- na początku zaznaczonych linii."), feature: "PD-EDIT-006") {
                TextEditing.toggleLineComment($0, selection: $1)
            },
            editCommand("edit.duplicateLine", L10n.tr("Powiel linię"), mac: ["cmd+shift+d"],
                        summary: L10n.tr("Powiela bieżącą linię albo zaznaczone linie."), feature: "PD-EDIT-020") {
                TextEditing.duplicateLines($0, selection: $1)
            },
            editCommand("edit.uppercase", L10n.tr("Wielkie litery"), mac: ["cmd+alt+u"],
                        summary: L10n.tr("Zamienia zaznaczenie na wielkie litery (bez literałów)."), feature: "PD-EDIT-005") {
                TextEditing.changeCase($0, selection: $1, upper: true)
            },
            editCommand("edit.lowercase", L10n.tr("Małe litery"), mac: ["cmd+alt+shift+u"],
                        summary: L10n.tr("Zamienia zaznaczenie na małe litery (bez literałów)."), feature: "PD-EDIT-005") {
                TextEditing.changeCase($0, selection: $1, upper: false)
            },
            editCommand("edit.indent", L10n.tr("Zwiększ wcięcie"), mac: ["cmd+]"],
                        summary: L10n.tr("Wcina zaznaczone linie."), feature: "PD-EDIT-005") { t, s in
                TextEditing.indent(t, selection: s)
            },
            editCommand("edit.outdent", L10n.tr("Zmniejsz wcięcie"), mac: ["cmd+["],
                        summary: L10n.tr("Cofa wcięcie zaznaczonych linii."), feature: "PD-EDIT-005") { t, s in
                TextEditing.indent(t, selection: s, outdent: true)
            },
            editCommand("edit.removeTrailingSpaces", L10n.tr("Usuń końcowe spacje"),
                        summary: L10n.tr("Usuwa spacje i tabulacje na końcach linii (zaznaczenie albo cały tekst)."), feature: "PD-EDIT-005") {
                TextEditing.removeTrailingSpaces($0, selection: $1)
            },
        ]
    }

    // MARK: Sesja

    @MainActor static var session: [Command] {
        [
            .planned(CommandDescriptor(id: "session.kill", title: L10n.tr("Zakończ sesję okna (Kill)"), category: .session,
                                       agent: .none, effect: .modifiesDatabase, summary: L10n.tr("Kończy sesję bazy okna, gdy Przerwij nie działa."),
                                       stage: 1, feature: "PD-CONN-027")),
            .planned(CommandDescriptor(id: "session.setPassword", title: L10n.tr("Zmień hasło…"), category: .session,
                                       agent: .none, effect: .settings, summary: L10n.tr("Zmienia hasło w bazie i w definicji połączenia."),
                                       stage: 1, feature: "PD-CONN-017")),
            .planned(CommandDescriptor(id: "session.sqlTrace", title: L10n.tr("SQL Trace"), category: .session,
                                       agent: .none, effect: .settings, summary: L10n.tr("Włącza lub wyłącza SQL Trace sesji okna."),
                                       stage: 3, feature: "PD-OPT-008")),
        ]
    }

    // MARK: Debugowanie (skróty do weryfikacji — docs/research/keys.md)

    @MainActor static var debug: [Command] { DebugCommands.all }

    // MARK: Narzędzia

    @MainActor static var tools: [Command] {
        let t: [(String, String, [String], Int, String, AgentAccess)] = [
        ]
        return t.map { id, title, pd, stage, feature, agent in
            .planned(CommandDescriptor(id: CommandID(rawValue: id), title: title, category: .tools, pd: pd, mac: pd.isEmpty ? [] : nil,
                                       agent: agent, effect: agent == .approval ? .modifiesDatabase : .none,
                                       summary: title, stage: stage, feature: feature))
        }
    }

    @MainActor static var reports: [Command] {
        [
        ]
    }

    // MARK: Widok

    @MainActor static var view: [Command] {
        [
            Command(CommandDescriptor(id: "view.commandPalette", title: L10n.tr("Paleta komend…"), category: .view,
                                      pd: ["cmd+shift+p"], mac: ["cmd+shift+p"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Wyszukuje i wykonuje komendę po nazwie."), feature: "PD-UI-007")) { ctx in
                ctx.ui?.showCommandPalette()
                return .ok
            },
            Command(CommandDescriptor(id: "view.codeContents", title: L10n.tr("Zawartość kodu"), category: .view,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Pokazuje lub ukrywa panel Zawartość kodu (struktura jednostek) obok edytora okna programu."),
                                      feature: "PD-CA-010")) { ctx in
                ctx.workspace.settings.showCodeContents.toggle()
                return .ok
            },
            .planned(CommandDescriptor(id: "view.objectBrowser", title: L10n.tr("Przeglądarka obiektów"), category: .view,
                                       agent: .none, effect: .uiState, summary: L10n.tr("Pokazuje lub ukrywa Przeglądarkę obiektów."),
                                       stage: 2, feature: "PD-OB-001")),
        ]
    }

    // MARK: Okno

    @MainActor static var window: [Command] {
        [
            Command(CommandDescriptor(id: "window.next", title: L10n.tr("Następne okno"), category: .window,
                                      pd: ["ctrl+tab"], mac: ["cmd+shift+]", "ctrl+tab"], agent: .full, effect: .uiState,
                                      summary: L10n.tr("Aktywuje następne okno z Listy okien."), feature: "PD-UI-004"),
                    validate: { $0.documents.count > 1 }) { ctx in
                ctx.workspace.cycleDocuments(forward: true)
                return .ok
            },
            Command(CommandDescriptor(id: "window.previous", title: L10n.tr("Poprzednie okno"), category: .window,
                                      pd: ["ctrl+shift+tab"], mac: ["cmd+shift+[", "ctrl+shift+tab"], agent: .full, effect: .uiState,
                                      summary: L10n.tr("Aktywuje poprzednie okno z Listy okien."), feature: "PD-UI-004"),
                    validate: { $0.documents.count > 1 }) { ctx in
                ctx.workspace.cycleDocuments(forward: false)
                return .ok
            },
        ]
    }

    // MARK: Pomoc

    @MainActor static var help: [Command] {
        [
            .planned(CommandDescriptor(id: "help.context", title: L10n.tr("Pomoc kontekstowa (dokumentacja Oracle)"), category: .help,
                                       pd: ["f1"], mac: ["f1"], agent: .none, effect: .external,
                                       summary: L10n.tr("Szuka słowa pod kursorem w dokumentacji Oracle."), stage: 2, feature: "PD-EDIT-026")),
        ]
    }
}
