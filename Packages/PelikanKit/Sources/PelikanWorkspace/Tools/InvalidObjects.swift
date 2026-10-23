import Foundation
import PelikanDB

/// Compile Invalid Objects (UG 24.3): lista nieprawidłowych obiektów schematu i kompilacja w kolejności zależności
/// (kolejne przebiegi, dopóki liczba nieprawidłowych maleje), z błędami z ALL_ERRORS.
public struct InvalidObjectResult: Sendable, Hashable, Identifiable {
    public var object: DBObject
    public var valid: Bool
    public var errors: [String]
    public var id: String { object.id }
}

@MainActor
public enum InvalidObjects {
    /// Kolejność typów przy kompilacji: najpierw te, od których zależą inne.
    static let typeOrder: [DBObjectType] = [.type, .package, .view, .materializedView, .synonym, .function, .procedure, .typeBody,
                                            .packageBody, .trigger, .javaSource, .mleModule]

    /// Nieprawidłowe obiekty (właściciel nil — wszyscy dostępni).
    public static func list(_ m: MetadataProvider, owner: String?) async throws -> [DBObject] {
        let s = try await m.session()
        var binds: [BindVariable] = []
        var sql = "select owner, object_name, object_type, status from all_objects where status = 'INVALID' and object_name not like 'BIN$%'"
        if let owner { sql += " and owner = :o"; binds.append(BindVariable(name: "o", value: .text(owner))) }
        sql += " order by owner, object_type, object_name"
        let (_, rows) = try await s.queryAll(sql, binds: binds, limit: 100_000)
        let objects = rows.compactMap { r -> DBObject? in
            guard let t = DBObjectType(rawValue: r[2].displayText ?? "") else { return nil }
            return DBObject(owner: r[0].displayText ?? "", name: r[1].displayText ?? "", type: t, status: r[3].displayText ?? "INVALID")
        }
        return objects.sorted { a, b in
            let ia = typeOrder.firstIndex(of: a.type) ?? typeOrder.count, ib = typeOrder.firstIndex(of: b.type) ?? typeOrder.count
            return ia != ib ? ia < ib : (a.owner, a.name) < (b.owner, b.name)
        }
    }

    /// Kompiluje obiekty w sesji kompilacji; `progress` po każdym obiekcie. Zwraca wynik dla każdego obiektu.
    public static func compile(_ objects: [DBObject], in ws: Workspace, connectionID: UUID,
                               progress: ((Int, Int) -> Void)? = nil) async throws -> [InvalidObjectResult] {
        let statements = objects.compactMap(ObjectCommands.compileStatement)
        try await ws.guardModification(statements, connectionID: connectionID)
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: connectionID))
        var pending = objects
        var done = 0
        // Przebiegi: obiekt nieprawidłowy po kompilacji może się udać po skompilowaniu zależności.
        for _ in 0..<4 where !pending.isEmpty {
            var still: [DBObject] = []
            for o in pending {
                guard let sql = ObjectCommands.compileStatement(o) else { continue }
                _ = try? await s.execute(sql)
                if try await status(o, session: s) != "VALID" { still.append(o) }
                done += 1
                progress?(min(done, objects.count), objects.count)
            }
            if still.count == pending.count { pending = still; break }
            pending = still
        }
        var results: [InvalidObjectResult] = []
        for o in objects {
            let valid = !pending.contains(o)
            var errors: [String] = []
            if !valid {
                let (_, rows) = try await s.queryAll("""
                    select line || ':' || position || ' ' || text from all_errors
                    where owner = :o and name = :n and type = :t and attribute = 'ERROR' order by sequence
                    """, binds: [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "n", value: .text(o.name)),
                                 BindVariable(name: "t", value: .text(o.type.rawValue))], limit: 200)
                errors = rows.compactMap { $0.first?.displayText?.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            results.append(InvalidObjectResult(object: o, valid: valid, errors: errors))
        }
        ws.metadata(for: connectionID)?.refresh()
        return results
    }

    static func status(_ o: DBObject, session s: any DatabaseSession) async throws -> String? {
        try await s.scalar("select status from all_objects where owner = :o and object_name = :n and object_type = :t",
                           binds: [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "n", value: .text(o.name)),
                                   BindVariable(name: "t", value: .text(o.type.rawValue))])
    }
}
