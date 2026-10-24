import Foundation
import PelikanDB

/// Układ liczb w siatce (PD-GRID-004, Preferences → Grid → Number layout).
public enum NumberLayout: String, Codable, CaseIterable, Sendable {
    /// Do prawej, bez zmian (domyślnie).
    case right
    /// Do lewej, bez zmian.
    case left
    /// Do prawej, separator dziesiętny z ustawień regionalnych.
    case formatted
    /// Do prawej, separator dziesiętny i separator tysięcy z ustawień regionalnych.
    case thousands

    public var displayName: String {
        switch self {
        case .right: L10n.tr("Do prawej")
        case .left: L10n.tr("Do lewej")
        case .formatted: L10n.tr("Formatowane (separator regionalny)")
        case .thousands: L10n.tr("Z separatorem tysięcy")
        }
    }

    public var alignsRight: Bool { self != .left }

    /// Tekst liczby (pełna precyzja, kropka dziesiętna) w danym układzie. Wartości niebędące zwykłą liczbą dziesiętną
    /// (notacja wykładnicza, Inf, Nan) zostają bez zmian — bez utraty cyfr.
    public func apply(_ text: String, decimal: String, group: String) -> String {
        guard self == .formatted || self == .thousands,
              text.range(of: #"^[+-]?(\d+(\.\d*)?|\.\d+)$"#, options: .regularExpression) != nil else { return text }
        var s = Substring(text)
        var sign = ""
        if let f = s.first, f == "-" || f == "+" { sign = String(f); s = s.dropFirst() }
        let parts = s.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        var integer = String(parts[0])
        let fraction = parts.count > 1 ? String(parts[1]) : nil
        if self == .thousands, integer.count > 3 {
            var out = ""
            for (i, ch) in integer.enumerated() {
                if i > 0, (integer.count - i) % 3 == 0 { out += group }
                out.append(ch)
            }
            integer = out
        }
        return sign + integer + (fraction.map { decimal + $0 } ?? "")
    }

    /// Separatory z ustawień regionalnych systemu.
    public static var localeSeparators: (decimal: String, group: String) {
        let l = Locale.current
        return (l.decimalSeparator ?? ".", l.groupingSeparator ?? " ")
    }
}

public extension ResultGridModel {
    /// Tekst komórki do wyświetlenia w siatce z układem liczb (PD-GRID-004). W trybie edycji — tekst surowy, żeby
    /// wpisana wartość dała się zinterpretować.
    func displayText(row: Int, column: Int, layout: NumberLayout,
                     separators: (decimal: String, group: String) = NumberLayout.localeSeparators) -> String {
        let t = text(row: row, column: column)
        guard columns[column].type.isNumeric, !edit.isEditing else { return t }
        return layout.apply(t, decimal: separators.decimal, group: separators.group)
    }

    /// Data / znacznik czasu bieżącej komórki (kalendarz przy edycji — PD-GRID-005).
    func timestamp(row: Int, column: Int) -> OracleTimestamp? {
        if case .timestamp(let t, _) = value(row: row, column: column) { return t }
        return nil
    }

    /// Czy kolumna przyjmuje datę z kalendarza.
    func isDateColumn(_ column: Int) -> Bool {
        [.date, .timestamp, .timestampTZ, .timestampLTZ].contains(columns[column].type)
    }

    /// Wybrana w kalendarzu data do komórki: bez czasu (`keepTime`) zachowuje godzinę dotychczasowej wartości.
    func setDate(_ chosen: OracleTimestamp, row: Int, column: Int, keepTime: Bool) throws {
        var t = chosen
        if keepTime, let old = timestamp(row: row, column: column) {
            t.hour = old.hour; t.minute = old.minute; t.second = old.second; t.fsecond = old.fsecond
            t.tzHourOffset = old.tzHourOffset; t.tzMinuteOffset = old.tzMinuteOffset
        }
        let mask = columns[column].type == .date ? format.dateFormat : format.timestampFormat
        try setText(t.formatted(mask, zone: columns[column].type == .timestampTZ), row: row, column: column)
    }
}

/// Blok komórek w siatce (PD-GRID-007): kolumny między komórką kotwicy a klikniętą, w kolejności widocznej.
public enum GridBlock {
    /// Kolumny bloku (indeksy danych) między `anchor` i `to` w kolejności `order` (widoczne kolumny).
    public static func columns(from anchor: Int, to: Int, order: [Int]) -> [Int] {
        guard let a = order.firstIndex(of: anchor), let b = order.firstIndex(of: to) else { return [to] }
        return Array(order[min(a, b)...max(a, b)])
    }

    /// Wiersze bloku (widoku) między kotwicą a klikniętym.
    public static func rows(from anchor: Int, to: Int) -> [Int] { Array(min(anchor, to)...max(anchor, to)) }
}

/// Pole widoku pojedynczego rekordu (PD-GRID-010): kolumna, wartość, typ i komentarz kolumny ze słownika.
public struct RecordField: Sendable, Hashable {
    public var column: Int
    public var name: String
    public var value: String
    public var type: String
    public var comment: String
    public var isNull: Bool
}

public extension ResultTab {
    /// Pola rekordu `row` (wiersz widoku) dla kolumn `columns` z komentarzami ze słownika (jeśli wczytany).
    func recordFields(row: Int, columns: [Int]) -> [RecordField] {
        guard let grid, row >= 0, row < grid.rowCount else { return [] }
        return columns.map { i in
            RecordField(column: i, name: grid.columns[i].name, value: grid.text(row: row, column: i), type: grid.columns[i].typeName,
                        comment: columnInfo?[i]?.comment ?? "", isNull: grid.value(row: row, column: i).isNull)
        }
    }
}
