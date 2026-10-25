import Foundation
import NIOCore
import OracleNIO
import PelikanDB
import PelikanSQL
import Synchronization

/// Sterownik „thin” (ADR 0001): OracleNIO w czystym Swifcie, bez Instant Client. Możliwości węższe niż Instant Client —
/// funkcje spoza `capabilities` są w interfejsie wyszarzone z podpowiedzią „przełącz na Instant Client”.
public struct ThinDriver: DatabaseDriver {
    public let kind = DriverKind.thin
    // Bez debugowania: DBMS_DEBUG wymaga Instant Client, JDWP pominięte (D106).
    public static let capabilitySet: DriverCapabilities = [.lobs, .proxyUser, .sysdba, .json, .tnsNames]
    public var capabilities: DriverCapabilities { Self.capabilitySet }

    public init() {}

    public func availability() -> Result<Void, DatabaseError> { .success(()) }

    /// Host, port i usługa z EZConnect albo deskryptora (alias TNS rozwija SessionManager/`resolve`).
    static func endpoint(_ connect: String) throws -> (host: String, port: Int, service: OracleServiceMethod) {
        var s = connect.trimmingCharacters(in: .whitespaces)
        if s.lowercased().hasPrefix("tcps://") {
            throw DatabaseError.unsupported("Połączenia TCPS (TLS/wallet) wymagają sterownika Instant Client")
        }
        if s.hasPrefix("(") {
            guard let host = TNSNames.value("HOST", in: s) else { throw DatabaseError.unsupported("Brak HOST w deskryptorze") }
            let port = TNSNames.value("PORT", in: s).flatMap(Int.init) ?? 1521
            if (TNSNames.value("PROTOCOL", in: s) ?? "TCP").uppercased() == "TCPS" {
                throw DatabaseError.unsupported("Połączenia TCPS (TLS/wallet) wymagają sterownika Instant Client")
            }
            if let svc = TNSNames.value("SERVICE_NAME", in: s) { return (host, port, .serviceName(svc)) }
            if let sid = TNSNames.value("SID", in: s) { return (host, port, .sid(sid)) }
            throw DatabaseError.unsupported("Brak SERVICE_NAME/SID w deskryptorze")
        }
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if s.hasPrefix("//") { s.removeFirst(2) }
        let parts = s.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw DatabaseError.unsupported("Sterownik thin wymaga EZConnect host[:port]/usługa albo aliasu TNS") }
        var hostPort = parts[0]
        var host = hostPort
        var port = 1521
        if hostPort.hasPrefix("["), let close = hostPort.firstIndex(of: "]") {
            host = String(hostPort[hostPort.index(after: hostPort.startIndex)..<close])
            hostPort = String(hostPort[hostPort.index(after: close)...])
            if hostPort.hasPrefix(":") { port = Int(hostPort.dropFirst()) ?? 1521 }
        } else if let colon = hostPort.lastIndex(of: ":") {
            host = String(hostPort[..<colon])
            port = Int(hostPort[hostPort.index(after: colon)...]) ?? 1521
        }
        let service = parts[1].split(separator: ":").first.map(String.init) ?? parts[1]
        return (host, port, .serviceName(service))
    }

    public func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions) async throws -> any DatabaseSession {
        if target.usesExternalCredentials { throw DatabaseError.unsupported("Uwierzytelnianie zewnętrzne (wallet, Kerberos) wymaga sterownika Instant Client") }
        if credentials.newPassword != nil { throw DatabaseError.unsupported("Zmiana wygasłego hasła wymaga sterownika Instant Client") }
        var connect = target.connectString
        if !connect.hasPrefix("("), !connect.contains("/") {
            let tns = TNSNames.load(directories: TNSNames.searchDirectories(configured: target.configDirectory))
            guard let e = tns.first(where: { $0.aliases.contains { $0.caseInsensitiveCompare(connect) == .orderedSame } }) else {
                throw DatabaseError.unsupported("Alias „\(connect)” nie występuje w tnsnames.ora")
            }
            connect = e.descriptor
        }
        let ep = try Self.endpoint(connect)
        var config = OracleConnection.Configuration(host: ep.host, port: ep.port, service: ep.service,
                                                    username: target.user, password: credentials.password ?? "")
        config.proxyUser = target.proxyClient
        switch target.role {
        case .normal: break
        case .sysdba: config.mode = .sysDBA
        case .sysoper: config.mode = .sysOPER
        case .sysbackup: config.mode = .sysBKP
        case .sysdg: config.mode = .sysDGD
        case .syskm: config.mode = .sysKMT
        case .sysasm: config.mode = .sysASM
        }
        config.options.connectTimeout = .seconds(20)
        let conn: OracleConnection
        do {
            conn = try await OracleConnection.connect(configuration: config, id: Int.random(in: 1...Int(Int32.max)))
        } catch {
            throw ThinSession.map(error)
        }
        let session = ThinSession(connection: conn, options: options)
        do { try await session.loadInfo() } catch { await session.close(); throw error }
        if !options.tags.module.isEmpty || options.tags.action != nil { try? await session.setTags(options.tags) }
        return session
    }
}

