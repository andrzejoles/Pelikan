import Foundation

/// Narzędzia edytora: makra (PD-EDIT-015), Special Copy i Paste from host language (PD-EDIT-016), historia schowka
/// (PD-EDIT-024), zadania To-Do (PD-TODO-001).
@MainActor
enum EditorToolCommands {
    static func selectionOrAll(_ d: Document) -> String {
        let ns = d.text as NSString
        let sel = min(d.selectedRange.lowerBound, ns.length)..<min(d.selectedRange.upperBound, ns.length)
        return sel.isEmpty ? d.text : ns.substring(with: NSRange(location: sel.lowerBound, length: sel.count))
    }

    /// Komenda kopiowania jako literał w formacie (wbudowanym albo z katalogu danych).
    static func specialCopy(_ f: CopyFormat) -> Command {
        Command(CommandDescriptor(id: CommandID(rawValue: "edit.specialCopy." + f.id), title: f.name, category: .edit,
                                  submenu: L10n.tr("Kopiuj jako literał"), agent: .none, effect: .uiState,
                                  summary: L10n.tr("Kopiuje zaznaczenie (albo cały tekst) jako literał tekstowy języka \(f.name); agent dostaje wynik zamiast schowka."),
                                  feature: "PD-EDIT-016"),
                validate: { BuiltinCommands.editable($0) != nil }) { ctx in
            guard let d = BuiltinCommands.editable(ctx.workspace) else { return .ok }
            let text = f.copy(selectionOrAll(d))
            if ctx.invoker == .user {
                ctx.ui?.copyToClipboard(text, html: nil)
                ctx.workspace.recordClipboard(text)
            }
            return CommandResult(value: .string(text))
        }
    }

    static let macroParameter = CommandParameter("macro", .string, required: true, L10n.tr("Identyfikator makra z biblioteki"))

    /// Makro biblioteki z argumentu `macro` (identyfikator).
    static func macroIndex(_ ctx: CommandContext) throws -> Int {
        let raw = ctx.arguments.string("macro") ?? ""
        guard let id = UUID(uuidString: raw), let i = ctx.workspace.macroLibrary.macros.firstIndex(where: { $0.id == id }) else {
            throw CommandError.invalidArgument("macro", raw)
        }
        return i
    }

    /// Zmiana makra biblioteki z zapisem i odświeżeniem komend makr (skróty).
    static func updateMacro(_ ctx: CommandContext, _ change: (inout Macro) -> Void) throws {
        let i = try macroIndex(ctx)
        var lib = ctx.workspace.macroLibrary
        change(&lib.macros[i])
        ctx.workspace.updateMacros(lib)
    }

