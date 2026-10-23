import Foundation
import PelikanSQL

extension Workspace {
    /// Automatyczne formatowanie okna programu (UG 29.4); przy błędzie tekst zostaje bez zmian.
    func autoBeautify(_ doc: Document) {
        guard doc.kind == .program, let f = try? Beautifier.format(doc.text, options: settings.beautifier), f != doc.text else { return }
        let caret = min(doc.selectedRange.lowerBound, (f as NSString).length)
        doc.text = f
        doc.selectedRange = caret..<caret
    }
}

extension BeautifierError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsafe(let token):
            L10n.tr("Formatowanie przerwane: wynik zmieniałby kod (przy „\(token)”). Tekst pozostaje bez zmian.")
        }
    }
}
