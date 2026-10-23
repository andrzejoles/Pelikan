import Foundation
import PelikanDB

/// Operacje administracyjne na obiektach (PD-OB-019, 020, 021, 023) i pomoc okna programu (PD-PROG-010, 011, 016).
public enum ObjectAdmin {
    static func ident(_ s: String) -> String { ResultExporter.identifier(s) }
    static func bind(_ n: String, _ v: String) -> BindVariable { BindVariable(name: n, value: .text(v)) }

    // MARK: Włączanie i wyłączanie

    /// Wyzwalacz: ALTER TRIGGER … ENABLE/DISABLE; tabela: wszystkie wyzwalacze albo wskazany więz.
    public static func setEnabled(_ o: DBObject, enabled: Bool, constraint: String? = nil) throws -> String {
        let state = enabled ? "ENABLE" : "DISABLE"
        switch o.type {
        case .trigger: return "ALTER TRIGGER \(ident(o.owner)).\(ident(o.name)) \(state)"
        case .table:
            if let c = constraint, !c.isEmpty { return "ALTER TABLE \(ident(o.owner)).\(ident(o.name)) \(state) CONSTRAINT \(ident(c.uppercased()))" }
            return "ALTER TABLE \(ident(o.owner)).\(ident(o.name)) \(state) ALL TRIGGERS"
        default: throw CommandError.notAvailable(L10n.tr("Włączanie i wyłączanie dotyczy wyzwalaczy i tabel (wyzwalacze, więzy)"))
        }
    }

    // MARK: Kosz

    public struct RecycledObject: Sendable, Hashable, Identifiable {
        public var binName: String
        public var originalName: String
        public var type: String
        public var dropTime: String
        public var canRestore: Bool
        public var id: String { binName }
    }

    public static func recycleBin(_ s: any DatabaseSession) async throws -> [RecycledObject] {
        let (_, rows) = try await s.queryAll("""
            select object_name, original_name, type, droptime, can_undrop from user_recyclebin order by droptime desc
            """, limit: 100_000)
        return rows.map { RecycledObject(binName: $0[0].displayText ?? "", originalName: $0[1].displayText ?? "", type: $0[2].displayText ?? "",
                                         dropTime: $0[3].displayText ?? "", canRestore: $0[4].displayText == "YES") }
    }

