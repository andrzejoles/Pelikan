import Foundation
import PelikanDB
import PelikanSQL

/// Tabela edytowana w siatce (UG 7.6): ustalona z ROWID pierwszego wiersza (od wersji 17 wzorca), kolumny edytowalne.
public struct EditTarget: Sendable, Hashable {
    public var owner: String?
    public var table: String
    public var rowidColumn: Int
    /// Kolumny wyniku, które można zmieniać (należą do tabeli, bez aliasu, nie wirtualne).
    public var editableColumns: Set<Int>
    /// Nazwa kolumny tabeli dla kolumny wyniku.
    public var tableColumn: [Int: String]
    /// Kolumny LOB/RAW tabeli — zmieniane w Large Data Editor (nie w komórce).
    public var largeDataColumns: Set<Int> = []

    public var qualifiedName: String {
        [owner, table].compactMap { $0 }.map(ResultExporter.identifier).joined(separator: ".")
    }
}

/// Stan edycji siatki: zmienione komórki, wstawione i usunięte wiersze (indeksy wierszy danych).
public struct GridEditState: Sendable {
    public var target: EditTarget?
    /// Przyczyna braku edycji (np. brak ROWID) — pokazywana w interfejsie.
    public var notEditableReason: String?
    public var isEditing = false
    public var changed: [Int: [Int: OracleValue]] = [:]
    public var inserted: Set<Int> = []
    public var deleted: Set<Int> = []
    /// Komórki z wartością przekraczającą rozmiar/precyzję kolumny (czerwony tekst — UG 7.6).
    public var overflow: Set<CellRef> = []

    public var hasChanges: Bool { !changed.isEmpty || !inserted.isEmpty || !deleted.isEmpty }

    public init() {}
}

public struct CellRef: Sendable, Hashable {
    public var row: Int, column: Int
    public init(row: Int, column: Int) { self.row = row; self.column = column }
}

public enum CellEditState: Sendable {
    case normal, modified, inserted, deleted
}

public enum GridEditError: Error, LocalizedError, Equatable {
    case notEditable(String)
    case readOnlyColumn(String)
    case invalidValue(column: String, reason: String)
    case postFailed(row: Int, column: Int?, message: String)

    public var errorDescription: String? {
        switch self {
        case .notEditable(let why): why
        case .readOnlyColumn(let c): L10n.tr("Kolumna \(c) jest tylko do odczytu")
        case .invalidValue(let c, let why): L10n.tr("Nieprawidłowa wartość w kolumnie \(c): \(why)")
        case .postFailed(let row, _, let message): L10n.tr("Wiersz \(row + 1): \(message)")
        }
    }
}

extension ResultGridModel {
    // MARK: Ustalenie tabeli edytowanej

    /// Indeks kolumny ROWID w wyniku.
    public var rowidColumn: Int? {
        columns.firstIndex { $0.type == .rowid || $0.type == .urowid || $0.name == "ROWID" }
    }

    /// Włącza edycję (Edit data): ustala tabelę z ROWID, kolumny edytowalne; bez ROWID — błąd z wyjaśnieniem.
    public func beginEditing() async throws {
        if edit.target == nil {
            do {
                edit.target = try await resolveTarget()
                edit.notEditableReason = nil
            } catch let e as GridEditError {
                if case .notEditable(let why) = e { edit.notEditableReason = why }
                throw e
            }
        }
        edit.isEditing = true
    }

    public func endEditing() { edit.isEditing = false }

