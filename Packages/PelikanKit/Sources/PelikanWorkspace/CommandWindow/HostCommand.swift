import Foundation

/// Polecenie systemu z Command Window (HOST, `!`, `$`; PD-CMDW-008): /bin/sh -c bez dziedziczenia zmiennych Pelikana,
/// wyjście (stdout i stderr) do okna, limit czasu.
public enum HostCommand {
    public struct Result: Sendable { public var status: Int32; public var output: String }

    public static func run(_ command: String, directory: URL?, timeout: TimeInterval = 120) throws -> Result {
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
        try p.run()
        final class Buffer: @unchecked Sendable { var data = Data() }   // zapis w wątku czytającym, odczyt po semaforze
        let buffer = Buffer()
        let reader = DispatchQueue(label: "pelikan.host.read")
        let done = DispatchSemaphore(value: 0)
        let handle = pipe.fileHandleForReading
        reader.async {
            buffer.data = handle.readDataToEndOfFile()
            done.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            _ = done.wait(timeout: .now() + 2)
            throw SQLPlusError(L10n.tr("Polecenie systemu przekroczyło limit \(Int(timeout)) s i zostało przerwane"))
        }
        p.waitUntilExit()
        return Result(status: p.terminationStatus, output: String(decoding: buffer.data, as: UTF8.self))
    }
}
