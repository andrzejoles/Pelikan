import Foundation

/// Polecenie systemu z Command Window (HOST, `!`, `$`; PD-CMDW-008): /bin/sh -c bez dziedziczenia zmiennych Pelikana,
/// wyjście (stdout i stderr) do okna, limit czasu. Wykonanie poza głównym aktorem — interfejs nie zamarza, a anulowanie
/// zadania (Przerwij) kończy całą grupę procesów polecenia.
public enum HostCommand {
    public struct Result: Sendable { public var status: Int32; public var output: String }

    /// Wyjście zbierane w wątku potoku, odczytywane po zakończeniu procesu.
    final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var eof = false
        private var stop = false
        func append(_ d: Data) { lock.withLock { if d.isEmpty { eof = true } else { data.append(d) } } }
        var finished: Bool { lock.withLock { eof } }
        var output: Data { lock.withLock { data } }
        /// Koniec odczytu na żądanie (wnuk w tle trzyma potok); wątek kończy się przy najbliższym `poll`.
        func requestStop() { lock.withLock { stop = true } }
        var stopRequested: Bool { lock.withLock { stop } }
    }

    /// Odczyt potoku w osobnym wątku przez `poll`/`read`; uchwyt zamyka tylko ten wątek (zamknięcie z innego wątku
    /// w trakcie odczytu to wyjątek NSFileHandle).
    static func startReading(_ handle: FileHandle, into collector: Collector) {
        Thread.detachNewThread {
            let fd = handle.fileDescriptor
            var buffer = [UInt8](repeating: 0, count: 65_536)
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            while !collector.stopRequested {
                let r = poll(&pfd, 1, 50)
                if r < 0 { if errno == EINTR { continue } else { break } }
                if r == 0 { continue }
                let n = read(fd, &buffer, buffer.count)
                if n > 0 { collector.append(Data(buffer[0..<n])) }
                else if n == 0 { break }
                else if errno != EINTR && errno != EAGAIN { break }
            }
            collector.append(Data())
            try? handle.close()
        }
    }

    public static func run(_ command: String, directory: URL?, timeout: TimeInterval = 120) async throws -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        if let directory { p.currentDirectoryURL = directory }
        // Środowisko bez zmiennych Pelikana (np. TNS_ADMIN katalogu zarządzanego, tokenów agentów).
        p.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("PELIKAN_") && $0.key != "TNS_ADMIN" }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        let collector = Collector()
        let handle = pipe.fileHandleForReading
        do { try p.run() } catch { try? handle.close(); throw error }
        startReading(handle, into: collector)
        // Koniec odczytu: proces wnuk (np. `cmd &`) trzymający potok nie blokuje końca polecenia.
        func closePipe() { collector.requestStop() }
        // Process uruchamia polecenie we własnej grupie procesów (pgid = pid) — sygnał do grupy kończy też wnuki.
        let group = p.processIdentifier
        let deadline = ContinuousClock.now + .seconds(timeout)
        while p.isRunning {
            if Task.isCancelled || ContinuousClock.now >= deadline {
                kill(-group, SIGTERM)
                for _ in 0..<20 where p.isRunning { usleep(50_000) }
                if p.isRunning { kill(-group, SIGKILL) }
                closePipe()
                if Task.isCancelled { throw SQLPlusError(L10n.tr("Polecenie systemu przerwane")) }
                throw SQLPlusError(L10n.tr("Polecenie systemu przekroczyło limit \(Int(timeout)) s i zostało przerwane"))
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        // Reszta wyjścia po zakończeniu powłoki (krótko — wnuk w tle może trzymać potok bez końca).
        for _ in 0..<20 where !collector.finished { try? await Task.sleep(for: .milliseconds(25)) }
        closePipe()
        return Result(status: p.terminationStatus, output: String(decoding: collector.output, as: UTF8.self))
    }
}
