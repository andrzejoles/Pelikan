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
                                      agent: .full, effect: .modifiesEditor,
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
                                      agent: .full, effect: .modifiesEditor,
                                      summary: L10n.tr("Usuwa jednostkę (kartę) z tekstu okna programu razem z kończącym ukośnikiem; obiekt w bazie zostaje."),
                                      feature: "PD-PROG-001"),
                    validate: { ws in programDocument(ws).map { ProgramCompiler.units(in: $0.text).count > 0 } ?? false }) { ctx in
                guard let doc = programDocument(ctx.workspace) else { throw CommandError.notAvailable(L10n.tr("Aktywne okno nie jest oknem programu")) }
                let units = ProgramCompiler.units(in: doc.text)
                let unit: ProgramUnit
                if let spec = ctx.arguments.string("unit") {
                    let words = spec.uppercased().split(separator: " ").map(String.init)
                    let body = words.count > 1 && words[1] == "BODY"
                    guard let u = units.first(where: { $0.name == words.first && [.packageBody, .typeBody].contains($0.type) == body })
                            ?? units.first(where: { $0.name == words.first }) else {
                        throw CommandError.invalidArgument("unit", L10n.tr("nie ma takiej jednostki"))
                    }
                    unit = u
                } else {
                    let caret = doc.selectedRange.lowerBound
                    guard let u = units.last(where: { $0.range.lowerBound <= caret }) ?? units.first else {
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
            Command(CommandDescriptor(id: "prog.revert", title: L10n.tr("Przywróć"), category: .file,
                                      parameters: [
                                          CommandParameter("source", .string, L10n.tr("Skąd: baseline — stan z otwarcia lub zapisu (domyślnie), database — źródło z bazy"),
                                                           allowed: ["baseline", "database"]),
                                      ],
                                      agent: .full, effect: .modifiesEditor,
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

    @MainActor
    static func programDocument(_ ws: Workspace) -> Document? {
        guard let d = ws.activeDocument, d.kind == .program, !d.isReadOnly else { return nil }
        return d
    }
}
