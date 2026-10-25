import Foundation
import PelikanSQL

/// Zmiana tekstu okna wykonana przez agenta (cofanie sesji agenta, PROMPT §7.6).
public struct AgentEdit: Sendable, Hashable {
    public var session: String
    public var document: DocumentID
    public var before: String
    public var after: String
    /// Okno utworzone przez agenta (cofnięcie je zamyka).
    public var created: Bool
}

extension Workspace {
    /// Klucz wewnętrzny z połączeniem ustalonym przez bramkę uprawnień (agent go nie poda — klucze `__` są usuwane):
    /// zgoda, podgląd i wykonanie dotyczą tego samego połączenia, nawet gdy w trakcie zgody zmieni się aktywne okno.
    public static let agentConnectionKey = "__connectionID"

    /// Klucz wewnętrzny z poleceniami z podglądu, na które zgodził się użytkownik (ustawia bramka; agent go nie poda):
    /// komenda czytająca polecenia z okna (agent.compile) wykonuje dokładnie je, nawet gdy w trakcie zgody zmieni się
    /// tekst okna albo aktywne okno (np. replace_range czy navigate_to agenta).
    public static let agentStatementsKey = "__statements"

    /// Podgląd do okna zgody i argumenty do wykonania po zgodzie — z przypiętymi poleceniami podglądu.
    public func agentApprovalPreview(_ id: CommandID, _ arguments: CommandArguments, invoker: Invoker) async throws -> (EffectPreview, CommandArguments) {
        let preview = try await self.preview(id, arguments, invoker: invoker)
        var pinned = arguments
        pinned[Self.agentStatementsKey] = .array(preview.statements.map { .string($0) })
        return (preview, pinned)
    }

    /// Połączenie narzędzia agenta: przypięte przez bramkę albo z aliasu w argumencie `connection`.
    public func agentConnection(_ arguments: CommandArguments) throws -> ConnectionDefinition {
        if let raw = arguments.string(Self.agentConnectionKey) {
            guard let id = UUID(uuidString: raw), let def = connections.connection(id), def.agent.visibleToAgent else { throw CommandError.notConnected }
            return def
        }
        return try agentConnection(alias: arguments.string("connection"))
    }

    /// Połączenie widoczne dla agenta pod aliasem (PROMPT §7.3 p.1); bez aliasu — połączenie aktywnego okna albo główne.
    public func agentConnection(alias: String?) throws -> ConnectionDefinition {
        if let alias, !alias.isEmpty {
            guard let def = connections.connections.first(where: { $0.agentAlias.caseInsensitiveCompare(alias) == .orderedSame && $0.agent.visibleToAgent }) else {
                throw CommandError.invalidArgument("connection", L10n.tr("nieznane połączenie „\(alias)”"))
            }
            return def
        }
        let id = activeDocument.flatMap { effectiveConnection(of: $0) } ?? sessions.mainConnectionID
        guard let id, let def = connections.connection(id), def.agent.visibleToAgent else { throw CommandError.notConnected }
        return def
    }

    /// Okno wskazane przez agenta identyfikatorem z `get_state` (bez — aktywne).
    /// Okno do zmiany tekstu przez agenta: okno tylko do odczytu (Plik › Tylko do odczytu) jest odrzucane (PD-FILE-003).
    func agentEditableDocument(_ id: String?) throws -> Document {
        let d = try agentDocument(id)
        guard !d.isReadOnly else { throw CommandError.notAvailable(L10n.tr("Okno „\(d.title)” jest tylko do odczytu")) }
        return d
    }

    /// Okno poleceń jest poza zasięgiem agenta (PROMPT §7.3): jego tekst może zawierać `CONNECT u/hasło`, a tekst
    /// wstawiony przez agenta (SPOOL, HOST, CONNECT) wykonałby użytkownik jednym Execute.
    func agentDocument(_ id: String?) throws -> Document {
        let d: Document
        if let id, !id.isEmpty {
            guard let found = documents.first(where: { Self.agentWindowID($0) == id.lowercased() }) else {
                throw CommandError.invalidArgument("window", L10n.tr("nieznane okno „\(id)”"))
            }
            d = found
        } else {
            guard let active = activeDocument else { throw CommandError.notAvailable(L10n.tr("Brak aktywnego okna")) }
            d = active
        }
        guard d.kind != .command else { throw AgentDenial.permissionDenied(L10n.tr("okno poleceń jest niedostępne dla agenta")) }
        return d
    }