    func resolveTarget() async throws -> EditTarget {
        guard let rid = rowidColumn else {
            throw GridEditError.notEditable(L10n.tr("Wynik nie jest edytowalny: dodaj ROWID do zapytania (np. select t.*, t.rowid from …)"))
        }
        var owner: String?
        var table: String?
        // Tabela z ROWID (działa dla złączeń — ROWID wskazuje, z której tabeli są edytowane kolumny).
        if let firstRowid = rows.lazy.map({ $0[rid] }).first(where: { !$0.isNull }) {
            let (_, r) = try await session.queryAll("""
                select o.owner, o.object_name from all_objects o
                where o.data_object_id = dbms_rowid.rowid_object(:rid)
                  and o.object_type in ('TABLE', 'TABLE PARTITION', 'TABLE SUBPARTITION')
                fetch first 1 row only
                """, binds: [BindVariable(name: "rid", value: .text(firstRowid.format(.default)))], limit: 1)
            if let row = r.first { owner = row[0].displayText; table = row[1].displayText }
        }
        if table == nil {
            guard let name = ResultExporter.tableName(fromQuery: sql) else {
                throw GridEditError.notEditable(L10n.tr("Nie można ustalić tabeli do edycji"))
            }
            let parts = name.split(separator: ".").map(String.init)
            if parts.count == 2 { owner = parts[0]; table = parts[1] } else { table = name }
        }
        guard let tableName = table else { throw GridEditError.notEditable(L10n.tr("Nie można ustalić tabeli do edycji")) }
        let (_, cols) = try await session.queryAll("""
            select column_name, virtual_column from all_tab_cols
            where table_name = :t and owner = nvl(:o, sys_context('USERENV', 'CURRENT_SCHEMA')) and hidden_column = 'NO'
            """, binds: [BindVariable(name: "t", value: .text(tableName)), BindVariable(name: "o", value: owner.map { .text($0) } ?? .null)], limit: 2000)
        let tableCols = Dictionary(cols.compactMap { r in r[0].displayText.map { ($0, r[1].displayText == "YES") } }, uniquingKeysWith: { a, _ in a })
        let items = SelectListParser.items(sql)
        let targetQualifier = items.first { $0.isRowid }?.qualifier
        var editable = Set<Int>()
        var mapping: [Int: String] = [:]
        let hasStar = items.contains { $0.isStar }
        if !hasStar, items.count == columns.count {
            // Pozycyjnie: kolumna wyniku ↔ element listy SELECT.
            for (i, item) in items.enumerated() {
                guard let col = item.column, item.alias == nil || item.alias == col, tableCols[col] == false else { continue }
                guard item.qualifier == nil || targetQualifier == nil || item.qualifier == targetQualifier else { continue }
                editable.insert(i)
                mapping[i] = col
            }
        } else {
            // Z gwiazdką: po nazwach; kolumny z aliasem z listy — tylko do odczytu.
            let aliased = Set(items.compactMap { $0.alias != nil && $0.alias != $0.column ? $0.alias : nil })
            let starOK = items.contains { $0.isStar && ($0.qualifier == nil || targetQualifier == nil || $0.qualifier == targetQualifier) }
            let plain = Set(items.compactMap { item -> String? in
                guard let c = item.column, item.alias == nil || item.alias == c else { return nil }
                return item.qualifier == nil || targetQualifier == nil || item.qualifier == targetQualifier ? c : nil
            })
            for (i, c) in columns.enumerated() where i != rid && tableCols[c.name] == false && !aliased.contains(c.name) {
                if starOK || plain.contains(c.name) {
                    editable.insert(i)
                    mapping[i] = c.name
                }
            }
        }
        // Typy nieedytowalne w komórce: BLOB/LONG RAW — Large Data Editor; obiekty, kursory, wektory, BFILE — wcale.
        let large = editable.filter { [.blob, .clob, .nclob, .longRaw, .raw, .long].contains(columns[$0].type) }
        editable = editable.filter { ![.blob, .bfile, .object, .refCursor, .longRaw, .vector].contains(columns[$0].type) }
        return EditTarget(owner: owner, table: tableName, rowidColumn: rid, editableColumns: editable, tableColumn: mapping,
                          largeDataColumns: large)
    }

    // MARK: Zmiany w siatce

    public func isEditable(column: Int) -> Bool {
        edit.isEditing && (edit.target?.editableColumns.contains(column) ?? false)
    }

    public func cellState(row: Int, column: Int) -> CellEditState {
        let r = dataRow(row)
        if edit.deleted.contains(r) { return .deleted }
        if edit.inserted.contains(r) { return .inserted }
        if edit.changed[r]?[column] != nil { return .modified }
        return .normal
    }

    public func isOverflow(row: Int, column: Int) -> Bool { edit.overflow.contains(CellRef(row: dataRow(row), column: column)) }

