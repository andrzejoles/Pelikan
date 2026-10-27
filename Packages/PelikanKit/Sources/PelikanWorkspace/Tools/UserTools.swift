import Foundation

/// Narzędzie użytkownika (UG 24.15, PD-TOOL-017): program zewnętrzny albo blok SQL dla sesji okna.
public struct UserTool: Sendable, Codable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable, CaseIterable { case external, session }
    /// Co zrobić z wyjściem programu zewnętrznego.
    public enum Output: String, Sendable, Codable, CaseIterable { case none, outputWindow, newWindow }

    public var id = UUID()
    public var name: String
    public var kind: Kind = .external
    /// Program: ścieżka bezwzględna albo nazwa szukana w katalogach systemowych (bez powłoki).
    public var program = ""
    /// Argumenty — każdy osobno, ze zmiennymi `#file`, `#object`… (rozwijane bez cytowania, bez powłoki).
    public var arguments: [String] = []
    public var workingDirectory = ""
    /// Blok SQL narzędzia sesji (zmienne jak w argumentach).
    public var sql = ""
    /// Narzędzie sesji: wykonać od razu w nowym oknie SQL (inaczej tylko otworzyć).
    public var executeImmediately = false
    /// Zapis pliku aktywnego okna przed uruchomieniem.
    public var saveBeforeRun = false
    public var output: Output = .outputWindow

    public init(name: String, kind: Kind = .external) { self.name = name; self.kind = kind }

    public var commandID: CommandID { CommandID(rawValue: "tools.user.\(id.uuidString.prefix(8).lowercased())") }
}

/// Zmienne narzędzi użytkownika. Celowo bez hasła, hosta, portu, usługi i nazwy użytkownika połączenia —
/// narzędzie dostaje tylko alias połączenia i schemat.
public struct UserToolContext: Sendable, Hashable {
    public var file = ""
    public var selection = ""
    public var owner = ""
    public var name = ""
    public var type = ""
    public var connection = ""
    public var schema = ""
    public var text = ""

    public init() {}

    public static let variables: [(String, String)] = [
        ("#file", L10n.tr("pełna ścieżka pliku aktywnego okna")),
        ("#filename", L10n.tr("nazwa pliku bez katalogu")),
        ("#filedir", L10n.tr("katalog pliku")),
        ("#fileext", L10n.tr("rozszerzenie pliku")),
        ("#selection", L10n.tr("zaznaczony tekst")),
        ("#text", L10n.tr("cały tekst aktywnego okna")),
        ("#object", L10n.tr("obiekt zaznaczony w Przeglądarce obiektów (SCHEMAT.NAZWA)")),
        ("#owner", L10n.tr("schemat obiektu")),
        ("#name", L10n.tr("nazwa obiektu")),
        ("#type", L10n.tr("typ obiektu")),
        ("#connection", L10n.tr("alias połączenia (bez danych logowania)")),
        ("#schema", L10n.tr("bieżący schemat sesji")),
    ]

    func value(_ variable: String) -> String? {
        let url = URL(fileURLWithPath: file)
        switch variable {
        case "#file": return file
        case "#filename": return file.isEmpty ? "" : url.lastPathComponent
        case "#filedir": return file.isEmpty ? "" : url.deletingLastPathComponent().path
        case "#fileext": return file.isEmpty ? "" : url.pathExtension
        case "#selection": return selection
        case "#text": return text
        case "#object": return name.isEmpty ? "" : (owner.isEmpty ? name : "\(owner).\(name)")
        case "#owner": return owner
        case "#name": return name
        case "#type": return type
        case "#connection": return connection
        case "#schema": return schema
        default: return nil
        }
    }
}

