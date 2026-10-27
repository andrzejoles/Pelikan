#if canImport(Darwin)
import Darwin
import Foundation
import MCP
@testable import PelikanAgent
@testable import PelikanBridgeKit
import Testing

@Suite("Most i transport gniazda: zamykanie bez wyścigów")
struct BridgeTransportTests {
    /// Czeka (poza pulą wątków Swifta) na sygnał z innego wątku.
    func wait(_ s: DispatchSemaphore, seconds: Double = 5) async -> Bool {
        await Task.detached { Self.block(s, seconds: seconds) }.value
    }

    static func block(_ s: DispatchSemaphore, seconds: Double) -> Bool { s.wait(timeout: .now() + seconds) == .success }

    @Test("SocketTransport: deskryptor zamyka wątek odczytu po EOF; zapis po rozłączeniu odrzucony bez dotykania deskryptora")
    func transportClose() async throws {
        for peerCloses in [false, true] {
            var fds: [Int32] = [0, 0]
            #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
            let closed = DispatchSemaphore(value: 0)
            let t = SocketTransport(fd: fds[0], onClose: { closed.signal() })
            try await t.connect()
            if peerCloses {
                close(fds[1])
            } else {
                await t.disconnect()
                // Druga strona widzi koniec strumienia (shutdown), zanim deskryptor zostanie zamknięty.
                var byte: UInt8 = 0
                #expect(read(fds[1], &byte, 1) == 0)
                close(fds[1])
            }
            #expect(await wait(closed))
            await #expect(throws: (any Error).self) { try await t.send(Data("{}".utf8)) }
            await t.disconnect()
        }
    }

