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
        // Zakresy posortowane i rozłączne (`CodeFolding.hiddenRanges`) — wyszukiwanie binarne ostatniego zakresu
        // zaczynającego się nie dalej niż akapit („Zwiń wszystko” w dużym pakiecie).
        var lo = 0, hi = hidden.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if hidden[mid].lowerBound <= a { lo = mid + 1 } else { hi = mid }
        }
        return lo == 0 || b > hidden[lo - 1].upperBound
    }
}
