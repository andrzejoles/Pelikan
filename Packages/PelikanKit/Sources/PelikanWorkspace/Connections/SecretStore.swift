import Foundation
import Synchronization
#if canImport(Security)
import Security
#endif

/// Przechowywanie haseł (PROMPT §4.2 p.6: hasła tylko w Pęku kluczy). Testy używają `MemorySecretStore`.
public protocol SecretStore: Sendable {
    func password(for account: String) throws -> String?
    func setPassword(_ password: String, for account: String) throws
    func deletePassword(for account: String) throws
    /// Czy hasło jest zapisane — bez odczytu jego treści (stan połączenia na liście).
    func hasPassword(for account: String) throws -> Bool
}

extension SecretStore {
    public func hasPassword(for account: String) throws -> Bool { try password(for: account) != nil }
}

public enum SecretStoreError: Error, Equatable, Sendable {
    case keychain(Int32)
}

/// Hasła w pamięci (testy, praca bez zapisu hasła).
public final class MemorySecretStore: SecretStore {
    private let storage = Mutex<[String: String]>([:])
    public init() {}
    public func password(for account: String) throws -> String? { storage.withLock { $0[account] } }
    public func setPassword(_ password: String, for account: String) throws { storage.withLock { $0[account] = password } }
    public func deletePassword(for account: String) throws { _ = storage.withLock { $0.removeValue(forKey: account) } }
}

#if canImport(Security)
/// Pęk kluczy macOS (pęk logowania): hasła jako kSecClassGenericPassword (usługa = `<bundle id>.connection`, konto = id
/// połączenia), dostępne, gdy Mac jest odblokowany, bez synchronizacji z iCloud. Potwierdzenie Touch ID / hasłem Maca
/// przed użyciem zapisanego hasła robi menedżer sesji (D56) — atrybut kontroli dostępu wymagałby pęku chronionego
/// danymi, dostępnego tylko dla aplikacji podpisanych certyfikatem dewelopera.
public final class KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func hasPassword(for account: String) throws -> Bool {
        var q = baseQuery(account)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
        return true
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func password(for account: String) throws -> String? {
        var q = baseQuery(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw SecretStoreError.keychain(status) }
        return String(data: data, encoding: .utf8)
    }

    public func setPassword(_ password: String, for account: String) throws {
        try deletePassword(for: account)
        var q = baseQuery(account)
        q[kSecValueData as String] = Data(password.utf8)
        q[kSecAttrLabel as String] = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? service
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
    }

    public func deletePassword(for account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError.keychain(status) }
    }
}
#endif