    /// Wpisanie tekstu w komórkę: konwersja do typu kolumny (liczba, data wg formatu, tekst), pusty — NULL.
    public func setText(_ text: String, row: Int, column: Int) throws {
        guard let target = edit.target, edit.isEditing else { throw GridEditError.notEditable(L10n.tr("Edycja wyłączona")) }
        guard target.editableColumns.contains(column) else { throw GridEditError.readOnlyColumn(columns[column].name) }
        let value = try Self.parse(text, column: columns[column], format: format)
        let r = dataRow(row)
        if rows[r][column] == value, edit.changed[r]?[column] == nil { return }
        if edit.changed[r]?[column] == nil, !edit.inserted.contains(r) {
            edit.changed[r, default: [:]][column] = rows[r][column]    // wartość pierwotna (do anulowania)
        } else if edit.inserted.contains(r) {
            edit.changed[r, default: [:]][column] = .null
        }
        rows[r][column] = value
        let ref = CellRef(row: r, column: column)
        if Self.exceedsColumn(value, columns[column]) { edit.overflow.insert(ref) } else { edit.overflow.remove(ref) }
    }

    /// Wartość z Large Data Editor (CLOB/BLOB/RAW/LONG — także kolumny niedostępne do edycji w komórce).
    public func setValue(_ value: OracleValue, row: Int, column: Int) throws {
        guard let target = edit.target, edit.isEditing else { throw GridEditError.notEditable(L10n.tr("Edycja wyłączona")) }
        guard target.editableColumns.contains(column) || target.largeDataColumns.contains(column) else {
            throw GridEditError.readOnlyColumn(columns[column].name)
        }
        let r = dataRow(row)
        if edit.changed[r]?[column] == nil { edit.changed[r, default: [:]][column] = edit.inserted.contains(r) ? .null : rows[r][column] }
        rows[r][column] = value
    }

    /// Nowy wiersz (Insert record) — na końcu pobranych wierszy; zwraca wiersz widoku.
    @discardableResult
    public func insertRecord() throws -> Int {
        guard edit.isEditing, edit.target != nil else { throw GridEditError.notEditable(L10n.tr("Edycja wyłączona")) }
        rows.append(Array(repeating: .null, count: columns.count))
        let r = rows.count - 1
        edit.inserted.insert(r)
        if order != nil { order!.append(r) }
        return rowCount - 1
    }

    /// Usunięcie zaznaczonych wierszy (Delete record) — do zatwierdzenia przez Post; wstawione znikają od razu.
    public func deleteRecords(_ viewRows: [Int]) throws {
        guard edit.isEditing, edit.target != nil else { throw GridEditError.notEditable(L10n.tr("Edycja wyłączona")) }
        var removeNow: [Int] = []
        for v in viewRows {
            let r = dataRow(v)
            if edit.inserted.contains(r) { removeNow.append(r) } else { edit.deleted.insert(r) }
        }
        if !removeNow.isEmpty { removeDataRows(Set(removeNow)) }
    }

    /// Anulowanie wszystkich zmian (przywrócenie wartości pierwotnych).
    public func cancelChanges() {
        for (r, cols) in edit.changed where !edit.inserted.contains(r) {
            for (c, original) in cols { rows[r][c] = original }
        }
        let inserted = edit.inserted
        edit.changed = [:]
        edit.deleted = []
        edit.inserted = []
        edit.overflow = []
        if !inserted.isEmpty { removeDataRows(inserted) }
    }

    func removeDataRows(_ remove: Set<Int>) {
        guard !remove.isEmpty else { return }
        // Nowe indeksy: przesunięcie o liczbę usuniętych przed wierszem.
        let sorted = remove.sorted()
        func shift(_ r: Int) -> Int { r - sorted.prefix { $0 < r }.count }
        rows = rows.enumerated().filter { !remove.contains($0.offset) }.map(\.element)
        edit.changed = Dictionary(uniqueKeysWithValues: edit.changed.filter { !remove.contains($0.key) }.map { (shift($0.key), $0.value) })
        edit.inserted = Set(edit.inserted.subtracting(remove).map(shift))
        edit.deleted = Set(edit.deleted.subtracting(remove).map(shift))
        edit.overflow = Set(edit.overflow.filter { !remove.contains($0.row) }.map { CellRef(row: shift($0.row), column: $0.column) })
        if order != nil {
            if sortKeys.isEmpty {
                order = order!.filter { !remove.contains($0) }.map(shift)
            } else {
                applySort()
            }
        }
    }

    // MARK: SQL zmian i zatwierdzanie (Post)

    struct PlannedStatement {
        var dataRow: Int
        var sql: String
        var binds: [BindVariable]
        var preview: String
        var kind: Kind
        enum Kind { case delete, update, insert }
    }

