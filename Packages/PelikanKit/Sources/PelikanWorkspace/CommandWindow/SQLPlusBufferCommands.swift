import Foundation
import PelikanDB

/// Edycja bufora, pliki bufora i raporty BREAK/COMPUTE w Command Window (PD-CMDW-004).
extension SQLPlusEngine {
    /// Tekst po słowie polecenia bez pierwszej spacji (APPEND, INPUT — dalsze spacje należą do tekstu).
    nonisolated static func rawArgument(_ line: String) -> String {
        guard let r = line.firstIndex(where: { $0.isWhitespace }) else { return "" }
        return String(line[line.index(after: r)...])
    }

    var sqlBuffer: SQLPlusBuffer {
        get { SQLPlusBuffer(state.buffer, current: state.bufferLine) }
        set { state.buffer = newValue.text; state.bufferLine = newValue.current }
    }

    func bufferCommand(_ cmd: String, _ args: [String], line: String, baseDirectory: URL?) throws {
        var b = sqlBuffer
        switch cmd {
        case "LIST":
            emit(try b.list(args).joined(separator: "\n"))
        case "APPEND":
            try b.append(Self.rawArgument(line))
            emit(try b.list(["*"]).joined(separator: "\n"))
        case "CHANGE":
            try b.change(Self.rest(line))
            emit(try b.list(["*"]).joined(separator: "\n"))
        case "DEL":
            try b.delete(args)
        case "INPUT":
            let text = Self.rawArgument(line)
            guard !text.isEmpty else { throw SQLPlusError(L10n.tr("SP2-0042: INPUT wymaga tekstu nowej linii.")) }
            b.input(text)
        case "SAVE":
            guard let name = args.first, b.text != nil else { throw SQLPlusError(L10n.tr("SP2-0107: Nic do zapisania — bufor SQL jest pusty.")) }
            try write([b.text!, "/"], to: file(name, baseDirectory: baseDirectory), mode: args.dropFirst().first)
        case "GET":
            guard let name = args.first else { throw SQLPlusError(L10n.tr("SP2-0110: Podaj nazwę pliku.")) }
            let url = file(name, baseDirectory: baseDirectory)
            guard var text = try? String(contentsOf: url, encoding: .utf8) else {
                throw SQLPlusError(L10n.tr("SP2-0160: Nie można otworzyć pliku \(url.lastPathComponent)"))
            }
            var lines = text.components(separatedBy: "\n")
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty || last.trimmingCharacters(in: .whitespaces) == "/" {
                lines.removeLast()
            }
            text = lines.joined(separator: "\n")
            b = SQLPlusBuffer(text.isEmpty ? nil : text)
            if !["NOL", "NOLI", "NOLIS", "NOLIST"].contains(args.dropFirst().first?.uppercased() ?? ""), b.text != nil {
                emit(try b.list().joined(separator: "\n"))
            }
        case "STORE":
            guard args.first?.uppercased() == "SET", args.count > 1 else {
                throw SQLPlusError(L10n.tr("SP2-0285: Składnia: STORE SET plik [CREATE|REPLACE|APPEND]"))
            }
            try write(state.storeSetLines, to: file(args[1], baseDirectory: baseDirectory), mode: args.dropFirst(2).first)
            return
        case "BREAK":
            if args.isEmpty {
                emit(state.breaks.isEmpty ? L10n.tr("Nie zdefiniowano BREAK.") : state.breaks.map(\.description).joined(separator: "\n"))
            } else {
                state.breaks = try SQLPlusBreak.parse(args)
            }
            return
        case "COMPUTE":
            if args.isEmpty {
                emit(state.computes.isEmpty ? L10n.tr("Nie zdefiniowano COMPUTE.") : state.computes.map(\.description).joined(separator: "\n"))
            } else {
                let c = try SQLPlusCompute.parse(args)
                // Nowy COMPUTE na tej samej kolumnie ON zastępuje poprzedni (jak w SQL*Plus).
                state.computes.removeAll { Set($0.on) == Set(c.on) && Set($0.of) == Set(c.of) }
                state.computes.append(c)
            }
            return
        default:
            return
        }
        sqlBuffer = b
    }

    func file(_ name: String, baseDirectory: URL?) -> URL {
        let url = resolve(name, baseDirectory: baseDirectory)
        return url.pathExtension.isEmpty ? url.appendingPathExtension("sql") : url
    }

    /// Zapis pliku z opcją CREATE (domyślnie — błąd, gdy plik istnieje), REPLACE albo APPEND.
    func write(_ lines: [String], to url: URL, mode: String?) throws {
        let m = mode?.uppercased() ?? "CRE"
        let content = lines.joined(separator: "\n") + "\n"
        let exists = FileManager.default.fileExists(atPath: url.path)
        if m.hasPrefix("APP"), exists {
            let h = try FileHandle(forWritingTo: url)
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: Data(content.utf8))
        } else if m.hasPrefix("REP") || !exists {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } else {
            throw SQLPlusError(L10n.tr("SP2-0540: Plik \(url.lastPathComponent) już istnieje. Użyj opcji REPLACE."))
        }
        emit(L10n.tr("Zapisano plik \(url.lastPathComponent)"), .info)
    }
}
