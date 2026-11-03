import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PelikanWorkspace
import Testing

/// Serwer MCP podstawiony w `URLProtocol`: odpowiada na initialize i tools/call strumieniem SSE, zapisuje żądania.
final class FakeDocsServer: URLProtocol {
    nonisolated(unsafe) static var requests: [[String: Any]] = []
    nonisolated(unsafe) static var sessionHeaders: [String?] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "127.0.0.1" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map { s in
            s.open(); defer { s.close() }
            var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
            return d
        } ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        Self.lock.withLock {
            Self.requests.append(json)
            Self.sessionHeaders.append(request.value(forHTTPHeaderField: "Mcp-Session-Id"))
        }
        let id = json["id"] as? Int
        var result: Any = [String: Any]()
        if json["method"] as? String == "tools/call" {
            let text = """
            [1] Oracle 19c · Database PL/SQL Packages and Types Reference — DBMS_OUTPUT
            Section: 123 DBMS_OUTPUT > 123.8.7 PUT_LINE Procedure
            Source: https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_OUTPUT.html  (chunk_id=299800)

            ## 123.8.7 PUT_LINE Procedure
            This procedure places a line in the buffer.
            """
            result = ["content": [["type": "text", "text": text]]]
        }
        let payload = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id as Any, "result": result])
        let sse = Data("event: message\ndata: ".utf8) + payload + Data("\n\n".utf8)
        let resp = HTTPURLResponse(url: request.url!, statusCode: id == nil ? 202 : 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "text/event-stream", "Mcp-Session-Id": "s-1"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: id == nil ? Data() : sse)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Dokumentacja Oracle z lokalnego serwera MCP (D216)", .serialized)
struct LocalDocsTests {
    let sample = """
    [1] Oracle 19c · Database PL/SQL Packages and Types Reference — DBMS_OUTPUT
    Section: 123 DBMS_OUTPUT > 123.8 Summary of DBMS_OUTPUT Subprograms > 123.8.7 PUT_LINE Procedure
    Source: https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_OUTPUT.html  (chunk_id=299800)

    ## 123.8.7 PUT_LINE Procedure
    This procedure places a line in the buffer.

    ## Syntax
    DBMS_OUTPUT.PUT_LINE (
       item IN VARCHAR2);

    ---

    [2] Oracle 11g · Oracle Database Utilities — Using the Oracle Data Pump API
    Section: 6 Using the Oracle Data Pump API
    Source: https://docs.oracle.com/cd/E11882_01/server.112/e22490/dp_api.htm  (chunk_id=42)

    DECLARE
      ind NUMBER;
    """

    @Test("Wynik wyszukiwania: tytuł, sekcja, adres online, chunk_id, treść; separator --- w treści bloku")
    func parse() {
        let f = LocalDocsClient.parseSearch(sample)
        #expect(f.count == 2)
        #expect(f[0].chunk == 299800 && f[0].title == "Oracle 19c · Database PL/SQL Packages and Types Reference — DBMS_OUTPUT")
        #expect(f[0].heading == "123.8.7 PUT_LINE Procedure")
        #expect(f[0].link?.absoluteString == "https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_OUTPUT.html")
        #expect(f[0].text.hasPrefix("## 123.8.7 PUT_LINE Procedure") && f[0].text.contains("item IN VARCHAR2);"))
        #expect(f[1].chunk == 42 && f[1].text.hasPrefix("DECLARE"))
        #expect(LocalDocsClient.parseSearch("No results").isEmpty)
        #expect(DocFragment(chunk: 1, title: "", section: "161 DBMS_SCHEDULER > 161.6.30 CREATE_JOB Procedure > Syntax", link: nil, text: "").heading
                == "161.6.30 CREATE_JOB Procedure › Syntax")
    }

    @Test("Odpowiedź JSON-RPC z JSON i ze strumienia SSE")
    func messages() {
        let sse = Data("event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"ok\":1}}\n\n".utf8)
        #expect((LocalDocsClient.message(sse, id: 3)?["result"] as? [String: Any])?["ok"] as? Int == 1)
        let json = Data(#"{"jsonrpc":"2.0","id":4,"error":{"message":"nope"}}"#.utf8)
        #expect(LocalDocsClient.message(json, id: 4)?["error"] != nil)
        #expect(LocalDocsClient.message(Data("garbage".utf8), id: 1) == nil)
    }

    @Test("Adres: HTTPS albo HTTP tylko na tym komputerze; stare ustawienia bez pola")
    func endpoint() throws {
        #expect(LocalDocsSettings.endpoint("http://127.0.0.1:8765/mcp") != nil)
        #expect(LocalDocsSettings.endpoint("http://localhost:8765/mcp") != nil)
        #expect(LocalDocsSettings.endpoint("https://docs.example.com/mcp") != nil)
        #expect(LocalDocsSettings.endpoint("http://192.168.1.10:8765/mcp") == nil)
        #expect(LocalDocsSettings.endpoint("ftp://127.0.0.1/") == nil)
        #expect(LocalDocsSettings.endpoint("") == nil)
        let s = try JSONDecoder().decode(LocalDocsSettings.self, from: Data(#"{"enabled":true}"#.utf8))
        #expect(s.enabled && s.url == "http://127.0.0.1:8765/mcp" && s.version == "19c")
    }

    @Test("Klient: initialize, notifications/initialized, tools/call z identyfikatorem sesji i argumentami")
    func client() async throws {
        FakeDocsServer.lock.withLock { FakeDocsServer.requests = []; FakeDocsServer.sessionHeaders = [] }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [FakeDocsServer.self]
        let c = LocalDocsClient(endpoint: URL(string: "http://127.0.0.1:8765/mcp")!, urlSession: URLSession(configuration: cfg))
        let found = try await c.search("DBMS_OUTPUT.PUT_LINE", version: "11g", count: 40)
        #expect(found.map(\.chunk) == [299800])
        _ = try await c.search("NVL", version: "19c")
        let (reqs, sessions) = FakeDocsServer.lock.withLock { (FakeDocsServer.requests, FakeDocsServer.sessionHeaders) }
        #expect(reqs.map { $0["method"] as? String } == ["initialize", "notifications/initialized", "tools/call", "tools/call"])
        #expect(sessions.first! == nil && sessions.dropFirst().allSatisfy { $0 == "s-1" })
        let params = reqs[2]["params"] as? [String: Any]
        let args = params?["arguments"] as? [String: Any]
        #expect(params?["name"] as? String == "search_oracle_docs")
        #expect(args?["query"] as? String == "DBMS_OUTPUT.PUT_LINE" && args?["version"] as? String == "11g" && args?["k"] as? Int == 15)
    }
}
