import Foundation
import PelikanDB
import PelikanSQL

/// Pozycja listy wyboru pola ustawień (D211): wartość wpisywana do pola i opcjonalny opis obok niej.
public struct PreferenceChoice: Sendable, Hashable {
    public var value: String
    public var note: String?
    public init(_ value: String, _ note: String? = nil) { self.value = value; self.note = note }
    /// Tekst pozycji menu.
    public var label: String { note.map { "\(value) — \($0)" } ?? value }
}

/// Listy wyboru pól ustawień (D211): w każdym polu, w którym wartość dotąd wpisywało się ręcznie, można wybrać ją z listy
/// albo wpisać własną. Pola z listą wartości po przecinku dopisują albo usuwają wybraną pozycję.
public enum PreferenceChoices {
    private static func list(_ values: [String]) -> [PreferenceChoice] { values.map { PreferenceChoice($0) } }

    /// Formaty DATE i NLS_DATE_FORMAT.
    public static let dateFormats: [PreferenceChoice] = [
        PreferenceChoice("YYYY-MM-DD HH24:MI:SS", "ISO 8601"), PreferenceChoice("YYYY-MM-DD"),
        PreferenceChoice("DD.MM.YYYY HH24:MI:SS", L10n.tr("polski")), PreferenceChoice("DD.MM.YYYY"),
        PreferenceChoice("DD-MON-RR", L10n.tr("domyślny Oracle")), PreferenceChoice("DD-MON-YYYY HH24:MI:SS"),
        PreferenceChoice("DD/MM/YYYY HH24:MI:SS"), PreferenceChoice("MM/DD/YYYY HH:MI:SS AM"),
    ]
    /// Formaty TIMESTAMP i NLS_TIMESTAMP_FORMAT.
    public static let timestampFormats: [PreferenceChoice] = [
        PreferenceChoice("YYYY-MM-DD HH24:MI:SS.FF6", "ISO 8601"), PreferenceChoice("YYYY-MM-DD HH24:MI:SS.FF3"),
        PreferenceChoice("YYYY-MM-DD HH24:MI:SS.FF9"), PreferenceChoice("DD.MM.YYYY HH24:MI:SS.FF6", L10n.tr("polski")),
        PreferenceChoice("DD.MM.YYYY HH24:MI:SS.FF3"), PreferenceChoice("DD-MON-RR HH.MI.SSXFF AM", L10n.tr("domyślny Oracle")),
    ]

    /// Wartości parametrów NLS sesji.
    public static func sessionNLS(_ name: String) -> [PreferenceChoice] {
        switch name {
        case "NLS_DATE_FORMAT": dateFormats
        case "NLS_TIMESTAMP_FORMAT": timestampFormats
        case "NLS_NUMERIC_CHARACTERS": [PreferenceChoice(",.", L10n.tr("przecinek dziesiętny, kropka tysięcy")),
                                        PreferenceChoice(", ", L10n.tr("przecinek dziesiętny, spacja tysięcy")),
                                        PreferenceChoice(".,", L10n.tr("kropka dziesiętna, przecinek tysięcy"))]
        case "NLS_LANGUAGE": list(["POLISH", "AMERICAN", "ENGLISH", "GERMAN", "SPANISH", "UKRAINIAN", "FRENCH", "CZECH"])
        case "NLS_TERRITORY": list(["POLAND", "AMERICA", "UNITED KINGDOM", "GERMANY", "SPAIN", "UKRAINE", "FRANCE", "CZECH REPUBLIC"])
        case "NLS_SORT": list(["BINARY", "POLISH", "XPOLISH", "BINARY_CI", "BINARY_AI", "POLISH_CI", "POLISH_AI", "GENERIC_M"])
        case "NLS_COMP": list(["BINARY", "LINGUISTIC", "ANSI"])
        default: []
        }
    }

