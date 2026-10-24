import Foundation
import PelikanDB

/// Bufor SQL jako linie z bieżącą linią — LIST, APPEND, CHANGE, DEL, INPUT (SQL*Plus User's Guide, rozdz. 5; PD-CMDW-004).
public struct SQLPlusBuffer: Sendable, Equatable {
    public var lines: [String]
    /// Bieżąca linia (indeks od 0).
    public var current: Int

    public init(_ text: String?, current: Int? = nil) {
        lines = text.map { $0.components(separatedBy: "\n") } ?? []
        self.current = min(max(current ?? lines.count - 1, 0), max(lines.count - 1, 0))
    }

    public var text: String? { lines.isEmpty ? nil : lines.joined(separator: "\n") }

    /// Zakres linii z argumentów: `n`, `n m`, `*` (bieżąca), `LAST` (ostatnia); bez argumentów — wszystkie.
    func range(_ args: [String]) throws -> ClosedRange<Int> {
        guard !lines.isEmpty else { throw SQLPlusError(L10n.tr("SP2-0223: Bufor SQL jest pusty.")) }
        func index(_ s: String) throws -> Int {
            switch s.uppercased() {
            case "*": return current
            case "L", "LA", "LAS", "LAST": return lines.count - 1
            default:
                guard let n = Int(s), n >= 1 else { throw SQLPlusError(L10n.tr("SP2-0226: Nieprawidłowy numer linii: \(s)")) }
                guard n <= lines.count else { throw SQLPlusError(L10n.tr("SP2-0226: Nieprawidłowy numer linii: \(s)")) }
                return n - 1
            }
        }
        switch args.count {
        case 0: return 0...(lines.count - 1)
        case 1: let i = try index(args[0]); return i...i
        default:
            let a = try index(args[0]), b = try index(args[1])
            guard a <= b else { throw SQLPlusError(L10n.tr("SP2-0226: Nieprawidłowy numer linii: \(args[1])")) }
            return a...b
        }
    }

    /// LIST: linie z numerami, bieżąca oznaczona `*`; ostatnia wypisana staje się bieżącą.
    public mutating func list(_ args: [String] = []) throws -> [String] {
        let r = try range(args)
        current = r.upperBound
        return r.map { i in
            let n = String(i + 1)
            return String(repeating: " ", count: max(0, 3 - n.count)) + n + (i == current ? "* " : "  ") + lines[i]
        }
    }

    /// APPEND: tekst doklejony do bieżącej linii.
    public mutating func append(_ text: String) throws {
        guard !lines.isEmpty else { throw SQLPlusError(L10n.tr("SP2-0223: Bufor SQL jest pusty.")) }
        lines[current] += text
    }

    /// CHANGE sep stary sep nowy [sep] — pierwsze wystąpienie w bieżącej linii; bez nowego tekstu usuwa stary.
    public mutating func change(_ spec: String) throws {
        guard !lines.isEmpty else { throw SQLPlusError(L10n.tr("SP2-0223: Bufor SQL jest pusty.")) }
        let s = spec.trimmingCharacters(in: .whitespaces)
        guard let sep = s.first, !sep.isLetter, !sep.isNumber else {
            throw SQLPlusError(L10n.tr("SP2-0025: Nieprawidłowy format polecenia CHANGE."))
        }
        let parts = s.dropFirst().split(separator: sep, maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let old = parts[0]
        var new = parts.count > 1 ? parts[1] : ""
        if new.last == sep { new.removeLast() }
        if old.isEmpty {
            lines[current] = new + lines[current]
            return
        }
        guard let r = lines[current].range(of: old) else { throw SQLPlusError(L10n.tr("SP2-0023: Nie znaleziono ciągu.")) }
        lines[current].replaceSubrange(r, with: new)
    }

    /// DEL [n | n m | * | LAST]: usuwa linie; bieżącą staje się następna (albo ostatnia).
    public mutating func delete(_ args: [String]) throws {
        let r = args.isEmpty ? try range(["*"]) : try range(args)
        lines.removeSubrange(r)
        current = min(r.lowerBound, max(lines.count - 1, 0))
    }

    /// INPUT tekst: nowa linia po bieżącej, staje się bieżącą.
    public mutating func input(_ text: String) {
        let at = lines.isEmpty ? 0 : current + 1
        lines.insert(text, at: at)
        current = at
    }
}

/// BREAK ON kolumna [SKIP n] [DUPLICATES | NODUPLICATES] (SQL*Plus, rozdz. 12).
public struct SQLPlusBreak: Sendable, Hashable {
    /// Nazwa kolumny wielkimi literami albo `REPORT`.
    public var column: String
    public var skip = 0
    public var duplicates = false

    /// BREAK ON a SKIP 1 ON b DUP ON REPORT.
    public static func parse(_ args: [String]) throws -> [SQLPlusBreak] {
        var out: [SQLPlusBreak] = []
        var i = 0
        let u = args.map { $0.uppercased() }
        while i < u.count {
            switch u[i] {
            case "ON":
                guard i + 1 < args.count else { throw SQLPlusError(L10n.tr("SP2-0084: Brak nazwy kolumny po ON.")) }
                out.append(SQLPlusBreak(column: SQLPlusCompute.columnName(args[i + 1])))
                i += 1
            case "SKI", "SKIP":
                guard !out.isEmpty, i + 1 < u.count else { throw SQLPlusError(L10n.tr("SP2-0084: Brak nazwy kolumny po ON.")) }
                out[out.count - 1].skip = u[i + 1] == "PAGE" ? 1 : Int(u[i + 1]) ?? 1
                i += 1
            case "DUP", "DUPL", "DUPLI", "DUPLIC", "DUPLICA", "DUPLICAT", "DUPLICATE", "DUPLICATES":
                if !out.isEmpty { out[out.count - 1].duplicates = true }
            case "NODUP", "NODUPL", "NODUPLI", "NODUPLIC", "NODUPLICA", "NODUPLICAT", "NODUPLICATE", "NODUPLICATES":
                if !out.isEmpty { out[out.count - 1].duplicates = false }
            default:
                throw SQLPlusError(L10n.tr("SP2-0158: Nieznana opcja BREAK: \(args[i])"))
            }
            i += 1
        }
        return out
    }