/// Sesja OracleNIO. Wywołania są kolejne (jak w oknie wzorca); kursory trzymane w pudełkach z iteratorem.
public final class ThinSession: DatabaseSession, @unchecked Sendable {
    public private(set) var info: SessionInfo
    let connection: OracleConnection
    let options: ConnectOptions
    private let state = Mutex(State())

    final class Cursor: @unchecked Sendable {
        var iterator: OracleRowSequence.AsyncIterator
        let columns: [ColumnInfo]
        let lobLimit: Int
        init(iterator: OracleRowSequence.AsyncIterator, columns: [ColumnInfo], lobLimit: Int) {
            self.iterator = iterator; self.columns = columns; self.lobLimit = lobLimit
        }
    }

    struct State {
        var cursors: [UInt64: Cursor] = [:]
        var next: UInt64 = 1
    }

    init(connection: OracleConnection, options: ConnectOptions) {
        self.connection = connection
        self.options = options
        let v = connection.serverVersion
        info = SessionInfo(driver: .thin, driverVersion: "OracleNIO 1.0.0-rc.4", clientVersion: "thin",
                           server: ServerVersion(major: v.majorDatabaseReleaseNumber, minor: v.databaseMaintenanceReleaseNumber,
                                                 update: v.fusionMiddlewareReleaseNumber, portRelease: v.componentSpecificReleaseNumber,
                                                 portUpdate: v.platformSpecificReleaseNumber),
                           capabilities: ThinDriver.capabilitySet, currentSchema: "", sessionUser: "")
    }

    func loadInfo() async throws {
        let (_, rows) = try await queryAll("select sys_context('USERENV', 'SESSION_USER'), sys_context('USERENV', 'CURRENT_SCHEMA'), (select banner_full from v$version where rownum = 1) from dual")
        if let r = rows.first {
            info.sessionUser = r[0].displayText ?? ""
            info.currentSchema = r[1].displayText ?? ""
            info.server.banner = r[2].displayText ?? ""
        }
    }

    // MARK: Błędy

    static func map(_ error: any Error) -> any Error {
        guard let e = error as? OracleSQLError else { return error }
        if let s = e.serverInfo {
            let msg = (s.message ?? "ORA-\(s.number)").trimmingCharacters(in: .whitespacesAndNewlines)
            return OracleError(code: Int32(s.number), message: msg, offset: offset(of: s))
        }
        let connectionLost: Set<OracleSQLError.Code> = [.clientClosedConnection, .connectionError, .uncleanShutdown, .clientClosesConnection]
        if connectionLost.contains(e.code) {
            return OracleError(code: 3113, message: "ORA-03113: koniec pliku w kanale komunikacyjnym (\(e.code))")
        }
        if e.code == .statementCancelled { return OracleError(code: 1013, message: "ORA-01013: przerwano wykonanie") }
        return DatabaseError.unsupported("OracleNIO: \(e.code)\(e.underlying.map { " — \($0)" } ?? "")")
    }

