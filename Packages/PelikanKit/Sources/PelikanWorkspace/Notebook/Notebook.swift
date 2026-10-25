import Foundation
import PelikanDB
import PelikanSQL

/// Wynik komórki notatnika (zapisywany w pliku razem z komórką).
public struct NotebookResult: Sendable, Codable, Hashable {
    public var columns: [String] = []
    /// Typy kolumn (nazwy typów Oracle) — potrzebne do wykresu (liczby).
    public var columnTypes: [String] = []
    public var rows: [[String?]] = []
    public var truncated = false
    public var messages: [String] = []
    public var output: [String] = []
    public var error: String?
    public var milliseconds = 0
    public var finished = Date()
    public init() {}
}

/// Komórka notatnika: SQL/PL/SQL (skrypt) albo Markdown; opcjonalny wykres z wyniku (SD-NB-002).
public struct NotebookCell: Sendable, Codable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Codable, CaseIterable { case sql, markdown }
    public var id = UUID()
    public var kind: Kind
    public var text: String
    public var result: NotebookResult?
    public var chart: ChartDefinition?
    public init(kind: Kind, text: String) { self.kind = kind; self.text = text }
}

/// Notatnik SQL (plik `.sqlnb`, JSON) — SD-NB-001.
public struct Notebook: Sendable, Codable, Hashable {
    public var format = "pelikan-notebook"
    public var version = 1
    public var cells: [NotebookCell] = [NotebookCell(kind: .markdown, text: "# " + L10n.tr("Notatnik")), NotebookCell(kind: .sql, text: "select sysdate from dual")]
    /// Limit wierszy wyniku zapisywanego w komórce.
    public var maxRows = 200
    public init() {}

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(self)
    }

    public static func decode(_ data: Data) throws -> Notebook {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let n = try d.decode(Notebook.self, from: data)
        guard n.format == "pelikan-notebook" else { throw CommandError.notAvailable(L10n.tr("To nie jest notatnik Pelikana")) }
        return n
    }
}

extension NotebookResult {
    /// Dane wykresu z wyniku komórki (kolumny liczbowe rozpoznawane po typie Oracle).
    public func chartData(_ def: ChartDefinition) -> ChartData {
        let cols = zip(columns, columnTypes + Array(repeating: "", count: max(0, columns.count - columnTypes.count))).map { name, type -> ColumnInfo in
            let numeric = ["NUMBER", "FLOAT", "BINARY_DOUBLE", "BINARY_FLOAT", "INTEGER"].contains { type.uppercased().hasPrefix($0) }
            return ColumnInfo(name: name, type: numeric ? .number : .varchar2, typeName: type)
        }
        let values: [[OracleValue]] = rows.map { r in
            r.enumerated().map { i, v in
                guard let v else { return .null }
                return i < cols.count && cols[i].type == .number ? .number(v.replacingOccurrences(of: ",", with: ".")) : .text(v)
            }
        }
        return ChartBuilder.build(def, columns: cols, rows: values)
    }

    /// Propozycja wykresu (kategoria + kolumny liczbowe).
    public func suggestedChart() -> ChartDefinition {
        let cols = zip(columns, columnTypes).map { name, type in
            ColumnInfo(name: name, type: type.uppercased().hasPrefix("NUMBER") ? .number : .varchar2, typeName: type)
        }
        return ChartBuilder.suggest(cols)
    }
}

