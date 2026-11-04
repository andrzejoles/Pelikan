import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PelikanLog
import Synchronization

/// Dokumentacja Oracle z lokalnego serwera MCP (D216): wyszukiwanie pełnotekstowe i semantyczne w dokumentacji
/// zainstalowanej na komputerze użytkownika (narzędzia `search_oracle_docs` i `get_doc_section`), obok dokumentacji
/// online (docs.oracle.com). Serwer MCP w transporcie Streamable HTTP; tylko adres lokalny albo HTTPS.
public struct LocalDocsSettings: Sendable, Codable, Hashable {
    /// Pomoc F1 i „Dokumentacja Oracle…” najpierw w dokumentacji lokalnej.
    public var enabled = false
    /// Adres punktu MCP serwera dokumentacji.
    public var url = "http://127.0.0.1:8765/mcp"
    /// Wersja dokumentacji na serwerze: „19c”, „11g” albo „all”.
    public var version = "19c"
    public init() {}

    enum CodingKeys: String, CodingKey { case enabled, url, version }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LocalDocsSettings()
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)).flatMap { $0 } ?? d.enabled
        url = (try? c.decodeIfPresent(String.self, forKey: .url)).flatMap { $0 } ?? d.url
        version = (try? c.decodeIfPresent(String.self, forKey: .version)).flatMap { $0 } ?? d.version
    }

    /// Wersje dokumentacji serwera.
    public static let versions = ["19c", "11g", "all"]

    /// Adres serwera, jeśli dozwolony: HTTPS albo HTTP tylko na tym komputerze (zapytania nie wychodzą do sieci
    /// otwartym tekstem).
    public var endpoint: URL? { Self.endpoint(url) }

    public static func endpoint(_ raw: String) -> URL? {
        guard let u = URL(string: raw.trimmingCharacters(in: .whitespaces)), let scheme = u.scheme?.lowercased(), let host = u.host?.lowercased() else { return nil }
        if scheme == "https" { return u }
        if scheme == "http", ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host) { return u }
        return nil
    }
}

/// Fragment dokumentacji z wyniku wyszukiwania.
public struct DocFragment: Sendable, Hashable, Identifiable {
    public var id: Int { chunk }
    /// Identyfikator fragmentu na serwerze (`chunk_id`) — do pobrania całej sekcji.
    public var chunk: Int
    /// „Oracle 19c · Database PL/SQL Packages and Types Reference — DBMS_OUTPUT”.
    public var title: String
    /// Ścieżka sekcji („123 DBMS_OUTPUT > … > 123.8.7 PUT_LINE Procedure”).
    public var section: String
    /// Strona w dokumentacji online.
    public var link: URL?
    public var text: String

    public init(chunk: Int, title: String, section: String, link: URL?, text: String) {
        self.chunk = chunk; self.title = title; self.section = section; self.link = link; self.text = text
    }

    /// Nagłówek na liście wyników: ostatni człon ścieżki sekcji; człon bez numeru („Syntax”, „Usage Notes”) — razem
    /// z sekcją nadrzędną („… CREATE_JOB Procedure › Syntax”).
    public var heading: String {
        let parts = section.components(separatedBy: " > ")
        guard let last = parts.last else { return section }
        if last.first?.isNumber != true, parts.count > 1 { return parts[parts.count - 2] + " › " + last }
        return last
    }
}

public enum LocalDocsError: Error, LocalizedError, Equatable {
    case badAddress(String)
    case unreachable(String)
    case server(String)
    /// Kod HTTP i początek treści odpowiedzi (rozpoznanie wygasłej sesji).
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .http(let code, _): L10n.tr("Błąd serwera dokumentacji: HTTP \(code)")
        case .badAddress(let a): L10n.tr("Niedozwolony adres serwera dokumentacji: \(a) (HTTPS albo HTTP na tym komputerze)")
        case .unreachable(let m): L10n.tr("Serwer dokumentacji lokalnej nie odpowiada: \(m)")
        case .server(let m): L10n.tr("Błąd serwera dokumentacji: \(m)")
        }
    }
}

