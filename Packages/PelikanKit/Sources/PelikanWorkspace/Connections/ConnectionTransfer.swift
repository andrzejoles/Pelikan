import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
#if canImport(CommonCrypto)
import CommonCrypto
#endif

/// Hasła połączenia w pliku eksportu (D186): hasło bazy i hasło tunelu SSH.
public struct ConnectionSecrets: Codable, Sendable, Equatable {
    public var password: String?
    public var sshPassword: String?

    public init(password: String? = nil, sshPassword: String? = nil) {
        self.password = password
        self.sshPassword = sshPassword
    }

    var isEmpty: Bool { password == nil && sshPassword == nil }
}

/// Eksport i import połączeń z hasłami (PD-CONN-010, D186). Plik ma układ zwykłego eksportu definicji (starszy import
/// wczyta same definicje) i sekcję `secrets`: hasła jawnym tekstem albo zaszyfrowane frazą — AES-256-GCM z kluczem
/// z PBKDF2-HMAC-SHA256 (losowa sól, 600 000 iteracji). Fraza nie trafia do pliku, dziennika ani argumentów komendy.
public enum ConnectionTransfer {
    public enum Mode: String, Codable, Sendable { case plain, encrypted }

    /// Sekcja haseł pliku: klucze — identyfikatory definicji z tego pliku.
    public struct Envelope: Codable, Sendable, Equatable {
        public var mode: Mode
        public var plain: [String: ConnectionSecrets]?
        public var encrypted: Sealed?
    }

    public struct Sealed: Codable, Sendable, Equatable {
        public var kdf = "PBKDF2-HMAC-SHA256"
        public var iterations: Int
        public var salt: Data
        /// AES-GCM: nonce, szyfrogram i znacznik (`SealedBox.combined`).
        public var box: Data
        /// Definicje pliku (foldery i połączenia) uwierzytelnione razem z hasłami (dane dodatkowe AES-GCM): zmiana hosta albo
        /// tunelu po eksporcie odrzuca import. nil — plik sprzed tej ochrony.
        public var authenticatesDefinitions: Bool?
    }

    public enum TransferError: LocalizedError, Equatable {
        case wrongPassphrase, unsupported(String), weakPassphrase
        public var errorDescription: String? {
            switch self {
            case .wrongPassphrase: L10n.tr("Nieprawidłowa fraza albo uszkodzony plik — hasła nie zostały odszyfrowane")
            case .unsupported(let what): L10n.tr("Nieobsługiwany format haseł w pliku: \(what)")
            case .weakPassphrase: L10n.tr("Fraza musi mieć co najmniej \(minimumPassphraseLength) znaków")
            }
        }
    }

    public static let iterations = 600_000
    /// Górna granica iteracji z pliku: spreparowany plik nie zatrzyma importu na minuty.
    public static let maximumIterations = 2_000_000
    public static let minimumPassphraseLength = 8

    /// Sekcja haseł w trybie jawnym albo zaszyfrowanym. `definitions` — plik eksportu bez sekcji haseł: jego foldery
    /// i połączenia są uwierzytelniane razem z hasłami (tylko tryb zaszyfrowany).
    public static func envelope(_ secrets: [UUID: ConnectionSecrets], mode: Mode, passphrase: String?,
                                iterations: Int = iterations, definitions: Data? = nil) throws -> Envelope {
        let byID = Dictionary(uniqueKeysWithValues: secrets.filter { !$0.value.isEmpty }.map { ($0.key.uuidString, $0.value) })
        switch mode {
        case .plain:
            return Envelope(mode: .plain, plain: byID)
        case .encrypted:
            guard let passphrase, passphrase.count >= minimumPassphraseLength else { throw TransferError.weakPassphrase }
            let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
            let key = SymmetricKey(data: try pbkdf2(passphrase, salt: salt, iterations: iterations))
            let plain = try JSONEncoder().encode(byID)
            let sealed = try definitions.map { try AES.GCM.seal(plain, using: key, authenticating: try definitionsDigest($0)) } ?? AES.GCM.seal(plain, using: key)
            guard let box = sealed.combined else { throw TransferError.unsupported("AES-GCM") }
            return Envelope(mode: .encrypted, encrypted: Sealed(iterations: iterations, salt: salt, box: box,
                                                                authenticatesDefinitions: definitions != nil ? true : nil))
        }
    }