    nonisolated static func agentWindowID(_ d: Document) -> String { String(d.id.raw.uuidString.prefix(8)).lowercased() }

    func recordAgentEdit(_ ctx: CommandContext, _ doc: Document, before: String, created: Bool = false) {
        guard let s = ctx.invoker.agentSessionID else { return }
        agentEdits.append(AgentEdit(session: s, document: doc.id, before: before, after: doc.text, created: created))
    }

    /// Cofnięcie zmian edytorów sesji agenta w odwrotnej kolejności; okno zmienione później przez kogoś innego to
    /// konflikt (pomijany bez `force`). Zwraca liczbę cofniętych zmian i konflikty (tytuły okien).
    @discardableResult
    public func undoAgentEdits(session: String, force: Bool = false) -> (undone: Int, conflicts: [String]) {
        var undone = 0, conflicts: [String] = []
        for e in agentEdits.filter({ $0.session == session }).reversed() {
            guard let d = documents.first(where: { $0.id == e.document }) else { continue }
            if d.text != e.after && !force { conflicts.append(d.fullTitle); continue }
            if e.created { close(d.id) } else { d.text = e.before }
            undone += 1
        }
        agentEdits.removeAll { $0.session == session }
        return (undone, conflicts)
    }
}

/// Komendy agenta niezależne od bazy: połączenia, stan okien, edytor (PROMPT §7.5).
@MainActor
enum AgentCommands {
    static let windowParam = CommandParameter("window", .string, L10n.tr("Identyfikator okna z get_state (domyślnie aktywne)"))

    static func position(_ text: String, line: Int, column: Int = 1) -> Int {
        let ns = text as NSString
        var offset = 0, current = 1
        while current < line, offset < ns.length {
            let r = ns.lineRange(for: NSRange(location: offset, length: 0))
            offset = NSMaxRange(r)
            current += 1
        }
        return min(offset + max(0, column - 1), ns.length)
    }

    static func lineColumn(_ text: String, offset: Int) -> (Int, Int) {
        let ns = text as NSString
        let o = min(offset, ns.length)
        let before = ns.substring(to: o)
        let line = before.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        let nl = (before as NSString).range(of: "\n", options: .backwards)
        let col = (before as NSString).length - (nl.location == NSNotFound ? 0 : nl.location + 1) + 1
        return (line, col)
    }

