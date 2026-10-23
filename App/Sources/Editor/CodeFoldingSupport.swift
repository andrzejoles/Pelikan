import AppKit
import PelikanSQL

/// Ukrywanie zwiniętych linii w TextKit 2 (UG 25.17): magazyn treści pomija akapity leżące w całości w ukrytych
/// zakresach, więc nie powstają dla nich fragmenty układu (tekst pozostaje w dokumencie bez zmian).
final class FoldingContentDelegate: NSObject, NSTextContentStorageDelegate {
    var hidden: [Range<Int>] = []

    func textContentManager(_ textContentManager: NSTextContentManager, shouldEnumerate textElement: NSTextElement,
                            options: NSTextContentManager.EnumerationOptions = []) -> Bool {
        guard !hidden.isEmpty, let range = textElement.elementRange else { return true }
        let doc = textContentManager.documentRange.location
        let a = textContentManager.offset(from: doc, to: range.location)
        let b = textContentManager.offset(from: doc, to: range.endLocation)
        return !hidden.contains { $0.lowerBound <= a && b <= $0.upperBound }
    }
}
