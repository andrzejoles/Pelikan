#if canImport(Darwin)
import PelikanBridgeKit
import Darwin
import Foundation
import Logging
import MCP
import Synchronization

/// Deskryptor gniazda wspólny dla aktora, wątku odczytu i kolejki zapisu. Zamyka go tylko kolejka zapisu, po zapisach
/// już przyjętych (R8-06): wcześniej `disconnect` zamykał deskryptor od razu, a wątek odczytu albo czekający zapis mogły
/// trafić w ten sam numer przydzielony już gniazdu innego mostu.
final class SocketHandle: Sendable {
    let fd: Int32
    /// closing — po `shutdown`, nowe zapisy odrzucane; closed — deskryptor zamknięty.
    private let state = Mutex<(closing: Bool, closed: Bool)>((false, false))

    init(fd: Int32) { self.fd = fd }

    var isClosing: Bool { state.withLock { $0.closing } }

    /// Kończy ruch w obu kierunkach (wątek odczytu dostaje EOF); deskryptor zostaje otwarty do `close`.
    func shutdownBoth() {
        state.withLock { s in
            if !s.closing, !s.closed { _ = Darwin.shutdown(fd, SHUT_RDWR) }
            s.closing = true
        }
    }

    func close() {
        state.withLock { s in
            if !s.closed { _ = Darwin.close(fd) }
            s.closing = true
            s.closed = true
        }
    }
}

/// Żądania klienta (JSON-RPC z `id` i `method`), na które aplikacja nie wysłała jeszcze odpowiedzi. Po EOF od mostu
/// (klient zamknął wejście) transport czeka z zamknięciem, aż odpowiedzi w toku wyjdą — symetrycznie do mostu (R8-11).
final class PendingRequests: Sendable {
    private let ids = Mutex<Set<String>>([])

    var isEmpty: Bool { ids.withLock { $0.isEmpty } }

    func received(_ frame: Data) {
        let keys = Self.requestIDs(frame)
        if !keys.isEmpty { ids.withLock { $0.formUnion(keys) } }
    }

    func answered(_ key: String?) {
        guard let key else { return }
        _ = ids.withLock { $0.remove(key) }
    }

    /// Klucz identyfikatora JSON-RPC (liczba albo tekst).
    static func key(_ id: Any?) -> String? {
        if let s = id as? String { return "s:" + s }
        if let n = id as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return "n:\(n.int64Value)" }
        return nil
    }

    static func requestIDs(_ frame: Data) -> [String] {
        let object = try? JSONSerialization.jsonObject(with: frame)
        let items = (object as? [Any]) ?? [object as Any]
        return items.compactMap { item in
            guard let o = item as? [String: Any], o["method"] is String else { return nil }
            return key(o["id"])
        }
    }

    /// Identyfikator odpowiedzi wysyłanej przez serwer MCP (klucze posortowane: `{"id":…,"jsonrpc":"2.0","result":…`).
    /// Duże wyniki rozpoznawane po początku ramki, bez parsowania całości; błędy (`{"error":…`) są małe.
    static func responseID(_ frame: Data) -> String? {
        let head = String(decoding: frame.prefix(512), as: UTF8.self)
        if let m = head.firstMatch(of: #/^\{"id":("(?:[^"\\]|\\.)*"|-?[0-9]+),"jsonrpc":"2\.0","result":/#),
           let id = (try? JSONSerialization.jsonObject(with: Data("[\(m.1)]".utf8)) as? [Any])?.first {
            return key(id)
        }
        guard frame.count <= 256 * 1024, let o = (try? JSONSerialization.jsonObject(with: frame)) as? [String: Any],
              o["method"] == nil, o["result"] != nil || o["error"] != nil else { return nil }
        return key(o["id"])
    }
}