    /// Pozycja błędu w poleceniu (pole wewnętrzne OracleNIO, odczyt przez refleksję — 0, gdy niedostępne).
    static func offset(of info: OracleSQLError.ServerInfo) -> UInt32 {
        for child in Mirror(reflecting: info).children {
            for c in Mirror(reflecting: child.value).children where c.label == "position" || c.label == "errorPosition" {
                if let v = c.value as? Int { return UInt32(max(0, v)) }
                if let v = c.value as? UInt32 { return v }
                if let v = c.value as? UInt16 { return UInt32(v) }
            }
        }
        return 0
    }

    // MARK: Metadane kolumn

    static func oracleType(_ t: OracleDataType) -> OracleType {
        switch t {
        case .varchar, .long: .varchar2
        case .nVarchar, .longNVarchar: .nvarchar2
        case .char: .char
        case .nChar: .nchar
        case .number: .number
        case .binaryInteger: .binaryInteger
        case .binaryDouble: .binaryDouble
        case .binaryFloat: .binaryFloat
        case .date: .date
        case .timestamp: .timestamp
        case .timestampTZ: .timestampTZ
        case .timestampLTZ: .timestampLTZ
        case .intervalDS: .intervalDS
        case .intervalYM: .intervalYM
        case .raw: .raw
        case .longRAW: .longRaw
        case .clob: .clob
        case .nCLOB: .nclob
        case .blob: .blob
        case .bFile: .bfile
        case .rowID, .uRowID: .rowid
        case .boolean: .boolean
        case .json: .json
        case .vector: .vector
        case .cursor: .refCursor
        case .object: .object
        default: .unknown
        }
    }

    /// Opis kolumny z metadanych OracleNIO (typ, rozmiar, precyzja — pola wewnętrzne, odczyt przez refleksję).
    static func columnInfo(_ c: OracleColumn) -> ColumnInfo {
        var type = OracleType.unknown
        var size: UInt32 = 0, precision: Int16 = 0, scale: Int16 = 0, nullable = true
        var typeNameOverride: String?
        for child in Mirror(reflecting: c).children where child.label == "underlying" {
            for f in Mirror(reflecting: child.value).children {
                switch f.label {
                case "dataType": if let d = f.value as? OracleDataType { type = oracleType(d) }
                case "dataTypeSize": size = (f.value as? UInt32) ?? 0
                case "precision": precision = (f.value as? Int16) ?? 0
                case "scale": scale = (f.value as? Int16) ?? 0
                case "nullsAllowed": nullable = (f.value as? Bool) ?? true
                case "typeName": if let n = f.value as? String, !n.isEmpty { typeNameOverride = n }
                default: break
                }
            }
        }
        let typeName: String
        switch type {
        case .varchar2, .nvarchar2, .char, .nchar, .raw: typeName = "\(type.rawValue)(\(size))"
        case .number where precision > 0: typeName = scale > 0 ? "NUMBER(\(precision),\(scale))" : "NUMBER(\(precision))"
        case .object: typeName = typeNameOverride ?? "OBJECT"
        default: typeName = type.rawValue
        }
        return ColumnInfo(name: c.name, type: type, typeName: typeName, nullable: nullable, precision: precision,
                          scale: Int8(clamping: scale), size: size)
    }

    // MARK: Wartości

