import Foundation
import PelikanDB

/// Rozwiązywanie aliasów przez katalog LDAP przed przekazaniem ich klientowi Oracle (PD-CONN-013, D158).
///
/// `libclntsh.dylib` z Instant Client dla macOS jest konsolidowany z płaską przestrzenią nazw. W procesie z AppKit
/// systemowy LDAP.framework jest już załadowany, więc część wywołań `ldap_*` adaptera LDAP klienta Oracle trafia
/// do biblioteki systemowej, a część do własnej — wiązanie idzie jako LDAPv2 (OpenLDAP 2.5+ je odrzuca), a po
/// udanym wiązaniu proces kończy się asercją `LDAP_VALID(ld)` w `ldap_first_entry`. Dlatego na macOS Pelikan sam
/// pyta katalog (LDAPv3, wiązanie anonimowe, wyłącznie przez LDAP.framework) i przekazuje klientowi gotowy
/// deskryptor — adapter LDAP klienta nie jest wtedy w ogóle używany.
enum DirectoryLookup {
    /// Alias → deskryptor wg kolejności NAMES.DIRECTORY_PATH; nil — zostawiamy klientowi (brak konfiguracji LDAP).
    static func resolve(_ alias: String, directories: [String]) throws -> String? {
#if os(macOS)
        guard DirectoryNaming.isBareAlias(alias), let config = DirectoryNaming.config(directories: directories) else { return nil }
        for method in config.path {
            switch method {
            case "tnsnames":
                if let e = TNSNames.load(directories: [config.directory])
                    .first(where: { $0.aliases.contains { $0.caseInsensitiveCompare(alias) == .orderedSame } }) {
                    return e.descriptor
                }
            case "ldap":
                if let d = try search(alias, config: config) { return d }
            default:
                continue
            }
        }
        throw OracleError(code: 12154, message: "ORA-12154: Nie znaleziono aliasu \(alias) w tnsnames.ora ani w katalogu LDAP (\(config.directory)/ldap.ora)")
#else
        return nil
#endif
    }

    /// Kerberos w Instant Client dla macOS (PD-CONN-014, D159): adapter KERBEROS5 `libclntsh` (płaska przestrzeń
    /// nazw) miesza swoje funkcje `krb5_*` z systemowym Kerberos.framework, który każdy proces z AppKit ma załadowany —
    /// proces kończy się SIGABRT (ORA-24550) przy pierwszym połączeniu, także hasłem, gdy sqlnet.ora włącza KERBEROS5.
    /// Zamiast awarii aplikacji — czytelny błąd. Bez Kerberos.framework w procesie (np. narzędzia CLI) nic nie blokuje.
    static func checkKerberos(directories: [String]) throws {
#if os(macOS)
        guard let services = DirectoryNaming.sqlnetParameter("SQLNET.AUTHENTICATION_SERVICES", directories: directories),
              services.uppercased().contains("KERBEROS5"),
              let handle = dlopen("/System/Library/Frameworks/Kerberos.framework/Kerberos", RTLD_LAZY | RTLD_NOLOAD) else { return }
        dlclose(handle)
        throw DatabaseError.unsupported("""
            Uwierzytelnianie Kerberos (SQLNET.AUTHENTICATION_SERVICES=\(services) w sqlnet.ora) nie działa w Instant Client \
            dla macOS w procesie aplikacji: biblioteka klienta Oracle koliduje z systemowym Kerberos.framework i proces \
            zostałby przerwany. Usuń KERBEROS5 z sqlnet.ora, aby łączyć się hasłem lub portfelem.
            """)
#endif
    }

#if os(macOS)
    private typealias Initialize = @convention(c) (UnsafeMutablePointer<OpaquePointer?>, UnsafePointer<CChar>) -> Int32
    private typealias SetOption = @convention(c) (OpaquePointer?, Int32, UnsafeRawPointer?) -> Int32
    private typealias SimpleBind = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
    private typealias SearchExt = @convention(c) (OpaquePointer?, UnsafePointer<CChar>, Int32, UnsafePointer<CChar>,
                                                  UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?, Int32,
                                                  UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutablePointer<timeval>?,
                                                  Int32, UnsafeMutablePointer<OpaquePointer?>) -> Int32
    private typealias FirstEntry = @convention(c) (OpaquePointer?, OpaquePointer?) -> OpaquePointer?
    private typealias GetValuesLen = @convention(c) (OpaquePointer?, OpaquePointer?, UnsafePointer<CChar>) -> UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    private typealias ValueFreeLen = @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Void
    private typealias MsgFree = @convention(c) (OpaquePointer?) -> Int32
    private typealias Unbind = @convention(c) (OpaquePointer?) -> Int32
    private typealias Err2String = @convention(c) (Int32) -> UnsafePointer<CChar>?

