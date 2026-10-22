/// Leksowanie przyrostowe dla edytora (ADR 0002): stan leksera na początku każdej linii w pamięci podręcznej. Po edycji
/// leksujemy od zmienionej linii do miejsca za edycją, w którym stan na początku linii jest taki sam jak przed edycją —
/// w typowym pisaniu to jedna linia, niezależnie od długości pliku.
public final class IncrementalLexer {
    /// Początki linii (przesunięcia UTF-16).
    public private(set) var lineStarts: [Int] = [0]
    private var startStates: [LexState] = [.normal]

    public init() {}

    /// Pełne leksowanie (otwarcie pliku, zmiana całego tekstu). `onLine` przed tokenami każdej linii.
    public func lexAll(_ text: [UInt16], onLine: (Range<Int>) -> Void, onToken: (Token) -> Void) {
        lineStarts = Self.lineStarts(text)
        startStates = Array(repeating: .normal, count: lineStarts.count)
        let lexer = Lexer(utf16: text)
        var state = LexState.normal
        for i in lineStarts.indices {
            startStates[i] = state
            let range = lineRange(i, length: text.count)
            onLine(range)
            state = lexer.scan(range: range, state: state, onToken)
        }
    }

    /// Po edycji: `editedRange` w nowym tekście, `delta` — zmiana długości. Zwraca przeleksowany zakres UTF-16.
    @discardableResult
    public func relex(_ text: [UInt16], editedRange: Range<Int>, delta: Int,
                      onLine: (Range<Int>) -> Void, onToken: (Token) -> Void) -> Range<Int> {
        let oldStates = startStates
        let oldStarts = lineStarts
        lineStarts = Self.updatedLineStarts(oldStarts, text: text, editedRange: editedRange, delta: delta)
        let firstLine = line(containing: editedRange.lowerBound)
        var states = Array(oldStates.prefix(firstLine))
        var state = firstLine == 0 ? .normal : (firstLine < oldStates.count ? oldStates[firstLine] : .normal)
        let lexer = Lexer(utf16: text)
        var i = firstLine
        var end = lineStarts[firstLine]
        while i < lineStarts.count {
            states.append(state)
            let range = lineRange(i, length: text.count)
            onLine(range)
            state = lexer.scan(range: range, state: state, onToken)
            end = range.upperBound
            // Za edycją: stan na początku następnej linii zgodny ze starym — reszta pliku bez zmian.
            if range.upperBound >= editedRange.upperBound, i + 1 < lineStarts.count,
               let oi = Self.index(of: lineStarts[i + 1] - delta, in: oldStarts), oi < oldStates.count, oldStates[oi] == state {
                states.append(contentsOf: oldStates[oi...].prefix(lineStarts.count - (i + 1)))
                break
            }
            i += 1
        }
        while states.count < lineStarts.count { states.append(.normal) }
        startStates = Array(states.prefix(lineStarts.count))
        return lineStarts[firstLine]..<end
    }

    /// Numer linii (od 0) dla przesunięcia UTF-16.
    public func line(containing offset: Int) -> Int {
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Stan leksera na początku linii (np. czy kursor jest w komentarzu blokowym).
    public func state(atLine line: Int) -> LexState { line < startStates.count ? startStates[line] : .normal }

    private func lineRange(_ i: Int, length: Int) -> Range<Int> {
        lineStarts[i]..<(i + 1 < lineStarts.count ? lineStarts[i + 1] : length)
    }

    static func lineStarts(_ text: [UInt16]) -> [Int] {
        var starts = [0]
        starts.reserveCapacity(text.count / 32 + 1)
        text.withUnsafeBufferPointer { buf in
            for i in 0..<buf.count where buf[i] == 0x0A { starts.append(i + 1) }
        }
        return starts
    }

    /// Początki linii po edycji bez przeglądania całego tekstu: linie przed edycją bez zmian, w obszarze edycji
    /// liczone na nowo, za edycją przesunięte o `delta`.
    static func updatedLineStarts(_ old: [Int], text: [UInt16], editedRange: Range<Int>, delta: Int) -> [Int] {
        let oldEditEnd = editedRange.upperBound - delta          // koniec edytowanego fragmentu w starym tekście
        var result = Array(old.prefix { $0 <= editedRange.lowerBound })
        if result.isEmpty { result = [0] }
        let scanEnd = min(editedRange.upperBound, text.count)
        text.withUnsafeBufferPointer { buf in
            var i = editedRange.lowerBound
            while i < scanEnd {
                if buf[i] == 0x0A { result.append(i + 1) }
                i += 1
            }
        }
        for s in old where s > oldEditEnd { result.append(s + delta) }
        return result
    }

    static func index(of start: Int, in starts: [Int]) -> Int? {
        var lo = 0, hi = starts.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if starts[mid] == start { return mid }
            if starts[mid] < start { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }
}