    func plan() -> [PlannedStatement] {
        guard let t = edit.target else { return [] }
        let table = t.qualifiedName
        var out: [PlannedStatement] = []
        func bind(_ name: String, _ c: Int, _ v: OracleValue) -> BindVariable {
            // Duże wartości tekstowe i binarne wiązane jako LOB (literał/VARCHAR2 ma limit 32 767 bajtów).
            var type = Self.bindType(columns[c].type)
            if case .lob(let l) = v { type = l.kind == .blob ? .blob : (l.kind == .nclob ? .nclob : .clob) }
            return BindVariable(name: name, type: type, value: v, maxSize: max(4000, columns[c].size * 4))
        }
        for r in edit.deleted.sorted() {
            let rid = rows[r][t.rowidColumn]
            out.append(PlannedStatement(dataRow: r, sql: "DELETE FROM \(table) WHERE ROWID = :rid",
                                        binds: [BindVariable(name: "rid", type: .varchar2, value: .text(rid.format(.default)))],
                                        preview: "DELETE FROM \(table) WHERE ROWID = \(ResultExporter.literal(.text(rid.format(.default))));", kind: .delete))
        }
        for r in edit.changed.keys.sorted() where !edit.inserted.contains(r) && !edit.deleted.contains(r) {
            let cols = edit.changed[r]!.keys.sorted().filter { t.tableColumn[$0] != nil }
            guard !cols.isEmpty else { continue }
            let rid = rows[r][t.rowidColumn].format(.default)
            let set = cols.enumerated().map { "\(ResultExporter.identifier(t.tableColumn[$1]!)) = :v\($0)" }.joined(separator: ", ")
            let setPreview = cols.map { "\(ResultExporter.identifier(t.tableColumn[$0]!)) = \(ResultExporter.literal(rows[r][$0]))" }.joined(separator: ", ")
            var binds = cols.enumerated().map { bind("v\($0)", $1, rows[r][$1]) }
            binds.append(BindVariable(name: "rid", type: .varchar2, value: .text(rid)))
            out.append(PlannedStatement(dataRow: r, sql: "UPDATE \(table) SET \(set) WHERE ROWID = :rid", binds: binds,
                                        preview: "UPDATE \(table) SET \(setPreview) WHERE ROWID = \(ResultExporter.literal(.text(rid)));", kind: .update))
        }
        for r in edit.inserted.sorted() {
            let cols = t.editableColumns.union(t.largeDataColumns).sorted().filter { !rows[r][$0].isNull && t.tableColumn[$0] != nil }
            let names = cols.map { ResultExporter.identifier(t.tableColumn[$0]!) }.joined(separator: ", ")
            var binds = cols.enumerated().map { bind("v\($0)", $1, rows[r][$1]) }
            binds.append(BindVariable(name: "rid", type: .varchar2, direction: .output, maxSize: 4000))
            let values = cols.indices.map { ":v\($0)" }.joined(separator: ", ")
            let sql = cols.isEmpty ? "INSERT INTO \(table) VALUES (DEFAULT) RETURNING ROWID INTO :rid"
                : "INSERT INTO \(table) (\(names)) VALUES (\(values)) RETURNING ROWID INTO :rid"
            let preview = cols.isEmpty ? "INSERT INTO \(table) VALUES (DEFAULT);"
                : "INSERT INTO \(table) (\(names)) VALUES (\(cols.map { ResultExporter.literal(rows[r][$0]) }.joined(separator: ", ")));"
            out.append(PlannedStatement(dataRow: r, sql: sql, binds: binds, preview: preview, kind: .insert))
        }
        return out
    }

    /// SQL zmian do podglądu (UG 7.6: Post changes ▾ — pokaż w SQL Window / kopiuj).
    public func changesSQL() -> String { plan().map(\.preview).joined(separator: "\n") }

