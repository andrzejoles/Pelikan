import Foundation

/// Ostatnia linia obrony (D170): każda wartość wstawiana do dziennika — także jawna — traci hasła w typowych zapisach
/// (CONNECT u/hasło@baza, IDENTIFIED BY, password=…, poświadczenia w URL) i ścieżkę katalogu domowego.
/// Hasła nie powinny w ogóle trafiać do wpisów; ten filtr chroni przed pomyłką, nie zastępuje dyscypliny.
public enum LogRedactor {
    static let mask = "***"

    static let rules: [(NSRegularExpression, String)] = [
        // IDENTIFIED BY hasło / "hasło" / VALUES 'skrót'
        (try! NSRegularExpression(pattern: #"(?i)(identified\s+by\s+)(values\s+'[^']*'|"[^"]*"|\S+)"#), "$1" + mask),
        // użytkownik/hasło@baza (CONNECT, sqlplus, connect string)
        (try! NSRegularExpression(pattern: #"([A-Za-z0-9_$#."\[\]]+/)("[^"]*"|[^@\s/"]+)(@)"#), "$1" + mask + "$3"),
        // CONNECT użytkownik/hasło bez @
        (try! NSRegularExpression(pattern: #"(?i)(\bconn(?:ect)?\s+[^\s/]+/)([^\s@]+)"#), "$1" + mask),
        // password=…, pwd: …, secret=…, token=…
        (try! NSRegularExpression(pattern: #"(?i)\b(password|passwd|pwd|secret|token)(\s*[=:]\s*)("[^"]*"|'[^']*'|[^\s;,&"']+)"#), "$1$2" + mask),
        // schemat://użytkownik:hasło@host
        (try! NSRegularExpression(pattern: #"(://[^/\s:@]+:)([^@\s/]+)(@)"#), "$1" + mask + "$3"),
    ]

    static let home: String? = {
        let h = NSHomeDirectory()
        return h.count > 1 ? h : nil
    }()

    public static func redact(_ text: String) -> String {
        var t = text
        if let home, t.contains(home) { t = t.replacingOccurrences(of: home, with: "~") }
        guard t.contains(where: { $0 == "/" || $0 == "=" || $0 == ":" || $0 == "@" || $0 == " " }) else { return t }
        for (re, template) in rules {
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: template)
        }
        return t
    }
}
