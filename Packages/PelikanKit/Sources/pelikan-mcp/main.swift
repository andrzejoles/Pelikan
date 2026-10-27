#if canImport(Darwin)
import Darwin
import Foundation
import PelikanBridgeKit

// pelikan-mcp — serwer MCP (stdio) uruchamiany przez CLI agenta; przekazuje wiadomości
// do Pelikana przez gniazdo Unix. Użycie: pelikan-mcp --socket <ścieżka>
signal(SIGPIPE, SIG_IGN)
do {
    let options = try Bridge.options(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)
    try Bridge.run(options)
    exit(0)
} catch {
    // stderr zamknięty przez klienta MCP: błąd zapisu pomijany (stare `write(_:)` kończyło proces wyjątkiem ObjC).
    try? FileHandle.standardError.write(contentsOf: Data("pelikan-mcp: \(error)\n".utf8))
    exit(1)
}
#else
print("pelikan-mcp działa tylko na macOS")
#endif