    /// Zatwierdza zmiany w bazie (bez COMMIT). Po błędzie: wiersz i kolumna (jeśli z komunikatu) do pokazania;
    /// zmiany wykonane przed błędem zostają w transakcji, wiersz z błędem pozostaje do poprawienia.
    @discardableResult
    public func postChanges() async throws -> Int {
        guard let t = edit.target else { throw GridEditError.notEditable(L10n.tr("Edycja wyłączona")) }
        let statements = plan()
        var done = 0
        var deletedRows = Set<Int>()
        for p in statements {
            do {
                let result = try await session.execute(p.sql, binds: p.binds, options: ExecuteOptions())
                switch p.kind {
                case .delete:
                    deletedRows.insert(p.dataRow)
                case .update:
                    edit.changed[p.dataRow] = nil
                    try await refresh(dataRow: p.dataRow, target: t)
                case .insert:
                    if let rid = result.outBinds.first(where: { $0.key.lowercased() == "rid" })?.value {
                        rows[p.dataRow][t.rowidColumn] = .rowid(rid.format(.default))
                    }
                    edit.inserted.remove(p.dataRow)
                    edit.changed[p.dataRow] = nil
                    try await refresh(dataRow: p.dataRow, target: t)
                }
                done += 1
            } catch let e as OracleError {
                edit.deleted.subtract(deletedRows)
                removeDataRows(deletedRows)
                let col = Self.columnFromError(e.message, columns: columns)
                throw GridEditError.postFailed(row: viewRow(ofDataRow: p.dataRow - deletedRows.filter { $0 < p.dataRow }.count) ?? 0,
                                               column: col, message: e.message)
            }
        }
        edit.deleted.subtract(deletedRows)
        removeDataRows(deletedRows)
        edit.overflow = []
        return done
    }

    /// Wartości z bazy po zapisie (wyzwalacze, wartości domyślne, kolumny wirtualne — UG 7.6).
    func refresh(dataRow r: Int, target t: EditTarget) async throws {
        let mapped = t.tableColumn.sorted { $0.key < $1.key }
        guard !mapped.isEmpty else { return }
        let list = mapped.map { ResultExporter.identifier($0.value) }.joined(separator: ", ")
        let rid = rows[r][t.rowidColumn].format(.default)
        let (_, data) = try await session.queryAll("SELECT \(list) FROM \(t.qualifiedName) WHERE ROWID = :rid",
                                                   binds: [BindVariable(name: "rid", value: .text(rid))], limit: 1)
        guard let fresh = data.first else { return }
        for (i, m) in mapped.enumerated() where i < fresh.count { rows[r][m.key] = fresh[i] }
    }

    func viewRow(ofDataRow r: Int) -> Int? {
        guard let o = order else { return r }
        return o.firstIndex(of: r)
    }

    /// Kolumna z komunikatu ORA (np. ORA-12899: value too large for column "S"."T"."COL", ORA-01400 … ("S"."T"."COL")).
    static func columnFromError(_ message: String, columns: [ColumnInfo]) -> Int? {
        guard let m = message.range(of: #"\"[^\"]+\"\.\"[^\"]+\"\.\"([^\"]+)\""#, options: .regularExpression) else { return nil }
        let name = message[m].split(separator: ".").last.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        return columns.firstIndex { $0.name == name }
    }

    static func bindType(_ t: OracleType) -> OracleType {
        switch t {
        case .number, .binaryInteger, .binaryFloat, .binaryDouble, .date, .timestamp, .timestampTZ, .timestampLTZ, .raw, .clob, .nclob,
             .nvarchar2, .nchar, .char:
            t == .binaryFloat || t == .binaryDouble ? .number : t
        default: .varchar2
        }
    }

    // MARK: Konwersja i walidacja

    /// Tekst z komórki → wartość typu kolumny.
    static func parse(_ text: String, column c: ColumnInfo, format: ValueFormat) throws -> OracleValue {
        if text.isEmpty { return .null }
        switch c.type {
        case .number, .binaryInteger, .binaryFloat, .binaryDouble:
            let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            guard normalized.range(of: #"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$"#, options: .regularExpression) != nil else {
                throw GridEditError.invalidValue(column: c.name, reason: L10n.tr("oczekiwana liczba"))
            }
            return .number(normalized)
        case .date, .timestamp, .timestampTZ, .timestampLTZ:
            guard let ts = OracleTimestamp.parse(text, mask: c.type == .date ? format.dateFormat : format.timestampFormat)
                ?? OracleTimestamp.parse(text, mask: "YYYY-MM-DD HH24:MI:SS") ?? OracleTimestamp.parse(text, mask: "YYYY-MM-DD") else {
                throw GridEditError.invalidValue(column: c.name, reason: L10n.tr("oczekiwana data w formacie \(c.type == .date ? format.dateFormat : format.timestampFormat)"))
            }
            return .timestamp(ts, c.type)
        case .raw:
            guard text.count.isMultiple(of: 2), let d = Data(hex: text) else {
                throw GridEditError.invalidValue(column: c.name, reason: L10n.tr("oczekiwane cyfry szesnastkowe"))
            }
            return .raw(d)
        case .clob, .nclob:
            return .lob(LOBValue(kind: c.type == .nclob ? .nclob : .clob, text: text, length: UInt64(text.count), truncated: false))
        default:
            return .text(text)
        }
    }

    /// Przekroczenie rozmiaru (znaki/bajty) albo precyzji liczby.
    static func exceedsColumn(_ v: OracleValue, _ c: ColumnInfo) -> Bool {
        switch v {
        case .text(let s) where c.size > 0 && c.type.isCharacter && c.type != .clob && c.type != .nclob:
            return s.utf8.count > Int(c.size) && s.count > Int(c.size)
        case .number(let n) where c.precision > 0:
            let digits = n.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "+", with: "")
            let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
            let intDigits = parts.first.map { $0.drop { $0 == "0" }.count } ?? 0
            return intDigits > Int(c.precision) - Int(c.scale)
        default:
            return false
        }
    }
}

