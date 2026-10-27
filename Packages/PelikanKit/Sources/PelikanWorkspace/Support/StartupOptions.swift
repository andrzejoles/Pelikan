import Foundation
import PelikanDB

/// Parametry startowe (UG 37.4, PD-CLI-001): `klucz=wartość` jak we wzorcu, `--klucz[=wartość]`, ścieżki plików
/// i URL `pelikan://open?…`. Hasła w argumentach nie są obsługiwane (PROMPT §4.2 p.6) — `userid=u/hasło@baza` jest
/// przyjmowane bez hasła, z ostrzeżeniem; hasło pochodzi z Pęku kluczy albo z pytania.
public struct StartupOptions: Sendable, Equatable {
    /// Połączenie z definicji: nazwa albo `użytkownik@baza`.
    public var connection: String?
    /// Obiekt do podglądu / edycji: `[TYP:]WŁAŚCICIEL.NAZWA` (także `TYP,WŁAŚCICIEL.NAZWA`).
    public var viewObject: String?
    public var editObject: String?
    /// Skrypt wykonywany w Command Window po połączeniu.
    public var commandFile: String?
    public var project: String?
    public var workset: String?
    /// Bez przywracania okien zapisanego workseta przy starcie.
    public var noLoadDesktop = false
    /// Wzorce połączeń otwieranych w tym uruchomieniu tylko do odczytu (`*`, `%`).
    public var readOnly: [String] = []
    public var files: [String] = []
    public var warnings: [String] = []
    /// Parametry z linku `pelikan://` (dowolna strona albo wiadomość) — tylko otwieranie istniejącego, bez tworzenia.
    public var fromLink = false

    public init() {}

    public var isEmpty: Bool {
        connection == nil && viewObject == nil && editObject == nil && commandFile == nil && project == nil && workset == nil
            && !noLoadDesktop && readOnly.isEmpty && files.isEmpty
    }

    /// Argumenty procesu (bez nazwy programu). Argumenty systemu (`-NSDocumentRevisionsDebugMode YES`, `-AppleLanguages (en)`,
    /// `-psn_…`) są pomijane.
    public static func parse(_ args: [String]) -> StartupOptions {
        var o = StartupOptions()
        var i = 0
        while i < args.count {
            let a = args[i]
            i += 1
            if a.hasPrefix("--") {
                let body = String(a.dropFirst(2))
                if let eq = body.firstIndex(of: "=") {
                    o.apply(String(body[..<eq]), String(body[body.index(after: eq)...]))
                } else if flags.contains(body.lowercased()) {
                    o.apply(body, "")
                } else if i < args.count {
                    o.apply(body, args[i])
                    i += 1
                } else {
                    o.warnings.append(L10n.tr("Parametr --\(body) bez wartości"))
                }
            } else if a.hasPrefix("-") {
                // Argumenty AppKit/systemu: `-Klucz wartość` albo `-psn_0_123`.
                if !a.hasPrefix("-psn"), i < args.count, !args[i].hasPrefix("-") { i += 1 }
            } else if let eq = a.firstIndex(of: "="), !a.hasPrefix("/"), !a.contains("://") {
                o.apply(String(a[..<eq]), String(a[a.index(after: eq)...]))
            } else if flags.contains(a.lowercased()) {
                o.apply(a, "")
            } else {
                o.files.append(a)
            }
        }
        return o
    }