    @Test("SocketTransport: po EOF od mostu odpowiedź na żądanie w toku wychodzi przed zamknięciem gniazda i serwera")
    func transportDrainsAfterEOF() async throws {
        var fds: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        let closed = DispatchSemaphore(value: 0)
        let t = SocketTransport(fd: fds[0], drainTimeout: 5, onClose: { closed.signal() })
        try await t.connect()
        // Klient: żądanie i powiadomienie (bez id — nie czeka na odpowiedź), potem zamknięcie swojej strony zapisu.
        try Wire.writeFrame(Data(#"{"jsonrpc":"2.0","id":"a/1","method":"tools/list"}"#.utf8), to: fds[1])
        try Wire.writeFrame(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8), to: fds[1])
        shutdown(fds[1], SHUT_WR)
        var frames = 0
        for try await _ in await t.receive() { frames += 1 }
        #expect(frames == 2)
        #expect(!(await wait(closed, seconds: 0.3)))
        // Odpowiedź serwera MCP (klucze posortowane) — dopiero po niej transport się zamyka.
        let response = Data(#"{"id":"a\/1","jsonrpc":"2.0","result":{"tools":[]}}"#.utf8)
        try await t.send(response)
        #expect(await wait(closed))
        let peer = fds[1]
        let got = await Task.detached { try? Wire.readFrame(from: peer) }.value
        #expect(got == response)
        close(fds[1])
    }

    @Test("Identyfikatory żądań i odpowiedzi JSON-RPC: liczby, teksty, wsad, duży wynik po początku ramki")
    func pendingIDs() {
        #expect(PendingRequests.requestIDs(Data(#"{"jsonrpc":"2.0","id":7,"method":"x"}"#.utf8)) == ["n:7"])
        #expect(PendingRequests.requestIDs(Data(#"[{"id":"q","method":"x"},{"method":"n"},{"id":2,"result":{}}]"#.utf8)) == ["s:q"])
        #expect(PendingRequests.responseID(Data(#"{"id":7,"jsonrpc":"2.0","result":{}}"#.utf8)) == "n:7")
        #expect(PendingRequests.responseID(Data(#"{"error":{"code":-1,"message":"m"},"id":"q","jsonrpc":"2.0"}"#.utf8)) == "s:q")
        #expect(PendingRequests.responseID(Data(#"{"id":3,"jsonrpc":"2.0","method":"ping"}"#.utf8)) == nil)
        let big = Data(#"{"id":12,"jsonrpc":"2.0","result":{"text":""#.utf8) + Data(repeating: 0x61, count: 2_000_000) + Data(#""}}"#.utf8)
        #expect(PendingRequests.responseID(big) == "n:12")
    }

    @Test("MOD-01: wynik ponad limit ramki — przycięty ze znacznikiem; za duża odpowiedź zastąpiona błędem JSON-RPC")
    @MainActor
    func oversizedResults() throws {
        let small = AgentController.limitedContent("abc", untrusted: true)
        #expect(small.count == 1)
        let text = String(repeating: "zażółć \"gęślą\" jaźń\n", count: 200_000)
        let parts = AgentController.limitedContent(text, untrusted: true)
        // Tekst elementu treści przez JSON (wzorzec `.text(…)` koliduje z funkcjami `Content.text` z SDK).
        let texts = try parts.map { try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) as? [String: Any])["text"] as? String ?? "" }
        try #require(texts.count == 2)
        let (head, notice) = (texts[0], texts[1])
        #expect(head.utf8.count <= AgentController.maxResultBytes && text.hasPrefix(head) && !head.unicodeScalars.contains("\u{FFFD}"))
        #expect(notice.hasPrefix("result_truncated") && notice.contains("\(text.utf8.count)") && notice.contains("nie polecenia"))
        // Po podwójnym kodowaniu JSON (najgorszy przypadek: każdy bajt dwa razy) mieści się w ramce mostu.
        #expect(2 * AgentController.maxResultBytes + 4096 < Wire.maxFrame)

        #expect(SocketTransport.fittingFrame(Data("{}".utf8)) == Data("{}".utf8))
        let big = Data(#"{"id":"a\/1","jsonrpc":"2.0","result":{"text":""#.utf8) + Data(repeating: 0x61, count: Wire.maxFrame) + Data(#""}}"#.utf8)
        let replaced = try #require(SocketTransport.fittingFrame(big))
        let o = try #require(try JSONSerialization.jsonObject(with: replaced) as? [String: Any])
        #expect(o["id"] as? String == "a/1" && ((o["error"] as? [String: Any])?["message"] as? String)?.hasPrefix("result_too_large") == true)
        #expect(PendingRequests.responseID(replaced) == "s:a/1")
        #expect(SocketTransport.fittingFrame(Data(repeating: 0x20, count: Wire.maxFrame + 1)) == nil)
    }

    @Test("MOD-01: pelikan-mcp przy za dużej ramce z aplikacji kończy się z komunikatem i kodem ≠ 0")
    func bridgeReportsOversizedFrame() async throws {
        let path = "/tmp/pbt-\(UUID().uuidString.prefix(8)).sock"
        defer { unlink(path) }
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(listener) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let bytes = Array(path.utf8)
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        #expect(bound == 0 && listen(listener, 1) == 0)
        // Atrapa aplikacji: welcome, potem nagłówek ramki większej niż limit.
        let server = Thread {
            let c = accept(listener, nil, nil)
            guard c >= 0 else { return }
            defer { close(c) }
            guard (try? Wire.readFrame(from: c)) != nil,
                  (try? Wire.writeFrame(JSONEncoder().encode(Wire.Reply.welcome), to: c)) != nil else { return }
            var length = UInt32(Wire.maxFrame + 1).bigEndian
            try? Wire.writeAll(Data(bytes: &length, count: 4), to: c)
            usleep(2_000_000)
        }
        server.start()
        let client = try BridgeClient(socket: URL(fileURLWithPath: path), token: "test")
        defer { client.terminate() }
        #expect(await client.waitForExit() == 1)
        #expect(client.stderr.contains("\(Wire.maxFrame + 1)"))
    }

    @Test("pelikan-mcp: po EOF na wejściu odpowiedź aplikacji w drodze trafia jeszcze na wyjście")
    func bridgeDrainsAfterInputEOF() async throws {
        let path = "/tmp/pbt-\(UUID().uuidString.prefix(8)).sock"
        defer { unlink(path) }
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        #expect(listener >= 0)
        defer { close(listener) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let bytes = Array(path.utf8)
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        #expect(bound == 0 && listen(listener, 1) == 0)

        // Atrapa aplikacji: hello → welcome, żądanie → odpowiedź z opóźnieniem, potem zamknięcie.
        let server = Thread {
            let c = accept(listener, nil, nil)
            guard c >= 0 else { return }
            defer { close(c) }
            guard (try? Wire.readFrame(from: c)) != nil,
                  (try? Wire.writeFrame(JSONEncoder().encode(Wire.Reply.welcome), to: c)) != nil,
                  let request = try? Wire.readFrame(from: c) else { return }
            usleep(300_000)
            try? Wire.writeFrame(Data("odpowiedz:".utf8) + request, to: c)
        }
        server.start()

        var input: [Int32] = [0, 0], output: [Int32] = [0, 0]
        #expect(pipe(&input) == 0 && pipe(&output) == 0)
        try Wire.writeAll(Data("{\"id\":1}\n".utf8), to: input[1])
        close(input[1])
        let options = Bridge.Options(socketPath: path, token: "test")
        let (inFD, outFD) = (input[0], output[1])
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            try? Bridge.run(options, input: inFD, output: outFD, drainTimeout: 5, exitWhenClosed: false)
            close(outFD)
            done.signal()
        }
        #expect(await wait(done, seconds: 10))
        let readFD = output[0]
        let received = await Task.detached { () -> String in
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(readFD, &buffer, buffer.count)
                if n <= 0 { break }
                data.append(contentsOf: buffer[0..<n])
            }
            return String(decoding: data, as: UTF8.self)
        }.value
        close(input[0])
        close(output[0])
        #expect(received == "odpowiedz:{\"id\":1}\n")
    }
}

@MainActor
@Suite("Most i aplikacja: odpowiedź po zamknięciu wejścia")
struct BridgeEOFEndToEndTests {
    @Test("Klient wysyła żądanie i zamyka stdin: odpowiedź aplikacji dochodzi, most kończy się sam")
    func requestThenEOF() async throws {
        let env = try AgentEnv()
        defer { env.shutdown() }
        let (_, token) = env.session()
        let client = try BridgeClient(socket: env.socket, token: token)
        defer { client.terminate() }
        try await client.initialize()
        let r = try await client.requestThenCloseInput("tools/list")
        #expect(((r["result"] as? [String: Any])?["tools"] as? [Any])?.isEmpty == false)
        #expect(await client.waitForExit() == 0)
    }
}
#endif
