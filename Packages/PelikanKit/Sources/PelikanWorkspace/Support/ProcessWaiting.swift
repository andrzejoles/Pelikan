import Foundation

/// Wynik procesu uruchomionego przez `Process.runCapturingOutput`.
public struct ProcessOutput: Sendable {
    public var status: Int32
    public var output: Data
    /// Przekroczony limit czasu — proces zatrzymany (SIGTERM, po 5 s SIGKILL).
    public var timedOut: Bool
}

/// Czekanie na koniec procesu bez `waitUntilExit()`: ten kręci pętlą zdarzeń bieżącego wątku — na wątku puli zadań
/// potrafił nie wrócić wcale (zawieszone testy SSH, D182), a na głównym wątku obsługuje w trakcie zdarzenia interfejsu.
/// `isRunning` Foundation odświeża bez pętli zdarzeń, więc wystarczy je sondować.
extension Process {
    /// Czeka (blokując wątek) na koniec procesu; `timeout` — po nim proces jest zatrzymywany, wynik `false`.
    /// Do kodu synchronicznego w tle (wątki GCD). Wyjście w potoku czytaj przed czekaniem albo równolegle —
    /// pełny bufor potoku (64 KiB) zatrzymałby proces.
    @discardableResult
    public func waitForExit(timeout: TimeInterval? = nil) -> Bool {
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        while isRunning {
            if let deadline, Date() > deadline {
                stop { usleep(10_000) }
                return false
            }
            usleep(10_000)
        }
        return true
    }

    /// Czeka na koniec procesu bez blokowania wątku. Po `timeout` albo anulowaniu zadania proces jest zatrzymywany
    /// (SIGTERM, po 5 s SIGKILL), wynik `false`.
    @discardableResult
    public func waitForExitAsync(timeout: TimeInterval? = nil) async -> Bool {
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        while isRunning {
            if Task.isCancelled || deadline.map({ Date() > $0 }) == true {
                terminate()
                for step in 0..<1000 where isRunning {
                    if step == 500 { kill(processIdentifier, SIGKILL) }
                    await Self.pause()
                }
                return false
            }
            await Self.pause()
        }
        return true
    }

    /// Uruchamia proces z wyjściem w potoku czytanym równolegle (pełny bufor nie zatrzyma procesu) i czeka na koniec —
    /// najwyżej `timeout` sekund. `includeErrors` — stderr w tym samym potoku, inaczej /dev/null.
    public func runCapturingOutput(includeErrors: Bool = false, timeout: TimeInterval? = nil) async throws -> ProcessOutput {
        let pipe = Pipe()
        standardOutput = pipe
        standardError = includeErrors ? pipe : FileHandle.nullDevice
        if standardInput == nil { standardInput = FileHandle.nullDevice }
        try run()
        let handle = pipe.fileHandleForReading
        async let data: Data = withCheckedContinuation { c in
            DispatchQueue.global(qos: .utility).async { c.resume(returning: (try? handle.readToEnd()) ?? Data()) }
        }
        let exited = await waitForExitAsync(timeout: timeout)
        return ProcessOutput(status: terminationStatus, output: await data, timedOut: !exited)
    }

    /// SIGTERM, po 5 s SIGKILL; czeka najwyżej 10 s.
    private func stop(pause: () -> Void) {
        terminate()
        for step in 0..<1000 where isRunning {
            if step == 500 { kill(processIdentifier, SIGKILL) }
            pause()
        }
    }

    /// 10 ms bez blokowania wątku i bez reakcji na anulowanie (pętla zatrzymywania procesu musi się dokończyć).
    private static func pause() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(10)) { c.resume() }
        }
    }
}
