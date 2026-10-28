import Foundation
import PelikanSQL

/// Okno programu (UG 4): dodanie i usunięcie jednostki (PD-PROG-001), przywrócenie tekstu (Revert, PD-PROG-009).
enum ProgramUnitCommands {
    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "prog.addUnit", title: L10n.tr("Dodaj jednostkę…"), category: .file, submenu: L10n.tr("Okno programu"),
                                      parameters: [
                                          CommandParameter("template", .string, L10n.tr("Szablon jednostki: folder/nazwa albo nazwa (domyślnie procedura)")),
                                          CommandParameter("values", .object, L10n.tr("Wartości zmiennych szablonu (nazwa → tekst); brakujące — domyślne")),
                                          CommandParameter("text", .string, L10n.tr("Gotowy tekst jednostki zamiast szablonu")),
                                      ],
                                      agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Dodaje na końcu okna programu nową jednostkę (z szablonu albo z tekstu) jako kolejną kartę."),
                                      feature: "PD-PROG-001"),
                    validate: { programDocument($0) != nil }) { ctx in
                guard let doc = programDocument(ctx.workspace) else { throw CommandError.notAvailable(L10n.tr("Aktywne okno nie jest oknem programu")) }
                let original = doc.text
                var t = doc.text
                while let c = t.last, c.isWhitespace { t.removeLast() }
                if !t.isEmpty {
                    if t.last != "/" { t += "\n/" }
                    t += "\n\n"
                }
                if let text = ctx.arguments.string("text"), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    var unit = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if unit.last != "/" { unit += "\n/" }
                    let start = (t as NSString).length
                    doc.text = t + unit + "\n"
                    doc.selectedRange = start..<start
                    return CommandResult(message: L10n.tr("Dodano jednostkę"))
                }
                doc.text = t
                let end = (t as NSString).length
                doc.selectedRange = end..<end
                var args: [String: JSONValue] = ["template": .string(ctx.arguments.string("template") ?? TemplateLibrary.programFolder + "/" + L10n.tr("Procedura"))]
                if let v = ctx.arguments.values["values"] { args["values"] = v }
                do {
                    return try await ctx.workspace.invoke("edit.insertTemplate", CommandArguments(args), invoker: ctx.invoker)
                } catch {
                    doc.text = original
                    throw error
                }
            },
            Command(CommandDescriptor(id: "prog.removeUnit", title: L10n.tr("Usuń jednostkę"), category: .file, submenu: L10n.tr("Okno programu"),
                                      parameters: [
                                          CommandParameter("unit", .string, L10n.tr("Jednostka: nazwa albo „nazwa body” (domyślnie jednostka pod kursorem)")),
                                      ],
                                      agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Usuwa jednostkę (kartę) z tekstu okna programu razem z kończącym ukośnikiem; obiekt w bazie zostaje."),
                                      feature: "PD-PROG-001"),
                    validate: { ws in programDocument(ws) != nil }) { ctx in
                guard let doc = programDocument(ctx.workspace) else { throw CommandError.notAvailable(L10n.tr("Aktywne okno nie jest oknem programu")) }
                let units = doc.programUnits
                let unit: ProgramUnit
                if let spec = ctx.arguments.string("unit") {
                    let words = spec.uppercased().split(separator: " ").map(String.init)
                    let body = words.count > 1 && words[1] == "BODY"
                    // „nazwa body” — tylko ciało (nigdy specyfikacja w zastępstwie); sama nazwa — specyfikacja albo
                    // jedyna jednostka o tej nazwie.
                    guard let u = units.first(where: { $0.name == words.first && [.packageBody, .typeBody].contains($0.type) == body })
                            ?? (body ? nil : units.first(where: { $0.name == words.first })) else {
                        throw CommandError.invalidArgument("unit", L10n.tr("nie ma takiej jednostki"))
                    }
                    unit = u
                } else {
                    let caret = doc.selectedRange.lowerBound
                    // Okno z kartami: jednostka karty z kursorem (kursor na komentarzu przed CREATE jest już na karcie
                    // następnej jednostki, choć przed jej poleceniem).
                    let sorted = units.sorted { $0.range.lowerBound < $1.range.lowerBound }
                    let tabbed = doc.activeUnitTab.flatMap { sorted.indices.contains($0) && doc.programUnitTabs.count == sorted.count ? sorted[$0] : nil }
                    guard let u = tabbed ?? units.last(where: { $0.range.lowerBound <= caret }) ?? units.first else {
                        throw CommandError.notAvailable(L10n.tr("Brak jednostki"))
                    }
                    unit = u
                }
                if ctx.invoker == .user, let ui = ctx.ui {
                    let answer = await ui.ask(L10n.tr("Usunąć jednostkę \(unit.tabTitle) z okna?"),
                                              message: L10n.tr("Tekst jednostki zniknie z okna programu (można cofnąć). Obiekt w bazie nie jest usuwany."),
                                              buttons: [L10n.tr("Usuń"), L10n.tr("Anuluj")])
                    guard answer == 0 else { throw CommandError.cancelledByUser }
                }
                let start = (doc.text as NSString).lineRange(for: NSRange(location: unit.range.lowerBound, length: 0)).location
                doc.text = ProgramCompiler.removing(unit, from: doc.text)
                let c = min(start, (doc.text as NSString).length)
                doc.selectedRange = c..<c
                return CommandResult(message: L10n.tr("Usunięto jednostkę \(unit.tabTitle)"))
            },
            Command(CommandDescriptor(id: "prog.selectUnit", title: L10n.tr("Pokaż jednostkę…"), category: .file, submenu: L10n.tr("Okno programu"),
                                      parameters: [
                                          CommandParameter("unit", .string, L10n.tr("Karta: numer od 1, nazwa jednostki albo „nazwa body” (bez argumentu — wybór z listy)")),
                                      ],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Pokazuje w oknie programu kartę wskazanej jednostki (specyfikacji, ciała…); kursor wraca w miejsce, w którym był na tej karcie."),
                                      feature: "PD-PROG-001"),
                    validate: { tabbedDocument($0) != nil }) { ctx in
                let (doc, tabs) = try tabbed(ctx)
                let target: Int
                if let v = ctx.arguments.values["unit"] {
                    let spec: String
                    if case .int(let n) = v { spec = String(n) } else { spec = v.stringValue ?? "" }
                    guard let i = ProgramUnitTabs.find(spec, in: tabs) else {
                        throw CommandError.invalidArgument("unit", L10n.tr("nie ma takiej jednostki"))
                    }
                    target = i
                } else if let i = try await ctx.choose(L10n.tr("Pokaż jednostkę"), tabs.enumerated().map { ($0.element.title, $0.offset) }) {
                    return showUnit(target: i, doc, tabs, ctx).resolving(["unit": .string(tabs[i].key)])
                } else {
                    throw CommandError.missingArgument("unit")
                }
                return showUnit(target: target, doc, tabs, ctx)
            },
            Command(CommandDescriptor(id: "prog.nextUnit", title: L10n.tr("Następna jednostka"), category: .file, submenu: L10n.tr("Okno programu"),
                                      pd: ["ctrl+pagedown"], mac: ["alt+cmd+]"],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Pokazuje kartę następnej jednostki okna programu (po ostatniej — pierwszą)."),
                                      feature: "PD-PROG-001"),
                    validate: { tabbedDocument($0) != nil }) { ctx in
                let (doc, tabs) = try tabbed(ctx)
                return showUnit(target: ((doc.activeUnitTab ?? 0) + 1) % tabs.count, doc, tabs, ctx)
            },
            Command(CommandDescriptor(id: "prog.previousUnit", title: L10n.tr("Poprzednia jednostka"), category: .file, submenu: L10n.tr("Okno programu"),
                                      pd: ["ctrl+pageup"], mac: ["alt+cmd+["],
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Pokazuje kartę poprzedniej jednostki okna programu (przed pierwszą — ostatnią)."),
                                      feature: "PD-PROG-001"),
                    validate: { tabbedDocument($0) != nil }) { ctx in
                let (doc, tabs) = try tabbed(ctx)
                return showUnit(target: ((doc.activeUnitTab ?? 0) + tabs.count - 1) % tabs.count, doc, tabs, ctx)
            },
            Command(CommandDescriptor(id: "prog.revert", title: L10n.tr("Przywróć"), category: .file,
                                      parameters: [
                                          CommandParameter("source", .string, L10n.tr("Skąd: baseline — stan z otwarcia lub zapisu (domyślnie), database — źródło z bazy"),
                                                           allowed: ["baseline", "database"]),
                                      ],
                                      agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Odrzuca zmiany okna: przywraca tekst z chwili otwarcia, wczytania z bazy albo zapisu (albo ponownie wczytuje źródło jednostek z bazy)."),
                                      feature: "PD-PROG-009"),
                    validate: { ws in BuiltinCommands.editable(ws).map { $0.isModified && !$0.isReadOnly } ?? false }) { ctx in
                guard let doc = BuiltinCommands.editable(ctx.workspace) else { throw CommandError.notAvailable(L10n.tr("Brak aktywnego okna z tekstem")) }
                let fromDatabase = ctx.arguments.string("source") == "database"
                var text = doc.baselineText
                if fromDatabase {
                    guard doc.kind == .program else { throw CommandError.notAvailable(L10n.tr("Aktywne okno nie jest oknem programu")) }
                    guard let m = ctx.workspace.metadata(for: ctx.workspace.effectiveConnection(of: doc)) else { throw CommandError.notConnected }
                    text = try await CompareCommands.databaseText(of: doc.text, metadata: m)
                }
                if ctx.invoker == .user, doc.isModified, let ui = ctx.ui {
                    let answer = await ui.ask(L10n.tr("Odrzucić zmiany w oknie „\(doc.title)”?"),
                                              message: fromDatabase ? L10n.tr("Tekst zostanie zastąpiony źródłem z bazy.")
                                                  : L10n.tr("Tekst wróci do stanu z chwili otwarcia lub ostatniego zapisu."),
                                              buttons: [L10n.tr("Przywróć"), L10n.tr("Anuluj")])
                    guard answer == 0 else { throw CommandError.cancelledByUser }
                }
                let caret = doc.selectedRange.lowerBound
                doc.text = text
                // Stan bazowy (z otwarcia/zapisu) — okno niezmienione; źródło z bazy — zgodne z bazą, ale nie z plikiem.
                if fromDatabase { doc.isCompileStale = false } else { doc.isModified = false }
                let c = min(caret, (text as NSString).length)
                doc.selectedRange = c..<c
                return CommandResult(message: L10n.tr("Przywrócono tekst okna"))
            },
        ]
    }

    /// Aktywne okno programu z kartami jednostek (także tylko do odczytu — przełączanie kart nie zmienia tekstu).
    @MainActor
    static func tabbedDocument(_ ws: Workspace) -> Document? {
        guard let d = ws.activeDocument, d.kind == .program, d.unitTabCount > 1 else { return nil }
        return d
    }

    @MainActor
    static func tabbed(_ ctx: CommandContext) throws -> (Document, [ProgramUnitTab]) {
        guard let d = ctx.workspace.activeDocument, d.kind == .program else {
            throw CommandError.notAvailable(L10n.tr("Aktywne okno nie jest oknem programu"))
        }
        let tabs = d.programUnitTabs
        guard tabs.count > 1 else { throw CommandError.notAvailable(L10n.tr("Okno programu ma jedną jednostkę")) }
        return (d, tabs)
    }

    /// Przejście na kartę: zapamiętuje kursor bieżącej karty i stawia go tam, gdzie był na karcie docelowej (pierwszy
    /// raz — na początku linii nagłówka jednostki). Karta aktywna wynika z kursora (`Document.activeUnitTab`).
    @MainActor
    static func showUnit(target: Int, _ doc: Document, _ tabs: [ProgramUnitTab], _ ctx: CommandContext) -> CommandResult {
        let ns = doc.text as NSString
        let current = doc.activeUnitTab
        if let c = current {
            doc.unitCarets[tabs[c].key] = max(0, doc.selectedRange.lowerBound - tabs[c].segment.lowerBound)
        }
        let tab = tabs[target]
        if current != target {
            let header = ns.lineRange(for: NSRange(location: min(tab.sourceOffset, ns.length), length: 0)).location
            let wanted = doc.unitCarets[tab.key].map { tab.segment.lowerBound + $0 } ?? header
            let limit = ProgramUnitTabs.caretLimit(tab, isLast: target == tabs.count - 1, in: ns)
            let o = min(max(wanted, tab.segment.lowerBound), limit)
            ctx.workspace.recordJump()
            doc.selectedRange = o..<o
        }
        return CommandResult(message: tab.title, value: .int(Int64(target + 1)))
    }

    @MainActor
    static func programDocument(_ ws: Workspace) -> Document? {
        guard let d = ws.activeDocument, d.kind == .program, !d.isReadOnly else { return nil }
        return d
    }
}