    /// URL `<schemat>://open?connection=…&object=…&edit=…&file=…&workset=…&project=…` (schemat z Info.plist, marka
    /// w `Config/Brand.xcconfig`); hasło w URL jest ignorowane jak w argumentach.
    /// Link może otworzyć dowolna strona albo wiadomość, więc przyjmuje tylko otwieranie (połączenie, obiekt, plik,
    /// workset, projekt) i tryb tylko do odczytu — nigdy skryptu do wykonania (`commandfile`).
    public static func parse(url: URL, scheme: String) -> StartupOptions {
        var o = StartupOptions()
        o.fromLink = true
        guard url.scheme?.lowercased() == scheme.lowercased() else { return o }
        for q in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            guard let v = q.value else { continue }
            switch q.name.lowercased() {
            case "object", "view": o.apply("viewobject", v)
            case "edit": o.apply("editobject", v)
            case "file": o.files.append(v)
            case "connection", "connect", "userid", "workset", "project", "readonly", "password", "pwd": o.apply(q.name, v)
            default: o.warnings.append(L10n.tr("Parametr linku „\(q.name)” jest ignorowany"))
            }
        }
        return o
    }

    static let flags: Set<String> = ["noloaddesktop", "nologon"]

    mutating func apply(_ rawKey: String, _ value: String) {
        let v = value.trimmingCharacters(in: .whitespaces)
        switch rawKey.lowercased() {
        case "userid", "connection", "connect":
            connection = Self.withoutPassword(v, warnings: &warnings)
        case "viewobject": viewObject = v
        case "editobject": editObject = v
        case "commandfile": commandFile = v
        case "project": project = v
        case "workset": workset = v
        case "noloaddesktop": noLoadDesktop = v.isEmpty || ["1", "yes", "true", "tak"].contains(v.lowercased())
        case "nologon": connection = nil
        case "readonly":
            readOnly += v.split(whereSeparator: { $0 == "," || $0 == ";" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        case "password", "pwd":
            warnings.append(L10n.tr("Hasło w parametrach startowych jest ignorowane — Pelikan bierze je z Pęku kluczy albo pyta"))
        default:
            warnings.append(L10n.tr("Nieznany parametr startowy: \(rawKey)"))
        }
    }

    /// `u/hasło@baza` → `u@baza` (hasło odrzucone). Baza od ostatniego `@` (hasło może zawierać `@`), a `/` po nim
    /// należy do bazy (EZConnect `host:port/usługa`) — jak CONNECT w Command Window.
    static func withoutPassword(_ s: String, warnings: inout [String]) -> String {
        let at = s.lastIndex(of: "@")
        let user = at.map { s[..<$0] } ?? s[...]
        guard let slash = user.firstIndex(of: "/") else { return s }
        warnings.append(L10n.tr("Hasło w parametrach startowych jest ignorowane — Pelikan bierze je z Pęku kluczy albo pyta"))
        return String(user[..<slash]) + (at.map { String(s[$0...]) } ?? "")
    }

    /// Obiekt z `[TYP:]WŁAŚCICIEL.NAZWA` albo `TYP,WŁAŚCICIEL.NAZWA`.
    public static func object(_ spec: String) -> (type: String?, name: String) {
        for sep in [":", ","] where spec.contains(sep) {
            let parts = spec.split(separator: Character(sep), maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].contains(".") { return (parts[0].uppercased(), parts[1]) }
        }
        return (nil, spec.trimmingCharacters(in: .whitespaces))
    }
}

extension Workspace {
    /// Definicja połączenia z parametru startowego: nazwa (bez wielkości liter) albo `użytkownik@baza`.
    public func connectionDefinition(matching spec: String) -> ConnectionDefinition? {
        let s = spec.lowercased()
        return connections.connections.first { $0.name.lowercased() == s }
            ?? connections.connections.first { "\($0.target.user)@\($0.target.connectString)".lowercased() == s }
            ?? connections.connections.first { $0.displayName.lowercased() == s }
    }

    /// Wykonuje parametry startowe; zwraca komunikaty (ostrzeżenia i błędy kolejnych kroków).
    @discardableResult
    public func applyStartup(_ o: StartupOptions) async -> [String] {
        var messages = o.warnings
        startupReadOnlyPatterns += o.readOnly
        func step(_ what: String, _ body: () async throws -> Void) async {
            do { try await body() } catch { messages.append("\(what): \(error.localizedDescription)") }
        }
        if let p = o.project { await step(L10n.tr("Projekt")) { try await invoke("project.open", CommandArguments(["file": .string(p)])) } }
        if let w = o.workset {
            await step(L10n.tr("Workset")) {
                if worksets.existingName(w) != nil { try await invoke("workset.open", CommandArguments(["name": .string(w)])) }
                // Link nie tworzy workseta (nowy plik i przełączenie zamykają bieżące okna, D163) — tylko otwiera istniejący.
                else if o.fromLink { throw CommandError.notAvailable(L10n.tr("Nie ma workseta „\(w)”")) }
                else { try await invoke("workset.new", CommandArguments(["name": .string(w)])) }
            }
        }
        if let c = o.connection {
            await step(L10n.tr("Połączenie")) {
                guard let def = connectionDefinition(matching: c) else { throw CommandError.notAvailable(L10n.tr("Nie ma połączenia „\(c)”")) }
                try await invoke("connection.connectAsMain", CommandArguments(["connection": .string(def.id.uuidString)]))
            }
        }
        for f in o.files {
            await step(f) { try openFile(URL(fileURLWithPath: (f as NSString).expandingTildeInPath)) }
        }
        for (spec, command) in [(o.viewObject, CommandID("ob.properties")), (o.editObject, CommandID("ob.edit"))] {
            guard let spec else { continue }
            let (type, name) = StartupOptions.object(spec)
            var args: [String: JSONValue] = ["object": .string(name)]
            if let type { args["type"] = .string(type) }
            await step(spec) { try await invoke(command, CommandArguments(args)) }
        }
        if let f = o.commandFile {
            await step(L10n.tr("Skrypt")) {
                let path = (f as NSString).expandingTildeInPath
                guard FileManager.default.fileExists(atPath: path) else { throw CommandError.notAvailable(L10n.tr("Nie ma pliku \(f)")) }
                newDocument(.command)
                try await invoke("cmd.executeLine", CommandArguments(["line": .string("@\"\(path)\"")]))
            }
        }
        return messages
    }
}
