import Foundation
import PelikanDB

/// Linia wyjścia Command Window.
public struct ConsoleLine: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable { case output, echo, error, info, prompt }
    public let id = UUID()
    public var text: String
    public var kind: Kind
    public init(_ text: String, _ kind: Kind = .output) { self.text = text; self.kind = kind }
}

/// Ustawienia i stan sesji SQL*Plus okna (SET, DEFINE, VARIABLE, COLUMN, SPOOL, WHENEVER).
public struct SQLPlusState: Sendable {
    // SET (UG 8.3) — wartości domyślne jak w SQL*Plus, z wyjątkiem PAGESIZE (Command Window wzorca stronicuje rzadko).
    public var echo = false
    public var feedback = 1            // 0 = OFF; n = komunikat od n wierszy
    public var heading = true
    public var lineSize = 200
    public var pageSize = 50
    public var colSep = " "
    public var numWidth = 10
    public var long = 80
    public var colWidth = 80           // SET COLWIDTH (PL/SQL Developer): maksymalna szerokość kolumny tekstowej
    public var serverOutput = false
    public var termOut = true
    public var timing = false
    public var verify = true
    public var autoPrint = false
    public var defineEnabled = true
    public var defineChar: Character = "&"
    public var scan = true
    public var concatChar: Character = "."
    public var escapeChar: Character?
    public var sqlPrompt = "SQL> "
    public var execPause = false
    /// SET SQLFORMAT (SC-CMD-002); nil — format SQL*Plus.
    public var sqlFormat: SQLFormat?
    /// Historia poleceń SQL okna z czasami (HISTORY, SQLcl) i aliasy (ALIAS nazwa=polecenie).
    public var history: [(sql: String, milliseconds: Int)] = []
    public var aliases: [String: String] = [:]
    /// Po DISCONNECT: okno bez połączenia do następnego CONNECT (bez cichego przejścia na połączenie główne).
    public var disconnected = false

    /// Zmienne podstawiania (DEFINE, &&, ACCEPT, COLUMN NEW_VALUE, parametry &1…).
    public var defines: [String: String] = [:]
    /// Zmienne wiązane (VARIABLE).
    public var binds: [String: BindSlot] = [:]
    /// COLUMN … FORMAT/HEADING/NEW_VALUE.
    public var columns: [String: ColumnFormat] = [:]
    /// Bufor SQL (ostatnie polecenie SQL/PL/SQL — `/`, RUN, LIST).
    public var buffer: String? { didSet { bufferLine = nil } }
    /// Bieżąca linia bufora (LIST, APPEND, CHANGE, DEL, INPUT); nil — ostatnia.
    public var bufferLine: Int?
    /// BREAK i COMPUTE (PD-CMDW-004).
    public var breaks: [SQLPlusBreak] = []
    public var computes: [SQLPlusCompute] = []
    /// Ostatnio kompilowany obiekt (SHOW ERRORS bez argumentów).
    public var lastCompiled: (type: String, owner: String?, name: String)?
    public var whenever: Whenever = .continue
    public var spoolURL: URL?
    /// Katalog bieżący (CD, @plik, SPOOL).
    public var directory: URL?
    /// Katalog skryptów instalatora utPLSQL w trakcie instalacji (sprzątanie plików tymczasowych, UT-INS-002).
    var installerDirectory: URL?

    public enum Whenever: Sendable, Equatable {
        case `continue`
        case exit(commit: Bool)
    }

    public struct BindSlot: Sendable, Hashable {
        public var type: OracleType
        public var size: UInt32
        public var value: OracleValue
        public var declaration: String
    }

    public struct ColumnFormat: Sendable, Hashable {
        public var format: String?
        public var heading: String?
        public var newValue: String?
        public var isOn = true
    }

    public init() {}

    /// Wiersz SET … dla SHOW ALL (podzbiór).
    public var summary: [String] {
        [
            "autoprint \(autoPrint ? "ON" : "OFF")", "colsep \"\(colSep)\"", "define \(defineEnabled ? "\"\(defineChar)\"" : "OFF")",
            "echo \(echo ? "ON" : "OFF")", "feedback \(feedback == 0 ? "OFF" : "ON for \(feedback) or more rows")",
            "heading \(heading ? "ON" : "OFF")", "linesize \(lineSize)", "long \(long)", "numwidth \(numWidth)",
            "pagesize \(pageSize)", "serveroutput \(serverOutput ? "ON" : "OFF")", "termout \(termOut ? "ON" : "OFF")",
            "timing \(timing ? "ON" : "OFF")", "verify \(verify ? "ON" : "OFF")",
        ]
    }
}