/// Transport MCP po stronie aplikacji: ramki gniazda ⇄ wiadomości JSON-RPC.
public actor SocketTransport: Transport {
    public nonisolated let logger = Logger(label: "pelikan.agent.transport")
    private let socket: SocketHandle
    private let stream: AsyncThrowingStream<Data, any Swift.Error>
    private let continuation: AsyncThrowingStream<Data, any Swift.Error>.Continuation
    private let writeQueue = DispatchQueue(label: "pelikan.agent.write")
    private var started = false
    private var closed = false
    private let onClose: @Sendable () -> Void
    private let pending = PendingRequests()
    /// Najdłuższe czekanie na odpowiedzi w toku po EOF od mostu.
    private let drainTimeout: TimeInterval

    /// Diagnostyka: PELIKAN_MCP_TRACE=<plik> zapisuje wiadomości MCP (bez tokenu — token idzie tylko w hello).
    static let traceFile: String? = ProcessInfo.processInfo.environment["PELIKAN_MCP_TRACE"]

    static func trace(_ direction: String, _ data: Data) {
        guard let path = traceFile else { return }
        let line = Data("\(direction) \(String(decoding: data.prefix(4000), as: UTF8.self))\n".utf8)
        if let h = FileHandle(forWritingAtPath: path) {
            // Nowe API zgłasza błąd zapisu (pełny dysk) jako błąd Swift — stare `write(_:)` rzucało wyjątek ObjC (awaria).
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: line)
        } else {
            // Ślad zawiera wyniki zapytań — tylko dla właściciela.
            FileManager.default.createFile(atPath: path, contents: line, attributes: [.posixPermissions: 0o600])
        }
    }

    /// Klienci MCP deklarują możliwości z nowszych wersji specyfikacji (np. Codex:
    /// `elicitation: {form, url}`), których SDK nie dekoduje. Serwer Pelikana nie korzysta
    /// z możliwości klienta, więc w `initialize` zastępujemy je pustym obiektem.
    static func normalizeIncoming(_ frame: Data) -> Data {
        guard frame.count < 64 * 1024,
              var object = (try? JSONSerialization.jsonObject(with: frame)) as? [String: Any],
              object["method"] as? String == "initialize",
              var params = object["params"] as? [String: Any]
        else { return frame }
        params["capabilities"] = [String: Any]()
        object["params"] = params
        return (try? JSONSerialization.data(withJSONObject: object)) ?? frame
    }

    public init(fd: Int32, drainTimeout: TimeInterval = 30, onClose: @escaping @Sendable () -> Void = {}) {
        socket = SocketHandle(fd: fd)
        self.drainTimeout = drainTimeout
        self.onClose = onClose
        (stream, continuation) = AsyncThrowingStream.makeStream()
    }

    public func connect() async throws {
        guard !started else { return }
        started = true
        let socket = socket, continuation = continuation, onClose = onClose, writeQueue = writeQueue
        let pending = pending, drainTimeout = drainTimeout
        let reader = Thread {
            while true {
                do {
                    let frame = try Wire.readFrame(from: socket.fd)
                    SocketTransport.trace("→", frame)
                    pending.received(frame)
                    continuation.yield(SocketTransport.normalizeIncoming(frame))
                } catch {
                    continuation.finish()
                    // EOF: most zamknął tylko swoją stronę zapisu — odpowiedzi na żądania w toku jeszcze wysyłamy, zanim
                    // zamkniemy gniazdo i serwer MCP (`onClose` → `server.stop()`). Rozłączenie przerywa czekanie.
                    if error as? Wire.Error == .closed {
                        let deadline = Date().addingTimeInterval(drainTimeout)
                        while !pending.isEmpty, !socket.isClosing, Date() < deadline { usleep(20_000) }
                    }
                    // Jedyny właściciel zamknięcia: po wyjściu z pętli odczytu i po zapisach już w kolejce.
                    socket.shutdownBoth()
                    writeQueue.async { socket.close() }
                    onClose()
                    return
                }
            }
        }
        reader.name = "pelikan.agent.read"
        reader.start()
    }

    public func disconnect() async {
        guard !closed else { return }
        closed = true
        socket.shutdownBoth()
        // Bez wątku odczytu deskryptor zamyka kolejka zapisu tutaj; inaczej zrobi to wątek odczytu po EOF.
        if !started { let socket = socket; writeQueue.async { socket.close() } }
        continuation.finish()
    }

    /// Wiadomość mieszcząca się w ramce mostu: odpowiedź większa niż `Wire.maxFrame` zerwałaby połączenie MCP (most
    /// odrzuca taką ramkę), więc zastępuje ją błąd JSON-RPC dla tego samego żądania. Wyniki narzędzi przycina wcześniej
    /// `AgentController.limitedContent` — to zabezpieczenie dla pozostałych wiadomości. nil — nie da się zastąpić.
    static func fittingFrame(_ data: Data) -> Data? {
        guard data.count > Wire.maxFrame else { return data }
        let head = String(decoding: data.prefix(512), as: UTF8.self)
        guard let m = head.firstMatch(of: #/^\{"id":("(?:[^"\\]|\\.)*"|-?[0-9]+),/#) else { return nil }
        return Data(#"{"error":{"code":-32603,"message":"result_too_large: odpowiedź (\#(data.count) bajtów) przekracza limit kanału MCP (\#(Wire.maxFrame) bajtów)"},"id":\#(m.1),"jsonrpc":"2.0"}"#.utf8)
    }

    public func send(_ data: Data) async throws {
        guard !closed else { throw MCPError.connectionClosed }
        let socket = socket, pending = pending
        SocketTransport.trace("←", data)
        let answers = PendingRequests.responseID(data)
        guard let data = Self.fittingFrame(data) else {
            pending.answered(answers)
            throw MCPError.internalError("frame too large")
        }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Swift.Error>) in
            writeQueue.async {
                defer { pending.answered(answers) }
                guard !socket.isClosing else { c.resume(throwing: MCPError.connectionClosed); return }
                do {
                    try Wire.writeFrame(data, to: socket.fd)
                    c.resume()
                } catch {
                    c.resume(throwing: error)
                }
            }
        }
    }

    public func receive() -> AsyncThrowingStream<Data, any Swift.Error> { stream }
}
#endif
