import Foundation
import PelikanDB
import PelikanSQL

/// Rodzaj wykresu (UG 13, PD-GRAPH-001).
public enum ChartKind: String, Sendable, Codable, CaseIterable {
    case bar, line, area, point, pie

    public var displayName: String {
        switch self {
        case .bar: L10n.tr("Słupkowy")
        case .line: L10n.tr("Liniowy")
        case .area: L10n.tr("Warstwowy")
        case .point: L10n.tr("Punktowy")
        case .pie: L10n.tr("Kołowy")
        }
    }
}

/// Agregacja wartości serii w obrębie kategorii (kilka wierszy z tą samą kategorią).
public enum ChartAggregation: String, Sendable, Codable, CaseIterable {
    case none, sum, average, count, minimum, maximum

    public var displayName: String {
        switch self {
        case .none: L10n.tr("Bez agregacji (ostatnia wartość)")
        case .sum: L10n.tr("Suma")
        case .average: L10n.tr("Średnia")
        case .count: L10n.tr("Liczba")
        case .minimum: L10n.tr("Minimum")
        case .maximum: L10n.tr("Maksimum")
        }
    }
}

/// Definicja wykresu — także szablon zapisywany w katalogu danych (kolumny po nazwie, więc pasuje do innych zapytań
/// o tych samych kolumnach).
public struct ChartDefinition: Sendable, Codable, Hashable, Identifiable {
    public var id = UUID()
    public var name: String
    public var kind: ChartKind = .bar
    public var title = ""
    /// Kolumna kategorii (oś X, wycinki); nil — numer wiersza.
    public var categoryColumn: String?
    /// Kolumny serii (oś Y).
    public var seriesColumns: [String] = []
    public var aggregation: ChartAggregation = .none
    public var stacked = false
    public var showLegend = true
    public var showValues = false
    /// Kolory serii (styl); puste — kolory systemowe.
    public var colors: [RGBColor] = []
    /// Automatyczne odświeżanie: ponowne wykonanie zapytania co n sekund (0 — wyłączone).
    public var refreshSeconds = 0

    public init(name: String) { self.name = name }
}

public struct ChartPoint: Sendable, Hashable, Identifiable {
    public var series: String
    public var category: String
    /// Pozycja kategorii (kolejność pierwszego wystąpienia).
    public var index: Int
    public var value: Double
    public var id: String { "\(series)|\(index)" }
}

/// Dane gotowe do narysowania.
public struct ChartData: Sendable, Hashable {
    public var categories: [String]
    public var series: [String]
    public var points: [ChartPoint]
    /// Komórki serii pominięte, bo wartość nie jest liczbą.
    public var skipped: Int
}