    /// FLASHBACK TABLE "BIN$…" TO BEFORE DROP [RENAME TO nazwa].
    public static func restoreStatement(binName: String, renameTo: String? = nil) -> String {
        "FLASHBACK TABLE \"\(binName.replacingOccurrences(of: "\"", with: ""))\" TO BEFORE DROP"
            + (renameTo.flatMap { $0.isEmpty ? nil : " RENAME TO \(ident($0.uppercased()))" } ?? "")
    }

    /// PURGE TABLE/INDEX "BIN$…" albo cały kosz użytkownika.
    public static func purgeStatement(_ o: RecycledObject?) -> String {
        guard let o else { return "PURGE RECYCLEBIN" }
        let kind = o.type.uppercased() == "INDEX" ? "INDEX" : "TABLE"
        return "PURGE \(kind) \"\(o.binName.replacingOccurrences(of: "\"", with: ""))\""
    }

    // MARK: Flagi kompilacji warunkowej

    public static func ccflags(_ o: DBObject, in s: any DatabaseSession) async throws -> String {
        try await s.scalar("select plsql_ccflags from all_plsql_object_settings where owner = :o and name = :n and type = :t",
                           binds: [bind("o", o.owner), bind("n", o.name), bind("t", o.type.rawValue)]) ?? ""
    }

    /// ALTER … COMPILE PLSQL_CCFLAGS = '…' REUSE SETTINGS (ciało pakietu/typu: COMPILE BODY).
    public static func ccflagsStatement(_ o: DBObject, flags: String) throws -> String {
        guard !flags.contains("'"), flags.range(of: #"^[A-Za-z0-9_:, ]*$"#, options: .regularExpression) != nil else {
            throw CommandError.invalidArgument("flags", flags)
        }
        let (kind, body): (String, String) = switch o.type {
        case .packageBody: ("PACKAGE", " BODY")
        case .typeBody: ("TYPE", " BODY")
        case .package, .procedure, .function, .trigger, .type: (o.type.rawValue, "")
        default: throw CommandError.notAvailable(L10n.tr("Flagi kompilacji dotyczą jednostek PL/SQL"))
        }
        return "ALTER \(kind) \(ident(o.owner)).\(ident(o.name)) COMPILE\(body) PLSQL_CCFLAGS = '\(flags)' REUSE SETTINGS"
    }

    // MARK: Zmiany obiektów w bazie

    static func key(_ o: DBObject) -> String { "\(o.owner).\(o.name).\(o.type.rawValue)" }

    /// LAST_DDL_TIME (z sekundami) obiektów.
    public static func lastDDLTimes(_ objects: [DBObject], in s: any DatabaseSession) async throws -> [String: String] {
        var out: [String: String] = [:]
        for o in objects {
            if let t = try await s.scalar("""
                select to_char(last_ddl_time, 'YYYY-MM-DD HH24:MI:SS') from all_objects where owner = :o and object_name = :n and object_type = :t
                """, binds: [bind("o", o.owner), bind("n", o.name), bind("t", o.type.rawValue)]) { out[key(o)] = t }
        }
        return out
    }

    /// Obiekty okna zmienione w bazie od wczytania/kompilacji (klucze `WŁAŚCICIEL.NAZWA.TYP`).
    @MainActor
    public static func changedObjects(of doc: Document, in s: any DatabaseSession) async throws -> [String] {
        let objects = doc.objectTimestamps.keys.compactMap { k -> DBObject? in
            let p = k.split(separator: ".", maxSplits: 2).map(String.init)
            guard p.count == 3, let t = DBObjectType(rawValue: p[2]) else { return nil }
            return DBObject(owner: p[0], name: p[1], type: t)
        }
        let now = try await lastDDLTimes(objects, in: s)
        return doc.objectTimestamps.filter { k, v in now[k].map { $0 != v } ?? false }.map(\.key).sorted()
    }

    // MARK: Kompilacja próbna

    /// Tekst jednostki z nazwą zamienioną na tymczasową (pierwsze wystąpienie nazwy po CREATE … typ [schemat.]).
    public static func renamed(_ u: ProgramUnit, to temp: String) -> String? {
        let pattern = #"(?is)^(\s*create\s+(?:or\s+replace\s+)?(?:(?:editionable|noneditionable)\s+)?(?:package\s+body|type\s+body|package|procedure|function|type)\s+)((?:"?[A-Za-z0-9_$#]+"?\s*\.\s*)?"?[A-Za-z0-9_$#]+"?)"#
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: u.text, range: NSRange(location: 0, length: (u.text as NSString).length)) else { return nil }
        return (u.text as NSString).replacingCharacters(in: m.range(at: 2), with: temp)
    }

    /// Kompiluje jednostki okna pod nazwą tymczasową (bez zastępowania obiektów w bazie), zwraca komunikaty i usuwa
    /// obiekty tymczasowe. Wyzwalacze pomijane (tymczasowy wyzwalacz działałby na tabeli).
    public static func safeCompile(_ units: [ProgramUnit], in s: any DatabaseSession) async throws -> [CompileMessage] {
        var messages: [CompileMessage] = []
        var temps: [String: String] = [:]          // nazwa → tymczasowa (wspólna dla specyfikacji i ciała)
        var created: [(String, String)] = []       // (typ do DROP, nazwa)
        do {
            try await compileTemporary(units, temps: &temps, created: &created, messages: &messages, in: s)
        } catch {
            for (kind, name) in created.reversed() { _ = try? await s.execute("DROP \(kind) \(name)") }
            throw error
        }
        // Obiekty tymczasowe usuwane od razu (ciało pakietu znika razem ze specyfikacją).
        for (kind, name) in created.reversed() { _ = try? await s.execute("DROP \(kind) \(name)") }
        return messages
    }

    static func compileTemporary(_ units: [ProgramUnit], temps: inout [String: String], created: inout [(String, String)],
                                 messages: inout [CompileMessage], in s: any DatabaseSession) async throws {
        for u in units where u.type != .trigger {
            let base = u.name.uppercased()
            let temp = temps[base] ?? "PELIKAN$SAFE_\(UUID().uuidString.prefix(8).uppercased())"
            temps[base] = temp
            guard let text = renamed(u, to: temp) else { continue }
            do { _ = try await s.execute(text) } catch let e as OracleError {
                messages.append(CompileMessage(severity: .error, unit: u.tabTitle, line: u.line + 1, column: 1, text: e.message))
                continue
            }
            if [.package, .type, .procedure, .function].contains(u.type) { created.append((u.type.rawValue, temp)) }
            let (_, rows) = try await s.queryAll("""
                select line, position, text, attribute from user_errors where name = :n and type = :t order by sequence
                """, binds: [bind("n", temp), bind("t", u.type.rawValue)], limit: 10_000)
            for r in rows {
                let attr = (r[3].displayText ?? "ERROR").uppercased()
                messages.append(CompileMessage(severity: attr == "WARNING" ? .warning : .error, unit: u.tabTitle,
                                               line: u.line + (Int(r[0].format(.default)) ?? 1), column: Int(r[1].format(.default)) ?? 1,
                                               text: (r[2].displayText ?? "").replacingOccurrences(of: temp, with: base).trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }
}

extension Workspace {
    /// Sprawdza okna programu z zapisanymi znacznikami czasu i ostrzega na pasku stanu o obiektach zmienionych w bazie.
    @discardableResult
    public func checkProgramWindowChanges() async -> [DocumentID] {
        var changed: [DocumentID] = []
        for doc in documents where doc.kind == .program && !doc.objectTimestamps.isEmpty && !doc.isExecuting {
            guard let conn = effectiveConnection(of: doc), let s = sessions.existingSession(SessionKey(connectionID: conn, purpose: .main)),
                  let names = try? await ObjectAdmin.changedObjects(of: doc, in: s), !names.isEmpty else { continue }
            doc.statusText = L10n.tr("⚠️ Obiekt zmieniony w bazie po wczytaniu: \(names.joined(separator: ", ")) — porównaj ze źródłem w bazie przed kompilacją")
            changed.append(doc.id)
        }
        return changed
    }
}
