import Foundation

/// Widoczność wartości wstawionej do wpisu dziennika (jak `OSLogPrivacy`, D170).
public enum LogPrivacy: Sendable {
    /// Zawsze w jawnej postaci — liczby, kody błędów, identyfikatory komend, nazwy sterowników.
    case `public`
    /// Treść (komunikat błędu, tekst pokazany użytkownikowi, dane) — zawsze ukryta (`<private>`); jawna tylko w ujściu
    /// diagnostycznym testów. Przełącznik nazw w Preferencjach jej nie odsłania.
    case `private`
    /// Nazwa (połączenia, profilu, katalogu): krótki skrót z kluczem instalacji — te same nazwy dają ten sam skrót, ale
    /// nie da się ich odtworzyć. Jawna, gdy w Preferencjach włączono nazwy w dzienniku.
    case hash
}

/// Treść wpisu: stałe fragmenty i wartości z oznaczoną widocznością. Tekst (`String`) domyślnie jest prywatny,
/// liczby i wartości logiczne — jawne; pozostałe typy wymagają podania `privacy:`.
public struct LogMessage: ExpressibleByStringInterpolation, Sendable {
    enum Segment: Sendable, Equatable {
        case literal(String)
        case value(String, LogPrivacy)
    }

    var segments: [Segment]

    public init(stringLiteral value: String) { segments = [.literal(value)] }

    public init(stringInterpolation: StringInterpolation) { segments = stringInterpolation.segments }

    public struct StringInterpolation: StringInterpolationProtocol {
        var segments: [Segment] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            segments.reserveCapacity(interpolationCount * 2 + 1)
        }

        public mutating func appendLiteral(_ literal: String) {
            if !literal.isEmpty { segments.append(.literal(literal)) }
        }

        public mutating func appendInterpolation(_ value: some StringProtocol, privacy: LogPrivacy = .private) {
            segments.append(.value(String(value), privacy))
        }

        public mutating func appendInterpolation(_ value: (some StringProtocol)?, privacy: LogPrivacy = .private) {
            segments.append(value.map { .value(String($0), privacy) } ?? .literal("–"))
        }

        public mutating func appendInterpolation(_ value: some BinaryInteger) {
            segments.append(.value(String(value), .public))
        }

        public mutating func appendInterpolation(_ value: Bool) {
            segments.append(.value(value ? "tak" : "nie", .public))
        }

        /// Liczba zmiennoprzecinkowa z podaną liczbą miejsc po przecinku (zawsze kropka).
        public mutating func appendInterpolation(_ value: Double, decimals: Int = 1) {
            segments.append(.value(String(format: "%.\(max(0, decimals))f", value), .public))
        }

        /// Czas trwania w milisekundach od `start` (np. `\(ms: started)`).
        public mutating func appendInterpolation(ms start: ContinuousClock.Instant) {
            let d = ContinuousClock.now - start
            let ms = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
            segments.append(.value(String(Int(ms.rounded())) + " ms", .public))
        }

        /// Wartość innego typu — widoczność musi być podana jawnie.
        public mutating func appendInterpolation(_ value: some CustomStringConvertible, privacy: LogPrivacy) {
            segments.append(.value(value.description, privacy))
        }

        /// Błąd: część jawna (kod, typ) zawsze, komunikat — jak wartość prywatna.
        public mutating func appendInterpolation(_ error: any Error) {
            let d = LogErrorDescription(error)
            segments.append(.value(d.publicPart, .public))
            if let p = d.privatePart { segments.append(.literal(": ")); segments.append(.value(p, .private)) }
        }
    }

    /// Tekst wpisu: nazwy (`.hash`) jawne przy `revealNames`, wartości prywatne — tylko przy `revealPrivate` (ujście
    /// diagnostyczne); każda wartość przechodzi przez `LogRedactor`.
    func render(revealNames: Bool, revealPrivate: Bool = false, hash: (String) -> String) -> String {
        var out = ""
        for s in segments {
            switch s {
            case .literal(let t): out += t
            case .value(let v, .public): out += LogRedactor.redact(v)
            case .value(let v, .private): out += revealPrivate ? LogRedactor.redact(v) : "<private>"
            case .value(let v, .hash): out += revealNames || revealPrivate ? LogRedactor.redact(v) : "<#" + hash(v) + ">"
            }
        }
        return out
    }
}

/// Błąd z podziałem na część jawną (kod ORA-, domena i kod NSError, typ) i prywatną (komunikat, który może zawierać
/// nazwy obiektów, schematów albo ścieżki).
public protocol LogDescribableError: Error {
    var logPublicDescription: String { get }
    var logPrivateDescription: String? { get }
}

struct LogErrorDescription {
    var publicPart: String
    var privatePart: String?

    init(_ error: any Error) {
        if let e = error as? any LogDescribableError {
            publicPart = e.logPublicDescription
            privatePart = e.logPrivateDescription
            return
        }
        let ns = error as NSError
        let type = String(describing: Swift.type(of: error))
        if Swift.type(of: error) is NSError.Type {
            publicPart = "\(type) (\(ns.domain) \(ns.code))"
        } else {
            // Błąd Swifta: typ i przypadek bez wartości towarzyszących (`CommandError.notConnected`).
            let name = String(describing: error).prefix { $0 != "(" }
            let isCase = !name.isEmpty && name != type && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
            publicPart = isCase ? "\(type).\(name)" : type
        }
        let text = (error as? any LocalizedError)?.errorDescription ?? ns.localizedDescription
        privatePart = text.isEmpty ? nil : text
    }
}
