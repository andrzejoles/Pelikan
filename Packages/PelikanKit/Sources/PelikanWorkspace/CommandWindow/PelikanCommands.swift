import Foundation
import PelikanDB
import PelikanSQL

/// Polecenia własne okna poleceń (UG 8.3–8.4, PD-CMDW-009/010): obiekty przez komendy rejestru, pliki w katalogu
/// bieżącym (CD), eksport tabel i obiektów składnią `klucz=wartość`.
extension SQLPlusEngine {
    func pelikanCommand(_ cmd: String, _ args: [String], line: String) async throws {
        func object() throws -> String {
            guard let o = args.first else { throw SQLPlusError(L10n.tr("Podaj nazwę obiektu")) }
            return o
        }
        @discardableResult
        func invoke(_ id: CommandID, _ extra: [String: JSONValue] = [:]) async throws -> CommandResult {
            var a: [String: JSONValue] = ["object": .string(try object())]
            // Obiekt z połączenia tego okna poleceń, nie głównego (D185).
            if let windowConnection { a["connection"] = .string(windowConnection.uuidString) }
            for (k, v) in extra { a[k] = v }
            return try await workspace.invoke(id, CommandArguments(a))
        }
        switch cmd {
        case "EDIT":
            if args.isEmpty {
                // EDIT bez argumentu: bufor SQL w nowym oknie SQL (jak SQL*Plus EDIT).
                let d = workspace.newDocument(.sql, text: state.buffer ?? "")
                d.connectionID = windowConnection
            } else {
                try await invoke("ob.edit")
            }
        case "BROWSE":
            guard let m = workspace.metadata(for: windowConnection),
                  let o = try await m.find(try object()) else { throw SQLPlusError(L10n.tr("Nie znaleziono obiektu \(args.first ?? "")")) }
            workspace.selectedObject = o
            workspace.selectedObjects = [o]
            workspace.selectedObjectConnection = windowConnection
            emit(L10n.tr("Zaznaczono w przeglądarce obiektów: \(o.type.rawValue) \(o.qualifiedName)"))
        case "EDITDATA": try await invoke("ob.editData")
        case "QUERYDATA": try await invoke("ob.queryData")
        case "PROPERTIES": try await invoke("ob.properties")
        case "RECOMPILE":
            let r = try await invoke("ob.recompile")
            emit(r.message ?? r.value?.description ?? L10n.tr("Skompilowano"))
        case "TEST": try await invoke("ob.test")
        case "VIEW": try await invoke("ob.ddl")
        case "INFO" where line.uppercased().hasPrefix("INFO+"):
            guard let name = args.first else { throw SQLPlusError(L10n.tr("INFO+ obiekt")) }
            try await infoPlus(name)
        case "INFO":
            if let name = args.first {
                try await describe(name)
            } else {
                let conn = windowConnection.flatMap { workspace.connections.connection($0) }
                emit(L10n.tr("Połączenie: \(conn?.displayName ?? "—")"))
                if let s = try? await windowSession() {
                    let (_, rows) = try await s.queryAll("select user, sys_context('userenv','current_schema'), sys_context('userenv','db_name'), (select banner_full from v$version where rownum = 1) from dual", limit: 1)
                    if let r = rows.first {
                        emit(L10n.tr("Użytkownik: \(r[0].displayText ?? ""), schemat: \(r[1].displayText ?? ""), baza: \(r[2].displayText ?? "")"))
                        emit(r[3].displayText ?? "")
                    }
                }
            }
        case "DIR":
            let mask = args.first ?? "*"
            let files = (try? FileManager.default.contentsOfDirectory(atPath: currentDirectory.path)) ?? []
            for f in files.sorted() where Self.matches(mask, f) { emit(f) }
        case "BEAUTIFY":
            guard let file = args.first else { throw SQLPlusError(L10n.tr("Podaj plik")) }
            let url = resolve(file, baseDirectory: nil)
            let text = try String(contentsOf: url, encoding: .utf8)
            try Beautifier.format(text, options: workspace.settings.beautifier).write(to: url, atomically: true, encoding: .utf8)
            emit(L10n.tr("Sformatowano: \(url.lastPathComponent)"))
        case "ZIP":
            guard args.count >= 2 else { throw SQLPlusError(L10n.tr("ZIP archiwum.zip plik…")) }
            // Poza głównym aktorem jak HOST (R7-19): duże archiwum nie zamraża interfejsu, Przerwij kończy proces.
            let arguments = ["-q", "-j", resolve(args[0], baseDirectory: nil).path] + args.dropFirst().map { resolve($0, baseDirectory: nil).path }
            let directory = currentDirectory
            let task = Task.detached {
                try await HostCommand.run(executable: URL(fileURLWithPath: "/usr/bin/zip"), arguments: arguments, directory: directory, timeout: 3600)
            }
            hostTask = task
            defer { hostTask = nil }
            let r = try await task.value
            guard r.status == 0 else {
                if !r.output.isEmpty { emit(r.output.trimmingCharacters(in: .newlines), .output) }
                throw SQLPlusError(L10n.tr("ZIP zakończył się błędem \(r.status)"))
            }
            emit(L10n.tr("Utworzono: \(args[0])"))
        case "EXPORT":
            try await export(args)
        case "RUNTESTSET":
            // RUNTESTSET plik.pts — wynik każdego testu i podsumowanie (UG 8.5).
            guard let file = args.first, let conn = windowConnection else { throw SQLPlusError(L10n.tr("RUNTESTSET plik")) }
            let set = try TestSet.decode(Data(contentsOf: resolve(file, baseDirectory: nil)))
            let results = await TestManager.run(set, connectionID: conn, in: workspace)
            let ok = L10n.tr("OK"), failed = L10n.tr("BŁĄD"), width = max(ok.count, failed.count)
            for r in results {
                emit("\((r.passed ? ok : failed).padding(toLength: width, withPad: " ", startingAt: 0)) \(r.name) (\(String(format: "%.2f", r.seconds)) s)", r.passed ? .output : .error)
                for f in r.failures { emit("     " + f, .error) }
            }
            emit(L10n.tr("Testy: \(results.count), udane: \(results.filter(\.passed).count), nieudane: \(results.filter { !$0.passed }.count)"))
        default:
            break
        }
    }