public enum UserTools {
    /// Rozwija zmienne `#…` (najdłuższe nazwy najpierw, np. `#filename` przed `#file`); nieznane zostają bez zmian.
    public static func expand(_ s: String, _ ctx: UserToolContext) -> String {
        var out = ""
        var i = s.startIndex
        let names = UserToolContext.variables.map(\.0).sorted { $0.count > $1.count }
        while i < s.endIndex {
            if s[i] == "#", let v = names.first(where: { s[i...].lowercased().hasPrefix($0) }) {
                let end = s.index(i, offsetBy: v.count)
                // `#name2` nie jest zmienną `#name` — po nazwie nie może stać litera ani cyfra.
                if end == s.endIndex || !(s[end].isLetter || s[end].isNumber) {
                    out += ctx.value(v) ?? ""
                    i = end
                    continue
                }
            }
            out.append(s[i])
            i = s.index(after: i)
        }
        return out
    }

    static let searchPath = ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/usr/local/bin", "/opt/homebrew/bin"]

    /// Ścieżka programu: bezwzględna (z rozwinięciem `~`) albo wyszukana w katalogach systemowych.
    public static func resolve(_ program: String) -> URL? {
        let p = (program.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        guard !p.isEmpty else { return nil }
        if p.contains("/") { return FileManager.default.isExecutableFile(atPath: p) ? URL(fileURLWithPath: p) : nil }
        for dir in searchPath {
            let c = (dir as NSString).appendingPathComponent(p)
            if FileManager.default.isExecutableFile(atPath: c) { return URL(fileURLWithPath: c) }
        }
        return nil
    }

    /// Środowisko programu: środowisko aplikacji bez zmiennych Pelikana (tokeny agentów, konfiguracja testów).
    static func environment() -> [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("PELIKAN_") }
    }

    /// Proces bez powłoki: argumenty jako tablica po rozwinięciu zmiennych. Puste linie pola argumentów (np. końcowa)
    /// nie są argumentami.
    public static func process(_ tool: UserTool, _ ctx: UserToolContext) throws -> Process {
        guard let exe = resolve(expand(tool.program, ctx)) else {
            throw CommandError.notAvailable(L10n.tr("Nie znaleziono programu „\(tool.program)”"))
        }
        let p = Process()
        p.executableURL = exe
        p.arguments = tool.arguments.filter { !$0.isEmpty }.map { expand($0, ctx) }
        p.environment = environment()
        let dir = (expand(tool.workingDirectory, ctx) as NSString).expandingTildeInPath
        if !dir.isEmpty { p.currentDirectoryURL = URL(fileURLWithPath: dir) }
        return p
    }

    public struct RunResult: Sendable, Equatable {
        public var status: Int32
        public var output: String
        public var errors: String
    }

    /// Uruchamia narzędzie zewnętrzne i zbiera wyjście (poza wątkiem głównym).
    public static func run(_ tool: UserTool, _ ctx: UserToolContext) async throws -> RunResult {
        let p = try process(tool, ctx)
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<RunResult, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try p.run()
                    // stderr czytany równolegle — pełny bufor potoku (64 KiB) przy czytaniu po kolei zawiesiłby proces.
                    final class Buffer: @unchecked Sendable { var data = Data() }   // zapis w wątku czytającym, odczyt po grupie
                    let e = Buffer()
                    let group = DispatchGroup()
                    let errHandle = err.fileHandleForReading
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        // readToEnd: błąd odczytu jako błąd Swift (readDataToEndOfFile rzuca wyjątek ObjC — awaria).
                        e.data = (try? errHandle.readToEnd()) ?? Data()
                        group.leave()
                    }
                    let o = Result { try out.fileHandleForReading.readToEnd() ?? Data() }
                    group.wait()
                    p.waitForExit()
                    c.resume(returning: RunResult(status: p.terminationStatus, output: String(decoding: try o.get(), as: UTF8.self),
                                                  errors: String(decoding: e.data, as: UTF8.self)))
                } catch {
                    c.resume(throwing: error)
                }
            }
        }
    }
}

