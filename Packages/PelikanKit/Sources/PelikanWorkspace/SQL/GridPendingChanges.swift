import Foundation
import PelikanDB

/// Podsumowanie zmian oczekujących w siatce przed zapisem (DG-GRID-001): wiersze wstawione, zmienione, usunięte.
public struct GridPendingSummary: Sendable, Hashable {
    public var inserted = 0
    public var updated = 0
    /// Komórki z wartością różną od pierwotnej (w wierszach zmienionych).
    public var updatedCells = 0
    public var deleted = 0
    public var isEmpty: Bool { inserted + updated + deleted == 0 }

    /// Tekst na pasek siatki, np. „Oczekujące: +1 ~2 (3 kom.) −1”.
    public var text: String {
        isEmpty ? "" : L10n.tr("Oczekujące: +\(inserted) ~\(updated) (\(updatedCells) kom.) −\(deleted)")
    }
}

extension ResultGridModel {
    /// Czy komórka ma wartość różną od pierwotnej (zmiana cofnięta do oryginału nie jest już zmianą).
    func isReallyChanged(dataRow r: Int, column c: Int) -> Bool {
        guard let original = edit.changed[r]?[c] else { return false }
        return edit.inserted.contains(r) || original != rows[r][c]
    }

    /// Stan wiersza widoku do znacznika w nagłówku wiersza: usunięty, wstawiony, zmieniony albo bez zmian.
    public func rowEditState(row: Int) -> CellEditState {
        let r = dataRow(row)
        if edit.deleted.contains(r) { return .deleted }
        if edit.inserted.contains(r) { return .inserted }
        if let cols = edit.changed[r], cols.keys.contains(where: { isReallyChanged(dataRow: r, column: $0) }) { return .modified }
        return .normal
    }

    /// Stan komórki z pominięciem zmian przywróconych do wartości pierwotnej.
    public func pendingCellState(row: Int, column: Int) -> CellEditState {
        let s = cellState(row: row, column: column)
        if s == .modified, !isReallyChanged(dataRow: dataRow(row), column: column) { return .normal }
        return s
    }

    public var pendingSummary: GridPendingSummary {
        var s = GridPendingSummary()
        s.inserted = edit.inserted.count
        s.deleted = edit.deleted.count
        for (r, cols) in edit.changed where !edit.inserted.contains(r) && !edit.deleted.contains(r) {
            let n = cols.keys.filter { isReallyChanged(dataRow: r, column: $0) }.count
            if n > 0 { s.updated += 1; s.updatedCells += n }
        }
        return s
    }

    /// Następny (albo poprzedni) wiersz widoku ze zmianą oczekującą, z zawijaniem; nil — brak zmian.
    public func nextPendingRow(after row: Int?, forward: Bool = true) -> Int? {
        let n = rowCount
        guard n > 0 else { return nil }
        let start = row ?? (forward ? -1 : n)
        for step in 1...n {
            let v = ((start + (forward ? step : -step)) % n + n) % n
            if rowEditState(row: v) != .normal { return v }
        }
        return nil
    }

    /// Cofnięcie zmian wierszy widoku: wartości pierwotne, zdjęcie oznaczenia usunięcia, wstawione — usunięte.
    public func revertRows(_ viewRows: [Int]) {
        var removeNow = Set<Int>()
        for v in viewRows where v < rowCount {
            let r = dataRow(v)
            if edit.inserted.contains(r) { removeNow.insert(r); continue }
            edit.deleted.remove(r)
            for (c, original) in edit.changed[r] ?? [:] { rows[r][c] = original }
            edit.changed[r] = nil
            edit.overflow = edit.overflow.filter { $0.row != r }
        }
        if !removeNow.isEmpty {
            edit.inserted.subtract(removeNow)
            for r in removeNow { edit.changed[r] = nil }
            removeDataRows(removeNow)
        }
    }
}