    /// PLSQL_WARNINGS.
    public static let plsqlWarnings: [PreferenceChoice] = [
        PreferenceChoice("ENABLE:ALL", L10n.tr("wszystkie ostrzeżenia")), PreferenceChoice("DISABLE:ALL", L10n.tr("bez ostrzeżeń")),
        PreferenceChoice("ENABLE:SEVERE"), PreferenceChoice("ENABLE:PERFORMANCE"), PreferenceChoice("ENABLE:INFORMATIONAL"),
        PreferenceChoice("ENABLE:SEVERE, ENABLE:PERFORMANCE"), PreferenceChoice("ENABLE:ALL, DISABLE:INFORMATIONAL"),
        PreferenceChoice("ENABLE:ALL, ERROR:SEVERE", L10n.tr("poważne jako błędy")),
    ]
    /// PLSCOPE_SETTINGS.
    public static let plscope: [PreferenceChoice] = [
        PreferenceChoice("IDENTIFIERS:ALL"), PreferenceChoice("IDENTIFIERS:ALL, STATEMENTS:ALL", "12.2+"),
        PreferenceChoice("IDENTIFIERS:PUBLIC", "12.2+"), PreferenceChoice("IDENTIFIERS:NONE", L10n.tr("wyłączone")),
    ]
    /// PLSQL_CCFLAGS (pozycje po przecinku).
    public static let ccflags = list(["debug:TRUE", "debug:FALSE", "trace:TRUE", "trace:FALSE", "test:TRUE"])

    /// Konwencje nazw (przedrostki; kilka po przecinku). Pierwsze pozycje z przykładem — konwencja pakietów RMS
    /// (repozytorium właściciela, D215), dalej inne spotykane.
    public static func naming(_ kind: String) -> [PreferenceChoice] {
        let rms = { (v: String, example: String) in PreferenceChoice(v, L10n.tr("RMS, np. \(example)")) }
        switch kind {
        case "parameter": return [rms("I_", "I_item IN ITEM_MASTER.ITEM%TYPE")] + list(["p_", "pi_", "in_", "a_"])
        case "parameterOut": return [rms("O_", "O_exists OUT BOOLEAN")] + list(["p_", "po_", "out_", "x_"])
        case "parameterInOut": return [rms("O_", "O_error_message IN OUT VARCHAR2"), rms("IO_", "IO_qty IN OUT NUMBER")] + list(["p_", "pio_", "io_"])
        case "local": return [rms("L_", "L_program VARCHAR2(64)")] + list(["l_", "v_", "lv_"])
        case "global": return [rms("LP_", "LP_vdate DATE := GET_VDATE")] + list(["g_", "gv_", "gl_"])
        case "publicGlobal": return [rms("GP_", "GP_replace_mzs_loc BOOLEAN")] + list(["g_", "gv_", "pkg_"])
        case "constant": return [rms("K_", "K_max_rows CONSTANT NUMBER"), rms("GP_", "GP_CON_F_ERROR CONSTANT"), rms("CON_", "CON_status CONSTANT")]
            + list(["c_", "gc_", "co_"])
        case "cursor": return [rms("C_", "CURSOR C_get_item IS …")] + list(["cur_", "c_", "cr_"])
        case "type": return [rms("TYP_", "TYPE TYP_item_tbl IS TABLE OF …"), rms("T_", "TYPE T_rec IS RECORD …")] + list(["t_", "typ_", "tt_", "r_"])
        default: return []
        }
    }

    /// Rozszerzenia plików programów i testów (pozycje po przecinku).
    public static let programExtensions = list(["pls", "plb", "sps", "spb", "pkh", "pkg", "tab", "vw", "seq", "syn", "idx", "ddl"])
    public static let testExtensions = list(["tsts", "ut", "utp"])
    /// Rozszerzenia par specyfikacja/ciało (D194).
    public static let packageSpecExtensions = list(["pks", "spc", "pkh", "pls", "sps"])
    public static let packageBodyExtensions = list(["pkb", "bdy", "pkg", "plb", "spb"])
    public static let typeSpecExtensions = list(["tps", "tys", "typs"])
    public static let typeBodyExtensions = list(["tpb", "tyb", "typb"])

    /// Statystyki sesji po wykonaniu (nazwy z V$STATNAME, pozycje po przecinku).
    public static let statistics = list([
        "consistent gets", "db block gets", "physical reads", "physical writes", "redo size", "session logical reads",
        "CPU used by this session", "sorts (memory)", "sorts (disk)", "execute count", "parse count (total)",
        "parse count (hard)", "bytes sent via SQL*Net to client", "bytes received via SQL*Net from client",
        "SQL*Net roundtrips to/from client", "table scan rows gotten", "recursive calls", "user commits",
    ])

    /// Pisownia specjalna formatera (pozycje po przecinku).
    public static let specialCase = list([
        "DBMS_Output", "DBMS_SQL", "DBMS_Lob", "DBMS_Lock", "DBMS_Scheduler", "DBMS_Session", "DBMS_Utility", "DBMS_Crypto",
        "UTL_File", "UTL_Http", "UTL_Raw", "UTL_Smtp", "UTL_Mail", "APEX_JSON", "JSON_Object_T", "JSON_Array_T",
    ])

