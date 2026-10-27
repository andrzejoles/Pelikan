import Foundation
@testable import PelikanWorkspace
import Testing

/// Czekanie na procesy bez `waitUntilExit()` (D182): koniec, limit czasu z zatrzymaniem, wyjście ponad bufor potoku.
@Suite("Czekanie na procesy")
struct ProcessWaitingTests {
    func process(_ script: String) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        return p
    }

    @Test("koniec procesu: kod wyjścia, w wątku i asynchronicznie")
    func exits() async throws {
        let a = process("exit 3")
        try a.run()
        #expect(a.waitForExit(timeout: 10))
        #expect(a.terminationStatus == 3)
        let b = process("sleep 0.1; exit 4")
        try b.run()
        #expect(await b.waitForExitAsync(timeout: 10))
        #expect(b.terminationStatus == 4)
    }

    @Test("limit czasu: proces zatrzymany, wynik false — także gdy ignoruje SIGTERM")
    func timeout() async throws {
        let a = process("sleep 30")
        try a.run()
        let start = Date()
        #expect(!a.waitForExit(timeout: 0.2))
        #expect(!a.isRunning)
        #expect(Date().timeIntervalSince(start) < 5)
        let b = process("trap '' TERM; sleep 30")
        try b.run()
        #expect(!(await b.waitForExitAsync(timeout: 0.2)))
        #expect(!b.isRunning)   // SIGKILL po 5 s
    }

    @Test("anulowanie zadania zatrzymuje proces")
    func cancellation() async throws {
        let p = process("sleep 30")
        try p.run()
        let task = Task { await p.waitForExitAsync() }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        #expect(await task.value == false)
        #expect(!p.isRunning)
    }

    @Test("wyjście większe niż bufor potoku (64 KiB) bez zakleszczenia; stderr osobno albo razem")
    func capture() async throws {
        let p = process("head -c 300000 /dev/zero; echo blad >&2")
        let r = try await p.runCapturingOutput(timeout: 30)
        #expect(!r.timedOut && r.status == 0)
        #expect(r.output.count == 300_000)
        let q = process("echo wynik; echo blad >&2")
        let both = try await q.runCapturingOutput(includeErrors: true, timeout: 30)
        #expect(String(decoding: both.output, as: UTF8.self).contains("blad"))
        let slow = try await process("sleep 30").runCapturingOutput(timeout: 0.2)
        #expect(slow.timedOut)
    }
}
