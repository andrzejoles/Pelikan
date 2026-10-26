import Foundation
import Synchronization
#if canImport(os)
import os
#endif

/// Plik dziennika z rotacją: `Pelikan.log`, starsze `Pelikan.1.log` … `Pelikan.N.log` (najstarszy usuwany).
/// Katalog 0700, pliki 0600; zapis na osobnej kolejce — wątek wywołujący (także główny) nie czeka na dysk.
public final class FileLogSink: LogSink {
    public let directory: URL
    public let baseName: String
    let maxBytes: UInt64
    let keep: Int
    private let queue = DispatchQueue(label: "pelikan.log.file")
    private let handle = Mutex<FileHandle?>(nil)

    public init(directory: URL, baseName: String, maxBytes: UInt64 = 2_000_000, keep: Int = 4) {
        self.directory = directory
        self.baseName = baseName
        self.maxBytes = maxBytes
        self.keep = keep
    }

    /// Bieżący plik dziennika.
    public var currentFile: URL { directory.appendingPathComponent(baseName + ".log") }

    /// Pliki dziennika od najstarszego do bieżącego (istniejące).
    public var files: [URL] {
        let older = (1...max(1, keep)).reversed().map { directory.appendingPathComponent("\(baseName).\($0).log") }
        return (older + [currentFile]).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func write(_ entry: LogEntry) {
        let line = Self.format(entry)
        queue.async { self.append(line) }
    }

    /// Czeka na zapis wpisów z kolejki (eksport, testy, zamknięcie aplikacji).
    public func flush() {
        queue.sync {}
    }

    /// Linia: `2026-10-26 08:12:01.123+0100 INFO   connection  tekst`; dalsze linie tekstu wcięte tabulatorem.
    static func format(_ e: LogEntry) -> String {
        let category = e.category.padding(toLength: max(10, e.category.count), withPad: " ", startingAt: 0)
        let text = e.text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\n\t")
        return "\(timestamp(e.date)) \(e.level.label) \(category)  \(text)\n"
    }

    static let timeStyle = Date.ISO8601FormatStyle(dateSeparator: .dash, dateTimeSeparator: .space, timeSeparator: .colon,
                                                   timeZoneSeparator: .omitted, includingFractionalSeconds: true, timeZone: .current)

    static func timestamp(_ date: Date) -> String { date.formatted(timeStyle) }

    private func append(_ line: String) {
        let data = Data(line.utf8)
        handle.withLock { h in
            if h == nil { h = open() }
            guard let file = h else { return }
            if let size = try? file.seekToEnd(), size > 0, size + UInt64(data.count) > maxBytes {
                try? file.close()
                rotate()
                h = open()
            }
            try? h?.write(contentsOf: data)
        }
    }

    private func open() -> FileHandle? {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if !fm.fileExists(atPath: currentFile.path) {
            guard fm.createFile(atPath: currentFile.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { return nil }
        }
        let h = try? FileHandle(forWritingTo: currentFile)
        _ = try? h?.seekToEnd()
        return h
    }

    private func rotate() {
        let fm = FileManager.default
        let name = { (n: Int) in self.directory.appendingPathComponent("\(self.baseName).\(n).log") }
        try? fm.removeItem(at: name(keep))
        for n in stride(from: keep - 1, through: 1, by: -1) where fm.fileExists(atPath: name(n).path) {
            try? fm.moveItem(at: name(n), to: name(n + 1))
        }
        try? fm.moveItem(at: currentFile, to: name(1))
    }

    /// Czyści pliki dziennika (Preferencje); następny wpis tworzy nowy plik.
    public func clear() {
        queue.sync {
            handle.withLock { h in
                try? h?.close()
                h = nil
                for f in files { try? FileManager.default.removeItem(at: f) }
            }
        }
    }
}

#if canImport(os)
/// Dziennik systemowy macOS (Konsola, `log show --predicate 'subsystem == "…"'`). Tekst jest już po nałożeniu
/// widoczności, więc trafia jako jawny — wartości prywatne są w nim zastąpione wcześniej.
public final class UnifiedLogSink: LogSink {
    let subsystem: String
    private let loggers = Mutex<[String: os.Logger]>([:])

    public init(subsystem: String) { self.subsystem = subsystem }

    public func write(_ entry: LogEntry) {
        let logger = loggers.withLock { cache in
            if let l = cache[entry.category] { return l }
            let l = os.Logger(subsystem: subsystem, category: entry.category)
            cache[entry.category] = l
            return l
        }
        let type: OSLogType = switch entry.level {
        case .debug: .debug
        case .info: .info
        case .notice: .default
        case .error: .error
        case .fault: .fault
        }
        logger.log(level: type, "\(entry.text, privacy: .public)")
    }
}
#endif

extension Log {
    /// Plik dziennika aplikacji (nil, gdy aplikacja nie zapisuje dziennika do pliku — biblioteka, testy).
    public static var fileSink: FileLogSink? {
        configuration.withLock { c in c.sinks.lazy.compactMap { $0 as? FileLogSink }.first }
    }
}
