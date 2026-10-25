import Foundation

/// Wpis historii schowka (UG 30 PL/SQL Clipboard).
public struct ClipboardEntry: Sendable, Hashable, Identifiable {
    public let id: UUID
    public var text: String
    public var date: Date

    public init(text: String, date: Date) {
        id = UUID(); self.text = text; self.date = date
    }

    /// Pierwsza niepusta linia (lista).
    public var title: String {
        text.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }
}

/// Historia tekstów kopiowanych w Pelikanie: najnowszy pierwszy, bez duplikatów (ponowne kopiowanie przenosi na
/// górę), limit wpisów. Tylko w pamięci — schowek może zawierać dane z bazy (D-EDYTOR-3).
public struct ClipboardHistory: Sendable, Hashable {
    public private(set) var entries: [ClipboardEntry] = []
    public var limit = 100

    public init() {}

    public mutating func add(_ text: String, date: Date = Date()) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        entries.removeAll { $0.text == text }
        entries.insert(ClipboardEntry(text: text, date: date), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }

    public mutating func remove(_ id: UUID) { entries.removeAll { $0.id == id } }
    public mutating func clear() { entries.removeAll() }

    /// Filtr: wszystkie słowa (bez wielkości liter) muszą wystąpić w tekście.
    public func filtered(_ filter: String) -> [ClipboardEntry] {
        let words = filter.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return entries }
        return entries.filter { e in
            let t = e.text.lowercased()
            return words.allSatisfy { t.contains($0) }
        }
    }
}

extension Workspace {
    /// Tekst skopiowany w aplikacji (edytor, siatka, Special Copy) — do historii schowka.
    public func recordClipboard(_ text: String) { clipboardHistory.add(text) }

    /// Wstawia tekst w aktywnym edytorze w miejscu zaznaczenia.
    func insertInEditor(_ text: String) throws {
        guard let d = BuiltinCommands.editable(self) else { throw CommandError.notAvailable(L10n.tr("Brak okna z edytorem")) }
        if d.isReadOnly { throw CommandError.notAvailable(L10n.tr("Okno jest tylko do odczytu")) }
        let len = (d.text as NSString).length
        let sel = min(d.selectedRange.lowerBound, len)..<min(d.selectedRange.upperBound, len)
        d.text = (d.text as NSString).replacingCharacters(in: NSRange(location: sel.lowerBound, length: sel.count), with: text)
        let caret = sel.lowerBound + (text as NSString).length
        d.selectedRange = caret..<caret
    }
}
