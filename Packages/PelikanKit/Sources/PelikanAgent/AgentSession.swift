#if canImport(Darwin)
import Foundation
import PelikanWorkspace
import Security
import Synchronization

/// Sesja agenta: token, proces CLI, uprawnienia. Token żyje tylko w pamięci.
public final class AgentSession: Sendable, Identifiable {
    public let id: String
    public let profile: AgentProfile
    /// Katalog roboczy CLI (folder projektu albo katalog tymczasowy sesji).
    public let directory: String
    public let created = Date()
    /// Nadpisania poziomów dla tej sesji (komenda → poziom) z macierzy uprawnień przy starcie; nie podnoszą poziomu
    /// ponad poziom komendy.
    public let accessOverrides: [CommandID: AgentAccess]
    let tokenBytes: [UInt8]
    private let pid = Mutex<pid_t?>(nil)
    private let closedFlag = Atomic<Bool>(false)

    init(profile: AgentProfile, directory: String, accessOverrides: [CommandID: AgentAccess], tokenBytes: [UInt8]) {
        id = String(UUID().uuidString.prefix(8)).lowercased()
        self.profile = profile
        self.directory = directory
        self.accessOverrides = accessOverrides
        self.tokenBytes = tokenBytes
    }

    public var invoker: Invoker { .agent(sessionID: id, agentName: profile.id) }

    /// PID procesu CLI (ustawiany po uruchomieniu w terminalu).
    public var cliPID: pid_t? {
        get { pid.withLock { $0 } }
        set { pid.withLock { $0 = newValue } }
    }

    public var isClosed: Bool { closedFlag.load(ordering: .acquiring) }
    func markClosed() { closedFlag.store(true, ordering: .releasing) }
}

/// Rejestr aktywnych sesji. Używany z wątku gniazda (uwierzytelnianie) i z głównego aktora.
public final class SessionRegistry: Sendable {
    private let sessions = Mutex<[String: AgentSession]>([:])

    public init() {}

    /// Tworzy sesję z nowym, losowym 256-bitowym tokenem. Token (base64url) zwracany jest tylko tutaj — trafia
    /// wyłącznie do środowiska procesu CLI.
    public func create(profile: AgentProfile, directory: String, accessOverrides: [CommandID: AgentAccess] = [:]) -> (AgentSession, String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes")
        let session = AgentSession(profile: profile, directory: directory, accessOverrides: accessOverrides, tokenBytes: bytes)
        sessions.withLock { $0[session.id] = session }
        return (session, Self.base64url(bytes))
    }

    public func session(_ id: String) -> AgentSession? {
        sessions.withLock { $0[id] }.flatMap { $0.isClosed ? nil : $0 }
    }

    public var all: [AgentSession] { sessions.withLock { Array($0.values) }.filter { !$0.isClosed } }

    /// Unieważnia token sesji.
    public func close(_ id: String) {
        sessions.withLock { s in
            s[id]?.markClosed()
            s[id] = nil
        }
    }

    /// Szuka sesji po tokenie. Porównanie w stałym czasie (bez wczesnego wyjścia) dla wszystkich aktywnych sesji.
    public func authenticate(token: String) -> AgentSession? {
        guard let provided = Self.decodeBase64url(token), provided.count == 32 else { return nil }
        let candidates = sessions.withLock { Array($0.values) }
        var match: AgentSession?
        for s in candidates {
            if Self.constantTimeEqual(s.tokenBytes, provided), !s.isClosed { match = s }
        }
        return match
    }

    static func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }

    static func base64url(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decodeBase64url(_ s: String) -> [UInt8]? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b).map { [UInt8]($0) }
    }
}
#endif
