import CODPI
import Foundation
import PelikanDB
import Synchronization

/// Wykrywanie Oracle Instant Client. Pelikan go nie dołącza (licencja dystrybucji Oracle, docs/adr/0001):
/// użytkownik instaluje go sam, a aplikacja szuka w typowych miejscach albo w ścieżce z ustawień.
public enum InstantClientLocator {
#if os(macOS)
    static let libraryName = "libclntsh.dylib"
#else
    static let libraryName = "libclntsh.so"
#endif

    /// Kandydaci w kolejności: ścieżka z ustawień, PELIKAN_OCI_LIB_DIR, ~/Downloads/instantclient_* (instalator
    /// Oracle dla macOS), /opt/oracle/instantclient*, Homebrew, /usr/local/lib, katalogi Linuksa.
    public static func candidates(configured: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment,
                                  home: String = NSHomeDirectory()) -> [String] {
        stages(configured: configured, environment: environment, home: home).flatMap { $0() }
    }

    /// Etapy wyszukiwania liczone leniwie: odczyt ~/Downloads wywołuje pytanie systemu o dostęp (TCC), więc nie
    /// sięgamy tam, gdy biblioteka jest już w katalogu z ustawień albo ze zmiennej środowiskowej.
    static func stages(configured: String?, environment: [String: String], home: String) -> [() -> [String]] {
        let fm = FileManager.default
        func glob(_ parent: String, prefix: String) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: parent)) ?? [])
                .filter { $0.hasPrefix(prefix) }
                .sorted { $0.compare($1, options: .numeric) == .orderedDescending }   // najnowsza wersja pierwsza
                .map { parent + "/" + $0 }
        }
        var stages: [() -> [String]] = [
            { configured.map { $0.isEmpty ? [] : [($0 as NSString).expandingTildeInPath] } ?? [] },
            { environment["PELIKAN_OCI_LIB_DIR"].map { $0.isEmpty ? [] : [$0] } ?? [] },
            { ["/opt/homebrew/lib", "/usr/local/lib", "/usr/local/oracle/instantclient"] + glob("/opt/oracle", prefix: "instantclient") },
            { glob(home + "/Downloads", prefix: "instantclient_") + glob(home + "/Applications", prefix: "instantclient_") },
        ]
#if os(Linux)
        stages.append { glob("/usr/lib/oracle", prefix: "").map { $0 + "/client64/lib" } }
#endif
        stages.append { environment["LD_LIBRARY_PATH"].map { $0.split(separator: ":").map(String.init) } ?? [] }
        return stages
    }

    /// Pierwszy katalog zawierający bibliotekę klienta.
    public static func locate(configured: String? = nil, environment: [String: String] = ProcessInfo.processInfo.environment,
                              home: String = NSHomeDirectory()) -> String? {
        for stage in stages(configured: configured, environment: environment, home: home) {
            if let dir = stage().first(where: { FileManager.default.fileExists(atPath: $0 + "/" + libraryName) }) { return dir }
        }
        return nil
    }
}

/// Globalny kontekst ODPI-C. Jedna biblioteka klienta na proces (ograniczenie OCI), więc kontekst tworzony raz.
final class ODPIEnvironment: @unchecked Sendable {
    let context: OpaquePointer
    let libraryDirectory: String?
    let clientVersion: String

    private static let shared = Mutex<ODPIEnvironment?>(nil)

    private init(context: OpaquePointer, libraryDirectory: String?, clientVersion: String) {
        self.context = context; self.libraryDirectory = libraryDirectory; self.clientVersion = clientVersion
    }

    /// Kontekst dla podanego katalogu Instant Client (pierwsze wywołanie decyduje — kolejne go ignorują).
    static func get(libraryDirectory configured: String?) throws -> ODPIEnvironment {
        try shared.withLock { env in
            if let env { return env }
            let dir = InstantClientLocator.locate(configured: configured)
            var params = dpiContextCreateParams()
            var errorInfo = dpiErrorInfo()
            var ctx: OpaquePointer?
            let status: Int32 = "Pelikan".withCString { driverName in
                "UTF-8".withCString { enc in
                    withOptionalCString(dir) { libDir in
                        params.defaultDriverName = driverName
                        params.defaultEncoding = enc
                        params.oracleClientLibDir = libDir
                        return dpiContext_createWithParams(UInt32(DPI_MAJOR_VERSION), UInt32(DPI_MINOR_VERSION),
                                                           &params, &ctx, &errorInfo)
                    }
                }
            }
            guard status == DPI_SUCCESS, let ctx else {
                let e = ODPIEnvironment.error(from: errorInfo)
                throw DatabaseError.driverUnavailable(
                    "Nie udało się załadować Oracle Instant Client" + (dir.map { " (\($0))" } ?? "") + ": \(e.message)")
            }
            var v = dpiVersionInfo()
            dpiContext_getClientVersion(ctx, &v)
            let created = ODPIEnvironment(context: ctx, libraryDirectory: dir,
                                          clientVersion: "\(v.versionNum).\(v.releaseNum).\(v.updateNum).\(v.portReleaseNum).\(v.portUpdateNum)")
            env = created
            return created
        }
    }

    func lastError() -> OracleError {
        var info = dpiErrorInfo()
        dpiContext_getError(context, &info)
        return ODPIEnvironment.error(from: info)
    }

    static func error(from info: dpiErrorInfo) -> OracleError {
        let message = info.message.map { String(decoding: UnsafeRawBufferPointer(start: $0, count: Int(info.messageLength)), as: UTF8.self) } ?? "Nieznany błąd sterownika"
        var driverCode: String?
        if info.code == 0, let r = message.range(of: #"^DPI-\d{4}"#, options: .regularExpression) {
            driverCode = String(message[r])
        }
        return OracleError(code: info.code, message: message, offset: info.offset, isRecoverable: info.isRecoverable != 0,
                           isWarning: info.isWarning != 0, sqlState: info.sqlState.map { String(cString: $0) } ?? "",
                           driverCode: driverCode)
    }
}

func withOptionalCString<R>(_ s: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
    if let s { return s.withCString { body($0) } }
    return body(nil)
}
