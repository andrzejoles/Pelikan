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

    /// Diagnostyka: PELIKAN_MCP_TRACE=<plik> zapisuje wiadomości MCP (bez tokenu — token idzie tylko w hello).
    static let traceFile: String? = ProcessInfo.processInfo.environment["PELIKAN_MCP_TRACE"]

    static func trace(_ direction: String, _ data: Data) {
        guard let path = traceFile else { return }
        let line = Data("\(direction) \(String(decoding: data.prefix(4000), as: UTF8.self))\n".utf8)
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(line)
            h.closeFile()
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

    public init(fd: Int32, onClose: @escaping @Sendable () -> Void = {}) {
        socket = SocketHandle(fd: fd)
        self.onClose = onClose
        (stream, continuation) = AsyncThrowingStream.makeStream()
    }

    public func connect() async throws {
        guard !started else { return }
        started = true
        let socket = socket, continuation = continuation, onClose = onClose, writeQueue = writeQueue
        let reader = Thread {
            while true {
                do {
                    let frame = try Wire.readFrame(from: socket.fd)
                    SocketTransport.trace("→", frame)
                    continuation.yield(SocketTransport.normalizeIncoming(frame))
                } catch {
                    // Jedyny właściciel zamknięcia: po wyjściu z pętli odczytu i po zapisach już w kolejce.
                    socket.shutdownBoth()
                    writeQueue.async { socket.close() }
                    continuation.finish()
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

    public func send(_ data: Data) async throws {
        guard !closed else { throw MCPError.connectionClosed }
        let socket = socket
        SocketTransport.trace("←", data)
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Swift.Error>) in
            writeQueue.async {
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