    func value(_ cell: OracleCell, lobLimit: Int) async throws -> OracleValue {
        guard var buf = cell.bytes, buf.readableBytes > 0 || cell.dataType == .varchar else { return .null }
        let t = cell.dataType
        switch t {
        case .number, .binaryInteger:
            return OracleRaw.number(buf.readBytes(length: buf.readableBytes) ?? []).map { .number($0) } ?? .null
        case .date, .timestamp, .timestampTZ, .timestampLTZ:
            return OracleRaw.timestamp(buf.readBytes(length: buf.readableBytes) ?? []).map { .timestamp($0, Self.oracleType(t)) } ?? .null
        case .binaryDouble, .binaryFloat:
            return .double(try cell.decode(Double.self, context: .default))
        case .boolean:
            return .boolean(try cell.decode(Bool.self, context: .default))
        case .raw, .longRAW:
            return .raw(Data(buf.readBytes(length: buf.readableBytes) ?? []))
        case .rowID, .uRowID:
            return .rowid(try cell.decode(String.self, context: .default))
        case .clob, .nCLOB, .blob, .bFile:
            let lob = try cell.decode(LOB.self, context: .default)
            var data = Data()
            var stopped = false
            let total = lob.estimatedSize
            for try await chunk in lob.readChunks(on: connection) {
                data.append(contentsOf: chunk.readableBytesView)
                if data.count >= lobLimit { stopped = true; break }
            }
            // Obcięte: odczyt przerwany na limicie albo ostatnia porcja przekroczyła limit (prefix niżej ucina).
            let truncated = data.count > lobLimit || (stopped && total > data.count)
            switch t {
            case .clob, .nCLOB:
                let text = Self.clobText(data.prefix(lobLimit))
                return .lob(LOBValue(kind: t == .clob ? .clob : .nclob, text: text, length: UInt64(total), truncated: truncated))
            default:
                return .lob(LOBValue(kind: t == .blob ? .blob : .bfile, bytes: data.prefix(lobLimit), length: UInt64(total), truncated: truncated))
            }
        case .intervalDS:
            let i = try cell.decode(IntervalDS.self, context: .default)
            return .intervalDS(days: Int32(i.days), hours: Int32(i.hours), minutes: Int32(i.minutes), seconds: Int32(i.seconds),
                               fseconds: Int32(i.fractionalSeconds))
        case .varchar, .long, .nVarchar, .longNVarchar, .char, .nChar:
            return .text(try cell.decode(String.self, context: .default))
        default:
            if let s = try? cell.decode(String.self, context: .default) { return .text(s) }
            return .object(typeName: Self.oracleType(t).rawValue, description: "")
        }
    }

    // MARK: Wykonanie

    func bindings(_ binds: [BindVariable]) throws -> (OracleBindings, [(String, OracleRef, OracleType)]) {
        var b = OracleBindings(capacity: binds.count)
        var refs: [(String, OracleRef, OracleType)] = []
        for v in binds {
            let name = v.name.hasPrefix(":") ? String(v.name.dropFirst()) : v.name
            if v.direction != .input {
                let ref: OracleRef
                switch v.direction == .inputOutput ? v.value : .null {
                case .null: ref = OracleRef(dataType: Self.nioType(v.type))
                case .number(let n): ref = OracleRef(OracleNumber(n) ?? OracleNumber(0))
                case .double(let d): ref = OracleRef(d)
                default: ref = OracleRef(v.value.format(.default))
                }
                b.append(ref, bindName: name, isReturning: false)
                refs.append((v.name, ref, v.type))
                continue
            }
            switch v.value {
            case .null: b.appendNull(Self.nioType(v.type), bindName: name)
            case .number(let n):
                if let num = OracleNumber(n), String(num.doubleValue) == n || Double(n).map({ $0 == $0.rounded() && abs($0) < 1e15 }) == true {
                    b.append(num, context: .default, bindName: name)
                } else {
                    b.append(n, context: .default, bindName: name)     // pełna precyzja jako tekst (konwersja po stronie serwera)
                }
            case .double(let d): b.append(d, context: .default, bindName: name)
            case .boolean(let x): b.append(x, context: .default, bindName: name)
            case .raw(let d): b.append(ByteBuffer(bytes: d), context: .default, bindName: name)
            case .lob(let l):
                if let text = l.text { b.append(text, context: .default, bindName: name) }
                else { b.append(ByteBuffer(bytes: l.bytes ?? Data()), context: .default, bindName: name) }
            case .timestamp(let ts, _):
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(secondsFromGMT: Int(ts.tzHourOffset) * 3600 + Int(ts.tzMinuteOffset) * 60) ?? .gmt
                let date = cal.date(from: DateComponents(year: Int(ts.year), month: Int(ts.month), day: Int(ts.day), hour: Int(ts.hour),
                                                         minute: Int(ts.minute), second: Int(ts.second), nanosecond: Int(ts.fsecond))) ?? Date()
                b.append(date, context: .default, bindName: name)
            default:
                b.append(v.value.format(.default), context: .default, bindName: name)
            }
        }
        return (b, refs)
    }