/// Wykonanie komórek w sesji okna notatnika: każde polecenie skryptu po kolei, wynik ostatniego zapytania w komórce,
/// komunikaty i DBMS_OUTPUT; zmiany przez strażnika zmian (prod potwierdza, tylko do odczytu blokuje).
@MainActor
public enum NotebookRunner {
    public static func run(cell index: Int, in doc: Document, ws: Workspace) async {
        // Jedno wykonanie naraz w sesji okna; wynik trafia do komórki po identyfikatorze (komórki mogą się przestawić).
        guard !doc.isExecuting, doc.notebook.cells.indices.contains(index), doc.notebook.cells[index].kind == .sql else { return }
        let cellID = doc.notebook.cells[index].id
        doc.isExecuting = true
        defer { doc.isExecuting = false }
        let started = ContinuousClock.now
        var result = NotebookResult()
        let statements = ScriptSplitter.split(doc.notebook.cells[index].text, mode: .commandWindow).filter { $0.sqlplusCommand == nil }
        do {
            try await ws.guardModification(statements.map(\.text), connectionID: ws.effectiveConnection(of: doc))
            let s = try await ws.session(for: doc)
            try? await SessionUtilities.enableOutput(s, bufferSize: ws.settings.dbmsOutputBufferSize)
            for st in statements {
                var sql = st.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !st.isPLSQL { while sql.hasSuffix(";") { sql.removeLast() } }
                if sql.hasSuffix("/") { sql = String(sql.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
                guard !sql.isEmpty else { continue }
                let r = try await s.execute(sql, binds: [], options: ExecuteOptions(lobLimit: 16_000))
                if let rs = r.resultSet {
                    result.columns = rs.columns.map(\.name)
                    result.columnTypes = rs.columns.map(\.typeName)
                    result.rows = []
                    result.truncated = false
                    while true {
                        let batch = try await s.fetch(rs.id, maxRows: min(500, doc.notebook.maxRows + 1 - result.rows.count))
                        for row in batch.rows {
                            if result.rows.count >= doc.notebook.maxRows { result.truncated = true; break }
                            result.rows.append(row.map { v in
                                if case .null = v { return nil }
                                if case .lob(let l) = v { return l.text ?? "<\(l.kind.rawValue)>" }
                                return v.format(ws.settings.valueFormat)
                            })
                        }
                        if result.truncated || !batch.hasMore { break }
                    }
                    if result.truncated { await s.closeResultSet(rs.id) }
                } else if r.kind == .dml {
                    result.messages.append(L10n.tr("Wierszy: \(r.rowsAffected)"))
                    doc.transactionOpen = true
                } else {
                    result.messages.append(L10n.tr("Wykonano."))
                }
                result.output += (try? await SessionUtilities.readOutput(s)) ?? []
            }
        } catch {
            result.error = error.localizedDescription
        }
        let d = ContinuousClock.now - started
        result.milliseconds = Int(d.components.seconds) * 1000 + Int(d.components.attoseconds / 1_000_000_000_000_000)
        result.finished = Date()
        if let i = doc.notebook.cells.firstIndex(where: { $0.id == cellID }) {
            doc.notebook.cells[i].result = result
            doc.isModified = true
        }
    }

    /// Run All: komórki SQL po kolei; `stopOnError` — zatrzymanie na pierwszym błędzie.
    public static func runAll(_ doc: Document, ws: Workspace, stopOnError: Bool = true) async {
        for id in doc.notebook.cells.filter({ $0.kind == .sql }).map(\.id) {
            guard let i = doc.notebook.cells.firstIndex(where: { $0.id == id }) else { continue }
            await run(cell: i, in: doc, ws: ws)
            if stopOnError, doc.notebook.cells.first(where: { $0.id == id })?.result?.error != nil { break }
        }
    }

    /// Notatnik jako Markdown (eksport/podgląd): tekst komórek Markdown, SQL w blokach kodu, wyniki jako tabele.
    public static func markdown(_ n: Notebook) -> String {
        var out: [String] = []
        for c in n.cells {
            if c.kind == .markdown { out.append(c.text); continue }
            out.append("```sql\n\(c.text)\n```")
            guard let r = c.result else { continue }
            if let e = r.error { out.append("> " + e); continue }
            if !r.columns.isEmpty {
                out.append("| " + r.columns.joined(separator: " | ") + " |")
                out.append("|" + r.columns.map { _ in "---" }.joined(separator: "|") + "|")
                for row in r.rows { out.append("| " + row.map { ($0 ?? "").replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |") }
            }
            out += r.messages.map { "_\($0)_" }
            if !r.output.isEmpty { out.append("```\n" + r.output.joined(separator: "\n") + "\n```") }
        }
        return out.joined(separator: "\n\n") + "\n"
    }
}

/// Komendy notatnika.
@MainActor
enum NotebookCommands {
    static func notebook(_ ws: Workspace) -> Document? {
        guard let d = ws.activeDocument, d.kind == .notebook else { return nil }
        return d
    }

    static var all: [Command] {
        [
            Command(CommandDescriptor(id: "notebook.runAll", title: L10n.tr("Wykonaj wszystkie komórki"), category: .session, submenu: L10n.tr("Notatnik"),
                                      agent: .none, effect: .modifiesDatabase,
                                      summary: L10n.tr("Wykonuje po kolei komórki SQL notatnika; wyniki zapisują się w notatniku."), feature: "SD-NB-001"),
                    validate: { notebook($0) != nil }) { ctx in
                guard let d = notebook(ctx.workspace) else { return .ok }
                await NotebookRunner.runAll(d, ws: ctx.workspace)
                let errors = d.notebook.cells.filter { $0.result?.error != nil }.count
                return CommandResult(message: errors == 0 ? L10n.tr("Wykonano notatnik") : L10n.tr("Błędy w komórkach: \(errors)"))
            },
            Command(CommandDescriptor(id: "notebook.runCell", title: L10n.tr("Wykonaj komórkę"), category: .session, submenu: L10n.tr("Notatnik"),
                                      parameters: [CommandParameter("index", .integer, required: true, L10n.tr("Numer komórki (od 0)"))],
                                      agent: .none, effect: .modifiesDatabase, summary: L10n.tr("Wykonuje jedną komórkę SQL notatnika."), inMenu: false,
                                      feature: "SD-NB-001")) { ctx in
                guard let d = notebook(ctx.workspace), let i = ctx.arguments.int("index") else { return .ok }
                await NotebookRunner.run(cell: Int(i), in: d, ws: ctx.workspace)
                return .ok
            },
            Command(CommandDescriptor(id: "notebook.exportMarkdown", title: L10n.tr("Eksportuj notatnik jako Markdown…"), category: .file, submenu: L10n.tr("Notatnik"),
                                      agent: .none, effect: .external, summary: L10n.tr("Zapisuje notatnik z wynikami jako dokument Markdown."), feature: "SD-NB-001"),
                    validate: { notebook($0) != nil }) { ctx in
                guard let d = notebook(ctx.workspace) else { return .ok }
                _ = await ctx.ui?.saveFile(suggestedName: d.title, fileExtension: "md", data: Data(NotebookRunner.markdown(d.notebook).utf8))
                return .ok
            },
        ]
    }
}
