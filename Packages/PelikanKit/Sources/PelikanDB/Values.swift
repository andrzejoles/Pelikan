import Foundation

/// Typ kolumny lub zmiennej Oracle (nazwa jak w słowniku danych).
public enum OracleType: String, Sendable, Codable, Hashable {
    case varchar2 = "VARCHAR2", nvarchar2 = "NVARCHAR2", char = "CHAR", nchar = "NCHAR"
    case number = "NUMBER", binaryFloat = "BINARY_FLOAT", binaryDouble = "BINARY_DOUBLE", binaryInteger = "BINARY_INTEGER"
    case date = "DATE", timestamp = "TIMESTAMP", timestampTZ = "TIMESTAMP WITH TIME ZONE"
    case timestampLTZ = "TIMESTAMP WITH LOCAL TIME ZONE"
    case intervalDS = "INTERVAL DAY TO SECOND", intervalYM = "INTERVAL YEAR TO MONTH"
    case raw = "RAW", longRaw = "LONG RAW", long = "LONG"
    case clob = "CLOB", nclob = "NCLOB", blob = "BLOB", bfile = "BFILE"
    case rowid = "ROWID", urowid = "UROWID"
    case boolean = "BOOLEAN", json = "JSON", vector = "VECTOR", xmltype = "XMLTYPE"
    case object = "OBJECT", refCursor = "REF CURSOR"
    case unknown = "UNKNOWN"

    public var isLOB: Bool { self == .clob || self == .nclob || self == .blob || self == .bfile }
    public var isCharacter: Bool { [.varchar2, .nvarchar2, .char, .nchar, .long, .clob, .nclob].contains(self) }
    public var isNumeric: Bool { [.number, .binaryFloat, .binaryDouble, .binaryInteger].contains(self) }
    public var isTemporal: Bool { [.date, .timestamp, .timestampTZ, .timestampLTZ].contains(self) }
}

/// Data i czas Oracle bez utraty informacji (DATE ma sekundy, TIMESTAMP — ułamki do ns, strefę).
public struct OracleTimestamp: Sendable, Hashable, Codable {
    public var year: Int16, month: UInt8, day: UInt8
    public var hour: UInt8, minute: UInt8, second: UInt8
    public var fsecond: UInt32          // nanosekundy
    public var tzHourOffset: Int8, tzMinuteOffset: Int8

    public init(year: Int16, month: UInt8, day: UInt8, hour: UInt8 = 0, minute: UInt8 = 0, second: UInt8 = 0,
                fsecond: UInt32 = 0, tzHourOffset: Int8 = 0, tzMinuteOffset: Int8 = 0) {
        self.year = year; self.month = month; self.day = day
        self.hour = hour; self.minute = minute; self.second = second
        self.fsecond = fsecond; self.tzHourOffset = tzHourOffset; self.tzMinuteOffset = tzMinuteOffset
    }
}

/// Wartość z bazy. NUMBER trzymany jako tekst (bez utraty precyzji, 38 cyfr), konwersje na żądanie.
public enum OracleValue: Sendable, Hashable {
    case null
    case text(String)
    case number(String)
    case double(Double)
    case boolean(Bool)
    case timestamp(OracleTimestamp, OracleType)
    case intervalDS(days: Int32, hours: Int32, minutes: Int32, seconds: Int32, fseconds: Int32)
    case intervalYM(years: Int32, months: Int32)
    case raw(Data)
    /// LOB pobrany (w całości lub do limitu). `length` — pełna długość w znakach/bajtach.
    case lob(LOBValue)
    case rowid(String)
    case json(String)
    case vector([Double])
    /// Obiekt, kolekcja albo inny typ złożony — opis tekstowy (pełna struktura: Etap 3, debuger).
    case object(typeName: String, description: String)
    /// Zagnieżdżony kursor (REF CURSOR, CURSOR(...) w zapytaniu) — identyfikator wyniku w sesji.
    case cursor(ResultSetID)

    public var isNull: Bool { if case .null = self { true } else { false } }
}

public struct LOBValue: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable { case clob = "CLOB", nclob = "NCLOB", blob = "BLOB", bfile = "BFILE" }
    public var kind: Kind
    public var text: String?          // CLOB/NCLOB
    public var bytes: Data?           // BLOB/BFILE
    public var length: UInt64
    public var truncated: Bool

    public init(kind: Kind, text: String? = nil, bytes: Data? = nil, length: UInt64, truncated: Bool) {
        self.kind = kind; self.text = text; self.bytes = bytes; self.length = length; self.truncated = truncated
    }
}

public struct ResultSetID: Sendable, Hashable, Codable {
    public let raw: UInt64
    public init(_ raw: UInt64) { self.raw = raw }
}

/// Opis kolumny wyniku zapytania.
public struct ColumnInfo: Sendable, Hashable {
    public var name: String
    public var type: OracleType
    /// Pełna nazwa typu do wyświetlenia, np. `VARCHAR2(40)`, `NUMBER(9,2)`, `PELIKAN_TEST.ADDRESS_T`.
    public var typeName: String
    public var nullable: Bool
    public var precision: Int16
    public var scale: Int8
    public var size: UInt32

    public init(name: String, type: OracleType, typeName: String, nullable: Bool = true,
                precision: Int16 = 0, scale: Int8 = 0, size: UInt32 = 0) {
        self.name = name; self.type = type; self.typeName = typeName; self.nullable = nullable
        self.precision = precision; self.scale = scale; self.size = size
    }
}