    static func nioType(_ t: OracleType) -> OracleDataType {
        switch t {
        case .number, .binaryInteger: .number
        case .binaryDouble, .binaryFloat: .binaryDouble
        case .date: .date
        case .timestamp: .timestamp
        case .timestampTZ: .timestampTZ
        case .clob: .clob
        case .nclob: .nCLOB
        case .blob: .blob
        case .raw, .longRaw: .raw
        case .boolean: .boolean
        case .refCursor: .cursor
        default: .varchar
        }
    }

    static func kind(_ sql: String) -> StatementKind {
        switch StatementClassifier.classify(sql).category {
        case .query: .query
        case .dml: .dml
        case .plsql: .plsql
        case .ddl, .systemControl: .ddl
        case .transactionControl: .transaction
        case .sessionControl: .alterSession
        default: .other
        }
    }

    public func execute(_ sql: String, binds: [BindVariable], options: ExecuteOptions) async throws -> ExecutionResult {
        let start = ContinuousClock.now
        let (b, refs) = try bindings(binds)
        let stmt = OracleStatement(unsafeSQL: sql, binds: b)
        let rows: OracleRowSequence
        do {
            var so = StatementOptions()
            so.fetchLOBs = true                         // LOB jako lokator: odczyt do limitu, długość i znacznik obcięcia
            so.arraySize = Int(options.fetchArraySize ?? self.options.fetchArraySize)
            rows = try await connection.execute(stmt, options: so)
        } catch {
            throw Self.map(error)
        }
        var result = ExecutionResult(kind: Self.kind(sql))
        let columns = rows.columns.map(Self.columnInfo)
        if result.kind == .query || !columns.isEmpty {
            result.kind = .query
            let id = state.withLock { s -> UInt64 in
                let id = s.next
                s.next += 1
                s.cursors[id] = Cursor(iterator: rows.makeAsyncIterator(), columns: columns, lobLimit: options.lobLimit ?? self.options.lobPrefetchLimit)
                return id
            }
            result.resultSet = ResultSetDescriptor(id: ResultSetID(id), columns: columns)
        } else {
            result.rowsAffected = UInt64(max(0, (try? await rows.affectedRows) ?? 0))
        }
        for (name, ref, type) in refs {
            result.outBinds[name] = (try? await outValue(ref, type: type, lobLimit: options.lobLimit ?? self.options.lobPrefetchLimit)) ?? .null
        }
        // OracleNIO nie ma trybu „commit on success” ani limitu czasu wywołania: COMMIT po udanym poleceniu; limit
        // `callTimeoutMs` (zapytania agenta) na thin nie działa, tak jak przerwanie (D168).
        if options.autoCommit, result.kind != .query { try await commit() }
        if result.kind == .ddl, let object = Self.compiledObject(sql) {
            // Błędy kompilacji: OracleNIO nie przekazuje ostrzeżenia ORA-24344 — sprawdzamy ALL_ERRORS dla obiektu.
            if let w = try? await compileWarning(object) { result.warning = w }
        }
        result.elapsed = ContinuousClock.now - start
        return result
    }

