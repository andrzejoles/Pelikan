import Foundation
import PelikanDB
import PelikanSQL

/// Błąd polecenia SQL*Plus (komunikat w stylu SP2-…).
public struct SQLPlusError: Error, LocalizedError, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

extension SQLPlusEngine {
    /// Słowa polecenia z uwzględnieniem cudzysłowów ('…', "…").
    nonisolated static func words(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var quote: Character?
        var hadQuote = false
        for ch in text {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "'" || ch == "\"" {
                quote = ch
                hadQuote = true
            } else if ch.isWhitespace {
                if !current.isEmpty || hadQuote { out.append(current); current = ""; hadQuote = false }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty || hadQuote { out.append(current) }
        return out
    }

    /// Reszta tekstu po pierwszym słowie (PROMPT, EXECUTE, HOST).
    nonisolated static func rest(_ text: String) -> String {
        guard let r = text.firstIndex(where: { $0.isWhitespace }) else { return "" }
        return String(text[r...]).trimmingCharacters(in: .whitespaces)
    }

    func sqlplus(_ cmd: String, _ text: String, baseDirectory: URL?) async throws -> Outcome {
        var line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasSuffix(";"), !["PROMPT", "REMARK"].contains(cmd) { line.removeLast() }
        let w = Self.words(line)
        let args = Array(w.dropFirst())
        let upper = args.map { $0.uppercased() }
        switch cmd {
        case "PROMPT":
            emit(Self.rest(line), .output)
        case "SET" where upper.first.map({ $0.count >= 5 && "SQLFORMAT".hasPrefix($0) }) == true:
            // SET SQLFORMAT format [argumenty] — reszta linii należy do formatu (np. delimited | " ").
            state.sqlFormat = try SQLFormat.parse(Array(args.dropFirst()))
        case "SET":
            // Kilka opcji w jednej linii: SET FEEDBACK ON TIMING ON; SERVEROUTPUT ON SIZE UNLIMITED FORMAT WRAPPED.
            var i = 0
            while i < upper.count {
                var n = min(2, upper.count - i)
                if upper[i].hasPrefix("SERVEROUT") {
                    while i + n + 1 < upper.count, ["SIZE", "SIZ", "FORMAT", "FOR", "FORM"].contains(upper[i + n]) { n += 2 }
                }
                try set(Array(upper[i..<(i + n)]), Array(args[i..<(i + n)]))
                i += n
            }
        case "SHOW":
            try await show(upper, args)
        case "DEFINE":
            define(line)
        case "UNDEFINE":
            for a in upper { state.defines[a] = nil }
        case "VARIABLE":
            try variable(args)
        case "PRINT":
            printBinds(upper.isEmpty ? state.binds.keys.sorted() : upper.map { $0.hasPrefix(":") ? String($0.dropFirst()) : $0 })
        case "EXECUTE":
            let body = Self.rest(text).trimmingCharacters(in: CharacterSet(charactersIn: "; \n"))
            return await executeSQL("BEGIN \(body); END;", original: text, isPLSQL: true)
        case "ACCEPT":
            return await accept(args)
        case "PAUSE":
            let message = Self.rest(line)
            let choice = await workspace.ui?.ask(L10n.tr("Pauza"), message: message.isEmpty ? L10n.tr("Naciśnij Kontynuuj, aby wykonać dalszą część skryptu.") : message,
                                                 buttons: [L10n.tr("Kontynuuj"), L10n.tr("Przerwij")])
            if choice != 0 { emit(L10n.tr("Przerwano"), .info); return .stopped }
        case "COLUMN":
            column(args)
        case "CLEAR":
            switch upper.first ?? "" {
            case "SCR", "SCRE", "SCREE", "SCREEN": document.console.removeAll()
            case "COL", "COLU", "COLUM", "COLUMN", "COLUMNS": state.columns.removeAll()
            case "BUFF", "BUFFE", "BUFFER", "SQL": state.buffer = nil
            case "BRE", "BREA", "BREAK", "BREAKS": state.breaks.removeAll()
            case "COMP", "COMPU", "COMPUT", "COMPUTE", "COMPUTES": state.computes.removeAll()
            default: break
            }
        case "@", "@@", "START":
            return try await runFile(cmd, line: line, baseDirectory: baseDirectory)
        case "SPOOL":
            try spool(args)
        case "DESCRIBE":
            guard let name = args.first else { throw SQLPlusError(L10n.tr("SP2-0565: Nieprawidłowy identyfikator.")) }
            try await describe(name)
        case "WHENEVER":
            guard upper.first == "SQLERROR" || upper.first == "OSERROR" else { throw SQLPlusError(L10n.tr("SP2-0591: Nieznane polecenie WHENEVER.")) }
            if upper.dropFirst().first == "EXIT" {
                state.whenever = .exit(commit: upper.contains("COMMIT"))
            } else {
                state.whenever = .continue
            }
        case "CONNECT":
            try await connect(args)
        case "DISCONNECT":
            guard try await endTransactionBeforeLogoff() else { emit(L10n.tr("Anulowano"), .info); return .finished }
            let c = windowConnection
            document.connectionID = nil
            if let c {
                await workspace.sessions.close(workspace.sessions.key(forDocument: document.id, connection: c))
                releaseTemporary(c)
            }
            document.transactionOpen = false
            document.isDisconnected = true
            emit(L10n.tr("Rozłączono."))
        case "EXIT", "QUIT":
            return .exit
        case "LIST", "APPEND", "CHANGE", "DEL", "INPUT", "SAVE", "GET", "STORE", "BREAK", "COMPUTE":
            try bufferCommand(cmd, args, line: line, baseDirectory: baseDirectory)
        case "RUN":
            guard let b = state.buffer else { throw SQLPlusError(L10n.tr("SP2-0103: Bufor SQL jest pusty.")) }
            emit(Self.maskPassword(b), .echo)
            return await executeSQL(b, original: b, isPLSQL: ScriptSplitter.split(b).first?.isPLSQL ?? false)
        case "CD":
            guard let path = args.first else { emit(currentDirectory.path); break }
            let url = resolve(path, baseDirectory: nil)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                throw SQLPlusError(L10n.tr("Katalog nie istnieje: \(path)"))
            }
            state.directory = url
        case "HOST", "!", "$":
            // `!ls` / `$dir` bez spacji — polecenie od drugiego znaku (jak w SQL*Plus).
            func after(_ s: String) -> String {
                cmd == "HOST" ? Self.rest(s) : String(s.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst())
            }
            // Instalator utPLSQL sprząta po sobie `! rm plik` / `$ del plik`: tylko w jego przebiegu i tylko pliki
            // z katalogu instalatora, usuwane bez powłoki. Każde inne polecenie systemu pozostaje niedostępne.
            let hostArgs = Self.words(after(line))
            if let dir = state.installerDirectory, hostArgs.count == 2, ["RM", "DEL"].contains(hostArgs[0].uppercased()),
               !hostArgs[1].contains("/"), !hostArgs[1].contains("\\"), !hostArgs[1].hasPrefix(".") {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(hostArgs[1]))
                return .finished
            }
            // HOST (PD-CMDW-008): tylko użytkownik (agent nie ma dostępu do Command Window), zawsze po potwierdzeniu
            // z treścią polecenia — także w skryptach @plik; powłoka /bin/sh w katalogu CD, limit czasu, wyjście w oknie.
            let command = after(text).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else { throw SQLPlusError(L10n.tr("SP2-0042: brak polecenia systemu po HOST")) }
            guard let ui = workspace.ui, await ui.ask(L10n.tr("Wykonać polecenie systemu?"), message: command,
                                                     buttons: [L10n.tr("Wykonaj"), L10n.tr("Anuluj")]) == 0 else {
                emit(L10n.tr("Anulowano"), .info)
                return .finished
            }
            // Poza głównym aktorem (interfejs nie zamarza); Przerwij anuluje zadanie i kończy grupę procesów.
            let directory = state.directory ?? baseDirectory
            let task = Task.detached { try await HostCommand.run(command, directory: directory) }
            hostTask = task
            defer { hostTask = nil }
            let r = try await task.value
            if !r.output.isEmpty { emit(r.output.trimmingCharacters(in: .newlines), .output) }
            if r.status != 0 { emit(L10n.tr("Kod wyjścia: \(r.status)"), .error) }
        case "TIMING":
            state.timing.toggle()
        case "HELP":
            emit(L10n.tr("Polecenia: @ @@ / ACCEPT CLEAR COLUMN CONNECT DEFINE DESCRIBE DISCONNECT EXECUTE EXIT LIST PAUSE PRINT PROMPT REM RUN SET SHOW SPOOL START UNDEFINE VARIABLE WHENEVER CD; Pelikan: BEAUTIFY BROWSE DIR EDIT EDITDATA EXPORT INFO PROPERTIES QUERYDATA RECOMPILE TEST VIEW ZIP"))
        case "DDL", "LOAD", "FORMAT", "HISTORY", "ALIAS", "REPEAT", "CTAS":
            return try await sqlclCommand(cmd, args, line: line, baseDirectory: baseDirectory)
        case "BEAUTIFY", "BROWSE", "DIR", "EDIT", "EDITDATA", "INFO", "PROPERTIES", "QUERYDATA", "RECOMPILE", "TEST", "VIEW", "ZIP", "EXPORT", "RUNTESTSET":
            try await pelikanCommand(cmd, args, line: line)
        default:
            // Polecenia SQL*Plus/SQLcl jeszcze nieobsługiwane — informacja zamiast błędu (skrypty wsadowe — NF17).
            emit(L10n.tr("Polecenie \(cmd) nie jest jeszcze obsługiwane — pominięto."), .info)
        }
        return .finished
    }

