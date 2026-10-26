import Foundation
import PelikanDB
import PelikanLog

/// Zgłoszenie problemu (PL-INFRA-013, D173): treść nowego zgłoszenia (Issue) w repozytorium aplikacji na GitHubie.
/// Pelikan niczego nie wysyła sam — otwiera stronę nowego zgłoszenia z wypełnioną treścią, a użytkownik sprawdza ją
/// i wysyła ze swojego konta (bez tokenów w aplikacji). Repozytorium jest publiczne: części automatyczne (środowisko,
/// dziennik z ukrytymi nazwami, opis awarii) i tekst użytkownika przechodzą przez filtr haseł i ścieżki domowej.
public struct ProblemReport: Sendable, Equatable {
    public enum Origin: Sendable, Equatable {
        /// Pomoc › Zgłoś problem…
        case manual
        /// Przycisk „Zgłoś problem…” w komunikacie błędu.
        case error(String)
        /// Pytanie po nieoczekiwanym zamknięciu (opis awarii z raportu macOS, jeśli jest).
        case crash(CrashSummary?)
    }

    public var origin: Origin
    public var title: String
    public var details = ""
    public var includeEnvironment = true
    public var includeLog = true
    public var environment: String
    public var logTail: [String]

    public init(origin: Origin, title: String = "", environment: String, logTail: [String]) {
        self.origin = origin
        self.environment = environment
        self.logTail = logTail
        switch origin {
        case .manual: self.title = title
        case .error(let message):
            self.title = title.isEmpty ? L10n.tr("Błąd: \(Self.firstLine(message, limit: 80))") : title
        case .crash(let summary):
            self.title = title.isEmpty ? L10n.tr("Awaria: \(summary?.exceptionType ?? L10n.tr("nieoczekiwane zamknięcie"))") : title
        }
    }

    static func firstLine(_ s: String, limit: Int) -> String {
        let line = s.split(separator: "\n").first.map(String.init) ?? s
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }

    /// Treść zgłoszenia (Markdown); `logLines` — ile ostatnich wpisów dziennika (nil — wszystkie).
    public func body(logLines: Int? = nil) -> String {
        var out = "### " + L10n.tr("Co się stało") + "\n\n"
        let text = details.trimmingCharacters(in: .whitespacesAndNewlines)
        out += (text.isEmpty ? L10n.tr("(brak opisu)") : LogRedactor.redact(text)) + "\n\n"
        switch origin {
        case .manual: break
        case .error(let message):
            out += "### " + L10n.tr("Komunikat błędu") + "\n\n" + Self.fenced(LogRedactor.redact(message)) + "\n"
        case .crash(let summary):
            out += "### " + L10n.tr("Awaria") + "\n\n"
            out += Self.fenced(summary.map { LogRedactor.redact($0.text) } ?? L10n.tr("Aplikacja została zamknięta nieoczekiwanie (bez raportu awarii macOS).")) + "\n"
        }
        if includeEnvironment {
            out += "### " + L10n.tr("Środowisko") + "\n\n" + Self.fenced(LogRedactor.redact(environment)) + "\n"
        }
        if includeLog, !logTail.isEmpty {
            let lines = logLines.map { Array(logTail.suffix($0)) } ?? logTail
            out += "### " + L10n.tr("Ostatnie wpisy dziennika") + "\n\n" + Self.fenced(lines.map(LogRedactor.redact).joined(separator: "\n")) + "\n"
            if lines.count < logTail.count {
                out += L10n.tr("(skrócone do \(lines.count) ostatnich wpisów — pełna treść w schowku)") + "\n\n"
            }
        }
        out += "---\n" + L10n.tr("Zgłoszenie przygotowane w aplikacji (Pomoc › Zgłoś problem).") + "\n"
        return out
    }

    /// Blok kodu Markdown odporny na ``` w treści.
    static func fenced(_ s: String) -> String {
        var fence = "```"
        while s.contains(fence) { fence += "`" }
        return fence + "\n" + s + "\n" + fence + "\n"
    }