    /// Maska plików `*` i `?` bez wielkości liter (przenośnie — `fnmatch`/FNM_CASEFOLD nie ma w glibc).
    nonisolated static func matches(_ mask: String, _ name: String) -> Bool {
        let pattern = "^" + NSRegularExpression.escapedPattern(for: mask).replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".") + "$"
        return name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Parametry `klucz=wartość` (wartości z apostrofami albo cudzysłowami).
    nonisolated static func keyValues(_ args: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for a in args {
            guard let eq = a.firstIndex(of: "=") else { continue }
            out[a[..<eq].lowercased()] = String(a[a.index(after: eq)...])
        }
        return out
    }

    /// `EXPORT TABLES file=… tables=a,b [owner=…] [where=…] [drop=y create=y truncate=y delete=y triggers=n fk=n commit=100]`
    /// `EXPORT OBJECTS file=… objects=a,b|types=PACKAGE,VIEW [owner=…] [privileges=y storage=y schema=y]` (UG 8.4).
    func export(_ args: [String]) async throws {
        guard let kind = args.first?.uppercased(), ["TABLES", "OBJECTS"].contains(kind) else {
            throw SQLPlusError(L10n.tr("EXPORT TABLES … albo EXPORT OBJECTS …"))
        }
        let kv = Self.keyValues(Array(args.dropFirst()))
        guard let file = kv["file"] else { throw SQLPlusError(L10n.tr("Brak parametru file=")) }
        guard let s = try? await windowSession() else { throw CommandError.notConnected }
        var owner = kv["owner"]?.uppercased() ?? ""
        if owner.isEmpty { owner = try await s.scalar("select sys_context('userenv','current_schema') from dual") ?? "" }
        let yes: (String, Bool) -> Bool = { k, d in kv[k].map { ["y", "yes", "true", "1", "t"].contains($0.lowercased()) } ?? d }
        let list = { (k: String) in kv[k]?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() } ?? [] }
        let text: String
        if kind == "TABLES" {
            var o = TableExportOptions()
            o.drop = yes("drop", false); o.create = yes("create", false); o.truncate = yes("truncate", false); o.delete = yes("delete", false)
            o.disableTriggers = !yes("triggers", true); o.disableForeignKeys = !yes("fk", true)
            o.commitEvery = Int(kv["commit"] ?? "") ?? o.commitEvery
            o.whereClause = kv["where"] ?? ""
            let tables = list("tables").isEmpty ? try await TableTransfer.tables(owner: owner, in: s) : list("tables")
            text = try await TableTransfer.sqlInserts(tables, owner: owner, options: o, in: s)
        } else {
            var o = ObjectExportOptions()
            o.includePrivileges = yes("privileges", true); o.includeStorage = yes("storage", false); o.includeOwner = yes("schema", false)
            let all = try await ObjectExport.objects(owner: owner, in: s)
            let names = Set(list("objects")), types = Set(list("types"))
            let pick = all.filter { (names.isEmpty || names.contains($0.name)) && (types.isEmpty || types.contains($0.type.rawValue)) }
            text = try await ObjectExport.export(pick, options: o, in: s).first?.content ?? ""
        }
        let url = resolve(file, baseDirectory: nil)
        try text.write(to: url, atomically: true, encoding: .utf8)
        emit(L10n.tr("Wyeksportowano do \(url.lastPathComponent)"))
    }
}
