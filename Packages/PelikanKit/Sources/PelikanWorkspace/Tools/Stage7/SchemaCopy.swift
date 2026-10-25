import Foundation
import PelikanDB
import PelikanSQL

/// Kreator kopiowania schematu (Database Copy, SD-COPY-001): obiekty i dane schematu źródłowego do schematu
/// docelowego (to samo albo inne połączenie). Kolejność: sekwencje i typy, tabele bez kluczy obcych, dane, pozostałe
/// obiekty (indeksy, widoki, kod), klucze obce, wyzwalacze — wyzwalacze nie odpalają się przy kopiowaniu danych.
public enum SchemaCopy {
    public struct Options: Sendable, Hashable, Codable {
        /// Typy obiektów (puste — wszystkie).
        public var types: Set<String> = []
        /// Wybrane obiekty „TYP NAZWA” (puste — wszystkie typów z `types`).
        public var objects: Set<String> = []
        public var copyData = true
        /// Warunek WHERE dla danych wszystkich tabel.
        public var whereClause = ""
        /// Istniejący obiekt w celu: usunięcie i utworzenie (inaczej pominięcie z komunikatem).
        public var replaceExisting = false
        public var commitEvery = 1000
        public init() {}
    }

    public enum Phase: Int, Sendable, Hashable, Comparable {
        case early, tables, data, objects, foreignKeys, triggers
        public static func < (a: Phase, b: Phase) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Step: Sendable, Hashable {
        public var phase: Phase
        public var object: DBObject
    }

    public struct Report: Sendable {
        public var created: [String] = []
        public var skipped: [String] = []
        public var errors: [String] = []
        public var rows = 0
    }

    static func phase(_ t: DBObjectType) -> Phase {
        switch t {
        case .sequence, .type: .early
        case .table: .tables
        case .trigger: .triggers
        default: .objects
        }
    }

    /// Plan kopiowania (czysta funkcja): obiekty w kolejności faz i typów; dane i klucze obce dla tabel.
    public static func plan(_ objects: [DBObject], options: Options) -> [Step] {
        let chosen = objects.filter { o in
            (options.types.isEmpty || options.types.contains(o.type.rawValue)) && (options.objects.isEmpty || options.objects.contains("\(o.type.rawValue) \(o.name)"))
        }
        var steps = chosen.map { Step(phase: phase($0.type), object: $0) }
        let tables = chosen.filter { $0.type == .table }
        if options.copyData { steps += tables.map { Step(phase: .data, object: $0) } }
        steps += tables.map { Step(phase: .foreignKeys, object: $0) }
        return steps.sorted {
            ($0.phase, ObjectExport.sortKey($0.object.type), $0.object.name) < ($1.phase, ObjectExport.sortKey($1.object.type), $1.object.name)
        }
    }

