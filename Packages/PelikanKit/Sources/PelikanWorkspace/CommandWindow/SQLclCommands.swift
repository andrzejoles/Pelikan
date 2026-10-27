import Foundation
import PelikanDB
import PelikanSQL

/// Polecenia SQLcl w oknie poleceń (SC-CMD-001): INFO+, DDL, LOAD, FORMAT, HISTORY, ALIAS, REPEAT, CTAS.
extension SQLPlusEngine {
    func sqlclCommand(_ cmd: String, _ args: [String], line: String, baseDirectory: URL?) async throws -> Outcome {
        switch cmd {
        case "DDL":
            // DDL obiekt [plik] — DDL z DBMS_METADATA na ekran albo do pliku.
            guard let name = args.first else { throw SQLPlusError(L10n.tr("DDL obiekt [plik]")) }
            let o = try await resolveObject(name)
            let s = try await windowSession()
            let ddl = try await MetadataProvider.ddl(of: o, in: s)
            if args.count > 1 {
                let url = resolve(args[1], baseDirectory: baseDirectory)
                try ddl.write(to: url, atomically: true, encoding: .utf8)
                emit(L10n.tr("Zapisano DDL do \(url.lastPathComponent)"))
            } else {
                emit(ddl)
            }
        case "LOAD":
            // LOAD [schemat.]tabela plik.csv [NEW] — CSV/tekst rozdzielany do tabeli (NEW: utworzenie tabeli z danych).
            guard args.count >= 2 else { throw SQLPlusError(L10n.tr("LOAD tabela plik [NEW]")) }
            try await load(table: args[0], file: resolve(args[1], baseDirectory: baseDirectory), create: args.dropFirst(2).contains { $0.uppercased() == "NEW" })
        case "FORMAT":
            // FORMAT BUFFER | FORMAT FILE wejście [wyjście] — formatowanie regułami formatera Pelikana.
            let mode = args.first?.uppercased() ?? "BUFFER"
            if mode == "FILE" {
                guard args.count >= 2 else { throw SQLPlusError(L10n.tr("FORMAT FILE wejście [wyjście]")) }
                let input = resolve(args[1], baseDirectory: baseDirectory)
                let output = args.count > 2 ? resolve(args[2], baseDirectory: baseDirectory) : input
                guard let (text, format) = readScript(input) else {
                    throw SQLPlusError(L10n.tr("SP2-0310: Nie można otworzyć pliku „\(input.lastPathComponent)”."), osError: true)
                }
                try writeScript(try Beautifier.format(text, options: workspace.settings.beautifier), format: format, to: output)
                emit(L10n.tr("Sformatowano: \(output.lastPathComponent)"))
            } else {
                guard let b = state.buffer else { throw SQLPlusError(L10n.tr("SP2-0103: Bufor SQL jest pusty.")) }
                let f = try Beautifier.format(b, options: workspace.settings.beautifier)
                state.buffer = f
                emit(f)
            }
        case "HISTORY":
            // HISTORY [TIME | CLEAR | n] — polecenia okna (z czasami: TIME), ponowne wykonanie numeru n.
            let opt = args.first?.uppercased() ?? ""
            if opt == "CLEAR" { state.history.removeAll(); emit(L10n.tr("Historia wyczyszczona")); return .finished }
            if let n = Int(opt), n >= 1, n <= state.history.count {
                let sql = state.history[n - 1].sql
                emit(sql, .echo)
                return await run(sql, baseDirectory: baseDirectory)
            }
            for (i, h) in state.history.enumerated() {
                let first = h.sql.components(separatedBy: "\n").first ?? ""
                emit(opt == "TIME" ? String(format: "%4d  (%6.3f s)  %@", i + 1, Double(h.milliseconds) / 1000, first) : String(format: "%4d  %@", i + 1, first))
            }
        case "ALIAS":
            // ALIAS nazwa=polecenie | ALIAS LIST | ALIAS DROP nazwa.
            let rest = Self.rest(line).trimmingCharacters(in: .whitespacesAndNewlines)
            let upper = rest.uppercased()
            if rest.isEmpty || upper == "LIST" {
                for (k, v) in state.aliases.sorted(by: { $0.key < $1.key }) { emit("\(k) = \(v)") }
            } else if upper.hasPrefix("DROP ") {
                state.aliases[String(rest.dropFirst(5)).trimmingCharacters(in: .whitespaces).uppercased()] = nil
            } else if let eq = rest.firstIndex(of: "=") {
                let name = rest[..<eq].trimmingCharacters(in: .whitespaces).uppercased()
                guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { throw SQLPlusError(L10n.tr("Nieprawidłowa nazwa aliasu")) }
                state.aliases[name] = rest[rest.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
                emit(L10n.tr("Alias \(name) zapisany"))
            } else {
                throw SQLPlusError(L10n.tr("ALIAS nazwa=polecenie"))
            }
        case "REPEAT":
            // REPEAT n sekundy — powtarza bufor n razy co podaną liczbę sekund (przerywane przez Przerwij).
            guard let n = args.first.flatMap(Int.init), n > 0 else { throw SQLPlusError(L10n.tr("REPEAT liczba [sekundy]")) }
            let seconds = args.count > 1 ? Double(args[1].replacingOccurrences(of: ",", with: ".")) ?? 1 : 1
            guard let b = state.buffer else { throw SQLPlusError(L10n.tr("SP2-0103: Bufor SQL jest pusty.")) }
            for i in 1...n {
                if cancelled { return .stopped }
                emit(L10n.tr("Powtórzenie \(i) z \(n)"), .info)
                let o = await executeSQL(b, original: b, isPLSQL: ScriptSplitter.split(b).first?.isPLSQL ?? false)
                if o != .finished { return o }
                if i < n { try? await Task.sleep(for: .milliseconds(Int(seconds * 1000))) }
            }
        case "CTAS":
            // CTAS tabela nowa_tabela — polecenie CREATE TABLE … AS SELECT z listą kolumn do bufora i na ekran.
            guard args.count >= 2 else { throw SQLPlusError(L10n.tr("CTAS tabela nowa_tabela")) }
            let o = try await resolveObject(args[0])
            let s = try await windowSession()
            let (_, rows) = try await s.queryAll("select column_name from all_tab_columns where owner = :o and table_name = :t order by column_id",
                                                 binds: [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "t", value: .text(o.name))], limit: 2000)
            let cols = rows.compactMap { $0.first?.displayText }.map { "  " + ResultExporter.identifier($0) }.joined(separator: ",\n")
            // Nowa nazwa w cudzysłowie — bez zmiany wielkości liter.
            let newName = args[1].contains("\"") ? args[1] : args[1].lowercased()
            let sql = "create table \(newName) as\nselect\n\(cols)\n  from \(ResultExporter.displayQualified(owner: o.owner, name: o.name))"
            state.buffer = sql
            emit(sql + ";")
        default:
            break
        }
        return .finished
    }