    static var all: [Command] {
        [
            Command(CommandDescriptor(id: "agent.connections", title: L10n.tr("Połączenia (agent)"), category: .help,
                                      agent: .read, effect: .none,
                                      summary: L10n.tr("Połączenia widoczne dla agenta: alias, środowisko (dev/test/prod), czy połączone, czy agent może zmieniać dane. Bez danych logowania."),
                                      inMenu: false, feature: "AI-TOOL-001")) { ctx in
                let ws = ctx.workspace
                let list: [JSONValue] = ws.connections.connections.filter(\.agent.visibleToAgent).map { def in
                    let connected: Bool = if case .connected = ws.sessions.status(of: def.id) { true } else { false }
                    return .object([
                        "alias": .string(def.agentAlias),
                        "environment": .string(def.environment.rawValue),
                        "connected": .bool(connected),
                        "main": .bool(ws.sessions.mainConnectionID == def.id),
                        "changesAllowed": .bool(def.agent.allowChanges && !def.readOnly),
                    ])
                }
                return CommandResult(value: .array(list))
            },
            Command(CommandDescriptor(id: "agent.state", title: L10n.tr("Stan okien (agent)"), category: .help,
                                      agent: .read, effect: .none,
                                      summary: L10n.tr("Otwarte okna (identyfikator, rodzaj, tytuł, połączenie, zmienione, aktywne) i połączenie główne."),
                                      inMenu: false, feature: "AI-TOOL-001")) { ctx in
                let ws = ctx.workspace
                let windows: [JSONValue] = ws.documents.map { d in
                    let alias = ws.effectiveConnection(of: d).flatMap { ws.connections.connection($0) }.flatMap { $0.agent.visibleToAgent ? $0.agentAlias : nil }
                    return .object([
                        "window": .string(Workspace.agentWindowID(d)),
                        "kind": .string(d.kind.rawValue),
                        "title": .string(d.title),
                        "connection": alias.map { .string($0) } ?? .null,
                        "modified": .bool(d.isModified),
                        "active": .bool(ws.activeDocumentID == d.id),
                    ])
                }
                let main = ws.sessions.mainConnectionID.flatMap { ws.connections.connection($0) }.flatMap { $0.agent.visibleToAgent ? $0.agentAlias : nil }
                return CommandResult(value: untrusted(.object(["windows": .array(windows), "mainConnection": main.map { .string($0) } ?? .null])))
            },
            Command(CommandDescriptor(id: "agent.editor", title: L10n.tr("Treść edytora (agent)"), category: .help,
                                      parameters: [windowParam], agent: .read, effect: .none,
                                      summary: L10n.tr("Tekst okna, zaznaczenie, kursor (linia, kolumna) i komunikaty kompilacji."),
                                      inMenu: false, feature: "AI-TOOL-001")) { ctx in
                let d = try ctx.workspace.agentDocument(ctx.arguments.string("window"))
                let (line, col) = lineColumn(d.text, offset: d.selectedRange.lowerBound)
                let messages: [JSONValue] = d.compileMessages.map {
                    .object(["severity": .string($0.severity.rawValue), "unit": .string($0.unit), "line": .int(Int64($0.line)), "column": .int(Int64($0.column)), "text": .string($0.text)])
                }
                return CommandResult(value: untrusted(.object([
                    "window": .string(Workspace.agentWindowID(d)), "kind": .string(d.kind.rawValue), "text": .string(d.text),
                    "selection": .object(["start": .int(Int64(d.selectedRange.lowerBound)), "end": .int(Int64(d.selectedRange.upperBound))]),
                    "cursor": .object(["line": .int(Int64(line)), "column": .int(Int64(col))]),
                    "compileMessages": .array(messages),
                ])))
            },
            Command(CommandDescriptor(id: "agent.openEditor", title: L10n.tr("Nowe okno z tekstem (agent)"), category: .help,
                                      parameters: [CommandParameter("kind", .string, L10n.tr("Rodzaj okna"), allowed: ["sql", "program", "test"]),
                                                   CommandParameter("text", .string, L10n.tr("Tekst okna")),
                                                   CommandParameter("connection", .string, L10n.tr("Alias połączenia okna (domyślnie główne)"))],
                                      agent: .full, effect: .modifiesEditor,
                                      summary: L10n.tr("Otwiera nowe okno SQL, programu albo testu z tekstem (bez wykonania); cofnięcie sesji agenta je zamyka."),
                                      inMenu: false, feature: "AI-TOOL-002")) { ctx in
                let ws = ctx.workspace
                let kind = DocumentKind(rawValue: ctx.arguments.string("kind") ?? "sql") ?? .sql
                guard [.sql, .program, .test].contains(kind) else { throw CommandError.invalidArgument("kind", "sql, program, test") }
                let conn = try ctx.arguments.string("connection").map { try ws.agentConnection(alias: $0).id }
                let d = ws.newDocument(kind, text: ctx.arguments.string("text") ?? "")
                if let conn { d.connectionID = conn }
                ws.recordAgentEdit(ctx, d, before: "", created: true)
                return CommandResult(value: .object(["window": .string(Workspace.agentWindowID(d))]))
            },
            Command(CommandDescriptor(id: "agent.insertText", title: L10n.tr("Wstaw tekst (agent)"), category: .help,
                                      parameters: [windowParam, CommandParameter("text", .string, required: true, L10n.tr("Wstawiany tekst")),
                                                   CommandParameter("line", .integer, L10n.tr("Linia (od 1; domyślnie kursor)")),
                                                   CommandParameter("column", .integer, L10n.tr("Kolumna (od 1)"))],
                                      agent: .full, effect: .modifiesEditor,
                                      summary: L10n.tr("Wstawia tekst w oknie (w miejscu kursora albo podanej linii i kolumny), bez kompilacji ani wykonania."),
                                      inMenu: false, feature: "AI-TOOL-002")) { ctx in
                let d = try ctx.workspace.agentEditableDocument(ctx.arguments.string("window"))
                guard let text = ctx.arguments.string("text") else { throw CommandError.missingArgument("text") }
                let before = d.text
                let at = ctx.arguments.int("line").map { position(before, line: Int($0), column: Int(ctx.arguments.int("column") ?? 1)) }
                    ?? min(d.selectedRange.lowerBound, (before as NSString).length)
                d.text = (before as NSString).replacingCharacters(in: NSRange(location: at, length: 0), with: text)
                let end = at + (text as NSString).length
                d.selectedRange = end..<end
                ctx.workspace.recordAgentEdit(ctx, d, before: before)
                return .ok
            },
            Command(CommandDescriptor(id: "agent.replaceRange", title: L10n.tr("Zamień zakres linii (agent)"), category: .help,
                                      parameters: [windowParam, CommandParameter("fromLine", .integer, required: true, L10n.tr("Pierwsza linia (od 1)")),
                                                   CommandParameter("toLine", .integer, required: true, L10n.tr("Ostatnia linia (włącznie)")),
                                                   CommandParameter("text", .string, required: true, L10n.tr("Nowy tekst tych linii"))],
                                      agent: .full, effect: .modifiesEditor,
                                      summary: L10n.tr("Zamienia linie od–do w oknie na podany tekst, bez kompilacji ani wykonania."),
                                      inMenu: false, feature: "AI-TOOL-002")) { ctx in
                let d = try ctx.workspace.agentEditableDocument(ctx.arguments.string("window"))
                guard let from = ctx.arguments.int("fromLine"), let to = ctx.arguments.int("toLine"), from >= 1, to >= from,
                      var text = ctx.arguments.string("text") else { throw CommandError.missingArgument("fromLine, toLine, text") }
                let before = d.text
                let start = position(before, line: Int(from))
                let end = position(before, line: Int(to) + 1)
                let replacedEndsWithNewline = end > start && (before as NSString).substring(with: NSRange(location: end - 1, length: 1)) == "\n"
                if replacedEndsWithNewline, !text.hasSuffix("\n") { text += "\n" }
                d.text = (before as NSString).replacingCharacters(in: NSRange(location: start, length: end - start), with: text)
                d.selectedRange = start..<start
                ctx.workspace.recordAgentEdit(ctx, d, before: before)
                return .ok
            },
            Command(CommandDescriptor(id: "agent.navigate", title: L10n.tr("Przejdź do linii (agent)"), category: .help,
                                      parameters: [windowParam, CommandParameter("line", .integer, required: true, L10n.tr("Linia (od 1)"))],
                                      agent: .full, effect: .uiState,
                                      summary: L10n.tr("Aktywuje okno i ustawia kursor na początku linii."),
                                      inMenu: false, feature: "AI-TOOL-002")) { ctx in
                let d = try ctx.workspace.agentDocument(ctx.arguments.string("window"))
                let p = position(d.text, line: Int(ctx.arguments.int("line") ?? 1))
                ctx.workspace.activate(d.id)
                d.selectedRange = p..<p
                return .ok
            },
            Command(CommandDescriptor(id: "agent.format", title: L10n.tr("Formatuj kod (agent)"), category: .help,
                                      parameters: [windowParam], agent: .full, effect: .modifiesEditor,
                                      summary: L10n.tr("Formatuje cały tekst okna regułami formatera PL/SQL (tylko odstępy, układ linii, wielkość liter)."),
                                      inMenu: false, feature: "AI-TOOL-002")) { ctx in
                let d = try ctx.workspace.agentEditableDocument(ctx.arguments.string("window"))
                let before = d.text
                d.text = try Beautifier.format(before, options: ctx.workspace.settings.beautifier)
                ctx.workspace.recordAgentEdit(ctx, d, before: before)
                return .ok
            },
        ]
    }
}