    /// DDL obiektu bez schematu; tabele bez więzów kluczy obcych (te w fazie `foreignKeys`).
    static func ddl(_ o: DBObject, in s: any DatabaseSession) async throws -> String {
        if o.type != .table {
            var options = ObjectExportOptions()
            options.includePrivileges = false
            return try await ObjectExport.ddl(o, options: options, in: s)
        }
        let r = try await s.execute("""
            begin
              dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'DEFAULT', true);
              dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', true);
              dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SEGMENT_ATTRIBUTES', false);
              dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'REF_CONSTRAINTS', false);
              begin dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'EMIT_SCHEMA', false); exception when others then null; end;
              :ddl := dbms_metadata.get_ddl('TABLE', :n, :o);
              dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'DEFAULT', true);
            end;
            """, binds: [BindVariable(name: "ddl", type: .clob, direction: .output), BindVariable(name: "n", value: .text(o.name)), BindVariable(name: "o", value: .text(o.owner))])
        guard case .lob(let l)? = r.outBinds["ddl"], let text = l.text else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Więzy kluczy obcych tabeli jako polecenia ALTER (bez schematu) albo pusty tekst.
    static func foreignKeyDDL(_ o: DBObject, in s: any DatabaseSession) async throws -> String {
        let r = try await s.execute("""
            begin
              begin dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'EMIT_SCHEMA', false); exception when others then null; end;
              dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', true);
              begin :ddl := dbms_metadata.get_dependent_ddl('REF_CONSTRAINT', :n, :o); exception when others then :ddl := null; end;
              dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'DEFAULT', true);
            end;
            """, binds: [BindVariable(name: "ddl", type: .clob, direction: .output), BindVariable(name: "n", value: .text(o.name)), BindVariable(name: "o", value: .text(o.owner))])
        guard case .lob(let l)? = r.outBinds["ddl"], let text = l.text else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Polecenia skryptu DDL do wykonania (bez średników na końcu SQL; bloki PL/SQL bez „/”).
    static func statements(_ script: String) -> [String] {
        ScriptSplitter.split(script, mode: .commandWindow).compactMap { st in
            var t = st.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasSuffix("/") { t = String(t.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
            if !st.isPLSQL { while t.hasSuffix(";") { t.removeLast() } }
            return t.isEmpty || st.sqlplusCommand != nil ? nil : t
        }
    }

    /// Kopiowanie. `target` — sesja docelowa (jej bieżący schemat zostaje przełączony na `targetOwner`).
    public static func run(sourceOwner: String, source: any DatabaseSession, targetOwner: String, target: any DatabaseSession,
                           options: Options, progress: (@MainActor (String) -> Void)? = nil) async throws -> Report {
        var report = Report()
        let objects = try await ObjectExport.objects(owner: sourceOwner, in: source)
        let steps = plan(objects, options: options)
        let existing = Set(try await ObjectExport.objects(owner: targetOwner, in: target).map { "\($0.type.rawValue) \($0.name)" })
        let previous = try await target.scalar("select sys_context('userenv', 'current_schema') from dual") ?? targetOwner
        _ = try await target.execute("alter session set current_schema = \(ResultExporter.identifier(targetOwner))")
        do {
            try await copy(steps, existing: existing, sourceOwner: sourceOwner, source: source, targetOwner: targetOwner, target: target,
                           options: options, report: &report, progress: progress)
        } catch {
            _ = try? await target.execute("alter session set current_schema = \(ResultExporter.identifier(previous))")
            throw error
        }
        _ = try await target.execute("alter session set current_schema = \(ResultExporter.identifier(previous))")
        return report
    }

    static func copy(_ steps: [Step], existing: Set<String>, sourceOwner: String, source: any DatabaseSession, targetOwner: String,
                     target: any DatabaseSession, options: Options, report: inout Report, progress: (@MainActor (String) -> Void)?) async throws {
        var skippedTables: Set<String> = []
        for step in steps {
            try Task.checkCancellation()
            let o = step.object
            let key = "\(o.type.rawValue) \(o.name)"
            await progress?("\(o.type.rawValue.lowercased()) \(o.name)")
            switch step.phase {
            case .data:
                guard !skippedTables.contains(o.name) else { continue }
                let data = try await TableTransfer.exportNative([o.name], owner: sourceOwner, whereClause: options.whereClause, includeDDL: false, in: source)
                var io = TableImportOptions()
                io.create = false
                io.commitEvery = options.commitEvery
                let r = try await TableTransfer.importNative(try TableTransfer.unpackNative(data), tables: [o.name], intoOwner: targetOwner, options: io, in: target)
                report.rows += r.inserted
                report.errors += r.errors
            case .foreignKeys:
                guard !skippedTables.contains(o.name) else { continue }
                for st in statements(try await foreignKeyDDL(o, in: source)) {
                    do { _ = try await target.execute(st) } catch { report.errors.append("\(o.name): \(error.localizedDescription)") }
                }
            default:
                if existing.contains(key) {
                    guard options.replaceExisting else {
                        report.skipped.append(key)
                        if o.type == .table { skippedTables.insert(o.name) }
                        continue
                    }
                    // Kod, widoki i synonimy mają CREATE OR REPLACE; pozostałe usuwamy przed utworzeniem.
                    if [.table, .sequence, .index, .materializedView, .type].contains(o.type) {
                        let drop = "drop \(o.type.rawValue.lowercased()) \(ResultExporter.identifier(o.name))" + (o.type == .table ? " cascade constraints purge" : o.type == .type ? " force" : "")
                        do { _ = try await target.execute(drop) } catch { report.errors.append("\(key): \(error.localizedDescription)") }
                    }
                }
                var ok = true
                for st in statements(try await ddl(o, in: source)) {
                    do {
                        // ORA-24344 (kompilacja z błędami) sterowniki zgłaszają jako ostrzeżenie wyniku, nie wyjątek.
                        if try await target.execute(st).warning?.code == 24344 {
                            report.errors.append("\(key): " + L10n.tr("utworzono z błędami kompilacji"))
                        }
                    } catch {
                        ok = false
                        report.errors.append("\(key): \(error.localizedDescription)")
                        break
                    }
                }
                if ok { report.created.append(key) } else if o.type == .table { skippedTables.insert(o.name) }
            }
        }
    }
}
