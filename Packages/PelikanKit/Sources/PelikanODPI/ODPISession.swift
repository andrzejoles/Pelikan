import CODPI
import Dispatch
import Foundation
import PelikanDB
import Synchronization

/// Sesja Oracle przez ODPI-C + Instant Client.
///
/// Każda sesja ma własną kolejkę szeregową (wątki GCD, nie pula kooperacyjna Swifta), bo wywołania OCI
/// blokują. Cały stan zmienny jest dotykany tylko na tej kolejce; wyjątek to `breakExecution`, które OCI
/// pozwala wywołać z innego wątku w trakcie trwającego wywołania (tryb DPI_MODE_CREATE_THREADED).
public final class ODPISession: DatabaseSession, @unchecked Sendable {
    public private(set) var info: SessionInfo

    private let env: ODPIEnvironment
    private let conn: OpaquePointer
    private let queue: DispatchQueue
    private let options: ConnectOptions
    private var resultSets: [UInt64: OpenResultSet] = [:]
    /// Rozmiar pobierania bieżącego polecenia (ExecuteOptions albo opcje połączenia) — także dla kursorów potomnych.
    private var currentFetchArraySize: UInt32 = 500
    private var nextResultSetID: UInt64 = 1
    /// Zamknięte (true) — chronione blokadą, bo `breakExecution` działa poza kolejką i nie może trafić w zwolniony
    /// uchwyt połączenia w trakcie `close()`.
    private let closedState = Mutex<Bool>(false)
    private var closed: Bool { closedState.withLock { $0 } }

    private struct OpenResultSet {
        let stmt: OpaquePointer
        let columns: [ColumnInfo]
        let lobLimit: Int
    }

    /// Paczka pobierania hurtowego: przy opóźnieniu ~50 ms paczka 500 daje ~8 tys. wierszy/s, 5000 — 40–60 tys.
    /// Najwyżej 10 000 wierszy i ~16 MB buforów (szeroki wiersz — mniejsza paczka), nigdy mniej niż bieżąca.
    static func bulkFetchArraySize(rowBytes: Int, current: UInt32) -> UInt32 {
        let byMemory = (16 << 20) / max(1, rowBytes)
        return UInt32(max(Int(current), min(10_000, byMemory)))
    }

    /// Bajty bufora jednego wiersza po stronie klienta (wartość + opis `dpiData`); LOB i typy dynamiczne liczone
    /// jako lokator — ich treść pobierana jest osobno.
    private func clientRowBytes(_ stmt: OpaquePointer, columns: UInt32) -> Int {
        var total = 0
        for pos in 0..<columns {
            var q = dpiQueryInfo()
            guard dpiStmt_getQueryInfo(stmt, pos + 1, &q) == DPI_SUCCESS else { return Int.max / 2 }
            total += max(Int(q.typeInfo.clientSizeInBytes), 24) + MemoryLayout<dpiData>.size
        }
        return total
    }

    /// Możliwości sterownika Instant Client (pełne OCI).
    public static let capabilities: DriverCapabilities = [
        .breakExecution, .dbmsDebug, .dbmsDebugJDWP, .lobs, .objectTypes, .refCursors, .implicitResults,
        .wallet, .kerberos, .proxyUser, .changePassword, .tnsNames, .ldap, .sysdba, .json, .vector, .oldServers,
    ]

    private init(env: ODPIEnvironment, conn: OpaquePointer, queue: DispatchQueue, options: ConnectOptions, info: SessionInfo) {
        self.env = env; self.conn = conn; self.queue = queue; self.options = options; self.info = info
    }

    deinit {
        if !closed {
            for (_, rs) in resultSets { dpiStmt_release(rs.stmt) }
            dpiConn_release(conn)
        }
    }