extension Data {
    init?(hex: String) {
        var data = Data(capacity: hex.count / 2)
        var it = hex.makeIterator()
        while let a = it.next(), let b = it.next() {
            guard let byte = UInt8(String([a, b]), radix: 16) else { return nil }
            data.append(byte)
        }
        self = data
    }
}

/// Elementy listy SELECT na najwyższym poziomie (do ustalenia kolumn edytowalnych).
enum SelectListParser {
    struct Item: Equatable {
        var qualifier: String?
        var column: String?
        var alias: String?
        var isStar = false
        var isRowid = false
    }

    static func items(_ sql: String) -> [Item] {
        let ns = sql as NSString
        let tokens = Lexer(sql).tokenize().filter { ![.whitespace, .newline, .lineComment, .blockComment, .hint].contains($0.kind) }
        func text(_ t: Token) -> String { ns.substring(with: NSRange(location: t.start, length: t.length)) }
        func name(_ t: Token) -> String { t.kind == .quotedIdentifier ? String(text(t).dropFirst().dropLast()) : text(t).uppercased() }
        guard let selectIndex = tokens.firstIndex(where: { text($0).uppercased() == "SELECT" }) else { return [] }
        var i = selectIndex + 1
        if i < tokens.count, ["DISTINCT", "UNIQUE", "ALL"].contains(text(tokens[i]).uppercased()) { i += 1 }
        var groups: [[Token]] = [[]]
        var depth = 0
        while i < tokens.count {
            let t = tokens[i]
            if t.kind == .leftParen { depth += 1 }
            if t.kind == .rightParen { depth -= 1 }
            if depth == 0, t.kind == .keyword || t.kind == .identifier, text(t).uppercased() == "FROM" { break }
            if depth == 0, t.kind == .comma { groups.append([]) } else { groups[groups.count - 1].append(t) }
            i += 1
        }
        return groups.filter { !$0.isEmpty }.map { g in
            var item = Item()
            var g = g
            // Alias: „… AS x” albo „… x” (identyfikator po wyrażeniu).
            if g.count >= 2, let last = g.last,
               last.kind == .identifier || last.kind == .quotedIdentifier || (last.kind == .keyword && !Keywords.reserved.contains(text(last).uppercased())) {
                let prev = g[g.count - 2]
                if text(prev).uppercased() == "AS" {
                    item.alias = name(last)
                    g.removeLast(2)
                } else if prev.kind != .dot {
                    item.alias = name(last)
                    g.removeLast()
                }
            }
            // Nazwą kolumny może być słowo kluczowe niezastrzeżone (BODY, DATA, TYPE…) i ROWID.
            let isIdent: (Token) -> Bool = {
                $0.kind == .identifier || $0.kind == .quotedIdentifier
                    || ($0.kind == .keyword && (!Keywords.reserved.contains(text($0).uppercased()) || text($0).uppercased() == "ROWID"))
            }
            if g.count == 1, text(g[0]) == "*" {
                item.isStar = true
            } else if g.count == 3, isIdent(g[0]), g[1].kind == .dot, text(g[2]) == "*" {
                item.isStar = true
                item.qualifier = name(g[0])
            } else if g.count == 1, isIdent(g[0]) {
                item.column = name(g[0])
            } else if g.count == 3, isIdent(g[0]), g[1].kind == .dot, isIdent(g[2]) {
                item.qualifier = name(g[0])
                item.column = name(g[2])
            }
            if item.column == "ROWID" { item.isRowid = true; item.column = nil }
            return item
        }
    }
}