/// Budowanie danych wykresu z wyniku zapytania (kolumny + wiersze).
public enum ChartBuilder {
    /// Liczba z wartości komórki (NUMBER, tekst z liczbą, także z przecinkiem dziesiętnym); nil — nie liczba.
    public static func number(_ v: OracleValue) -> Double? {
        if case .null = v { return nil }
        guard let t = v.displayText?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        // Tylko zapis dziesiętny: Double() przyjmuje też „inf”, „nan” i „0x10”.
        guard t.allSatisfy({ "0123456789+-.,eE ".contains($0) }) else { return nil }
        let d = Double(t) ?? Double(t.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "."))
        return d.flatMap { $0.isFinite ? $0 : nil }
    }

    public static func label(_ v: OracleValue, format: ValueFormat) -> String {
        if case .null = v { return "(null)" }
        return v.format(format)
    }

    /// Kolumna liczbowa wg typu Oracle.
    static func isNumeric(_ c: ColumnInfo) -> Bool {
        let t = c.typeName.uppercased()
        return t.hasPrefix("NUMBER") || t.hasPrefix("BINARY_") || t.hasPrefix("FLOAT") || t.hasPrefix("INTEGER")
    }

    /// Propozycja wykresu: kategoria — pierwsza kolumna nieliczbowa, a gdy wszystkie są liczbowe i jest ich kilka —
    /// pierwsza kolumna (zwykle klucz, np. DEPTNO); pozostałe kolumny liczbowe jako serie.
    public static func suggest(_ columns: [ColumnInfo], name: String = L10n.tr("Wykres")) -> ChartDefinition {
        var d = ChartDefinition(name: name)
        d.categoryColumn = columns.first { !isNumeric($0) }?.name ?? (columns.count > 1 ? columns.first?.name : nil)
        d.seriesColumns = columns.filter { isNumeric($0) && $0.name != d.categoryColumn }.map(\.name)
        if d.seriesColumns.isEmpty, let last = columns.last(where: { $0.name != d.categoryColumn }) { d.seriesColumns = [last.name] }
        return d
    }

    public static func build(_ def: ChartDefinition, columns: [ColumnInfo], rows: [[OracleValue]], format: ValueFormat = .default) -> ChartData {
        let names = columns.map { $0.name.uppercased() }
        let catIndex = def.categoryColumn.flatMap { names.firstIndex(of: $0.uppercased()) }
        let series = def.seriesColumns.compactMap { s in names.firstIndex(of: s.uppercased()).map { (columns[$0].name, $0) } }
        var categories: [String] = []
        var position: [String: Int] = [:]
        // seria → indeks kategorii → zebrane wartości
        var values: [String: [Int: [Double]]] = [:]
        var skipped = 0
        for (r, row) in rows.enumerated() {
            let category = catIndex.map { $0 < row.count ? label(row[$0], format: format) : "" } ?? String(r + 1)
            let idx: Int
            if let p = position[category] {
                idx = p
            } else {
                idx = categories.count
                position[category] = idx
                categories.append(category)
            }
            for (name, col) in series {
                let v = col < row.count ? row[col] : .null
                if def.aggregation == .count {
                    if case .null = v { continue }
                    values[name, default: [:]][idx, default: []].append(1)
                    continue
                }
                guard let n = number(v) else { skipped += 1; continue }
                values[name, default: [:]][idx, default: []].append(n)
            }
        }
        var points: [ChartPoint] = []
        for (name, _) in series {
            for (idx, category) in categories.enumerated() {
                guard let list = values[name]?[idx], !list.isEmpty else { continue }
                let value: Double = switch def.aggregation {
                case .none: list.last!
                case .sum, .count: list.reduce(0, +)
                case .average: list.reduce(0, +) / Double(list.count)
                case .minimum: list.min()!
                case .maximum: list.max()!
                }
                points.append(ChartPoint(series: name, category: category, index: idx, value: value))
            }
        }
        return ChartData(categories: categories, series: series.map(\.0), points: points, skipped: skipped)
    }

    public static func build(_ def: ChartDefinition, data: ExportData, format: ValueFormat = .default) -> ChartData {
        build(def, columns: data.columns, rows: data.rows, format: format)
    }
}

/// Szablony wykresów w katalogu danych (`ChartTemplates.json`).
public enum ChartTemplateStore {
    static func url(_ dir: URL?) -> URL? { dir?.appendingPathComponent("ChartTemplates.json") }

    public static func load(from dir: URL?) -> [ChartDefinition] {
        guard let u = url(dir), let data = try? Data(contentsOf: u) else { return [] }
        return (try? JSONDecoder().decode([ChartDefinition].self, from: data)) ?? []
    }

    public static func save(_ templates: [ChartDefinition], to dir: URL?) throws {
        guard let dir, let u = url(dir) else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(templates).write(to: u, options: .atomic)
    }

    /// Dodaje albo zastępuje szablon o tej samej nazwie.
    public static func upsert(_ t: ChartDefinition, in dir: URL?) throws {
        var all = load(from: dir).filter { $0.name != t.name }
        all.append(t)
        try save(all.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }, to: dir)
    }

    public static func remove(named name: String, in dir: URL?) throws {
        try save(load(from: dir).filter { $0.name != name }, to: dir)
    }
}

extension Workspace {
    /// Ponowne wykonanie polecenia karty wyników okna (auto-odświeżanie wykresu) przez wykonanie okna SQL: zaznaczenie
    /// polecenia, wykonanie, przywrócenie zaznaczenia; zwraca nową kartę wyniku (aktywną po wykonaniu). Tekst w zakresie
    /// musi być nadal tym samym poleceniem — po edycji okna zakres wskazywałby inny fragment (także DML/DDL).
    public func reexecute(_ tab: ResultTab, in doc: Document) async throws -> ResultTab? {
        guard !doc.isExecuting else { return nil }
        let saved = doc.selectedRange
        guard statementUnchanged(tab, in: doc) else { throw CommandError.notAvailable(L10n.tr("Polecenie wykresu zmieniło się w oknie")) }
        doc.selectedRange = tab.statementRange
        defer { doc.selectedRange = saved }
        _ = try await SQLExecutor.execute(doc, scope: .standard, in: self)
        return doc.results.first { $0.id == doc.activeResultID } ?? doc.results.last
    }

    /// Zakres karty w bieżącym tekście okna obejmuje dokładnie to samo polecenie, które dało wynik.
    func statementUnchanged(_ tab: ResultTab, in doc: Document) -> Bool {
        guard tab.statementRange.upperBound <= (doc.text as NSString).length, let expected = tab.statementText else { return false }
        return SQLExecutor.statements(text: doc.text, selection: tab.statementRange, scope: .standard,
                                      autoSelect: settings.autoSelectStatement).map(\.text) == [expected]
    }
}
