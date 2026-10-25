import Foundation

/// Wpis z tnsnames.ora: alias (może być kilka aliasów rozdzielonych przecinkami) i deskryptor połączenia.
public struct TNSEntry: Sendable, Hashable {
    public var aliases: [String]
    /// Deskryptor w postaci tekstowej (bez komentarzy), np. `(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=db)(PORT=1521))…)`.
    public var descriptor: String
    /// Plik, z którego pochodzi wpis (IFILE może dołączać inne pliki).
    public var file: String

    public var name: String { aliases.first ?? "" }

    /// Pierwszy adres z deskryptora (do rozwinięcia aliasu dla sterownika thin i do wyświetlenia w liście).
    public var host: String? { TNSNames.value("HOST", in: descriptor) }
    public var port: Int? { TNSNames.value("PORT", in: descriptor).flatMap(Int.init) }
    public var serviceName: String? { TNSNames.value("SERVICE_NAME", in: descriptor) }
    public var sid: String? { TNSNames.value("SID", in: descriptor) }
    public var protocolName: String? { TNSNames.value("PROTOCOL", in: descriptor) }
}

/// Parser tnsnames.ora (składnia Oracle Net: `alias[,alias…] = (DESCRIPTION = …)`, komentarze `#`, dołączanie IFILE).
/// Tolerancyjny: wpis z niedomkniętymi nawiasami jest pomijany, reszta pliku czytana dalej.
public enum TNSNames {
    /// Katalogi szukania tnsnames.ora w kolejności Oracle Net: katalog z ustawień połączenia, TNS_ADMIN,
    /// `$ORACLE_HOME/network/admin`, katalog Instant Client `network/admin`, `~/.tnsnames.ora` nie jest standardem (pomijamy).
    public static func searchDirectories(configured: String?, environment: [String: String] = ProcessInfo.processInfo.environment,
                                         instantClientDirectory: String? = nil) -> [String] {
        var dirs: [String] = []
        if let c = configured, !c.isEmpty { dirs.append((c as NSString).expandingTildeInPath) }
        if let t = environment["TNS_ADMIN"], !t.isEmpty { dirs.append((t as NSString).expandingTildeInPath) }
        if let h = environment["ORACLE_HOME"], !h.isEmpty { dirs.append(h + "/network/admin") }
        if let ic = instantClientDirectory { dirs.append(ic + "/network/admin") }
        return dirs
    }

    /// Wpisy z pierwszego znalezionego tnsnames.ora w podanych katalogach.
    public static func load(directories: [String]) -> [TNSEntry] {
        for d in directories {
            let path = d + "/tnsnames.ora"
            if FileManager.default.fileExists(atPath: path) { return load(file: path) }
        }
        return []
    }

    public static func load(file path: String, depth: Int = 0) -> [TNSEntry] {
        guard depth < 8, let text = (try? String(contentsOfFile: path, encoding: .utf8))
                ?? (try? String(contentsOfFile: path, encoding: .isoLatin1)) else { return [] }
        var entries: [TNSEntry] = []
        for e in parse(text, file: path) {
            if e.aliases.count == 1, e.aliases[0].uppercased() == "IFILE" {
                var inc = e.descriptor.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if !inc.hasPrefix("/") { inc = (path as NSString).deletingLastPathComponent + "/" + inc }
                entries += load(file: inc, depth: depth + 1)
            } else {
                entries.append(e)
            }
        }
        return entries
    }

    /// Parsowanie tekstu pliku.
    public static func parse(_ text: String, file: String = "") -> [TNSEntry] {
        // Usuń komentarze (# do końca linii) — w tnsnames.ora nie ma literałów, w których # byłby znaczący.
        let cleaned = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            if let i = line.firstIndex(of: "#") { return line[..<i] }
            return line[...]
        }.joined(separator: "\n")
        var entries: [TNSEntry] = []
        let chars = Array(cleaned)
        var i = 0
        while i < chars.count {
            // Nazwa: do znaku '='.
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            guard i < chars.count else { break }
            let nameStart = i
            while i < chars.count, chars[i] != "=", chars[i] != "(" { i += 1 }
            guard i < chars.count, chars[i] == "=" else {
                // Śmieci albo nawias bez nazwy — przeskocz do końca linii.
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            let names = String(chars[nameStart..<i]).split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            i += 1
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            guard i < chars.count else { break }
            if chars[i] == "(" {
                // Deskryptor w nawiasach — do zbilansowania.
                var depth = 0
                let s = i
                var closed = false
                while i < chars.count {
                    if chars[i] == "(" { depth += 1 }
                    if chars[i] == ")" {
                        depth -= 1
                        if depth == 0 { i += 1; closed = true; break }
                    }
                    i += 1
                }
                guard closed else { break }
                let desc = Self.compact(String(chars[s..<i]))
                if !names.isEmpty { entries.append(TNSEntry(aliases: names, descriptor: desc, file: file)) }
            } else {
                // Wartość prosta (np. IFILE = /ścieżka) — do końca linii.
                let s = i
                while i < chars.count, chars[i] != "\n" { i += 1 }
                let value = String(chars[s..<i]).trimmingCharacters(in: .whitespaces)
                if !names.isEmpty { entries.append(TNSEntry(aliases: names, descriptor: value, file: file)) }
            }
        }
        return entries
    }