    /// Adres strony nowego zgłoszenia z treścią. Gdy adres byłby za długi dla przeglądarki i GitHuba, dziennik jest
    /// skracany od najstarszych wpisów (`truncated` — pełną treść trzeba wkleić ze schowka).
    public func issueURL(repository: String, maxLength: Int = 7500) -> (url: URL, truncated: Bool)? {
        func make(_ body: String) -> URL? {
            var c = URLComponents()
            c.scheme = "https"
            c.host = "github.com"
            c.path = "/\(repository)/issues/new"
            c.queryItems = [URLQueryItem(name: "title", value: LogRedactor.redact(title)), URLQueryItem(name: "body", value: body),
                            URLQueryItem(name: "labels", value: "bug")]
            // `+` w treści byłby odczytany jako spacja.
            c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            return c.url
        }
        guard let full = make(body()) else { return nil }
        if full.absoluteString.count <= maxLength { return (full, false) }
        var lines = includeLog ? logTail.count : 0
        while lines > 0 {
            lines = lines > 20 ? lines * 3 / 4 : lines - 5
            if let u = make(body(logLines: max(lines, 0))), u.absoluteString.count <= maxLength { return (u, true) }
        }
        var bare = self
        bare.includeLog = false
        bare.details = Self.firstLine(details, limit: 1500)
        guard let u = make(bare.body() + L10n.tr("(treść skrócona — pełna treść w schowku)") + "\n") else { return nil }
        return (u, true)
    }
}

/// Opis awarii z raportu macOS (`~/Library/Logs/DiagnosticReports/<aplikacja>-….ips`): wyjątek, sygnał i stos wątku,
/// w którym nastąpiła awaria — tylko nazwy modułów i symboli, bez ścieżek i danych procesu.
public struct CrashSummary: Sendable, Equatable {
    public var exceptionType: String
    public var signal: String?
    public var reason: String?
    public var frames: [String]
    public var date: String?

    public var text: String {
        var lines = [L10n.tr("Wyjątek: \(exceptionType)") + (signal.map { " (\($0))" } ?? "")]
        if let reason { lines.append(L10n.tr("Przyczyna: \(reason)")) }
        if let date { lines.append(L10n.tr("Czas: \(date)")) }
        lines.append(L10n.tr("Stos wątku z awarią:"))
        lines += frames.enumerated().map { "\($0.offset)  \($0.element)" }
        return lines.joined(separator: "\n")
    }

    /// Raport `.ips`: pierwsza linia — nagłówek JSON, reszta — treść JSON (format macOS 12+).
    public static func parse(_ ips: String, maxFrames: Int = 25) -> CrashSummary? {
        guard let newline = ips.firstIndex(of: "\n"),
              let header = try? JSONSerialization.jsonObject(with: Data(ips[..<newline].utf8)) as? [String: Any],
              let body = try? JSONSerialization.jsonObject(with: Data(ips[ips.index(after: newline)...].utf8)) as? [String: Any]
        else { return nil }
        let exception = body["exception"] as? [String: Any]
        let type = exception?["type"] as? String ?? (body["termination"] as? [String: Any])?["indicator"] as? String ?? "?"
        let images = (body["usedImages"] as? [[String: Any]] ?? []).map { $0["name"] as? String ?? "?" }
        let threads = body["threads"] as? [[String: Any]] ?? []
        let faulting = body["faultingThread"] as? Int ?? threads.firstIndex { $0["triggered"] as? Bool == true } ?? 0
        let frames = threads.indices.contains(faulting) ? (threads[faulting]["frames"] as? [[String: Any]] ?? []) : []
        let described = frames.prefix(maxFrames).map { f -> String in
            let image = (f["imageIndex"] as? Int).flatMap { images.indices.contains($0) ? images[$0] : nil } ?? "?"
            if let symbol = f["symbol"] as? String {
                return "\(image)  \(symbol)" + ((f["symbolLocation"] as? Int).map { " + \($0)" } ?? "")
            }
            return "\(image)  +\(f["imageOffset"] as? Int ?? 0)"
        }
        let termination = body["termination"] as? [String: Any]
        let reason = (body["asi"] as? [String: [String]])?.values.flatMap { $0 }.first
            ?? termination?["indicator"] as? String
        return CrashSummary(exceptionType: type, signal: exception?["signal"] as? String, reason: reason == type ? nil : reason,
                            frames: described, date: header["timestamp"] as? String)
    }
}