    /// Łączy się z bazą. `libraryDirectory` — katalog Instant Client z ustawień (nil = wykrywanie).
    public static func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions = ConnectOptions(),
                               libraryDirectory: String? = nil, configDirectory: String? = nil) async throws -> ODPISession {
        let env = try ODPIEnvironment.get(libraryDirectory: libraryDirectory, configDirectory: configDirectory)
        let queue = DispatchQueue(label: "pelikan.odpi.session", qos: .userInitiated)
        var resolved = target
        // Magazyn haseł (portfel z poświadczeniami) szuka wpisu po dokładnym tekście aliasu — bez rozwijania (D53).
        if target.walletAuth == true { resolved.externalAuth = true }
        resolved.connectString = TNSNames.resolveForConnection(target.connectString, configDirectory: target.configDirectory,
                                                               walletDirectory: target.walletDirectory, keepAlias: resolved.externalAuth)
        // Token (Entra ID / OAuth2): klient Oracle sam pobiera token; logowanie bez użytkownika i hasła (SD-AUTH-001).
        if let token = target.tokenAuth {
            let missing = token.missingFields
            guard missing.isEmpty else { throw DatabaseError.unsupported("Uwierzytelnianie tokenem: brak \(missing.joined(separator: ", "))") }
            // Alias bez katalogu połączenia: rozwinięcie z konfiguracji Oracle Net Pelikana (IFILE do tnsnames.ora użytkownika).
            let expanded = TNSNames.applyTokenAuth(resolved.connectString, parameters: token.parameters) == nil && configDirectory != nil
                ? TNSNames.resolveForConnection(resolved.connectString, configDirectory: configDirectory) : resolved.connectString
            guard let s = TNSNames.applyTokenAuth(expanded, parameters: token.parameters) else {
                throw DatabaseError.unsupported("Uwierzytelnianie tokenem: nie znaleziono aliasu w tnsnames.ora — podaj EZConnect albo deskryptor")
            }
            resolved.connectString = s
            resolved.externalAuth = true
            resolved.user = ""
        }
        let finalTarget = resolved
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                cont.resume(with: Result { try connectSync(env: env, queue: queue, target: finalTarget, credentials: credentials, options: options) })
            }
        }
    }

    private static func connectSync(env: ODPIEnvironment, queue: DispatchQueue, target: ConnectionTarget,
                                    credentials: Credentials, options: ConnectOptions) throws -> ODPISession {
        var common = dpiCommonCreateParams()
        var create = dpiConnCreateParams()
        dpiContext_initCommonCreateParams(env.context, &common)
        dpiContext_initConnCreateParams(env.context, &create)
        common.createMode = dpiCreateMode(DPI_MODE_CREATE_THREADED)
        common.stmtCacheSize = options.statementCacheSize
        create.authMode = authMode(target.role)
        create.externalAuth = target.externalAuth ? 1 : 0

        var conn: OpaquePointer?
        let user = target.externalAuth && target.proxyClient == nil ? "" : target.driverUserName
        let password = target.externalAuth ? "" : (credentials.password ?? "")
        let status: Int32 = user.withCString { u in
            password.withCString { p in
                target.connectString.withCString { cs in
                    withOptionalCString(target.edition) { ed in
                        withOptionalCString(credentials.newPassword) { np in
                            if let ed { common.edition = ed; common.editionLength = UInt32(strlen(ed)) }
                            if let np { create.newPassword = np; create.newPasswordLength = UInt32(strlen(np)) }
                            return dpiConn_create(env.context, user.isEmpty ? nil : u, UInt32(user.utf8.count),
                                                  password.isEmpty ? nil : p, UInt32(password.utf8.count),
                                                  cs, UInt32(target.connectString.utf8.count), &common, &create, &conn)
                        }
                    }
                }
            }
        }
        guard status == DPI_SUCCESS, let conn else { throw env.lastError() }

        var release: UnsafePointer<CChar>?
        var releaseLen: UInt32 = 0
        var v = dpiVersionInfo()
        dpiConn_getServerVersion(conn, &release, &releaseLen, &v)
        let banner = release.map { String(decoding: UnsafeRawBufferPointer(start: $0, count: Int(releaseLen)), as: UTF8.self) } ?? ""
        let server = ServerVersion(major: Int(v.versionNum), minor: Int(v.releaseNum), update: Int(v.updateNum),
                                   portRelease: Int(v.portReleaseNum), portUpdate: Int(v.portUpdateNum), banner: banner)
        let session = ODPISession(env: env, conn: conn, queue: queue, options: options,
                                  info: SessionInfo(driver: .instantClient, driverVersion: "ODPI-C \(DPI_MAJOR_VERSION).\(DPI_MINOR_VERSION)",
                                                    clientVersion: env.clientVersion, server: server,
                                                    capabilities: capabilities, currentSchema: "", sessionUser: ""))
        try session.applyTagsSync(options.tags)
        // Bieżący schemat i użytkownik sesji (SYS_CONTEXT działa na każdej wersji od 8i).
        let r = try session.executeSync("SELECT SYS_CONTEXT('USERENV','CURRENT_SCHEMA'), SYS_CONTEXT('USERENV','SESSION_USER') FROM dual",
                                        binds: [], options: ExecuteOptions())
        if let rs = r.resultSet {
            let batch = try session.fetchSync(rs.id, maxRows: 1)
            if let row = batch.rows.first {
                session.info.currentSchema = row[0].displayText ?? ""
                session.info.sessionUser = row[1].displayText ?? ""
            }
            session.closeSync(rs.id)
        }
        return session
    }

    private static func authMode(_ role: ConnectRole) -> dpiAuthMode {
        switch role {
        case .normal: dpiAuthMode(DPI_MODE_AUTH_DEFAULT)
        case .sysdba: dpiAuthMode(DPI_MODE_AUTH_SYSDBA)
        case .sysoper: dpiAuthMode(DPI_MODE_AUTH_SYSOPER)
        case .sysbackup: dpiAuthMode(DPI_MODE_AUTH_SYSBKP)
        case .sysdg: dpiAuthMode(DPI_MODE_AUTH_SYSDGD)
        case .syskm: dpiAuthMode(DPI_MODE_AUTH_SYSKMT)
        case .sysasm: dpiAuthMode(DPI_MODE_AUTH_SYSASM)
        }
    }

    // MARK: - Kolejka

    private func onQueue<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                if closed { cont.resume(throwing: DatabaseError.closed); return }
                cont.resume(with: Result { try body() })
            }
        }
    }

    private func check(_ status: Int32) throws {
        if status != DPI_SUCCESS { throw env.lastError() }
    }

    // MARK: - DatabaseSession

    public func execute(_ sql: String, binds: [BindVariable], options: ExecuteOptions) async throws -> ExecutionResult {
        try await onQueue { [self] in try executeSync(sql, binds: binds, options: options) }
    }

    public func fetch(_ resultSet: ResultSetID, maxRows: Int) async throws -> RowBatch {
        try await onQueue { [self] in try fetchSync(resultSet, maxRows: maxRows) }
    }

    public func columns(of resultSet: ResultSetID) async -> [ColumnInfo] {
        (try? await onQueue { [self] in resultSets[resultSet.raw]?.columns ?? [] }) ?? []
    }

    public func closeResultSet(_ resultSet: ResultSetID) async {
        _ = try? await onQueue { [self] in closeSync(resultSet) }
    }

    public func commit() async throws {
        try await onQueue { [self] in try check(dpiConn_commit(conn)) }
    }

    public func rollback() async throws {
        try await onQueue { [self] in try check(dpiConn_rollback(conn)) }
    }

    public func breakExecution() {
        // Celowo poza kolejką: kolejka jest zajęta przez przerywane wywołanie. Blokada wyklucza wyścig z close().
        closedState.withLock { isClosed in
            if !isClosed { dpiConn_breakExecution(conn) }
        }
    }

    public func ping() async throws {
        try await onQueue { [self] in try check(dpiConn_ping(conn)) }
    }

    public func setTags(_ tags: SessionTags) async throws {
        try await onQueue { [self] in try applyTagsSync(tags) }
    }

    public func close() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                closedState.withLock { isClosed in
                    guard !isClosed else { return }
                    for (_, rs) in resultSets { dpiStmt_release(rs.stmt) }
                    resultSets.removeAll()
                    // Sterownik nigdy nie zatwierdza po cichu: decyzję COMMIT/ROLLBACK podejmuje wcześniej interfejs
                    // (D10); tu zostaje bezpieczne ROLLBACK przed zamknięciem.
                    dpiConn_rollback(conn)
                    dpiConn_close(conn, dpiConnCloseMode(DPI_MODE_CONN_CLOSE_DEFAULT), nil, 0)
                    dpiConn_release(conn)
                    isClosed = true
                }
                cont.resume()
            }
        }
    }

    // MARK: - Implementacja na kolejce

    private func applyTagsSync(_ tags: SessionTags) throws {
        try tags.module.withCString { try check(dpiConn_setModule(conn, $0, UInt32(tags.module.utf8.count))) }
        let action = tags.action ?? ""
        try action.withCString { try check(dpiConn_setAction(conn, $0, UInt32(action.utf8.count))) }
        let ci = tags.clientInfo ?? ""
        try ci.withCString { try check(dpiConn_setClientInfo(conn, $0, UInt32(ci.utf8.count))) }
        if let id = tags.clientIdentifier {
            try id.withCString { try check(dpiConn_setClientIdentifier(conn, $0, UInt32(id.utf8.count))) }
        }
    }

    func executeSync(_ sql: String, binds: [BindVariable], options: ExecuteOptions) throws -> ExecutionResult {
        let start = ContinuousClock.now
        var stmtOpt: OpaquePointer?
        try sql.withCString { try check(dpiConn_prepareStmt(conn, 0, $0, UInt32(sql.utf8.count), nil, 0, &stmtOpt)) }
        guard let stmt = stmtOpt else { throw DatabaseError.closed }
        var keepStmt = false
        defer { if !keepStmt { dpiStmt_release(stmt) } }

        var stmtInfo = dpiStmtInfo()
        try check(dpiStmt_getInfo(stmt, &stmtInfo))
        let kind = Self.kind(stmtInfo)

        try check(dpiConn_setCallTimeout(conn, options.callTimeoutMs))
        let vars = try bindVariables(binds, to: stmt)
        defer { for v in vars { dpiVar_release(v.handle) } }

        currentFetchArraySize = options.fetchArraySize ?? self.options.fetchArraySize
        if stmtInfo.isQuery != 0 { try check(dpiStmt_setFetchArraySize(stmt, currentFetchArraySize)) }
        var mode = dpiExecMode(DPI_MODE_EXEC_DEFAULT)
        if options.describeOnly { mode |= dpiExecMode(DPI_MODE_EXEC_DESCRIBE_ONLY) }
        if options.autoCommit { mode |= dpiExecMode(DPI_MODE_EXEC_COMMIT_ON_SUCCESS) }
        var numCols: UInt32 = 0
        try check(dpiStmt_execute(stmt, mode, &numCols))
        // Sukces z ostrzeżeniem, np. ORA-24344 (kompilacja z błędami) albo ORA-28002 (hasło wkrótce wygaśnie).
        var warning: OracleError?
        let last = env.lastError()
        if last.isWarning { warning = last }

        var result = ExecutionResult(kind: kind, warning: warning)
        if stmtInfo.isQuery != 0 {
            // Przed definicją zmiennych (describeColumns) — potem ODPI-C nie pozwala powiększyć paczki.
            if options.bulk, options.fetchArraySize == nil {
                let size = Self.bulkFetchArraySize(rowBytes: clientRowBytes(stmt, columns: numCols), current: currentFetchArraySize)
                if size > currentFetchArraySize {
                    try check(dpiStmt_setFetchArraySize(stmt, size))
                    currentFetchArraySize = size
                }
            }
            let columns = try describeColumns(stmt, count: numCols)
            result.resultSet = register(stmt: stmt, columns: columns, lobLimit: options.lobLimit ?? self.options.lobPrefetchLimit)
            keepStmt = true
        } else {
            var count: UInt64 = 0
            if dpiStmt_getRowCount(stmt, &count) == DPI_SUCCESS, stmtInfo.isDML != 0 { result.rowsAffected = count }
        }
        for v in vars where v.bind.direction != .input {
            result.outBinds[v.bind.name] = try value(native: v.nativeType, oracle: v.oracleType, data: v.data, typeName: v.bind.type.rawValue, lobLimit: options.lobLimit ?? self.options.lobPrefetchLimit)
        }
        if stmtInfo.isPLSQL != 0 {
            result.implicitResults = try implicitResults(stmt, lobLimit: options.lobLimit ?? self.options.lobPrefetchLimit)
        }
        result.elapsed = ContinuousClock.now - start
        return result
    }

    private static func kind(_ i: dpiStmtInfo) -> StatementKind {
        if i.isQuery != 0 { return .query }
        if i.isDML != 0 { return .dml }
        if i.isPLSQL != 0 { return .plsql }
        if i.isDDL != 0 { return .ddl }
        switch Int32(i.statementType) {
        case DPI_STMT_TYPE_COMMIT, DPI_STMT_TYPE_ROLLBACK: return .transaction
        case DPI_STMT_TYPE_ALTER: return .alterSession
        default: return .other
        }
    }

    private func register(stmt: OpaquePointer, columns: [ColumnInfo], lobLimit: Int) -> ResultSetDescriptor {
        let id = nextResultSetID
        nextResultSetID += 1
        resultSets[id] = OpenResultSet(stmt: stmt, columns: columns, lobLimit: lobLimit)
        return ResultSetDescriptor(id: ResultSetID(id), columns: columns)
    }

    private func implicitResults(_ stmt: OpaquePointer, lobLimit: Int) throws -> [ResultSetDescriptor] {
        var out: [ResultSetDescriptor] = []
        while true {
            var child: OpaquePointer?
            guard dpiStmt_getImplicitResult(stmt, &child) == DPI_SUCCESS, let child else { break }
            dpiStmt_addRef(child)
            var n: UInt32 = 0
            try check(dpiStmt_getNumQueryColumns(child, &n))
            try check(dpiStmt_setFetchArraySize(child, currentFetchArraySize))
            out.append(register(stmt: child, columns: try describeColumns(child, count: n), lobLimit: lobLimit))
        }
        return out
    }

    private func describeColumns(_ stmt: OpaquePointer, count: UInt32) throws -> [ColumnInfo] {
        var cols: [ColumnInfo] = []
        cols.reserveCapacity(Int(count))
        for pos in 1...max(count, 1) where count > 0 {
            var q = dpiQueryInfo()
            try check(dpiStmt_getQueryInfo(stmt, pos, &q))
            let name = String(decoding: UnsafeRawBufferPointer(start: q.name, count: Int(q.nameLength)), as: UTF8.self)
            let t = q.typeInfo
            let type = Self.oracleType(t.oracleTypeNum, isJson: t.isJson != 0)
            cols.append(ColumnInfo(name: name, type: type, typeName: Self.typeName(type, t), nullable: q.nullOk != 0,
                                   precision: t.precision, scale: t.scale, size: t.sizeInChars > 0 ? t.sizeInChars : t.dbSizeInBytes))
            // NUMBER jako tekst — bez utraty precyzji (38 cyfr nie mieści się w Double).
            if t.oracleTypeNum == UInt32(DPI_ORACLE_TYPE_NUMBER) {
                try check(dpiStmt_defineValue(stmt, pos, dpiOracleTypeNum(DPI_ORACLE_TYPE_NUMBER), dpiNativeTypeNum(DPI_NATIVE_TYPE_BYTES), 0, 0, nil))
            }
        }
        return cols
    }

    static func oracleType(_ n: UInt32, isJson: Bool = false) -> OracleType {
        if isJson { return .json }
        switch Int32(n) {
        case DPI_ORACLE_TYPE_VARCHAR: return .varchar2
        case DPI_ORACLE_TYPE_NVARCHAR: return .nvarchar2
        case DPI_ORACLE_TYPE_CHAR: return .char
        case DPI_ORACLE_TYPE_NCHAR: return .nchar
        case DPI_ORACLE_TYPE_ROWID: return .rowid
        case DPI_ORACLE_TYPE_UROWID: return .urowid
        case DPI_ORACLE_TYPE_RAW: return .raw
        case DPI_ORACLE_TYPE_NATIVE_FLOAT: return .binaryFloat
        case DPI_ORACLE_TYPE_NATIVE_DOUBLE: return .binaryDouble
        case DPI_ORACLE_TYPE_NATIVE_INT, DPI_ORACLE_TYPE_NATIVE_UINT: return .binaryInteger
        case DPI_ORACLE_TYPE_NUMBER: return .number
        case DPI_ORACLE_TYPE_DATE: return .date
        case DPI_ORACLE_TYPE_TIMESTAMP: return .timestamp
        case DPI_ORACLE_TYPE_TIMESTAMP_TZ: return .timestampTZ
        case DPI_ORACLE_TYPE_TIMESTAMP_LTZ: return .timestampLTZ
        case DPI_ORACLE_TYPE_INTERVAL_DS: return .intervalDS
        case DPI_ORACLE_TYPE_INTERVAL_YM: return .intervalYM
        case DPI_ORACLE_TYPE_CLOB: return .clob
        case DPI_ORACLE_TYPE_NCLOB: return .nclob
        case DPI_ORACLE_TYPE_BLOB: return .blob
        case DPI_ORACLE_TYPE_BFILE: return .bfile
        case DPI_ORACLE_TYPE_STMT: return .refCursor
        case DPI_ORACLE_TYPE_BOOLEAN: return .boolean
        case DPI_ORACLE_TYPE_OBJECT: return .object
        case DPI_ORACLE_TYPE_LONG_VARCHAR, DPI_ORACLE_TYPE_LONG_NVARCHAR: return .long
        case DPI_ORACLE_TYPE_LONG_RAW: return .longRaw
        case DPI_ORACLE_TYPE_JSON, DPI_ORACLE_TYPE_JSON_OBJECT, DPI_ORACLE_TYPE_JSON_ARRAY, DPI_ORACLE_TYPE_JSON_ID: return .json
        case DPI_ORACLE_TYPE_XMLTYPE: return .xmltype
        case DPI_ORACLE_TYPE_VECTOR: return .vector
        default: return .unknown
        }
    }

    private static func typeName(_ type: OracleType, _ t: dpiDataTypeInfo) -> String {
        switch type {
        case .varchar2, .nvarchar2, .char, .nchar:
            return "\(type.rawValue)(\(t.sizeInChars))"
        case .raw:
            return "RAW(\(t.dbSizeInBytes))"
        case .number:
            if t.precision == 0 && t.scale == -127 { return "NUMBER" }
            if t.precision == 0 { return "NUMBER" }
            return t.scale == 0 ? "NUMBER(\(t.precision))" : "NUMBER(\(t.precision),\(t.scale))"
        case .object:
            if let ot = t.objectType {
                var oi = dpiObjectTypeInfo()
                if dpiObjectType_getInfo(ot, &oi) == DPI_SUCCESS {
                    let schema = String(decoding: UnsafeRawBufferPointer(start: oi.schema, count: Int(oi.schemaLength)), as: UTF8.self)
                    let name = String(decoding: UnsafeRawBufferPointer(start: oi.name, count: Int(oi.nameLength)), as: UTF8.self)
                    return schema.isEmpty ? name : "\(schema).\(name)"
                }
            }
            return "OBJECT"
        default:
            return type.rawValue
        }
    }

    func fetchSync(_ id: ResultSetID, maxRows: Int) throws -> RowBatch {
        guard let rs = resultSets[id.raw] else { throw DatabaseError.unknownResultSet }
        var rows: [[OracleValue]] = []
        rows.reserveCapacity(min(maxRows, 10_000))
        var found: Int32 = 0
        var bufferRowIndex: UInt32 = 0
        let n = rs.columns.count
        while rows.count < maxRows {
            try check(dpiStmt_fetch(rs.stmt, &found, &bufferRowIndex))
            if found == 0 {
                closeSync(id)
                return RowBatch(rows: rows, hasMore: false)
            }
            var row: [OracleValue] = []
            row.reserveCapacity(n)
            for pos in 0..<n {
                var native: dpiNativeTypeNum = 0
                var data: UnsafeMutablePointer<dpiData>?
                try check(dpiStmt_getQueryValue(rs.stmt, UInt32(pos + 1), &native, &data))
                row.append(try value(native: native, oracle: rs.columns[pos].type, data: data, typeName: rs.columns[pos].typeName, lobLimit: rs.lobLimit))
            }
            rows.append(row)
        }
        return RowBatch(rows: rows, hasMore: true)
    }

    func closeSync(_ id: ResultSetID) {
        if let rs = resultSets.removeValue(forKey: id.raw) {
            dpiStmt_close(rs.stmt, nil, 0)
            dpiStmt_release(rs.stmt)
        }
    }

    // MARK: - Wartości

    private func value(native: dpiNativeTypeNum, oracle: OracleType, data: UnsafeMutablePointer<dpiData>?, typeName: String, lobLimit: Int) throws -> OracleValue {
        guard let data, data.pointee.isNull == 0 else { return .null }
        let v = data.pointee.value
        switch Int32(native) {
        case DPI_NATIVE_TYPE_BYTES:
            let b = v.asBytes
            let bytes = UnsafeRawBufferPointer(start: b.ptr, count: Int(b.length))
            switch oracle {
            case .raw, .longRaw: return .raw(Data(bytes))
            case .number: return .number(Self.normalizeNumber(String(decoding: bytes, as: UTF8.self)))
            case .json: return .json(String(decoding: bytes, as: UTF8.self))
            default: return .text(String(decoding: bytes, as: UTF8.self))
            }
        case DPI_NATIVE_TYPE_DOUBLE: return .double(v.asDouble)
        case DPI_NATIVE_TYPE_FLOAT: return .double(Double(v.asFloat))
        case DPI_NATIVE_TYPE_INT64: return .number(String(v.asInt64))
        case DPI_NATIVE_TYPE_UINT64: return .number(String(v.asUint64))
        case DPI_NATIVE_TYPE_BOOLEAN: return .boolean(v.asBoolean != 0)
        case DPI_NATIVE_TYPE_TIMESTAMP:
            let t = v.asTimestamp
            return .timestamp(OracleTimestamp(year: t.year, month: t.month, day: t.day, hour: t.hour, minute: t.minute,
                                              second: t.second, fsecond: t.fsecond, tzHourOffset: t.tzHourOffset,
                                              tzMinuteOffset: t.tzMinuteOffset), oracle)
        case DPI_NATIVE_TYPE_INTERVAL_DS:
            let i = v.asIntervalDS
            return .intervalDS(days: i.days, hours: i.hours, minutes: i.minutes, seconds: i.seconds, fseconds: i.fseconds)
        case DPI_NATIVE_TYPE_INTERVAL_YM:
            let i = v.asIntervalYM
            return .intervalYM(years: i.years, months: i.months)
        case DPI_NATIVE_TYPE_ROWID:
            var p: UnsafePointer<CChar>?
            var len: UInt32 = 0
            try check(dpiRowid_getStringValue(v.asRowid, &p, &len))
            return .rowid(String(decoding: UnsafeRawBufferPointer(start: p, count: Int(len)), as: UTF8.self))
        case DPI_NATIVE_TYPE_LOB:
            return .lob(try readLOB(v.asLOB, type: oracle, limit: lobLimit))
        case DPI_NATIVE_TYPE_JSON:
            var node: UnsafeMutablePointer<dpiJsonNode>?
            try check(dpiJson_getValue(v.asJson, UInt32(DPI_JSON_OPT_NUMBER_AS_STRING), &node))
            guard let node else { return .null }
            return .json(Self.jsonText(node.pointee))
        case DPI_NATIVE_TYPE_VECTOR:
            var vi = dpiVectorInfo()
            try check(dpiVector_getValue(v.asVector, &vi))
            return .vector(Self.vectorValues(vi))
        case DPI_NATIVE_TYPE_STMT:
            guard let child = v.asStmt else { return .null }
            dpiStmt_addRef(child)
            var n: UInt32 = 0
            try check(dpiStmt_getNumQueryColumns(child, &n))
            try check(dpiStmt_setFetchArraySize(child, currentFetchArraySize))
            let rs = register(stmt: child, columns: try describeColumns(child, count: n), lobLimit: lobLimit)
            return .cursor(rs.id)
        case DPI_NATIVE_TYPE_OBJECT:
            return .object(typeName: typeName, description: "")
        default:
            return .text("<\(typeName)>")
        }
    }

    /// ODPI zwraca NUMBER jako tekst w formacie Oracle (np. ".5", "-.25") — dopisujemy wiodące zero.
    static func normalizeNumber(_ s: String) -> String {
        if s.hasPrefix(".") { return "0" + s }
        if s.hasPrefix("-.") { return "-0" + s.dropFirst() }
        return s
    }

    private func readLOB(_ lob: OpaquePointer?, type: OracleType, limit lobLimit: Int) throws -> LOBValue {
        guard let lob else { return LOBValue(kind: .clob, length: 0, truncated: false) }
        let kind: LOBValue.Kind = switch type {
        case .nclob: .nclob
        case .blob: .blob
        case .bfile: .bfile
        default: .clob
        }
        var size: UInt64 = 0
        try check(dpiLob_getSize(lob, &size))
        let limit = UInt64(lobLimit)
        let amount = min(size, limit)
        if amount == 0 { return LOBValue(kind: kind, text: kind == .clob || kind == .nclob ? "" : nil, bytes: kind == .blob || kind == .bfile ? Data() : nil, length: size, truncated: false) }
        var bufSize: UInt64 = 0
        try check(dpiLob_getBufferSize(lob, amount, &bufSize))
        var buffer = [CChar](repeating: 0, count: Int(bufSize))
        var read = bufSize
        try buffer.withUnsafeMutableBufferPointer { p in
            try check(dpiLob_readBytes(lob, 1, amount, p.baseAddress, &read))
        }
        let bytes = buffer.withUnsafeBytes { Data($0.prefix(Int(read))) }
        if kind == .clob || kind == .nclob {
            return LOBValue(kind: kind, text: String(decoding: bytes, as: UTF8.self), length: size, truncated: size > amount)
        }
        return LOBValue(kind: kind, bytes: bytes, length: size, truncated: size > amount)
    }

    private static func vectorValues(_ vi: dpiVectorInfo) -> [Double] {
        let n = Int(vi.numDimensions)
        guard let p = vi.dimensions.asPtr else { return [] }
        switch Int32(vi.format) {
        case DPI_VECTOR_FORMAT_FLOAT32: return (0..<n).map { Double(p.assumingMemoryBound(to: Float.self)[$0]) }
        case DPI_VECTOR_FORMAT_FLOAT64: return (0..<n).map { p.assumingMemoryBound(to: Double.self)[$0] }
        case DPI_VECTOR_FORMAT_INT8: return (0..<n).map { Double(p.assumingMemoryBound(to: Int8.self)[$0]) }
        default: return (0..<(n / 8)).map { Double(p.assumingMemoryBound(to: UInt8.self)[$0]) }
        }
    }

    /// Węzeł JSON z ODPI → tekst JSON (liczby jako tekst, bez utraty precyzji).
    static func jsonText(_ node: dpiJsonNode) -> String {
        guard let v = node.value else { return "null" }
        switch Int32(node.nativeTypeNum) {
        case DPI_NATIVE_TYPE_NULL: return "null"
        case DPI_NATIVE_TYPE_BOOLEAN: return v.pointee.asBoolean != 0 ? "true" : "false"
        case DPI_NATIVE_TYPE_DOUBLE: return String(v.pointee.asDouble)
        case DPI_NATIVE_TYPE_FLOAT: return String(v.pointee.asFloat)
        case DPI_NATIVE_TYPE_INT64: return String(v.pointee.asInt64)
        case DPI_NATIVE_TYPE_BYTES:
            let b = v.pointee.asBytes
            let s = String(decoding: UnsafeRawBufferPointer(start: b.ptr, count: Int(b.length)), as: UTF8.self)
            if node.oracleTypeNum == UInt32(DPI_ORACLE_TYPE_NUMBER) { return normalizeNumber(s) }
            if node.oracleTypeNum == UInt32(DPI_ORACLE_TYPE_RAW) {
                return quote(Data(UnsafeRawBufferPointer(start: b.ptr, count: Int(b.length))).map { String(format: "%02X", $0) }.joined())
            }
            return quote(s)
        case DPI_NATIVE_TYPE_TIMESTAMP:
            let t = v.pointee.asTimestamp
            let ts = OracleTimestamp(year: t.year, month: t.month, day: t.day, hour: t.hour, minute: t.minute, second: t.second, fsecond: t.fsecond)
            return quote(ts.formatted("YYYY-MM-DD\"T\"HH24:MI:SS"))
        case DPI_NATIVE_TYPE_JSON_OBJECT:
            let o = v.pointee.asJsonObject
            var parts: [String] = []
            for i in 0..<Int(o.numFields) {
                let name = String(decoding: UnsafeRawBufferPointer(start: o.fieldNames[i], count: Int(o.fieldNameLengths[i])), as: UTF8.self)
                parts.append(quote(name) + ":" + jsonText(o.fields[i]))
            }
            return "{" + parts.joined(separator: ",") + "}"
        case DPI_NATIVE_TYPE_JSON_ARRAY:
            let a = v.pointee.asJsonArray
            return "[" + (0..<Int(a.numElements)).map { jsonText(a.elements[$0]) }.joined(separator: ",") + "]"
        default:
            return "null"
        }
    }

    private static func quote(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where ch.value < 0x20: out += String(format: "\\u%04x", ch.value)
            default: out.unicodeScalars.append(ch)
            }
        }
        return out + "\""
    }

    // MARK: - Zmienne wiązane

    private struct BoundVar {
        let bind: BindVariable
        let handle: OpaquePointer
        let data: UnsafeMutablePointer<dpiData>
        let oracleType: OracleType
        let nativeType: dpiNativeTypeNum
    }

    private func bindVariables(_ binds: [BindVariable], to stmt: OpaquePointer) throws -> [BoundVar] {
        var out: [BoundVar] = []
        do {
            for b in binds {
                let (ot, nt, size) = Self.bindTypes(b)
                var v: OpaquePointer?
                var data: UnsafeMutablePointer<dpiData>?
                try check(dpiConn_newVar(conn, ot, nt, 1, size, 1, 0, nil, &v, &data))
                guard let v, let data else { throw DatabaseError.closed }
                out.append(BoundVar(bind: b, handle: v, data: data, oracleType: b.type, nativeType: nt))
                if b.direction != .output { try setValue(b.value, type: b.type, native: nt, variable: v, data: data) }
                else { data.pointee.isNull = 1 }
                let name = b.name.hasPrefix(":") ? String(b.name.dropFirst()) : b.name
                try name.withCString { try check(dpiStmt_bindByName(stmt, $0, UInt32(name.utf8.count), v)) }
            }
        } catch {
            for v in out { dpiVar_release(v.handle) }
            throw error
        }
        return out
    }

    private static func bindTypes(_ b: BindVariable) -> (dpiOracleTypeNum, dpiNativeTypeNum, UInt32) {
        func t(_ o: Int32, _ n: Int32, _ s: UInt32 = 0) -> (dpiOracleTypeNum, dpiNativeTypeNum, UInt32) {
            (dpiOracleTypeNum(o), dpiNativeTypeNum(n), s)
        }
        switch b.type {
        case .number, .binaryInteger: return t(DPI_ORACLE_TYPE_NUMBER, DPI_NATIVE_TYPE_BYTES, 64)
        case .binaryFloat, .binaryDouble: return t(DPI_ORACLE_TYPE_NATIVE_DOUBLE, DPI_NATIVE_TYPE_DOUBLE)
        case .date: return t(DPI_ORACLE_TYPE_DATE, DPI_NATIVE_TYPE_TIMESTAMP)
        case .timestamp: return t(DPI_ORACLE_TYPE_TIMESTAMP, DPI_NATIVE_TYPE_TIMESTAMP)
        case .timestampTZ: return t(DPI_ORACLE_TYPE_TIMESTAMP_TZ, DPI_NATIVE_TYPE_TIMESTAMP)
        case .timestampLTZ: return t(DPI_ORACLE_TYPE_TIMESTAMP_LTZ, DPI_NATIVE_TYPE_TIMESTAMP)
        case .raw, .longRaw: return t(DPI_ORACLE_TYPE_RAW, DPI_NATIVE_TYPE_BYTES, b.maxSize)
        case .clob: return t(DPI_ORACLE_TYPE_CLOB, DPI_NATIVE_TYPE_LOB)
        case .nclob: return t(DPI_ORACLE_TYPE_NCLOB, DPI_NATIVE_TYPE_LOB)
        case .blob: return t(DPI_ORACLE_TYPE_BLOB, DPI_NATIVE_TYPE_LOB)
        case .boolean: return t(DPI_ORACLE_TYPE_BOOLEAN, DPI_NATIVE_TYPE_BOOLEAN)
        case .refCursor: return t(DPI_ORACLE_TYPE_STMT, DPI_NATIVE_TYPE_STMT)
        case .nvarchar2, .nchar: return t(DPI_ORACLE_TYPE_NVARCHAR, DPI_NATIVE_TYPE_BYTES, b.maxSize)
        case .char: return t(DPI_ORACLE_TYPE_CHAR, DPI_NATIVE_TYPE_BYTES, b.maxSize)
        case .rowid, .urowid: return t(DPI_ORACLE_TYPE_VARCHAR, DPI_NATIVE_TYPE_BYTES, 4000)
        default: return t(DPI_ORACLE_TYPE_VARCHAR, DPI_NATIVE_TYPE_BYTES, b.maxSize)
        }
    }

    private func setValue(_ value: OracleValue, type: OracleType, native: dpiNativeTypeNum, variable: OpaquePointer,
                          data: UnsafeMutablePointer<dpiData>) throws {
        if value.isNull { data.pointee.isNull = 1; return }
        data.pointee.isNull = 0
        switch Int32(native) {
        case DPI_NATIVE_TYPE_BYTES:
            let bytes: Data = switch value {
            case .raw(let d): d
            default: Data((value.displayText ?? "").utf8)
            }
            try bytes.withUnsafeBytes { p in
                try check(dpiVar_setFromBytes(variable, 0, p.baseAddress?.assumingMemoryBound(to: CChar.self), UInt32(p.count)))
            }
        case DPI_NATIVE_TYPE_DOUBLE:
            switch value {
            case .double(let d): data.pointee.value.asDouble = d
            default: data.pointee.value.asDouble = Double(value.displayText ?? "") ?? 0
            }
        case DPI_NATIVE_TYPE_BOOLEAN:
            switch value {
            case .boolean(let b): data.pointee.value.asBoolean = b ? 1 : 0
            default: data.pointee.value.asBoolean = ["TRUE", "1", "Y", "YES"].contains((value.displayText ?? "").uppercased()) ? 1 : 0
            }
        case DPI_NATIVE_TYPE_TIMESTAMP:
            guard case .timestamp(let t, _) = value else {
                throw DatabaseError.unsupported("Wartość daty musi być typu timestamp")
            }
            data.pointee.value.asTimestamp = dpiTimestamp(year: t.year, month: t.month, day: t.day, hour: t.hour, minute: t.minute,
                                                          second: t.second, fsecond: t.fsecond, tzHourOffset: t.tzHourOffset,
                                                          tzMinuteOffset: t.tzMinuteOffset)
        case DPI_NATIVE_TYPE_LOB:
            // LOB IN: tymczasowy LOB wypełniony tekstem/bajtami.
            let bytes: Data = switch value {
            case .raw(let d): d
            case .lob(let l): l.bytes ?? Data((l.text ?? "").utf8)
            default: Data((value.displayText ?? "").utf8)
            }
            try bytes.withUnsafeBytes { p in
                try check(dpiVar_setFromBytes(variable, 0, p.baseAddress?.assumingMemoryBound(to: CChar.self), UInt32(p.count)))
            }
        default:
            throw DatabaseError.unsupported("Nieobsługiwany typ zmiennej wiązanej: \(type.rawValue)")
        }
    }
}