    private static let LDAP_OPT_DEREF: Int32 = 0x02
    private static let LDAP_OPT_TIMELIMIT: Int32 = 0x04
    private static let LDAP_OPT_PROTOCOL_VERSION: Int32 = 0x11
    private static let LDAP_OPT_NETWORK_TIMEOUT: Int32 = 0x5005
    private static let LDAP_SCOPE_BASE: Int32 = 0
    private static let LDAP_NO_SUCH_OBJECT: Int32 = 0x20

    /// Wpis usługi z katalogu: atrybut `orclNetDescString` (aliasy katalogowe dereferencjonowane przez serwer).
    static func search(_ alias: String, config: DirectoryNaming.Config) throws -> String? {
        guard let dn = DirectoryNaming.distinguishedName(alias: alias, context: config.adminContext) else { return nil }
        guard let lib = dlopen("/System/Library/Frameworks/LDAP.framework/LDAP", RTLD_LAZY) else {
            throw DatabaseError.unsupported("Nazewnictwo LDAP: brak systemowej biblioteki LDAP")
        }
        defer { dlclose(lib) }
        func fn<T>(_ name: String, _: T.Type) throws -> T {
            guard let p = dlsym(lib, name) else { throw DatabaseError.unsupported("Nazewnictwo LDAP: brak funkcji \(name)") }
            return unsafeBitCast(p, to: T.self)
        }
        let initialize = try fn("ldap_initialize", Initialize.self)
        let setOption = try fn("ldap_set_option", SetOption.self)
        let bind = try fn("ldap_simple_bind_s", SimpleBind.self)
        let searchExt = try fn("ldap_search_ext_s", SearchExt.self)
        let firstEntry = try fn("ldap_first_entry", FirstEntry.self)
        let getValues = try fn("ldap_get_values_len", GetValuesLen.self)
        let valueFree = try fn("ldap_value_free_len", ValueFreeLen.self)
        let msgFree = try fn("ldap_msgfree", MsgFree.self)
        let unbind = try fn("ldap_unbind", Unbind.self)
        let err2string = try fn("ldap_err2string", Err2String.self)
        func message(_ rc: Int32) -> String { err2string(rc).map { String(cString: $0) } ?? "LDAP \(rc)" }

        var lastError: String?
        for server in config.servers {
            var ld: OpaquePointer?
            guard initialize(&ld, "ldap://\(server.host):\(server.port)") == 0, let ld else { continue }
            defer { _ = unbind(ld) }
            var version: Int32 = 3, deref: Int32 = 3 /* LDAP_DEREF_ALWAYS */, limit: Int32 = 10
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            _ = setOption(ld, LDAP_OPT_PROTOCOL_VERSION, &version)
            _ = setOption(ld, LDAP_OPT_DEREF, &deref)
            _ = setOption(ld, LDAP_OPT_TIMELIMIT, &limit)
            _ = setOption(ld, LDAP_OPT_NETWORK_TIMEOUT, &timeout)
            let rcBind = bind(ld, nil, nil)
            guard rcBind == 0 else { lastError = message(rcBind); continue }
            var result: OpaquePointer?
            let attribute = strdup("orclNetDescString")
            defer { free(attribute) }
            var attrs: [UnsafeMutablePointer<CChar>?] = [attribute, nil]
            var searchTimeout = timeval(tv_sec: 10, tv_usec: 0)
            let rc = attrs.withUnsafeMutableBufferPointer { a in
                searchExt(ld, dn, LDAP_SCOPE_BASE, "(objectClass=*)", a.baseAddress, 0, nil, nil, &searchTimeout, 1, &result)
            }
            defer { if result != nil { _ = msgFree(result) } }
            if rc == LDAP_NO_SUCH_OBJECT { return nil }
            guard rc == 0 else { lastError = message(rc); continue }
            guard let entry = firstEntry(ld, result), let values = getValues(ld, entry, "orclNetDescString") else { return nil }
            defer { valueFree(values) }
            // struct berval { ber_len_t bv_len; char *bv_val; }
            guard let first = values.pointee,
                  let bytes = first.load(fromByteOffset: MemoryLayout<UInt>.stride, as: UnsafeRawPointer?.self) else { return nil }
            let data = Data(bytes: bytes, count: Int(first.load(as: UInt.self)))
            return TNSNames.compact(String(decoding: data, as: UTF8.self))
        }
        throw OracleError(code: 12154, message: "ORA-12154: Katalog LDAP niedostępny (\(config.servers.map { "\($0.host):\($0.port)" }.joined(separator: ", "))): \(lastError ?? "brak połączenia")")
    }
#endif
}