    public var description: String {
        "break on \(column.lowercased())" + (skip > 0 ? " skip \(skip)" : "") + (duplicates ? " dup" : " nodup")
    }
}

/// COMPUTE funkcja… [LABEL tekst] OF kolumna… ON kolumna… | REPORT (SQL*Plus, rozdz. 12).
public struct SQLPlusCompute: Sendable, Hashable {
    public enum Function: String, Sendable, CaseIterable {
        case sum, avg, count, minimum, maximum, number
        init?(word: String) {
            switch word.uppercased() {
            case "SUM": self = .sum
            case "AVG": self = .avg
            case "COU", "COUN", "COUNT": self = .count
            case "MIN", "MINI", "MINIM", "MINIMU", "MINIMUM": self = .minimum
            case "MAX", "MAXI", "MAXIM", "MAXIMU", "MAXIMUM": self = .maximum
            case "NUM", "NUMB", "NUMBE", "NUMBER": self = .number
            default: return nil
            }
        }
    }
    public var functions: [Function]
    public var label: String?
    public var of: [String]
    public var on: [String]

    static func columnName(_ s: String) -> String {
        s.hasPrefix("\"") ? String(s.dropFirst().dropLast()) : s.uppercased()
    }

    public static func parse(_ args: [String]) throws -> SQLPlusCompute {
        var c = SQLPlusCompute(functions: [], of: [], on: [])
        var mode = 0  // 0 funkcje, 1 OF, 2 ON
        var i = 0
        while i < args.count {
            let u = args[i].uppercased()
            if u == "OF" { mode = 1 } else if u == "ON" { mode = 2 } else if mode == 0, ["LAB", "LABE", "LABEL"].contains(u), i + 1 < args.count {
                c.label = args[i + 1]
                i += 1
            } else if mode == 0 {
                guard let f = Function(word: u) else { throw SQLPlusError(L10n.tr("SP2-0087: Nieznana funkcja COMPUTE: \(args[i])")) }
                c.functions.append(f)
            } else if mode == 1 {
                c.of.append(columnName(args[i]))
            } else {
                c.on.append(columnName(args[i]))
            }
            i += 1
        }
        guard !c.functions.isEmpty, !c.of.isEmpty, !c.on.isEmpty else {
            throw SQLPlusError(L10n.tr("SP2-0082: COMPUTE wymaga funkcji, OF kolumna i ON kolumna albo REPORT."))
        }
        return c
    }

    public var description: String {
        "compute " + functions.map(\.rawValue).joined(separator: " ") + (label.map { " label '\($0)'" } ?? "")
            + " of " + of.map { $0.lowercased() }.joined(separator: " ") + " on " + on.map { $0.lowercased() }.joined(separator: " ")
    }
}

/// Akumulator jednej grupy BREAK (wartości kolumn OF).
struct ComputeAccumulator {
    var rows = 0
    var numbers: [Int: [Double]] = [:]
    var texts: [Int: [String]] = [:]

    mutating func add(_ row: [OracleValue], columns: Set<Int>) {
        rows += 1
        for i in columns {
            switch row[i] {
            case .null: continue
            case .number(let n): if let d = Double(n) { numbers[i, default: []].append(d) }
            default: break
            }
            texts[i, default: []].append(row[i].format(.default))
        }
    }

    func value(_ f: SQLPlusCompute.Function, column i: Int) -> (number: Double?, text: String?) {
        let nums = numbers[i] ?? []
        let txt = texts[i] ?? []
        switch f {
        case .sum: return (nums.isEmpty ? nil : nums.reduce(0, +), nil)
        case .avg: return (nums.isEmpty ? nil : nums.reduce(0, +) / Double(nums.count), nil)
        case .count: return (Double(txt.count), nil)
        case .number: return (Double(rows), nil)
        case .minimum: return nums.count == txt.count && !nums.isEmpty ? (nums.min(), nil) : (nil, txt.min())
        case .maximum: return nums.count == txt.count && !nums.isEmpty ? (nums.max(), nil) : (nil, txt.max())
        }
    }
}

extension SQLPlusState {
    /// SET… dla STORE SET (plik do odtworzenia ustawień przez @plik).
    public var storeSetLines: [String] {
        func onOff(_ b: Bool) -> String { b ? "on" : "off" }
        return [
            "set autoprint \(onOff(autoPrint))", "set colsep \"\(colSep)\"",
            "set define " + (defineEnabled ? "\"\(defineChar)\"" : "off"), "set echo \(onOff(echo))",
            "set feedback " + (feedback == 0 ? "off" : "\(feedback)"), "set heading \(onOff(heading))",
            "set linesize \(lineSize)", "set long \(long)", "set numwidth \(numWidth)", "set pagesize \(pageSize)",
            "set serveroutput \(onOff(serverOutput))", "set sqlprompt \"\(sqlPrompt)\"", "set termout \(onOff(termOut))",
            "set timing \(onOff(timing))", "set verify \(onOff(verify))",
        ]
    }
}