    /// Wartość parametru `(NAZWA=wartość)` z deskryptora (pierwsze wystąpienie, bez rozróżniania wielkości liter).
    public static func value(_ key: String, in descriptor: String) -> String? {
        guard let r = descriptor.range(of: "(\(key)=", options: .caseInsensitive) else { return nil }
        let rest = descriptor[r.upperBound...]
        guard let end = rest.firstIndex(of: ")") else { return nil }
        let v = String(rest[..<end])
        return v.isEmpty ? nil : v
    }

    /// Alias → EZConnect (`host:port/usługa`) dla sterownika thin, który nie czyta tnsnames.ora. nil, gdy deskryptor
    /// jest złożony (wiele adresów z failover, protokół inny niż TCP/TCPS) i wymaga Instant Client.
    public static func easyConnect(for entry: TNSEntry) -> String? {
        let addressCount = entry.descriptor.uppercased().components(separatedBy: "(ADDRESS=").count - 1
        guard addressCount == 1, let host = entry.host else { return nil }
        let proto = (entry.protocolName ?? "TCP").uppercased()
        guard proto == "TCP" || proto == "TCPS" else { return nil }
        let port = entry.port ?? 1521
        let prefix = proto == "TCPS" ? "tcps://" : ""
        if let s = entry.serviceName { return "\(prefix)\(host):\(port)/\(s)" }
        if let sid = entry.sid { return "\(prefix)\(host):\(port)/\(sid)" }   // EZConnect nie rozróżnia SID; thin dostaje SID osobno
        return nil
    }
}

extension TNSNames {
    /// Deskryptor bez białych znaków poza wartościami w cudzysłowie — `SSL_SERVER_CERT_DN="CN=…,O=Oracle Corporation"`
    /// czy katalog portfela ze spacją muszą dojść do klienta bez zmian.
    public static func compact(_ descriptor: String) -> String {
        var out = ""
        var quoted = false
        for c in descriptor {
            if c == "\"" { quoted.toggle() }
            if !quoted, c.isWhitespace { continue }
            out.append(c)
        }
        return out
    }
}

public extension TNSNames {
    /// Dopisuje parametry uwierzytelniania tokenem: w deskryptorze do sekcji SECURITY (tworzonej, gdy jej brak),
    /// w EZConnect jako parametry `?klucz=wartość`. Alias trzeba wcześniej rozwinąć (nil — nie da się dopisać).
    static func applyTokenAuth(_ connect: String, parameters: [(String, String)]) -> String? {
        let s = connect.trimmingCharacters(in: .whitespaces)
        guard !parameters.isEmpty else { return s }
        if s.hasPrefix("(") {
            let items = parameters.map { "(\($0.0)=\($0.1))" }.joined()
            if let r = s.range(of: "(SECURITY=", options: .caseInsensitive) {
                var out = s
                out.insert(contentsOf: items, at: r.upperBound)
                return out
            }
            guard let close = s.lastIndex(of: ")") else { return nil }
            var out = s
            out.insert(contentsOf: "(SECURITY=\(items))", at: close)
            return out
        }
        guard s.contains("/") || s.contains(":") else { return nil }
        return s + (s.contains("?") ? "&" : "?") + parameters.map { "\($0.0.lowercased())=\($0.1)" }.joined(separator: "&")
    }

    /// Connect string dla połączenia z własnym katalogiem konfiguracji (tnsnames.ora, wallet): alias z tego katalogu
    /// rozwijany do deskryptora; przy TCPS bez wskazanego wallet dopisywany `MY_WALLET_DIRECTORY` = katalog połączenia.
    /// Bez katalogu konfiguracji — bez zmian (klient czyta TNS_ADMIN / domyślne miejsca).
    /// `walletDirectory` — portfel TLS połączenia (pierwszeństwo przed katalogiem konfiguracji); przy EZConnect
    /// `tcps://…` dopisywany parametr `wallet_location` (Instant Client 21+). `keepAlias` — alias przekazywany bez
    /// rozwinięcia (magazyn haseł szuka poświadczenia po dokładnym tekście aliasu, D53).
    static func resolveForConnection(_ connect: String, configDirectory: String?, walletDirectory: String? = nil, keepAlias: Bool = false) -> String {
        let walletDir = (walletDirectory ?? configDirectory).map { ($0 as NSString).expandingTildeInPath }.flatMap { $0.isEmpty ? nil : $0 }
        var s = connect.trimmingCharacters(in: .whitespaces)
        if let w = walletDir, s.lowercased().hasPrefix("tcps://"), !s.lowercased().contains("wallet_location") {
            return s + (s.contains("?") ? "&" : "?") + "wallet_location=\(w)"
        }
        let dir = configDirectory.map { ($0 as NSString).expandingTildeInPath } ?? ""
        if dir.isEmpty && walletDir == nil { return connect }
        if !keepAlias, !dir.isEmpty, !s.hasPrefix("("), !s.contains("/"), !s.contains(":") {
            guard let e = load(directories: [dir]).first(where: { $0.aliases.contains { $0.caseInsensitiveCompare(s) == .orderedSame } }) else {
                return connect
            }
            s = e.descriptor
        }
        if let w = walletDir, s.hasPrefix("("), (value("PROTOCOL", in: s) ?? "").uppercased() == "TCPS", value("MY_WALLET_DIRECTORY", in: s) == nil,
           let close = s.lastIndex(of: ")") {
            s.insert(contentsOf: "(SECURITY=(MY_WALLET_DIRECTORY=\(w)))", at: close)
        }
        return s
    }
}
