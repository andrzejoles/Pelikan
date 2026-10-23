import Foundation
import PelikanDB

/// Sterownik Instant Client dla modelu aplikacji (DatabaseDriver).
public struct ODPIDriver: DatabaseDriver {
    public let kind = DriverKind.instantClient
    /// Katalog Instant Client z ustawień (nil = wykrywanie).
    public var libraryDirectory: String?
    /// Katalog Oracle Net zarządzany przez Pelikana (TNS_ADMIN klienta: portfel magazynu haseł, IFILE użytkownika).
    public var configDirectory: String?

    public init(libraryDirectory: String? = nil, configDirectory: String? = nil) {
        self.libraryDirectory = libraryDirectory
        self.configDirectory = configDirectory
    }

    public var capabilities: DriverCapabilities { ODPISession.capabilities }

    public func availability() -> Result<Void, DatabaseError> {
        if InstantClientLocator.locate(configured: libraryDirectory) != nil { return .success(()) }
        return .failure(.clientMissing(
            "Nie znaleziono Oracle Instant Client. Pobierz „Basic” dla macOS (ARM64) ze strony "
                + "https://www.oracle.com/database/technologies/instant-client/macos-arm64-downloads.html, "
                + "zainstaluj (domyślnie ~/Downloads/instantclient_23_26) albo wskaż katalog w Ustawieniach."))
    }

    public func connect(target: ConnectionTarget, credentials: Credentials, options: ConnectOptions) async throws -> any DatabaseSession {
        try await ODPISession.connect(target: target, credentials: credentials, options: options, libraryDirectory: libraryDirectory, configDirectory: configDirectory)
    }
}