    /// Hasła z sekcji pliku (zaszyfrowane — po podaniu frazy). `definitions` — cały plik importu (definicje
    /// uwierzytelnione przy eksporcie muszą się zgadzać). Pusta fraza, zła fraza i zmieniony plik — `wrongPassphrase`.
    public static func open(_ envelope: Envelope, passphrase: String?, definitions: Data? = nil) throws -> [String: ConnectionSecrets] {
        switch envelope.mode {
        case .plain:
            return envelope.plain ?? [:]
        case .encrypted:
            guard let sealed = envelope.encrypted else { throw TransferError.unsupported("encrypted") }
            guard sealed.kdf == "PBKDF2-HMAC-SHA256", (1...maximumIterations).contains(sealed.iterations) else { throw TransferError.unsupported(sealed.kdf) }
            guard sealed.salt.count >= 16 else { throw TransferError.unsupported("salt") }
            guard let passphrase, !passphrase.isEmpty else { throw TransferError.wrongPassphrase }
            var aad: Data?
            if sealed.authenticatesDefinitions == true {
                guard let definitions else { throw TransferError.unsupported("definitions") }
                aad = try definitionsDigest(definitions)
            }
            let key = SymmetricKey(data: try pbkdf2(passphrase, salt: sealed.salt, iterations: sealed.iterations))
            do {
                let box = try AES.GCM.SealedBox(combined: sealed.box)
                let plain = try aad.map { try AES.GCM.open(box, using: key, authenticating: $0) } ?? AES.GCM.open(box, using: key)
                return try JSONDecoder().decode([String: ConnectionSecrets].self, from: plain)
            } catch {
                throw TransferError.wrongPassphrase
            }
        }
    }

    /// Sekcja haseł pliku eksportu (nil — plik bez haseł).
    public static func envelope(in data: Data) throws -> Envelope? {
        struct File: Decodable { var secrets: Envelope? }
        return try JSONDecoder.pelikan.decode(File.self, from: data).secrets
    }

    /// Skrót SHA-256 folderów i połączeń pliku eksportu w postaci kanonicznej (JSON z posortowanymi kluczami, bez sekcji
    /// haseł) — dane dodatkowe AES-GCM. Ogólny JSON, nie model: plik z nowszej wersji z dodatkowymi polami daje ten sam skrót.
    static func definitionsDigest(_ file: Data) throws -> Data {
        guard let root = try JSONSerialization.jsonObject(with: file) as? [String: Any] else { throw TransferError.unsupported("JSON") }
        let canonical = try JSONSerialization.data(withJSONObject: ["folders": root["folders"] ?? [Any](), "connections": root["connections"] ?? [Any]()],
                                                   options: [.sortedKeys])
        return Data(SHA256.hash(data: canonical))
    }

    /// PBKDF2-HMAC-SHA256 (RFC 8018), klucz 32 bajty: CommonCrypto na macOS, HMAC z Crypto na Linuksie. Błąd CommonCrypto
    /// (np. pusta fraza albo sól) — `wrongPassphrase`, nie zatrzymanie aplikacji.
    static func pbkdf2(_ passphrase: String, salt: Data, iterations: Int) throws -> Data {
        #if canImport(CommonCrypto)
        var key = [UInt8](repeating: 0, count: 32)
        let pass = Array(passphrase.utf8)
        let status = pass.withUnsafeBufferPointer { p in
            salt.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self) },
                                     p.count, s.bindMemory(to: UInt8.self).baseAddress, s.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &key, key.count)
            }
        }
        guard status == kCCSuccess else { throw TransferError.wrongPassphrase }
        return Data(key)
        #else
        return pbkdf2HMAC(passphrase, salt: salt, iterations: iterations)
        #endif
    }

    /// PBKDF2-HMAC-SHA256 w Swifcie — jeden blok (32 bajty klucza AES-256).
    static func pbkdf2HMAC(_ passphrase: String, salt: Data, iterations: Int) -> Data {
        let key = SymmetricKey(data: Data(passphrase.utf8))
        var u = Data(HMAC<SHA256>.authenticationCode(for: salt + Data([0, 0, 0, 1]), using: key))
        var t = [UInt8](u)
        if iterations > 1 {
            for _ in 2...iterations {
                u = Data(HMAC<SHA256>.authenticationCode(for: u, using: key))
                for (i, b) in u.enumerated() { t[i] ^= b }
            }
        }
        return Data(t)
    }
}

extension ConnectionStore {
    /// Hasła do eksportu: hasło bazy (Pęk kluczy albo podane w tej sesji) i hasło tunelu SSH, dla definicji, które je mają.
    /// `password` — hasło bazy znane menedżerowi sesji (podane przy logowaniu, zmienione w sesji); domyślnie z magazynu.
    public func secretsForExport(password known: ((UUID) -> String?)? = nil) -> [UUID: ConnectionSecrets] {
        var out: [UUID: ConnectionSecrets] = [:]
        for c in connections {
            let s = ConnectionSecrets(password: known?(c.id) ?? password(for: c.id), sshPassword: c.sshTunnel?.usesPassword == true ? sshPassword(for: c.id) : nil)
            if !s.isEmpty { out[c.id] = s }
        }
        return out
    }
}