extension Workspace {
    /// Zmienne narzędzi z bieżącego stanu (aktywne okno, zaznaczony obiekt, połączenie pod aliasem).
    public func userToolContext() -> UserToolContext {
        var c = UserToolContext()
        if let d = activeDocument {
            c.file = d.fileURL?.path ?? ""
            c.text = d.text
            let ns = d.text as NSString
            let sel = d.selectedRange
            if !sel.isEmpty, sel.upperBound <= ns.length { c.selection = ns.substring(with: NSRange(location: sel.lowerBound, length: sel.count)) }
        }
        if let o = selectedObject { c.owner = o.owner; c.name = o.name; c.type = o.type.rawValue }
        let conn = activeDocument.flatMap { effectiveConnection(of: $0) } ?? sessions.mainConnectionID
        if let conn {
            c.connection = connections.connection(conn)?.agentAlias ?? ""
            c.schema = sessions.connectedSchema(conn) ?? ""
        }
        return c
    }

    /// Wykonanie narzędzia użytkownika (komenda `tools.user.<id>`).
    public func runUserTool(_ tool: UserTool) async throws -> CommandResult {
        if tool.saveBeforeRun, let d = activeDocument, d.fileURL != nil, d.isModified {
            try await invoke("file.save")
        }
        let ctx = userToolContext()
        switch tool.kind {
        case .session:
            // Połączenie okna wyjściowego (jak zmienne #connection i #schema) — przed `newDocument`, które aktywuje nowe okno.
            let connection = activeDocument.flatMap { effectiveConnection(of: $0) } ?? sessions.mainConnectionID
            let d = newDocument(.sql, text: UserTools.expand(tool.sql, ctx))
            d.connectionID = connection
            d.isModified = false
            if tool.executeImmediately { try await invoke("sql.execute") }
            return CommandResult(message: tool.name)
        case .external:
            let r = try await UserTools.run(tool, ctx)
            let text = r.output + (r.errors.isEmpty ? "" : "\n" + r.errors)
            switch tool.output {
            case .none: break
            case .outputWindow: ui?.showToolOutput(title: tool.name, text: text, status: r.status)
            case .newWindow:
                let d = newDocument(.sql, text: text)
                d.customTitle = tool.name
                d.isModified = false
            }
            return CommandResult(message: L10n.tr("\(tool.name): kod wyjścia \(r.status)"), value: .int(Int64(r.status)))
        }
    }

    /// Zmiana listy narzędzi (Preferencje) — zapis w ustawieniach; komendy odświeża `refreshUserToolCommands`.
    public func updateUserTools(_ tools: [UserTool]) {
        settings.userTools = tools
    }

    /// Komendy narzędzi po każdej zmianie listy (Preferencje, import preferencji, zestaw preferencji połączenia
    /// głównego): usunięte narzędzia znikają z menu, nowe i zmienione są rejestrowane.
    func refreshUserToolCommands(previous: [UserTool]) {
        guard previous != settings.userTools else { return }
        unregister(previous.map(\.commandID).filter { id in !settings.userTools.contains { $0.commandID == id } })
        registerUserToolCommands()
    }

    /// Komendy `tools.user.<id>` (menu Narzędzia › Narzędzia użytkownika, paleta).
    func registerUserToolCommands() {
        register(settings.userTools.map { t in
            Command(CommandDescriptor(id: t.commandID, title: t.name, category: .tools, submenu: L10n.tr("Narzędzia użytkownika"),
                                      agent: .none, effect: t.kind == .external ? .external : .uiState,
                                      summary: t.kind == .external ? L10n.tr("Uruchamia program „\(t.program)” ze zmiennymi bieżącego okna i obiektu (bez danych logowania).")
                                          : L10n.tr("Otwiera okno SQL z blokiem narzędzia „\(t.name)”."),
                                      feature: "PD-TOOL-017")) { ctx in
                try await ctx.workspace.runUserTool(t)
            }
        })
    }
}

/// Komenda konfiguracji narzędzi użytkownika.
@MainActor
enum UserToolCommands {
    static var all: [Command] {
        [
            Command(CommandDescriptor(id: "tools.configureTools", title: L10n.tr("Narzędzia użytkownika…"), category: .tools,
                                      agent: .none, effect: .settings,
                                      summary: L10n.tr("Lista własnych narzędzi: programy zewnętrzne ze zmiennymi i bloki SQL dla sesji."),
                                      feature: "PD-TOOL-017")) { ctx in
                ctx.ui?.showUserToolsSettings()
                return .ok
            },
        ]
    }
}