    /// Obiekt kompilowany poleceniem `CREATE [OR REPLACE] [EDITIONABLE|NONEDITIONABLE|FORCE…] typ [BODY] [schemat.]nazwa`
    /// (typ jak w ALL_ERRORS); nil dla innych poleceń.
    static func compiledObject(_ sql: String) -> (owner: String?, name: String, type: String)? {
        var words: [String] = []
        var i = sql.startIndex
        while i < sql.endIndex, words.count < 12 {
            let c = sql[i]
            if c.isWhitespace { i = sql.index(after: i); continue }
            if c == "-", sql[i...].hasPrefix("--") { i = sql[i...].firstIndex(of: "\n") ?? sql.endIndex; continue }
            if c == "/", sql[i...].hasPrefix("/*") { i = sql[i...].range(of: "*/")?.upperBound ?? sql.endIndex; continue }
            if c == "." { words.append("."); i = sql.index(after: i); continue }
            if c == "\"" {
                let start = sql.index(after: i)
                guard let end = sql[start...].firstIndex(of: "\"") else { return nil }
                words.append("\"" + sql[start..<end]); i = sql.index(after: end); continue
            }
            guard c.isLetter || c.isNumber || c == "_" || c == "$" || c == "#" else { break }
            let start = i
            while i < sql.endIndex, sql[i].isLetter || sql[i].isNumber || "_$#".contains(sql[i]) { i = sql.index(after: i) }
            words.append(sql[start..<i].uppercased())
        }
        guard words.first == "CREATE" else { return nil }
        var k = 1
        if k + 1 < words.count, words[k] == "OR", words[k + 1] == "REPLACE" { k += 2 }
        while k < words.count, ["EDITIONABLE", "NONEDITIONABLE", "EDITIONING", "FORCE", "NOFORCE"].contains(words[k]) { k += 1 }
        guard k < words.count else { return nil }
        var type = words[k]
        guard ["PROCEDURE", "FUNCTION", "PACKAGE", "TRIGGER", "TYPE", "VIEW"].contains(type) else { return nil }
        k += 1
        if k < words.count, words[k] == "BODY", type == "PACKAGE" || type == "TYPE" { type += " BODY"; k += 1 }
        func ident(_ w: String) -> String { w.hasPrefix("\"") ? String(w.dropFirst()) : w }
        guard k < words.count else { return nil }
        if k + 2 < words.count, words[k + 1] == "." { return (ident(words[k]), ident(words[k + 2]), type) }
        return (nil, ident(words[k]), type)
    }

    func compileWarning(_ object: (owner: String?, name: String, type: String)) async throws -> OracleError? {
        let count = try await scalar("""
            select count(*) from all_errors where attribute = 'ERROR'
               and owner = nvl(:o, sys_context('userenv', 'current_schema')) and name = :n and type = :t
            """, binds: [BindVariable(name: "o", value: object.owner.map { .text($0) } ?? .null),
                         BindVariable(name: "n", value: .text(object.name)), BindVariable(name: "t", value: .text(object.type))])
        guard count.flatMap(Int.init) ?? 0 > 0 else { return nil }
        return OracleError(code: 24344, message: "ORA-24344: success with compilation error", isWarning: true)
    }

    /// Tekst CLOB z bajtów odczytanych z lokatora: przy wielobajtowym zestawie znaków bazy CLOB jest w AL16UTF16 (UTF-16BE).
    static func clobText(_ data: Data) -> String {
        if data.count >= 2, data.count % 2 == 0, data.contains(0) {
            return String(decoding: stride(from: 0, to: data.count, by: 2).map { i in
                UInt16(data[data.startIndex + i]) << 8 | UInt16(data[data.startIndex + i + 1])
            }, as: UTF16.self)
        }
        return String(decoding: data, as: UTF8.self)
    }

