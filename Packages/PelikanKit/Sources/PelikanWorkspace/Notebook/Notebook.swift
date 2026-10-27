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
        var session: (any DatabaseSession)?
        do {
            try await ws.guardModification(statements.map(\.text), connectionID: ws.effectiveConnection(of: doc))
            let s = try await ws.session(for: doc)
            session = s
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
                } else {
                    result.messages.append(L10n.tr("Wykonano."))
                }
                result.output += (try? await SessionUtilities.readOutput(s)) ?? []
            }
        } catch {
            result.error = error.localizedDescription
        }
        // Stan transakcji z sesji (DML w bloku PL/SQL, SELECT FOR UPDATE, DDL zatwierdzający) — jak w oknie SQL.
        if let session { doc.transactionOpen = (try? await SessionUtilities.transactionOpen(session)) ?? doc.transactionOpen }
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

    /// Notatnik bez trwającego wykonania (usuwanie i przestawianie komórek czeka na koniec — wynik trafia po id komórki).
    static func idleNotebook(_ ws: Workspace) -> Document? {
        notebook(ws).flatMap { $0.isExecuting ? nil : $0 }
    }

    /// Komórka z argumentu `index` (od 0).
    static func cellIndex(_ ctx: CommandContext, in d: Document) throws -> Int {
        guard let i = ctx.arguments.int("index") else { throw CommandError.missingArgument("index") }
        guard d.notebook.cells.indices.contains(Int(i)) else { throw CommandError.invalidArgument("index", String(i)) }
        return Int(i)
    }

    static let indexParameter = CommandParameter("index", .integer, required: true, L10n.tr("Numer komórki (od 0)"))

    /// Dodanie komórki SQL albo Markdown (SD-NB-001): na końcu albo przed komórką `index`, z tekstem `text`.
    static func addCell(_ kind: NotebookCell.Kind, id: CommandID, title: String) -> Command {
        Command(CommandDescriptor(id: id, title: title, category: .edit, submenu: L10n.tr("Notatnik"),
                                  parameters: [CommandParameter("text", .string, L10n.tr("Tekst komórki")),
                                               CommandParameter("index", .integer, L10n.tr("Pozycja nowej komórki (od 0; domyślnie na końcu)"))],
                                  agent: .none, effect: .modifiesEditor,
                                  summary: L10n.tr("Dodaje do notatnika nową komórkę; notatnik jest zmieniony do zapisu."), feature: "SD-NB-001"),
                validate: { notebook($0) != nil }) { ctx in
            guard let d = notebook(ctx.workspace) else { return .ok }
            let cell = NotebookCell(kind: kind, text: ctx.arguments.string("text") ?? "")
            let at = ctx.arguments.int("index").map { min(max(0, Int($0)), d.notebook.cells.count) } ?? d.notebook.cells.count
            d.notebook.cells.insert(cell, at: at)
            d.isModified = true
            return CommandResult(value: .int(Int64(at)))
        }
    }

    static var all: [Command] {
        [
            addCell(.sql, id: "notebook.addSQLCell", title: L10n.tr("Dodaj komórkę SQL")),
            addCell(.markdown, id: "notebook.addMarkdownCell", title: L10n.tr("Dodaj komórkę Markdown")),
            Command(CommandDescriptor(id: "notebook.removeCell", title: L10n.tr("Usuń komórkę"), category: .edit, submenu: L10n.tr("Notatnik"),
                                      parameters: [indexParameter], agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Usuwa komórkę notatnika razem z jej wynikiem."), inMenu: false, feature: "SD-NB-001"),
                    validate: { idleNotebook($0) != nil }) { ctx in
                guard let d = idleNotebook(ctx.workspace) else { return .ok }
                d.notebook.cells.remove(at: try cellIndex(ctx, in: d))
                d.isModified = true
                return .ok
            },
            Command(CommandDescriptor(id: "notebook.moveCell", title: L10n.tr("Przesuń komórkę"), category: .edit, submenu: L10n.tr("Notatnik"),
                                      parameters: [indexParameter, CommandParameter("by", .integer, required: true, L10n.tr("Przesunięcie: -1 w górę, 1 w dół"))],
                                      agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Przesuwa komórkę notatnika w górę albo w dół."), inMenu: false, feature: "SD-NB-001"),
                    validate: { idleNotebook($0) != nil }) { ctx in
                guard let d = idleNotebook(ctx.workspace) else { return .ok }
                let i = try cellIndex(ctx, in: d)
                guard let by = ctx.arguments.int("by") else { throw CommandError.missingArgument("by") }
                let j = i + Int(by)
                guard d.notebook.cells.indices.contains(j) else { return .ok }
                d.notebook.cells.swapAt(i, j)
                d.isModified = true
                return .ok
            },
            Command(CommandDescriptor(id: "notebook.toggleChart", title: L10n.tr("Wykres z wyniku komórki"), category: .edit, submenu: L10n.tr("Notatnik"),
                                      parameters: [indexParameter], agent: .none, effect: .modifiesEditor,
                                      summary: L10n.tr("Pokazuje wykres z wyniku komórki SQL (propozycja z kolumn liczbowych) albo go usuwa."), inMenu: false,
                                      feature: "SD-NB-002"),
                    validate: { notebook($0) != nil }) { ctx in
                guard let d = notebook(ctx.workspace) else { return .ok }
                let i = try cellIndex(ctx, in: d)
                guard let r = d.notebook.cells[i].result, !r.columns.isEmpty else {
                    throw CommandError.notAvailable(L10n.tr("Komórka nie ma wyniku zapytania"))
                }
                d.notebook.cells[i].chart = d.notebook.cells[i].chart == nil ? r.suggestedChart() : nil
                d.isModified = true
                return .ok
            },
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