    /// Agenci CLI (polecenie).
    public static let agentExecutables: [PreferenceChoice] = [
        PreferenceChoice("claude", "Claude Code"), PreferenceChoice("codex", "OpenAI Codex CLI"),
        PreferenceChoice("gemini", "Gemini CLI"), PreferenceChoice("aider", "Aider"), PreferenceChoice("goose", "Goose"),
    ]

    /// Wyszukiwania w sieci (adres z %s).
    public static let webSearches: [PreferenceChoice] = [
        PreferenceChoice("https://www.google.com/search?q=%s", "Google"),
        PreferenceChoice("https://duckduckgo.com/?q=%s", "DuckDuckGo"),
        PreferenceChoice("https://www.bing.com/search?q=%s", "Bing"),
        PreferenceChoice("https://docs.oracle.com/search/?q=%s", L10n.tr("Dokumentacja Oracle")),
        PreferenceChoice("https://asktom.oracle.com/ords/asktom.search?p_string=%s", "Ask TOM"),
        PreferenceChoice("https://stackoverflow.com/search?q=%s", "Stack Overflow"),
        PreferenceChoice("https://github.com/search?type=code&q=%s", "GitHub"),
    ]
    /// Dokumenty (Narzędzia › Dokumenty): podręczniki Oracle w sieci.
    public static let oracleDocuments: [PreferenceChoice] = [
        PreferenceChoice("https://docs.oracle.com/en/database/oracle/oracle-database/23/lnpls/", "PL/SQL Language Reference 23ai"),
        PreferenceChoice("https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/", "SQL Language Reference 23ai"),
        PreferenceChoice("https://docs.oracle.com/en/database/oracle/oracle-database/23/arpls/", "PL/SQL Packages and Types 23ai"),
        PreferenceChoice("https://docs.oracle.com/en/database/oracle/oracle-database/19/lnpls/", "PL/SQL Language Reference 19c"),
        PreferenceChoice("https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/", "SQL Language Reference 19c"),
        PreferenceChoice("https://www.utplsql.org/utPLSQL/latest/", "utPLSQL"),
    ]
    /// Aplikacje do otwierania plików (nazwa .app).
    public static let applications = list(["TextEdit", "Visual Studio Code", "BBEdit", "Sublime Text", "Xcode", "Numbers", "Microsoft Excel"])
    /// Programy porównujące pliki (polecenie).
    public static let diffPrograms: [PreferenceChoice] = [
        PreferenceChoice("/usr/bin/opendiff", "FileMerge"), PreferenceChoice("/usr/local/bin/ksdiff", "Kaleidoscope"),
        PreferenceChoice("/usr/local/bin/bcomp", "Beyond Compare"), PreferenceChoice("/usr/local/bin/code", "Visual Studio Code"),
        PreferenceChoice("/usr/local/bin/bbdiff", "BBEdit"),
    ]
    /// Argumenty programu porównującego (%1, %2 — pliki).
    public static let diffArguments: [PreferenceChoice] = [
        PreferenceChoice("%1 %2"), PreferenceChoice("--diff %1 %2", "Visual Studio Code"), PreferenceChoice("--wait --diff %1 %2", "Visual Studio Code"),
        PreferenceChoice("%1 %2 --label1 %3 --label2 %4", "Kaleidoscope"), PreferenceChoice("%1 %2 -title1=%3 -title2=%4", "Beyond Compare"),
    ]

    /// Klauzule filtrów Object Browsera.
    public static let browserWhere = list([
        "o.owner = :browser_user", "o.status = 'INVALID'", "o.last_ddl_time > sysdate - 7", "o.object_name like '&browser_filter%'",
        "o.owner not in ('SYS', 'SYSTEM')", "o.temporary = 'N'", "o.generated = 'N'",
    ])
    public static let browserOrder = list(["o.object_name", "o.object_type, o.object_name", "o.last_ddl_time desc", "o.owner, o.object_name"])

    /// Wzorce połączeń `user@baza` z listy połączeń: dokładne, użytkownik na każdej bazie i każdy użytkownik bazy.
    public static func connectionPatterns(_ connections: [ConnectionDefinition]) -> [PreferenceChoice] {
        var seen = Set<String>(), out: [PreferenceChoice] = []
        func add(_ v: String) { if seen.insert(v).inserted { out.append(PreferenceChoice(v)) } }
        for c in connections.sorted(by: { $0.connectionString < $1.connectionString }) {
            let user = c.target.driverUserName.lowercased(), db = c.target.connectString
            add("\(user)@\(db)")
        }
        for c in connections {
            add("\(c.target.driverUserName.lowercased())@*")
            add("*@\(c.target.connectString)")
        }
        ["*@*prod*", "sys@*", "system@*"].forEach(add)
        return out
    }