    func outValue(_ ref: OracleRef, type: OracleType, lobLimit: Int) async throws -> OracleValue {
        switch type {
        case .number, .binaryInteger:
            // OracleNumber trzyma surowy NUMBER w polu `value` — dekodujemy go bez Double (pełna precyzja).
            let n = try ref.decode(as: OracleNumber.self)
            if var raw = Mirror(reflecting: n).children.first(where: { $0.label == "value" })?.value as? ByteBuffer,
               let text = OracleRaw.number(raw.readBytes(length: raw.readableBytes) ?? []) {
                return .number(text)
            }
            return .number(n.description.hasSuffix(".0") ? String(n.description.dropLast(2)) : n.description)
        case .binaryDouble, .binaryFloat: return .double(try ref.decode(as: Double.self))
        case .boolean: return .boolean(try ref.decode(as: Bool.self))
        case .clob, .nclob, .blob:
            let lob = try ref.decode(as: LOB.self)
            var data = Data()
            for try await chunk in lob.readChunks(on: connection) {
                data.append(contentsOf: chunk.readableBytesView)
                if data.count >= lobLimit { break }
            }
            let total = UInt64(lob.estimatedSize)
            if type == .blob { return .lob(LOBValue(kind: .blob, bytes: data, length: total, truncated: Int(total) > data.count)) }
            let s = Self.clobText(data)
            return .lob(LOBValue(kind: type == .nclob ? .nclob : .clob, text: s, length: total, truncated: Int(total) > data.count))
        default: return .text(try ref.decode(as: String.self))
        }
    }

    public func fetch(_ resultSet: ResultSetID, maxRows: Int) async throws -> RowBatch {
        guard let cursor = state.withLock({ $0.cursors[resultSet.raw] }) else { throw DatabaseError.unknownResultSet }
        var out: [[OracleValue]] = []
        out.reserveCapacity(min(maxRows, 10_000))
        do {
            while out.count < maxRows {
                guard let row = try await cursor.iterator.next() else {
                    _ = state.withLock { $0.cursors.removeValue(forKey: resultSet.raw) }
                    return RowBatch(rows: out, hasMore: false)
                }
                var values: [OracleValue] = []
                values.reserveCapacity(cursor.columns.count)
                for cell in row { values.append(try await value(cell, lobLimit: cursor.lobLimit)) }
                out.append(values)
            }
        } catch let e as OracleError {
            throw e
        } catch {
            throw Self.map(error)
        }
        return RowBatch(rows: out, hasMore: true)
    }

    public func closeResultSet(_ resultSet: ResultSetID) async {
        _ = state.withLock { $0.cursors.removeValue(forKey: resultSet.raw) }
    }

    public func commit() async throws {
        do { try await connection.commit() } catch { throw Self.map(error) }
    }

    public func rollback() async throws {
        do { try await connection.rollback() } catch { throw Self.map(error) }
    }

    /// OracleNIO nie udostępnia przerwania wywołania (break) — możliwość wyłączona w `capabilities`.
    public func breakExecution() {}

    public func ping() async throws {
        do { try await connection.ping() } catch { throw Self.map(error) }
    }

    public func setTags(_ tags: SessionTags) async throws {
        var plsql = "dbms_application_info.set_module(:m, :a);"
        var binds = [BindVariable(name: "m", value: .text(tags.module)), BindVariable(name: "a", value: tags.action.map { .text($0) } ?? .null)]
        if let info = tags.clientInfo {
            plsql += " dbms_application_info.set_client_info(:ci);"
            binds.append(BindVariable(name: "ci", value: .text(info)))
        }
        if let id = tags.clientIdentifier {
            plsql += " dbms_session.set_identifier(:cid);"
            binds.append(BindVariable(name: "cid", value: .text(id)))
        }
        _ = try await execute("begin \(plsql) end;", binds: binds, options: ExecuteOptions())
    }

    public func close() async {
        state.withLock { $0.cursors.removeAll() }
        // Wylogowanie zatwierdza otwartą transakcję (OCISessionEnd/OracleNIO): jak w ODPISession — ROLLBACK przed
        // zamknięciem, decyzję o COMMIT podejmuje wcześniej interfejs (D10).
        try? await connection.rollback()
        try? await connection.close()
    }
}