/// Klient MCP serwera dokumentacji: `initialize` przy pierwszym wywołaniu (z identyfikatorem sesji, jeśli serwer go
/// nada), potem `tools/call`. Odpowiedź JSON albo strumień SSE (`data:`). Jeden klient na adres (`shared`) — sesja MCP
/// jest używana ponownie, a po restarcie serwera (HTTP 404 dla starej sesji) nawiązywana od nowa.
public actor LocalDocsClient {
    private static let clients = Mutex<[URL: LocalDocsClient]>([:])

    /// Wspólny klient dla adresu serwera (okno dokumentacji, F1, ustawienia, agent).
    public static func shared(for endpoint: URL) -> LocalDocsClient {
        clients.withLock { c in
            if let existing = c[endpoint] { return existing }
            // Jeden klient — dla bieżącego adresu (zmiana adresu w ustawieniach zwalnia poprzedniego klienta i jego sesję).
            let new = LocalDocsClient(endpoint: endpoint)
            c = [endpoint: new]
            return new
        }
    }

    public let endpoint: URL
    private var session: String?
    private var nextID = 1
    private let urlSession: URLSession

    public init(endpoint: URL, urlSession: URLSession = .shared) {
        self.endpoint = endpoint
        self.urlSession = urlSession
    }

    /// Wyszukiwanie: fragmenty w kolejności trafności.
    public func search(_ query: String, version: String, count: Int = 8, book: String? = nil) async throws -> [DocFragment] {
        var args: [String: Any] = ["query": query, "k": max(1, min(15, count)), "version": version]
        if let book, !book.isEmpty { args["book"] = book }
        let text = try await callTool("search_oracle_docs", args)
        // Wersja bywa z argumentu agenta — jawnie tylko znane wartości (stałe techniczne).
        let shown = LocalDocsSettings.versions.contains(version) ? version : "?"
        Log.tools.info("Dokumentacja lokalna: wyszukiwanie, wersja \(shown, privacy: .public)")
        return Self.parseSearch(text)
    }

    /// Cała sekcja fragmentu (składnia, tabela parametrów, uwagi).
    public func section(_ chunk: Int, parent: Bool = false, maxChars: Int = 12000) async throws -> String {
        try await callTool("get_doc_section", ["chunk_id": chunk, "scope": parent ? "parent" : "section", "max_chars": max(2000, min(20000, maxChars))])
    }

    private func callTool(_ name: String, _ arguments: [String: Any]) async throws -> String {
        do {
            return try await callToolOnce(name, arguments)
        } catch let expired as SessionExpired {
            // Sesja wygasła albo serwer uruchomiono ponownie — nowa sesja i jedno ponowienie. Sesję kasuje tylko
            // pierwsze wywołanie, które ją zobaczyło; równoczesne dołączają do nowej inicjalizacji.
            if session == expired.session {
                session = nil
                initialization = nil
            }
            do {
                return try await callToolOnce(name, arguments)
            } catch let again as SessionExpired {
                throw again.error
            }
        }
    }

    /// Odrzucona sesja: 404 (MCP: nieznana sesja) albo inny kod 4xx z komunikatem o sesji („No valid session ID”).
    /// Inne błędy 4xx (argumenty, autoryzacja pośrednika) nie kasują sesji wspólnej dla okna, F1 i agenta.
    static func sessionRejected(_ code: Int, _ body: String) -> Bool {
        code == 404 || ((400..<500).contains(code) && body.range(of: "session", options: .caseInsensitive) != nil)
    }

    /// Odrzucona sesja daje jedną próbę z nową sesją; ponowny błąd idzie do wywołującego jako `LocalDocsError`.
    private struct SessionExpired: Error {
        let session: String
        let error: LocalDocsError
    }

    /// Inicjalizacja sesji MCP raz — równoczesne pierwsze wywołania (aktor jest współbieżny przy `await`) czekają na
    /// to samo zadanie zamiast inicjować po kilka sesji.
    private var initialization: Task<Void, any Error>?

    /// Czeka na zakończoną inicjalizację bieżącej sesji. Gdy w trakcie czekania inne wywołanie unieważniło sesję
    /// (wygasła — nowa inicjalizacja), czeka na nową, zamiast wysłać żądanie bez sesji albo przed `initialized`.
    private func ensureInitialized() async throws {
        for _ in 0..<3 {
            let task: Task<Void, any Error>
            if let initialization {
                task = initialization
            } else {
                task = Task { [self] in
                    _ = try await rpc("initialize", ["protocolVersion": "2025-06-18", "capabilities": [String: Any](),
                                                     "clientInfo": ["name": "Pelikan", "version": "1"]])
                    try await notify("notifications/initialized")
                }
                initialization = task
            }
            do { try await task.value } catch {
                if initialization == task { initialization = nil }
                throw error
            }
            if initialization == task { return }
        }
        // Sesja unieważniana raz po raz (serwer ciągle odrzuca) — błąd zamiast żądania bez zainicjowanej sesji.
        throw LocalDocsError.server(L10n.tr("nie udało się nawiązać sesji MCP"))
    }

    private func callToolOnce(_ name: String, _ arguments: [String: Any]) async throws -> String {
        try await ensureInitialized()
        // Sesja odczytana bez zawieszenia przed zbudowaniem żądania — ta sama, którą żądanie wysyła.
        let used = session
        let result: [String: Any]
        do {
            result = try await rpc("tools/call", ["name": name, "arguments": arguments])
        } catch LocalDocsError.http(let code, let body) where used != nil && Self.sessionRejected(code, body) {
            throw SessionExpired(session: used!, error: .http(code, body))
        }
        let content = (result["content"] as? [[String: Any]]) ?? []
        let text = content.compactMap { $0["type"] as? String == "text" || $0["type"] == nil ? $0["text"] as? String : nil }.joined(separator: "\n")
        if result["isError"] as? Bool == true { throw LocalDocsError.server(text) }
        return text
    }

    private func request(_ body: [String: Any]) throws -> URLRequest {
        var r = URLRequest(url: endpoint, timeoutInterval: 30)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        r.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
        if let session { r.setValue(session, forHTTPHeaderField: "Mcp-Session-Id") }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    private func notify(_ method: String) async throws {
        _ = try? await urlSession.data(for: request(["jsonrpc": "2.0", "method": method]))
    }

    private func rpc(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request(["jsonrpc": "2.0", "id": id, "method": method, "params": params]))
        } catch {
            Log.tools.error("Dokumentacja lokalna: brak połączenia z serwerem")
            throw LocalDocsError.unreachable(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse {
            // Identyfikator sesji tylko z udanej odpowiedzi na initialize (odpowiedź błędu nie ustanawia sesji).
            if method == "initialize", (200..<300).contains(http.statusCode), let s = http.value(forHTTPHeaderField: "Mcp-Session-Id") { session = s }
            guard (200..<300).contains(http.statusCode) else {
                throw LocalDocsError.http(http.statusCode, String(decoding: data.prefix(500), as: UTF8.self))
            }
        }
        guard let message = Self.message(data, id: id) else { throw LocalDocsError.server(L10n.tr("nieczytelna odpowiedź")) }
        if let e = message["error"] as? [String: Any] { throw LocalDocsError.server(e["message"] as? String ?? "\(e)") }
        return message["result"] as? [String: Any] ?? [:]
    }

    /// Odpowiedź JSON-RPC o identyfikatorze z treści JSON albo zdarzeń SSE.
    static func message(_ data: Data, id: Int) -> [String: Any]? {
        func parse(_ d: Data) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] }
        if let m = parse(data), m["id"] != nil || m["error"] != nil { return m }
        let text = String(decoding: data, as: UTF8.self)
        var payload = ""
        var found: [String: Any]?
        func flush() {
            if !payload.isEmpty, let m = parse(Data(payload.utf8)), (m["id"] as? Int) == id || found == nil && m["result"] != nil { found = m }
            payload = ""
        }
        for line in text.components(separatedBy: "\n") {
            let l = line.hasSuffix("\r") ? String(line.dropLast()) : line
            if l.isEmpty { flush(); continue }
            if l.hasPrefix("data:") { payload += (payload.isEmpty ? "" : "\n") + l.dropFirst(5).trimmingCharacters(in: .whitespaces) }
        }
        flush()
        return found
    }

    /// Fragmenty z tekstu wyniku `search_oracle_docs`: bloki „[n] tytuł / Section: … / Source: adres (chunk_id=N)”
    /// oddzielone linią `---`.
    public static func parseSearch(_ text: String) -> [DocFragment] {
        text.components(separatedBy: "\n---\n").compactMap { block in
            let lines = block.trimmingCharacters(in: .newlines).components(separatedBy: "\n")
            guard let first = lines.first, first.hasPrefix("[") else { return nil }
            let title = first.replacingOccurrences(of: #"^\[\d+\]\s*"#, with: "", options: .regularExpression)
            var section = "", link: URL?, chunk: Int?
            var bodyStart = 1
            for (i, l) in lines.enumerated().dropFirst() {
                if l.hasPrefix("Section:") { section = l.dropFirst(8).trimmingCharacters(in: .whitespaces); bodyStart = i + 1 }
                else if l.hasPrefix("Source:") {
                    let rest = l.dropFirst(7).trimmingCharacters(in: .whitespaces)
                    if let r = rest.range(of: #"\(chunk_id=(\d+)\)"#, options: .regularExpression) {
                        chunk = Int(rest[r].filter(\.isNumber))
                        link = URL(string: rest[..<r.lowerBound].trimmingCharacters(in: .whitespaces))
                    } else { link = URL(string: rest) }
                    bodyStart = i + 1
                } else if !l.isEmpty { break }
            }
            guard let chunk else { return nil }
            let body = lines.dropFirst(bodyStart).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return DocFragment(chunk: chunk, title: title, section: section, link: link, text: body)
        }
    }
}
