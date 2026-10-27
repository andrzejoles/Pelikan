import Foundation
import Synchronization
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Poziom wpisu (od najmniej ważnego). Ustawiony w Preferencjach poziom pomija wpisy niższe.
public enum LogLevel: String, Sendable, Codable, CaseIterable, Comparable {
    case debug, info, notice, error, fault

    var rank: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .notice: 2
        case .error: 3
        case .fault: 4
        }
    }

    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rank < b.rank }

    /// Etykieta w pliku dziennika (stała szerokość).
    var label: String {
        switch self {
        case .debug: "DEBUG "
        case .info: "INFO  "
        case .notice: "UWAGA "
        case .error: "BŁĄD  "
        case .fault: "AWARIA"
        }
    }
}

/// Obszar aplikacji — kategoria w dzienniku systemowym macOS i kolumna w pliku.
public struct LogCategory: Sendable, Hashable {
    public let name: String
    public init(_ name: String) { self.name = name }
}

/// Wpis po nałożeniu widoczności (gotowy tekst dla ujść).
public struct LogEntry: Sendable, Equatable {
    public var date: Date
    public var level: LogLevel
    public var category: String
    public var text: String
}

/// Ujście wpisów: plik, dziennik systemowy, pamięć (testy).
public protocol LogSink: Sendable {
    func write(_ entry: LogEntry)
    /// Ujście diagnostyczne (testy): dostaje wpisy wszystkich poziomów z jawnymi wartościami prywatnymi — niezależnie
    /// od ustawień, więc testy nie zmieniają globalnej konfiguracji i mogą działać równolegle.
    var receivesEverything: Bool { get }
}

extension LogSink {
    public var receivesEverything: Bool { false }
}

/// Rejestrator jednego obszaru. Treść wpisu jest budowana dopiero, gdy poziom jest włączony.
public struct Logger: Sendable {
    public let category: LogCategory

    public init(_ category: String) { self.category = LogCategory(category) }

    public func debug(_ message: @autoclosure () -> LogMessage) { Log.emit(.debug, category, message) }
    public func info(_ message: @autoclosure () -> LogMessage) { Log.emit(.info, category, message) }
    public func notice(_ message: @autoclosure () -> LogMessage) { Log.emit(.notice, category, message) }
    public func error(_ message: @autoclosure () -> LogMessage) { Log.emit(.error, category, message) }
    public func fault(_ message: @autoclosure () -> LogMessage) { Log.emit(.fault, category, message) }
}

/// Dziennik aplikacji (PL-INFRA-011, D170). Bez konfiguracji wpisy nigdzie nie trafiają (biblioteka, testy, Linux).
public enum Log {
    // Obszary aplikacji.
    public static let app = Logger("app")
    public static let connection = Logger("connection")
    public static let sql = Logger("sql")
    public static let command = Logger("command")
    public static let agent = Logger("agent")
    public static let ssh = Logger("ssh")
    public static let proc = Logger("proc")
    public static let update = Logger("update")
    public static let tools = Logger("tools")
    public static let debugger = Logger("debugger")
    public static let tests = Logger("tests")
    public static let keychain = Logger("keychain")

    struct Configuration: Sendable {
        var level: LogLevel = .info
        var revealPrivate = false
        var hashKey: [UInt8] = []
        var sinks: [any LogSink] = []
        var extraSinks: [UUID: any LogSink] = [:]

        var all: [any LogSink] { sinks + extraSinks.values }
    }

    static let configuration = Mutex(Configuration())

    /// Ujścia wpisów aplikacji (zastępuje poprzednie; dodane przez `addSink` zostają).
    public static func setSinks(_ sinks: [any LogSink]) {
        configuration.withLock { $0.sinks = sinks }
    }

    /// Dodatkowe ujście (testy); zwraca identyfikator dla `removeSink`.
    @discardableResult
    public static func addSink(_ sink: any LogSink) -> UUID {
        let id = UUID()
        configuration.withLock { $0.extraSinks[id] = sink }
        return id
    }

    public static func removeSink(_ id: UUID) {
        configuration.withLock { $0.extraSinks[id] = nil }
    }

    /// Poziom i widoczność wartości prywatnych (Preferencje › Ogólne › Dziennik aplikacji).
    public static func configure(level: LogLevel, revealPrivate: Bool) {
        configuration.withLock { $0.level = level; $0.revealPrivate = revealPrivate }
    }

    /// Klucz skrótów `LogPrivacy.hash` — losowy dla instalacji; bez niego skrót byłby odwracalny słownikiem nazw.
    public static func setHashKey(_ key: [UInt8]) {
        configuration.withLock { $0.hashKey = key }
    }

    public static var level: LogLevel { configuration.withLock { $0.level } }

    static func isEnabled(_ level: LogLevel) -> Bool {
        configuration.withLock { c in c.all.contains { $0.receivesEverything || level >= c.level } }
    }

    static func emit(_ level: LogLevel, _ category: LogCategory, _ message: () -> LogMessage) {
        emit(level, category, message, configuration.withLock { $0 })
    }

    static func emit(_ level: LogLevel, _ category: LogCategory, _ message: () -> LogMessage, _ c: Configuration) {
        let sinks = c.all
        let regular = level >= c.level ? sinks.filter { !$0.receivesEverything } : []
        let diagnostic = sinks.filter(\.receivesEverything)
        guard !regular.isEmpty || !diagnostic.isEmpty else { return }
        let m = message()
        let date = Date()
        func entry(_ reveal: Bool) -> LogEntry {
            LogEntry(date: date, level: level, category: category.name,
                     text: m.render(revealPrivate: reveal) { hash($0, key: c.hashKey) })
        }
        if !regular.isEmpty {
            let e = entry(c.revealPrivate)
            for s in regular { s.write(e) }
        }
        if !diagnostic.isEmpty {
            let e = entry(true)
            for s in diagnostic { s.write(e) }
        }
    }

    /// Sześć znaków szesnastkowych skrótu z kluczem (HMAC-SHA256 na macOS, FNV-1a z kluczem gdzie indziej).
    static func hash(_ value: String, key: [UInt8]) -> String {
        #if canImport(CryptoKit)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: SymmetricKey(data: key.isEmpty ? [0] : key))
        return mac.prefix(3).map { String(format: "%02x", $0) }.joined()
        #else
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in key + [0] + Array(value.utf8) { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return String(format: "%06x", Int(h & 0xff_ffff))
        #endif
    }
}

/// Wpisy w pamięci — testy i podgląd.
public final class MemoryLogSink: LogSink {
    private let entries = Mutex<[LogEntry]>([])
    public let receivesEverything: Bool

    /// `everything` — wszystkie poziomy i jawne wartości prywatne (testy szczelności dziennika).
    public init(everything: Bool = false) { receivesEverything = everything }

    public func write(_ entry: LogEntry) { entries.withLock { $0.append(entry) } }

    public var all: [LogEntry] { entries.withLock { $0 } }

    /// Cały tekst wpisów (do sprawdzania, czego w dzienniku nie ma).
    public var text: String { all.map(\.text).joined(separator: "\n") }
}