    var currentDirectory: URL {
        state.directory ?? document.fileURL?.deletingLastPathComponent() ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    func resolve(_ path: String, baseDirectory: URL?) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded) }
        return (baseDirectory ?? currentDirectory).appendingPathComponent(expanded)
    }

    // MARK: SET

    func onOff(_ v: String?) throws -> Bool {
        switch v {
        case "ON": return true
        case "OFF": return false
        default: throw SQLPlusError(L10n.tr("SP2-0265: Wartość musi być ON albo OFF."))
        }
    }

    func set(_ upper: [String], _ args: [String]) throws {
        guard let option = upper.first else { throw SQLPlusError(L10n.tr("SP2-0158: Nieznana opcja SET.")) }
        let value = upper.count > 1 ? upper[1] : nil
        let raw = args.count > 1 ? args[1] : nil
        func int() throws -> Int {
            guard let v = value, let n = Int(v), n >= 0 else { throw SQLPlusError(L10n.tr("SP2-0268: Nieprawidłowa wartość liczbowa.")) }
            return n
        }
        func matches(_ full: String, _ min: Int) -> Bool { option.count >= min && full.hasPrefix(option) }
        if matches("AUTOPRINT", 5) { state.autoPrint = try onOff(value) }
        else if matches("COLSEP", 4) { state.colSep = raw ?? " " }
        else if matches("COLWIDTH", 4) { state.colWidth = try int() }
        else if matches("DEFINE", 3) {
            if value == "ON" || value == "OFF" { state.defineEnabled = value == "ON" }
            else if let c = raw?.first { state.defineChar = c; state.defineEnabled = true }
        }
        else if matches("ECHO", 4) { state.echo = try onOff(value) }
        else if matches("ESCAPE", 3) {
            if value == "OFF" { state.escapeChar = nil } else if value == "ON" { state.escapeChar = "\\" } else { state.escapeChar = raw?.first }
        }
        else if matches("CONCAT", 3) {
            if value == "OFF" { state.concatChar = "\u{0}" } else if value == "ON" { state.concatChar = "." } else if let c = raw?.first { state.concatChar = c }
        }
        else if matches("FEEDBACK", 4) {
            if value == "ON" { state.feedback = 1 } else if value == "OFF" { state.feedback = 0 } else { state.feedback = try int() }
        }
        else if matches("HEADING", 3) { state.heading = try onOff(value) }
        else if matches("LINESIZE", 3) { state.lineSize = try int() }
        else if matches("LONG", 4) { state.long = try int() }
        else if matches("NUMWIDTH", 3) { state.numWidth = try int() }
        else if matches("PAGESIZE", 5) { state.pageSize = try int() }
        else if matches("SCAN", 3) { state.scan = try onOff(value) }
        else if matches("SERVEROUTPUT", 9) { state.serverOutput = try onOff(value) }
        else if matches("SQLPROMPT", 4) || matches("PROMPT", 6) { state.sqlPrompt = raw ?? "SQL> " }
        else if matches("TERMOUT", 4) { state.termOut = try onOff(value) }
        else if matches("TIMING", 3) { state.timing = try onOff(value) }
        else if matches("VERIFY", 3) { state.verify = try onOff(value) }
        else if matches("EXECPAUSE", 5) { state.execPause = try onOff(value) }
        // Pozostałe SET (TRIMSPOOL, ARRAYSIZE, SQLBLANKLINES…) — bez skutku i bez błędu (NF17).
    }

    // MARK: SHOW

    func show(_ upper: [String], _ args: [String]) async throws {
        switch upper.first ?? "" {
        case "USER":
            let s = try await windowSession()
            emit(L10n.tr("USER to „\(s.info.sessionUser)”"))
        case "REL", "RELE", "RELEA", "RELEAS", "RELEASE":
            let s = try await windowSession()
            emit("Release \(s.info.server.description)")
        case "CON", "CONN", "CONNECTION":
            if let c = windowConnection, let def = workspace.connections.connection(c) {
                emit(def.displayName)
            } else {
                emit(L10n.tr("Brak połączenia"))
            }
        case "ERR", "ERRO", "ERROR", "ERRORS":
            try await showErrors(Array(args.dropFirst()))
        case "ALL":
            emit(state.summary.joined(separator: "\n"))
        case "SQLFORMAT", "SQLFO", "SQLFOR", "SQLFORM", "SQLFORMA":
            emit(L10n.tr("SQL Format: \(state.sqlFormat?.name ?? "default")"))
        case "SPOOL", "SPOO":
            emit(state.spoolURL.map { L10n.tr("spool ON: \($0.path)") } ?? L10n.tr("spool OFF"))
        case "SQLCODE", "SQLCO":
            emit("sqlcode 0")
        case "DEFINE":
            define("DEFINE")
        default:
            if let key = upper.first, let line = state.summary.first(where: { $0.uppercased().hasPrefix(key) }) { emit(line) }
            else { throw SQLPlusError(L10n.tr("SP2-0158: Nieznana opcja SHOW.")) }
        }
    }

    /// SHOW ERRORS [typ] [schemat.]nazwa — błędy kompilacji z ALL_ERRORS (domyślnie ostatnio tworzony obiekt).
    func showErrors(_ args: [String]) async throws {
        var type: String?
        var owner: String?
        var name: String?
        if !args.isEmpty {
            var rest = args.map { $0 }
            if rest.count >= 2 {
                type = rest.removeFirst().uppercased()
                if type == "PACKAGE" || type == "TYPE", rest.first?.uppercased() == "BODY" { type! += " BODY"; rest.removeFirst() }
            }
            let parts = (rest.first ?? "").split(separator: ".").map { String($0).uppercased() }
            if parts.count == 2 { owner = parts[0]; name = parts[1] } else { name = parts.first }
        } else if let last = state.lastCompiled {
            type = last.type; owner = last.owner; name = last.name
        }
        guard let objectName = name else { emit(L10n.tr("Brak błędów.")); return }
        let session = try await windowSession()
        var sql = "select line, position, text from all_errors where name = :n and owner = nvl(:o, sys_context('USERENV', 'CURRENT_SCHEMA'))"
        var binds = [BindVariable(name: "n", value: .text(objectName)), BindVariable(name: "o", value: owner.map { .text($0) } ?? .null)]
        if let type { sql += " and type = :t"; binds.append(BindVariable(name: "t", value: .text(type))) }
        sql += " order by sequence"
        let (_, rows) = try await session.queryAll(sql, binds: binds, limit: 10_000)
        guard !rows.isEmpty else { emit(L10n.tr("Brak błędów.")); return }
        emit(L10n.tr("Błędy dla \(type ?? "") \(owner.map { "\($0)." } ?? "")\(objectName):").replacingOccurrences(of: "  ", with: " "))
        emit("")
        emit("LINE/COL ERROR")
        emit("-------- -----------------------------------------------------------------")
        for r in rows {
            let pos = "\(r[0].format(.default))/\(r[1].format(.default))"
            let msg = r[2].format(.default).replacingOccurrences(of: "\n", with: "\n         ")
            emit(pos.padding(toLength: max(8, pos.count), withPad: " ", startingAt: 0) + " " + msg, .error)
        }
    }

    // MARK: DEFINE, VARIABLE, ACCEPT, COLUMN

    func define(_ line: String) {
        let body = Self.rest(line)
        if body.isEmpty {
            for k in state.defines.keys.sorted() { emit("DEFINE \(k) = \"\(state.defines[k]!)\" (CHAR)") }
            return
        }
        if let eq = body.firstIndex(of: "=") {
            let name = body[..<eq].trimmingCharacters(in: .whitespaces).uppercased()
            var value = body[body.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("'") && value.hasSuffix("'")) || (value.hasPrefix("\"") && value.hasSuffix("\"")), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            state.defines[name] = value
        } else {
            let name = body.uppercased()
            if let v = state.defines[name] { emit("DEFINE \(name) = \"\(v)\" (CHAR)") } else { emit(L10n.tr("SP2-0135: Symbol \(name) nie jest zdefiniowany."), .error) }
        }
    }

    func variable(_ args: [String]) throws {
        guard let rawName = args.first else {
            for (k, v) in state.binds.sorted(by: { $0.key < $1.key }) { emit(L10n.tr("zmienna \(k)\n typ: \(v.declaration)")) }
            return
        }
        let name = rawName.uppercased()
        guard args.count >= 2 else {
            if let v = state.binds[name] { emit(L10n.tr("zmienna \(name)\n typ: \(v.declaration)")) } else { throw SQLPlusError(L10n.tr("SP2-0552: Zmienna wiązana „\(name)” nie jest zadeklarowana.")) }
            return
        }
        // Typ (z rozmiarem) i opcjonalnie := wartość.
        let decl = args.dropFirst().joined(separator: " ")
        let parts = decl.components(separatedBy: ":=")
        let typeText = parts[0].trimmingCharacters(in: .whitespaces).uppercased()
        let base = typeText.split(separator: "(").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? typeText
        let size = UInt32(typeText.split(separator: "(").dropFirst().first?.filter(\.isNumber) ?? "") ?? 4000
        let type: OracleType
        switch base {
        case "NUMBER", "BINARY_FLOAT", "BINARY_DOUBLE": type = .number
        case "VARCHAR2", "VARCHAR", "CHAR", "NCHAR", "NVARCHAR2": type = .varchar2
        case "CLOB", "NCLOB": type = .clob
        case "BLOB": type = .blob
        case "REFCURSOR": type = .refCursor
        case "DATE": type = .date
        case "BOOLEAN": type = .boolean
        default: throw SQLPlusError(L10n.tr("SP2-0553: Nieprawidłowy typ zmiennej: \(base)"))
        }
        var value: OracleValue = .null
        if parts.count > 1 {
            var v = parts[1].trimmingCharacters(in: .whitespaces)
            if v.hasPrefix("'"), v.hasSuffix("'"), v.count >= 2 { v = String(v.dropFirst().dropLast()) }
            value = type == .number ? .number(v) : .text(v)
        }
        state.binds[name] = .init(type: type, size: max(size, type == .varchar2 ? 1 : 4000), value: value, declaration: typeText)
    }

    func accept(_ args: [String]) async -> Outcome {
        guard let name = args.first?.uppercased() else { emit(L10n.tr("SP2-0003: Brak nazwy zmiennej."), .error); return .finished }
        var prompt = name
        var def: String?
        var i = 1
        while i < args.count {
            switch args[i].uppercased() {
            case "PROMPT": if i + 1 < args.count { prompt = args[i + 1]; i += 1 }
            case "DEFAULT", "DEF": if i + 1 < args.count { def = args[i + 1]; i += 1 }
            default: break
            }
            i += 1
        }
        var options = VariableOptions(name: prompt)
        options.defaultValue = def
        let request = VariableRequest(name: name, kind: .substitution, options: options, value: state.defines[name].map { .text($0) })
        guard let answers = await workspace.ui?.askVariables([request], document: document) else { emit(L10n.tr("Anulowano"), .info); return .stopped }
        if case .text(let t)? = answers[name] { state.defines[name] = t } else { state.defines[name] = def ?? "" }
        return .finished
    }

    func column(_ args: [String]) {
        guard let name = args.first?.uppercased() else {
            for (k, v) in state.columns.sorted(by: { $0.key < $1.key }) { emit("COLUMN \(k) \(v.format.map { "FORMAT \($0)" } ?? "") \(v.heading.map { "HEADING '\($0)'" } ?? "")") }
            return
        }
        var f = state.columns[name] ?? .init()
        var i = 1
        while i < args.count {
            let key = args[i].uppercased()
            let next = i + 1 < args.count ? args[i + 1] : nil
            switch key {
            case "FOR", "FORM", "FORMA", "FORMAT": f.format = next; i += 1
            case "HEA", "HEAD", "HEADI", "HEADIN", "HEADING": f.heading = next; i += 1
            case "NEW_V", "NEW_VA", "NEW_VAL", "NEW_VALU", "NEW_VALUE": f.newValue = next; i += 1
            case "CLE", "CLEA", "CLEAR": f = .init()
            case "ON": f.isOn = true
            case "OFF": f.isOn = false
            default: break
            }
            i += 1
        }
        state.columns[name] = f
    }

    // MARK: Pliki

    /// @plik [parametry], @@plik (względem bieżącego skryptu), START plik.
    func runFile(_ cmd: String, line: String, baseDirectory: URL?) async throws -> Outcome {
        var body = line
        if body.hasPrefix("@@") { body.removeFirst(2) } else if body.hasPrefix("@") { body.removeFirst() } else { body = Self.rest(body) }
        let parts = Self.words(body)
        guard var path = parts.first else { throw SQLPlusError(L10n.tr("SP2-0310: Brak nazwy pliku.")) }
        if (path as NSString).pathExtension.isEmpty { path += ".sql" }
        let url = resolve(path, baseDirectory: cmd == "@@" ? baseDirectory : nil)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw SQLPlusError(L10n.tr("SP2-0310: Nie można otworzyć pliku „\(url.lastPathComponent)”."))
        }
        guard depth < 20 else { throw SQLPlusError(L10n.tr("SP2-0309: Zbyt głębokie zagnieżdżenie skryptów.")) }
        let script = String(decoding: data, as: UTF8.self)
        depth += 1
        defer { depth -= 1 }
        let saved = (1...9).map { state.defines[String($0)] }
        defer { for (i, v) in saved.enumerated() { state.defines[String(i + 1)] = v } }
        return await run(script, arguments: Array(parts.dropFirst()), baseDirectory: url.deletingLastPathComponent())
    }

    func spool(_ args: [String]) throws {
        guard let first = args.first else {
            emit(state.spoolURL.map { L10n.tr("spool ON: \($0.path)") } ?? L10n.tr("spool OFF"))
            return
        }
        switch first.uppercased() {
        case "OFF", "OUT":
            state.spoolURL = nil
        default:
            var path = first
            if (path as NSString).pathExtension.isEmpty { path += ".lst" }
            let url = resolve(path, baseDirectory: nil)
            let append = args.dropFirst().contains { $0.uppercased() == "APPEND" || $0.uppercased() == "APP" }
            if !append || !FileManager.default.fileExists(atPath: url.path) {
                guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
                    throw SQLPlusError(L10n.tr("SP2-0606: Nie można utworzyć pliku SPOOL „\(url.path)”."))
                }
            }
            state.spoolURL = url
        }
    }

    // MARK: DESCRIBE

    func describe(_ raw: String) async throws {
        let session = try await windowSession()
        let parts = raw.split(separator: ".").map { $0.hasPrefix("\"") ? String($0.dropFirst().dropLast()) : String($0).uppercased() }
        let owner: String? = parts.count >= 2 ? parts[0] : nil
        let name = parts.last ?? raw.uppercased()
        // Synonim → obiekt docelowy.
        var targetOwner = owner
        var targetName = name
        let (_, syn) = try await session.queryAll("""
            select table_owner, table_name from all_synonyms
            where synonym_name = :n and owner in (nvl(:o, sys_context('USERENV', 'CURRENT_SCHEMA')), 'PUBLIC')
            order by decode(owner, 'PUBLIC', 2, 1) fetch first 1 row only
            """, binds: [BindVariable(name: "n", value: .text(name)), BindVariable(name: "o", value: owner.map { .text($0) } ?? .null)], limit: 1)
        if let s = syn.first {
            let (_, own) = try await session.queryAll("select count(*) from all_objects where object_name = :n and owner = nvl(:o, sys_context('USERENV', 'CURRENT_SCHEMA'))",
                                                      binds: [BindVariable(name: "n", value: .text(name)), BindVariable(name: "o", value: owner.map { .text($0) } ?? .null)], limit: 1)
            if own.first?.first?.displayText == "0" { targetOwner = s[0].displayText; targetName = s[1].displayText ?? name }
        }
        let ob = [BindVariable(name: "n", value: .text(targetName)), BindVariable(name: "o", value: targetOwner.map { .text($0) } ?? .null)]
        let (_, cols) = try await session.queryAll("""
            select column_name, nullable, data_type, data_length, data_precision, data_scale, char_used, char_length
            from all_tab_columns where table_name = :n and owner = nvl(:o, sys_context('USERENV', 'CURRENT_SCHEMA')) order by column_id
            """, binds: ob, limit: 5000)
        if !cols.isEmpty {
            let rows = cols.map { r -> (String, String, String) in
                (r[0].format(.default), r[1].displayText == "N" ? "NOT NULL" : "", Self.typeText(r))
            }
            let w = max(4, rows.map(\.0.count).max() ?? 4)
            emit(" " + L10n.tr("Nazwa").padding(toLength: w, withPad: " ", startingAt: 0) + "  " + L10n.tr("Null?").padding(toLength: 8, withPad: " ", startingAt: 0) + " " + L10n.tr("Typ"))
            emit(" " + String(repeating: "-", count: w) + "  -------- " + String(repeating: "-", count: 28))
            for r in rows { emit(" " + r.0.padding(toLength: w, withPad: " ", startingAt: 0) + "  " + r.1.padding(toLength: 8, withPad: " ", startingAt: 0) + " " + r.2) }
            return
        }
        // Procedura, funkcja albo pakiet — argumenty z ALL_ARGUMENTS.
        let (_, argRows) = try await session.queryAll("""
            select nvl(package_name, '-'), object_name, nvl(overload, '0'), argument_name, data_type, in_out, position, defaulted
            from all_arguments
            where owner = nvl(:o, sys_context('USERENV', 'CURRENT_SCHEMA')) and (package_name = :n or (package_name is null and object_name = :n))
              and data_level = 0
            order by object_name, overload, sequence
            """, binds: ob, limit: 10_000)
        guard !argRows.isEmpty else { throw SQLPlusError(L10n.tr("ORA-04043: Obiekt \(raw) nie istnieje.")) }
        var current = ""
        for r in argRows {
            let header = r[1].format(.default) + (r[2].format(.default) == "0" ? "" : " (\(r[2].format(.default)))")
            if header != current {
                current = header
                let isFunction = argRows.contains { $0[1] == r[1] && $0[2] == r[2] && $0[6].displayText == "0" }
                emit("")
                emit((isFunction ? "FUNCTION " : "PROCEDURE ") + header + (isFunction ? " RETURNS " + (argRows.first { $0[1] == r[1] && $0[2] == r[2] && $0[6].displayText == "0" }?[4].format(.default) ?? "") : ""))
                emit(" " + L10n.tr("Argument").padding(toLength: 30, withPad: " ", startingAt: 0) + " " + L10n.tr("Typ").padding(toLength: 24, withPad: " ", startingAt: 0)
                     + " " + L10n.tr("In/Out").padding(toLength: 6, withPad: " ", startingAt: 0) + " " + L10n.tr("Domyślny?"))
                emit(" ------------------------------ ------------------------ ------ ---------")
            }
            guard r[6].displayText != "0", !r[3].isNull else { continue }
            emit(" " + r[3].format(.default).padding(toLength: 30, withPad: " ", startingAt: 0) + " " + r[4].format(.default).padding(toLength: 24, withPad: " ", startingAt: 0)
                 + " " + r[5].format(.default).padding(toLength: 6, withPad: " ", startingAt: 0) + " " + (r[7].displayText == "Y" ? L10n.tr("TAK") : ""))
        }
    }

    nonisolated static func typeText(_ r: [OracleValue]) -> String {
        let type = r[2].format(.default)
        let len = r[3].format(.default), prec = r[4].displayText, scale = r[5].displayText
        switch type {
        case "VARCHAR2", "NVARCHAR2", "CHAR", "NCHAR", "RAW":
            let chars = r[6].displayText == "C" ? " CHAR" : ""
            let n = r[6].displayText == "C" ? r[7].format(.default) : len
            return "\(type)(\(n)\(chars))"
        case "NUMBER":
            guard let p = prec else { return scale == "0" ? "INTEGER" : "NUMBER" }
            return scale == nil || scale == "0" ? "NUMBER(\(p))" : "NUMBER(\(p),\(scale!))"
        default: return type
        }
    }

    // MARK: CONNECT

    /// CONNECT nazwa_połączenia | user[/hasło]@baza [AS SYSDBA] — zapisane połączenie albo tymczasowe (tylko pamięć).
    func connect(_ args: [String]) async throws {
        guard let spec = args.first else { throw SQLPlusError(L10n.tr("SP2-0306: Nieprawidłowa opcja CONNECT.")) }
        var role: ConnectRole = .normal
        if args.count >= 3, args[1].uppercased() == "AS" {
            switch args[2].uppercased() {
            case "SYSDBA": role = .sysdba
            case "SYSOPER": role = .sysoper
            case "SYSDG": role = .sysdg
            case "SYSBACKUP": role = .sysbackup
            case "SYSKM": role = .syskm
            default: break
            }
        }
        // Zapisane połączenie po nazwie albo user@baza.
        let lower = spec.lowercased()
        if !spec.contains("/"), let def = workspace.connections.connections.first(where: {
            $0.name.lowercased() == lower || $0.displayName.lowercased() == lower
                || "\($0.target.user)@\($0.target.connectString)".lowercased() == lower
        }) {
            guard try await endTransactionBeforeLogoff() else { emit(L10n.tr("Anulowano"), .info); return }
            try await switchConnection(def.id)
            return
        }
        var user = spec
        var password: String?
        var db = ""
        if let at = spec.lastIndex(of: "@") { db = String(spec[spec.index(after: at)...]); user = String(spec[..<at]) }
        if let slash = user.firstIndex(of: "/") { password = String(user[user.index(after: slash)...]); user = String(user[..<slash]) }
        if db.isEmpty, let c = workspace.effectiveConnection(of: document), let cur = workspace.connections.connection(c) { db = cur.target.connectString }
        guard !user.isEmpty, !db.isEmpty else { throw SQLPlusError(L10n.tr("SP2-0306: Podaj użytkownika i bazę: CONNECT użytkownik@baza.")) }
        var target = ConnectionTarget(user: user, connectString: db)
        target.role = role
        let def = ConnectionDefinition(name: "\(user)@\(db)", target: target, savePassword: false)
        guard try await endTransactionBeforeLogoff() else { emit(L10n.tr("Anulowano"), .info); return }
        workspace.connections.registerTemporary(def, password: password)
        try await switchConnection(def.id)
    }

    /// Otwarta transakcja przed CONNECT/DISCONNECT: COMMIT albo ROLLBACK wg ustawienia, pytanie jak przy zamykaniu okna
    /// (D10, SECURITY A18). false — anulowano. Bez interfejsu — ROLLBACK (jak przy zamknięciu sesji).
    func endTransactionBeforeLogoff() async throws -> Bool {
        guard document.transactionOpen, !document.isDisconnected else { return true }
        let commit: Bool
        switch workspace.settings.logoffWithOpenTransaction {
        case .commit: commit = true
        case .rollback: commit = false
        case .ask:
            guard let ui = workspace.ui else { commit = false; break }
            let choice = await ui.ask(L10n.tr("Transakcja okna „\(document.title)” jest otwarta"),
                                      message: L10n.tr("Zatwierdzić czy wycofać zmiany przed zmianą połączenia okna?"),
                                      buttons: [L10n.tr("Zatwierdź"), L10n.tr("Wycofaj"), L10n.tr("Anuluj")])
            guard let choice, choice < 2 else { return false }
            commit = choice == 0
        }
        try await workspace.endTransactions(of: [document], commit: commit)
        return true
    }

    /// Połączenie tymczasowe (CONNECT u/hasło@baza) po odejściu okna: usunięte razem z hasłem z pamięci, chyba że
    /// używa go inne okno albo jest połączeniem głównym.
    func releaseTemporary(_ id: UUID) {
        guard !workspace.connections.connections.contains(where: { $0.id == id }), workspace.connections.connection(id) != nil,
              workspace.sessions.mainConnectionID != id,
              !workspace.documents.contains(where: { $0.connectionID == id }) else { return }
        workspace.connections.removeTemporary(id)
    }

    func switchConnection(_ id: UUID) async throws {
        let old = windowConnection
        if let old {
            await workspace.sessions.close(workspace.sessions.key(forDocument: document.id, connection: old))
        }
        document.connectionID = id
        document.transactionOpen = false
        document.isDisconnected = false
        if let old, old != id { releaseTemporary(old) }
        let s = try await workspace.session(for: document)
        emit(L10n.tr("Połączono jako \(s.info.sessionUser)."))
    }
}