    func resolveObject(_ name: String) async throws -> DBObject {
        guard let m = workspace.metadata(for: windowConnection), let o = try await m.find(name) else {
            throw SQLPlusError(L10n.tr("Nie znaleziono obiektu \(name)"))
        }
        return o
    }

    /// INFO+ — kolumny ze statystykami optymalizatora (liczba różnych wartości, NULL, histogram, ostatnia analiza).
    func infoPlus(_ name: String) async throws {
        let o = try await resolveObject(name)
        let s = try await windowSession()
        emit(L10n.tr("\(o.type.rawValue) \(o.qualifiedName)"))
        let (cols, rows) = try await s.queryAll("""
            select c.column_name, c.data_type || case when c.data_type in ('VARCHAR2','CHAR','NVARCHAR2','RAW') then '(' || c.data_length || ')'
                   when c.data_precision is not null then '(' || c.data_precision || nvl2(c.data_scale, ',' || c.data_scale, '') || ')' end typ,
                   c.nullable, st.num_distinct, st.num_nulls, st.histogram, to_char(st.last_analyzed, 'YYYY-MM-DD HH24:MI') last_analyzed
              from all_tab_columns c left join all_tab_col_statistics st
                on st.owner = c.owner and st.table_name = c.table_name and st.column_name = c.column_name
             where c.owner = :o and c.table_name = :t order by c.column_id
            """, binds: [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "t", value: .text(o.name))], limit: 2000)
        var f = TextResultFormatter(columns: cols, state: state, format: workspace.settings.valueFormat)
        emit(f.lines(rows, first: true).joined(separator: "\n"))
        if let n = try await s.scalar("select num_rows from all_tables where owner = :o and table_name = :t",
                                      binds: [BindVariable(name: "o", value: .text(o.owner)), BindVariable(name: "t", value: .text(o.name))]) {
            emit(L10n.tr("Wierszy (statystyki): \(n)"))
        }
    }

    /// LOAD: plik rozdzielany do tabeli w sesji okna (mapowanie kolumn po nazwach nagłówka; NEW — nowa tabela).
    func load(table: String, file: URL, create: Bool) async throws {
        let (text, _) = TextImport.decode(try Data(contentsOf: file))
        let format = TextImport.detect(text)
        let (header, rows) = TextImport.parse(text, format)
        guard !header.isEmpty else { throw SQLPlusError(L10n.tr("Plik nie ma nagłówka z nazwami kolumn")) }
        let s = try await windowSession()
        let parts = table.split(separator: ".").map { ResultExporter.dictionaryName(String($0)) }
        let owner = parts.count == 2 ? parts[0] : (try await s.scalar("select sys_context('userenv','current_schema') from dual") ?? "")
        let name = parts.last ?? ResultExporter.dictionaryName(table)
        let conn = windowConnection
        var mappings: [FieldMapping]
        if create {
            let ddl = TextImport.createTable(owner: owner, table: name, fieldNames: header, rows: rows)
            try await workspace.guardModification([ddl.sql], connectionID: conn)
            _ = try await s.execute(ddl.sql)
            mappings = ddl.mappings
        } else {
            mappings = try await TextImport.defaultMappings(owner: owner, table: name, fieldNames: header, in: s)
        }
        try await workspace.guardModification(["insert into \(owner).\(name) values (null)"], connectionID: conn)
        let target = ImportTarget(owner: owner, table: name, mappings: mappings)
        let r = try await TextImport.run(rows, fieldNames: header, target: target, in: s)
        emit(L10n.tr("Wczytano wierszy: \(r.inserted), pominięto: \(r.skipped), błędy: \(r.errors.count)"))
        for e in r.errors.prefix(10) { emit(e, .error) }
        document.transactionOpen = (try? await SessionUtilities.transactionOpen(s)) ?? document.transactionOpen
    }
}
