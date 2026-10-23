import Foundation
import Synchronization

/// Teksty interfejsu. Kluczem jest polskie zdanie (język źródłowy); każda interpolacja `\(…)` to w kluczu `%@`, a `%`
/// tekstu to `%%`, więc klucz da się odtworzyć ze źródeł (`scripts/l10n.py`). Tłumaczenia leżą w `Localizable.xcstrings`
/// celu aplikacji; mogą zmieniać kolejność argumentów (`%2$@`). Brak tłumaczenia = polski tekst.
public enum L10n {
    private static let selected = Mutex<Bundle?>(nil)

    /// Klucz tłumaczenia z interpolacją (literał w wywołaniu `L10n.tr("…")`).
    public struct Key: ExpressibleByStringInterpolation, Sendable, Equatable {
        /// Klucz w katalogu: polski tekst z `%@` w miejscu wartości i `%%` w miejscu `%`.
        public let format: String
        public let arguments: [String]

        public init(stringLiteral value: String) {
            format = value.replacingOccurrences(of: "%", with: "%%")
            arguments = []
        }

        public init(stringInterpolation: Interpolation) {
            format = stringInterpolation.format
            arguments = stringInterpolation.arguments
        }

        public struct Interpolation: StringInterpolationProtocol, Sendable {
            var format = ""
            var arguments: [String] = []

            public init(literalCapacity: Int, interpolationCount: Int) {
                format.reserveCapacity(literalCapacity + 2 * interpolationCount)
            }

            public mutating func appendLiteral(_ literal: String) {
                format += literal.replacingOccurrences(of: "%", with: "%%")
            }

            public mutating func appendInterpolation<T>(_ value: T) {
                format += "%@"
                arguments.append(String(describing: value))
            }
        }
    }

    public static func tr(_ key: Key) -> String {
        let bundle = selected.withLock { $0 } ?? .main
        let translated = bundle.localizedString(forKey: key.format, value: key.format, table: nil)
        return fill(translated, key.arguments)
    }

    /// Podstawia argumenty w miejsce `%@` (kolejno) i `%n$@` (wg numeru); `%%` → `%`. Własna implementacja zamiast
    /// `String(format:)`: tłumaczenie z błędnym specyfikatorem nie może wywrócić aplikacji.
    static func fill(_ format: String, _ args: [String]) -> String {
        var out = ""
        var next = 0
        var i = format.startIndex
        while i < format.endIndex {
            let c = format[i]
            guard c == "%", format.index(after: i) < format.endIndex else { out.append(c); i = format.index(after: i); continue }
            var j = format.index(after: i)
            if format[j] == "%" { out.append("%"); i = format.index(after: j); continue }
            if format[j] == "@" {
                out += next < args.count ? args[next] : ""
                next += 1
                i = format.index(after: j)
                continue
            }
            var digits = ""
            while j < format.endIndex, format[j].isASCII, format[j].isNumber { digits.append(format[j]); j = format.index(after: j) }
            if !digits.isEmpty, j < format.endIndex, format[j] == "$", format.index(after: j) < format.endIndex, format[format.index(after: j)] == "@",
               let n = Int(digits), n >= 1 {
                out += n <= args.count ? args[n - 1] : ""
                i = format.index(j, offsetBy: 2)
                continue
            }
            out.append(c)
            i = format.index(after: i)
        }
        return out
    }

    /// Katalog `.lproj` języka wybranego w ustawieniach (`nil` = język systemu przez `Bundle.main`).
    public static func use(_ bundle: Bundle?) {
        selected.withLock { $0 = bundle }
    }
}