/// Wykrywanie nieoczekiwanego zamknięcia: znacznik pracy aplikacji w katalogu danych, usuwany przy czystym zamknięciu.
public struct CrashMonitor: Sendable {
    public let marker: URL

    public init(dataDirectory: URL) {
        marker = dataDirectory.appendingPathComponent(".running")
    }

    /// Start aplikacji: data startu poprzedniej sesji, jeśli nie zakończyła się czysto (nil — zamknięta poprawnie).
    public func begin(now: Date = Date()) -> Date? {
        let previous = (try? FileManager.default.attributesOfItem(atPath: marker.path)[.modificationDate]) as? Date
        try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: marker.path, contents: Data(), attributes: [.modificationDate: now])
        return previous
    }

    /// Czyste zamknięcie.
    public func end() {
        try? FileManager.default.removeItem(at: marker)
    }

    /// Najnowszy raport awarii aplikacji `appName` nie starszy niż `since` w katalogu raportów macOS.
    public static func latestReport(appName: String, since: Date, in directory: URL) -> CrashSummary? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let candidates = files.filter { $0.lastPathComponent.hasPrefix(appName + "-") && $0.pathExtension == "ips" }
            .compactMap { url -> (URL, Date)? in
                guard let d = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, d >= since else { return nil }
                return (url, d)
            }
            .sorted { $0.1 > $1.1 }
        guard let newest = candidates.first, let text = try? String(contentsOf: newest.0, encoding: .utf8) else { return nil }
        return CrashSummary.parse(text)
    }
}

extension Workspace {
    /// Opis środowiska do eksportu dziennika i zgłoszeń: wersja, system, sterowniki, liczba połączeń — bez nazw i adresów.
    public func environmentSummary() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let drivers = DriverKind.allCases.map { kind -> String in
            guard let d = sessions.driver(for: kind) else { return "\(kind.rawValue): brak" }
            if case .failure = d.availability() { return "\(kind.rawValue): niedostępny" }
            return "\(kind.rawValue): dostępny"
        }
        return """
        Wersja: \(version) (\(build))
        System: \(v.majorVersion).\(v.minorVersion).\(v.patchVersion), \(arch)
        Dziennik: poziom \(settings.logLevel.rawValue), nazwy \(settings.logIncludeNames ? "jawne" : "ukryte")
        Sterowniki: \(drivers.joined(separator: ", "))
        Połączenia: \(connections.connections.count), tryb sesji: \(settings.sessionMode.rawValue)
        """
    }

    /// Ostatnie wpisy dziennika z pliku (linie z wcięciem należą do wpisu powyżej).
    public func recentLogLines(_ count: Int = 80) -> [String] {
        guard let sink = Log.fileSink else { return [] }
        sink.flush()
        var lines: [String] = []
        for f in sink.files.reversed() where lines.count < count {
            let text = (try? String(contentsOf: f, encoding: .utf8)) ?? ""
            lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) + lines
        }
        return Array(lines.suffix(count))
    }

    /// Szkic zgłoszenia z opisem środowiska i ostatnimi wpisami dziennika.
    public func problemReport(_ origin: ProblemReport.Origin) -> ProblemReport {
        ProblemReport(origin: origin, environment: environmentSummary(), logTail: recentLogLines())
    }
}