    static var all: [Command] {
        [
            Command(CommandDescriptor(id: "edit.macroRecord", title: L10n.tr("Nagrywaj makro"), category: .edit, submenu: L10n.tr("Makra"),
                                      pd: ["f11"], mac: ["f11"], agent: .none, effect: .uiState,
                                      summary: L10n.tr("Rozpoczyna albo kończy nagrywanie makra: wpisywany tekst i komendy edytora."),
                                      feature: "PD-EDIT-015")) { ctx in
                let on = ctx.workspace.toggleMacroRecording()
                return CommandResult(message: on ? L10n.tr("Nagrywanie makra…") : L10n.tr("Nagrywanie makra zakończone"))
            },
            Command(CommandDescriptor(id: "edit.macroPlay", title: L10n.tr("Odtwórz makro"), category: .edit, submenu: L10n.tr("Makra"),
                                      pd: ["f12"], mac: ["f12"], agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Odtwarza ostatnio nagrane makro w aktywnym oknie."), feature: "PD-EDIT-015"),
                    validate: { $0.currentMacro != nil && !$0.isRecordingMacro && BuiltinCommands.editable($0) != nil }) { ctx in
                guard let m = ctx.workspace.currentMacro else { throw CommandError.notAvailable(L10n.tr("Brak nagranego makra")) }
                try await ctx.workspace.play(m)
                return .ok
            },
            Command(CommandDescriptor(id: "edit.macroRepeat", title: L10n.tr("Odtwórz makro wielokrotnie…"), category: .edit, submenu: L10n.tr("Makra"),
                                      pd: ["shift+f12"], mac: ["shift+f12"],
                                      parameters: [CommandParameter("times", .integer, L10n.tr("Liczba powtórzeń"))],
                                      agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Odtwarza ostatnio nagrane makro podaną liczbę razy (Repeat Play)."), feature: "PD-EDIT-015"),
                    validate: { $0.currentMacro != nil && !$0.isRecordingMacro && BuiltinCommands.editable($0) != nil }) { ctx in
                guard let m = ctx.workspace.currentMacro else { throw CommandError.notAvailable(L10n.tr("Brak nagranego makra")) }
                var times = Int(ctx.arguments.int("times") ?? 0)
                if times <= 0 {
                    guard let answer = await ctx.ui?.askText(L10n.tr("Odtwórz makro wielokrotnie"), message: L10n.tr("Liczba powtórzeń:"), defaultValue: "10"),
                          let n = Int(answer.trimmingCharacters(in: .whitespaces)), n > 0 else { throw CommandError.cancelledByUser }
                    times = n
                }
                try await ctx.workspace.play(m, times: min(times, 10_000))
                return .ok
            },
            Command(CommandDescriptor(id: "edit.macroSave", title: L10n.tr("Zapisz makro w bibliotece…"), category: .edit, submenu: L10n.tr("Makra"),
                                      parameters: [CommandParameter("name", .string, L10n.tr("Nazwa makra")),
                                                   CommandParameter("key", .string, L10n.tr("Skrót klawiszowy, np. ctrl+shift+1"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Zapisuje ostatnio nagrane makro w bibliotece pod nazwą, opcjonalnie ze skrótem klawiszowym."),
                                      feature: "PD-EDIT-015"),
                    validate: { $0.currentMacro != nil }) { ctx in
                let ws = ctx.workspace
                guard var m = ws.currentMacro else { throw CommandError.notAvailable(L10n.tr("Brak nagranego makra")) }
                var name = ctx.arguments.string("name") ?? ""
                if name.isEmpty {
                    guard let n = await ctx.ui?.askText(L10n.tr("Zapisz makro"), message: L10n.tr("Nazwa makra:"), defaultValue: L10n.tr("Makro \(ws.macroLibrary.macros.count + 1)")),
                          !n.trimmingCharacters(in: .whitespaces).isEmpty else { throw CommandError.cancelledByUser }
                    name = n.trimmingCharacters(in: .whitespaces)
                }
                m.id = UUID()
                m.name = name
                if let k = ctx.arguments.string("key"), !k.isEmpty {
                    guard KeyChord(string: k) != nil else { throw CommandError.invalidArgument("key", L10n.tr("nieprawidłowy skrót")) }
                    m.key = k
                }
                var lib = ws.macroLibrary
                lib.macros.append(m)
                ws.updateMacros(lib)
                return CommandResult(message: L10n.tr("Zapisano makro „\(name)”"))
            },
            Command(CommandDescriptor(id: "edit.macroLibrary", title: L10n.tr("Biblioteka makr…"), category: .edit, submenu: L10n.tr("Makra"),
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Okno biblioteki makr: odtwarzanie, nazwy, skróty klawiszowe, usuwanie."), feature: "PD-EDIT-015")) { ctx in
                ctx.ui?.showMacroLibrary()
                return .ok
            },
            Command(CommandDescriptor(id: "edit.macroRename", title: L10n.tr("Zmień nazwę makra"), category: .edit, submenu: L10n.tr("Makra"),
                                      parameters: [macroParameter, CommandParameter("name", .string, required: true, L10n.tr("Nazwa makra"))],
                                      agent: .none, effect: .settings, summary: L10n.tr("Zmienia nazwę makra w bibliotece."), inMenu: false,
                                      feature: "PD-EDIT-015")) { ctx in
                guard let name = ctx.arguments.string("name")?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                    throw CommandError.missingArgument("name")
                }
                try updateMacro(ctx) { $0.name = name }
                return .ok
            },
            Command(CommandDescriptor(id: "edit.macroSetKey", title: L10n.tr("Skrót makra"), category: .edit, submenu: L10n.tr("Makra"),
                                      parameters: [macroParameter, CommandParameter("key", .string, L10n.tr("Skrót klawiszowy, np. ctrl+shift+1 (pusty — bez skrótu)"))],
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Ustawia albo usuwa skrót klawiszowy makra z biblioteki (skrót zajęty przez inną komendę jest pomijany)."),
                                      inMenu: false, feature: "PD-EDIT-015")) { ctx in
                let key = ctx.arguments.string("key")?.trimmingCharacters(in: .whitespaces) ?? ""
                if !key.isEmpty, KeyChord(string: key) == nil { throw CommandError.invalidArgument("key", L10n.tr("nieprawidłowy skrót")) }
                try updateMacro(ctx) { $0.key = key.isEmpty ? nil : key }
                return .ok
            },
            Command(CommandDescriptor(id: "edit.macroRemove", title: L10n.tr("Usuń makro"), category: .edit, submenu: L10n.tr("Makra"),
                                      parameters: [macroParameter], agent: .none, effect: .settings,
                                      summary: L10n.tr("Usuwa makro z biblioteki (po potwierdzeniu) razem z jego komendą i skrótem."), inMenu: false,
                                      feature: "PD-EDIT-015")) { ctx in
                let ws = ctx.workspace
                let macro = ws.macroLibrary.macros[try macroIndex(ctx)]
                if let ui = ctx.ui {
                    guard await ui.ask(L10n.tr("Usunąć makro „\(macro.name)”?"), message: L10n.tr("Makro zniknie z biblioteki razem ze skrótem."),
                                       buttons: [L10n.tr("Usuń"), L10n.tr("Anuluj")]) == 0 else { throw CommandError.cancelledByUser }
                }
                // Po potwierdzeniu biblioteka mogła się zmienić — usunięcie po identyfikatorze.
                var lib = ws.macroLibrary
                lib.macros.removeAll { $0.id == macro.id }
                ws.updateMacros(lib)
                return .ok
            },
        ] + CopyFormat.builtIn.map(specialCopy) + [
            Command(CommandDescriptor(id: "edit.pasteHostLanguage", title: L10n.tr("Wklej z języka programowania"), category: .edit,
                                      submenu: L10n.tr("Kopiuj jako literał"),
                                      parameters: [CommandParameter("text", .string, L10n.tr("Kod z literałem (domyślnie schowek)")),
                                                   CommandParameter("format", .string, L10n.tr("Identyfikator formatu (domyślnie wykrywany)"))],
                                      agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Wkleja SQL wydobyty z literałów tekstowych kodu (Java, C#, Delphi, VB…): cudzysłowy, sklejanie i escapy usunięte."),
                                      feature: "PD-EDIT-016"),
                    validate: { BuiltinCommands.editable($0) != nil }) { ctx in
                let ws = ctx.workspace
                let code = ctx.arguments.string("text") ?? (ctx.invoker == .user ? ctx.ui?.clipboardText() : nil) ?? ""
                guard !code.isEmpty else { throw CommandError.missingArgument("text") }
                let format = ctx.arguments.string("format").flatMap { id in CopyFormat.all(dataDirectory: ws.dataDirectory).first { $0.id == id } }
                let sql = format.map { $0.paste(code) } ?? CopyFormat.pasteDetecting(code)
                try ws.insertInEditor(sql)
                return CommandResult(value: .string(sql))
            },
            Command(CommandDescriptor(id: "view.clipboardHistory", title: L10n.tr("Historia schowka"), category: .view,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Lista tekstów skopiowanych w Pelikanie z filtrem i podglądem; dwuklik wkleja do edytora."),
                                      feature: "PD-EDIT-024")) { ctx in
                ctx.ui?.showClipboardHistory()
                return .ok
            },
            Command(CommandDescriptor(id: "edit.pasteFromHistory", title: L10n.tr("Wklej z historii schowka"), category: .edit,
                                      parameters: [CommandParameter("index", .integer, L10n.tr("Pozycja w historii (0 — najnowszy)"))],
                                      agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Wkleja wpis historii schowka w miejscu kursora."), feature: "PD-EDIT-024"),
                    validate: { BuiltinCommands.editable($0) != nil && !$0.clipboardHistory.entries.isEmpty }) { ctx in
                let ws = ctx.workspace
                let i = Int(ctx.arguments.int("index") ?? 0)
                guard ws.clipboardHistory.entries.indices.contains(i) else { throw CommandError.invalidArgument("index", L10n.tr("brak wpisu")) }
                let text = ws.clipboardHistory.entries[i].text
                try ws.insertInEditor(text)
                ws.recordClipboard(text)
                return .ok
            },
            Command(CommandDescriptor(id: "view.todoItems", title: L10n.tr("Zadania To-Do"), category: .view,
                                      agent: .none, effect: .uiState,
                                      summary: L10n.tr("Zadania TODO/DONE z komentarzy otwartych okien: priorytet, kategoria, właściciel; agent dostaje listę."),
                                      feature: "PD-TODO-001")) { ctx in
                if ctx.invoker == .user { ctx.ui?.showTodoItems(); return .ok }
                let list: [JSONValue] = ctx.workspace.documents.flatMap { d in
                    TodoItems.parse(d.text).map { i in
                        .object(["window": .string(d.title), "line": .int(Int64(i.line)), "text": .string(i.text), "closed": .bool(i.closed),
                                 "owner": i.owner.map { .string($0) } ?? .null, "priority": i.priority.map { .int(Int64($0)) } ?? .null,
                                 "category": i.category.map { .string($0) } ?? .null])
                    }
                }
                return CommandResult(value: .array(list))
            },
            Command(CommandDescriptor(id: "edit.todoInsert", title: L10n.tr("Wstaw zadanie To-Do"), category: .edit,
                                      parameters: [CommandParameter("owner", .string, L10n.tr("Właściciel zadania"))],
                                      agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Wstawia nad bieżącą linią komentarz „-- TODO: ” z wcięciem linii."), feature: "PD-TODO-001"),
                    validate: { BuiltinCommands.editable($0) != nil }) { ctx in
                guard let d = BuiltinCommands.editable(ctx.workspace) else { return .ok }
                try BuiltinCommands.checkWritable(d)
                let r = TodoItems.insert(in: d.text, at: d.selectedRange.lowerBound, owner: ctx.arguments.string("owner"))
                d.text = r.text
                d.selectedRange = r.caret..<r.caret
                return .ok
            },
            Command(CommandDescriptor(id: "edit.todoToggle", title: L10n.tr("Zamknij lub otwórz zadanie To-Do"), category: .edit,
                                      parameters: [CommandParameter("line", .integer, L10n.tr("Linia zadania (domyślnie linia kursora)"))],
                                      agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Zamienia TODO na DONE (zamknięcie) albo DONE na TODO w zadaniu z linii."), feature: "PD-TODO-001"),
                    validate: { BuiltinCommands.editable($0) != nil }) { ctx in
                guard let d = BuiltinCommands.editable(ctx.workspace) else { return .ok }
                try BuiltinCommands.checkWritable(d)
                let line = ctx.arguments.int("line").map(Int.init)
                    ?? (d.text as NSString).substring(to: min(d.selectedRange.lowerBound, (d.text as NSString).length)).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
                guard let item = TodoItems.parse(d.text).first(where: { $0.line == line }) else {
                    throw CommandError.notAvailable(L10n.tr("W linii \(line) nie ma zadania To-Do"))
                }
                let sel = d.selectedRange
                d.text = TodoItems.toggle(item, in: d.text)
                d.selectedRange = sel
                return .ok
            },
        ]
    }
}

extension Workspace {
    /// Formaty Special Copy z katalogu danych (spoza wbudowanych) jako komendy.
    func registerCopyFormatCommands() {
        // Nowe formaty i zmienione wbudowane (ten sam identyfikator — komenda zastępuje wbudowaną).
        let custom = CopyFormat.all(dataDirectory: dataDirectory).filter { !CopyFormat.builtIn.contains($0) }
        guard !custom.isEmpty else { return }
        register(custom.map(EditorToolCommands.specialCopy))
    }
}
