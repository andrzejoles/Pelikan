#if canImport(Darwin)
import Darwin
import Foundation
import PelikanBridgeKit

// pelikan-mcp — serwer MCP (stdio) uruchamiany przez CLI agenta; przekazuje wiadomości
// do Pelikana przez gniazdo Unix. Użycie: pelikan-mcp --socket <ścieżka>
//
// `pelikan-mcp --exec <program> [argumenty…]` — start powłoki agenta w terminalu: zamyka wszystkie deskryptory powyżej
// 2 odziedziczone po aplikacji (forkpty+execve terminala ich nie zamyka — połączenia z bazą, potoki `ssh`, gniazdo
// agentów) i zastępuje się programem (ten sam proces — PID dla kontroli pochodzenia mostu się nie zmienia).
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == Bridge.execFlag {
    Bridge.closeInheritedDescriptors()
    let program = CommandLine.arguments[2]
    let argv = CommandLine.arguments[2...].map { strdup($0) } + [nil]
    execv(program, argv)
    try? FileHandle.standardError.write(contentsOf: Data("pelikan-mcp: nie można uruchomić \(program): \(String(cString: strerror(errno)))\n".utf8))
    exit(127)
}
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
