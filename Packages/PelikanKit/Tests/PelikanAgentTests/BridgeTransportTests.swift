#if canImport(Darwin)
import Darwin
import Foundation
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
#endif