    /// Użytkownicy baz z listy połączeń (wielkie litery, jak w słowniku Oracle).
    public static func databaseUsers(_ connections: [ConnectionDefinition]) -> [PreferenceChoice] {
        Array(Set(connections.map { $0.target.user.uppercased() }).filter { !$0.isEmpty }).sorted().map { PreferenceChoice($0) }
    }

    /// Pozycje listy wartości po przecinku: wybór dopisuje pozycję albo usuwa ją, gdy już jest (bez wielkości liter).
    public static func toggle(_ item: String, in list: String) -> String {
        var items = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let i = items.firstIndex(where: { $0.caseInsensitiveCompare(item) == .orderedSame }) { items.remove(at: i) } else { items.append(item) }
        return items.joined(separator: ", ")
    }

    /// Czy pozycja jest na liście wartości po przecinku.
    public static func contains(_ item: String, in list: String) -> Bool {
        list.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(item) == .orderedSame }
    }
}

/// Listy wyboru okna definicji połączenia (D211): wartości z innych połączeń, aliasy TNS, hosty z ~/.ssh/config i klucze
/// z ~/.ssh — każde pole można też wpisać ręcznie.
public struct ConnectionFieldChoices: Sendable {
    public var users: [PreferenceChoice] = []
    public var databases: [PreferenceChoice] = []
    public var configDirectories: [PreferenceChoice] = []
    public var walletDirectories: [PreferenceChoice] = []
    public var editions: [PreferenceChoice] = []
    public var schemas: [PreferenceChoice] = []
    public var sshHosts: [PreferenceChoice] = []
    public var sshUsers: [PreferenceChoice] = []
    public var sshKeys: [PreferenceChoice] = []
    public init() {}

    /// `sshConfig` — treść ~/.ssh/config (nil — brak), `sshKeys` — ścieżki kluczy prywatnych.
    public static func from(_ connections: [ConnectionDefinition], tnsAliases: [String], sshConfig: String?, sshKeys: [String]) -> Self {
        func unique(_ values: [String?], sorted: Bool = true) -> [PreferenceChoice] {
            var seen = Set<String>(), out: [String] = []
            for v in values {
                guard let v = v?.trimmingCharacters(in: .whitespaces), !v.isEmpty, seen.insert(v.lowercased()).inserted else { continue }
                out.append(v)
            }
            return (sorted ? out.sorted { $0.localizedStandardCompare($1) == .orderedAscending } : out).map { PreferenceChoice($0) }
        }
        var c = ConnectionFieldChoices()
        c.users = unique(connections.map { $0.target.user.lowercased() })
        c.databases = unique(tnsAliases, sorted: false)
            + unique(connections.map(\.target.connectString)).filter { d in !tnsAliases.contains { $0.caseInsensitiveCompare(d.value) == .orderedSame } }
        c.configDirectories = unique(connections.map(\.target.configDirectory) + ["~/Oracle/network/admin", "/opt/oracle/network/admin"], sorted: false)
        c.walletDirectories = unique(connections.map(\.target.walletDirectory))
        c.editions = unique(["ORA$BASE"] + connections.map(\.target.edition), sorted: false)
        c.schemas = unique(connections.map { $0.target.user.uppercased() } + connections.map(\.currentSchema))
        let hosts = sshConfig.map(Self.sshConfigHosts) ?? []
        c.sshHosts = unique(hosts + connections.map { $0.sshTunnel?.host } + connections.map { $0.sshTunnel?.jumpHost })
        c.sshUsers = unique([NSUserName()] + connections.map { $0.sshTunnel?.user })
        c.sshKeys = unique(sshKeys + connections.map { $0.sshTunnel?.identityFile })
        return c
    }

    /// Nazwy hostów z linii `Host` pliku konfiguracji ssh, bez wzorców z `*`, `?` i `!`.
    public static func sshConfigHosts(_ config: String) -> [String] {
        var out: [String] = []
        for line in config.split(whereSeparator: \.isNewline) {
            let words = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "=" }).map(String.init)
            guard words.count > 1, words[0].lowercased() == "host" else { continue }
            for h in words.dropFirst() where !h.contains(where: { "*?!".contains($0) }) && !out.contains(h) { out.append(h) }
        }
        return out
    }
}
