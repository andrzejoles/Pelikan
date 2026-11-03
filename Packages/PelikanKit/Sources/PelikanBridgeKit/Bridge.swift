#if canImport(Darwin)
import Darwin
import Foundation

/// Most MCP: stdio (wiadomości JSON rozdzielone znakiem nowej linii) ⇄ gniazdo Unix aplikacji.
/// Most nie interpretuje wiadomości — cała logika i polityka uprawnień są w aplikacji.
public enum Bridge {
    /// Tryb startu powłoki agenta (`pelikan-mcp --exec program …`): zamknięcie odziedziczonych deskryptorów i `execv`.
    public static let execFlag = "--exec"

    /// Zamyka deskryptory powyżej 2 (w świeżym procesie przed `execv` — nic tu ich nie używa): według listy otwartych
    /// (`proc_pidinfo` PROC_PIDLISTFDS — bez górnej granicy numerów), a gdy lista niedostępna — wszystkie do limitu.
    public static func closeInheritedDescriptors() {
        let stride = MemoryLayout<proc_fdinfo>.stride
        let needed = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, nil, 0)
        if needed > 0 {
            var infos = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 16)
            let got = infos.withUnsafeMutableBytes { proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
            if got > 0 {
                for info in infos.prefix(Int(got) / stride) where info.proc_fd > 2 { close(info.proc_fd) }
                return
            }
        }
        let limit = getdtablesize()
        if limit > 3 { for fd in 3..<limit { close(fd) } }
    }

    /// Argumenty terminala: powłoka przez `pelikan-mcp --exec`.
    public static func execArguments(shell: String, arguments: [String]) -> [String] {
        [execFlag, shell] + arguments
    }

    public static let tokenVariable = "PELIKAN_AGENT_TOKEN"
    public static let socketVariable = "PELIKAN_AGENT_SOCKET"

    public struct Options: Sendable {
        public var socketPath: String
        public var token: String

        public init(socketPath: String, token: String) {
            self.socketPath = socketPath
            self.token = token
        }
    }

    public enum Failure: Error, CustomStringConvertible {
        case missingToken
        case missingSocket
        case rejected(String)
        case connection(String)

        public var description: String {
            switch self {
            case .missingToken: "brak \(Bridge.tokenVariable) — most działa tylko w sesji agenta uruchomionej z aplikacji"
            case .missingSocket: "brak ścieżki gniazda (--socket)"
            case .rejected(let m): "aplikacja odrzuciła połączenie: \(m)"
            case .connection(let m): "nie można połączyć się z aplikacją: \(m)"
            }
        }
    }

    /// Opcje z argumentów (`--socket <ścieżka>`) i środowiska. Token: zmienna środowiskowa
    /// procesu, a jeśli CLI agenta jej nie przekazało — środowisko najbliższego przodka
    /// (proces CLI uruchomiony przez aplikację), nigdy plik ani argument.
    public static func options(arguments: [String], environment: [String: String]) throws -> Options {
        var socket = environment[socketVariable]
        if let i = arguments.firstIndex(of: "--socket"), i + 1 < arguments.count { socket = arguments[i + 1] }
        guard let socket, !socket.isEmpty else { throw Failure.missingSocket }
        if let token = environment[tokenVariable], !token.isEmpty {
            return Options(socketPath: socket, token: token)
        }
        for pid in ProcessTree.ancestry(of: getpid()).dropFirst() {
            if let token = ProcessTree.environmentValue(tokenVariable, of: pid), !token.isEmpty {
                return Options(socketPath: socket, token: token)
            }
        }
        throw Failure.missingToken
    }

    /// Opis błędu odczytu ramki z aplikacji (stderr mostu).
    static func describe(_ error: any Swift.Error) -> String {
        switch error as? Wire.Error {
        case .frameTooLarge(let n): "wiadomość z aplikacji ma \(n) bajtów — więcej niż limit \(Wire.maxFrame); połączenie z aplikacją przerwane"
        case .io(let e): "błąd odczytu z gniazda aplikacji (errno \(e))"
        default: "błąd odczytu z gniazda aplikacji (\(error))"
        }
    }

    /// Łączy się, przechodzi uzgadnianie i przekazuje dane do końca jednego ze strumieni. Po EOF na wejściu czeka
    /// (najwyżej `drainTimeout`), aż aplikacja zamknie swoją stronę — odpowiedzi w drodze trafiają jeszcze na wyjście
    /// (R8-11: `echo … | pelikan-mcp` kończył się przed odpowiedzią). `exitWhenClosed` — zamknięcie gniazda przez
    /// aplikację kończy proces mostu (także gdy wejście jest jeszcze otwarte); testy wyłączają.
    public static func run(_ options: Options, input: Int32 = STDIN_FILENO, output: Int32 = STDOUT_FILENO,
                           drainTimeout: TimeInterval = 30, exitWhenClosed: Bool = true) throws {
        let fd: Int32
        do {
            fd = try Wire.connect(path: options.socketPath)
        } catch {
            throw Failure.connection("\(error)")
        }
        defer { close(fd) }

        let hello = Wire.Hello(token: options.token, pid: getpid())
        try Wire.writeFrame(JSONEncoder().encode(hello), to: fd)
        Wire.setReadTimeout(fd, seconds: 10)
        let replyData: Data
        do {
            replyData = try Wire.readFrame(from: fd)
        } catch {
            throw Failure.rejected("brak odpowiedzi (\(error))")
        }
        let reply = try JSONDecoder().decode(Wire.Reply.self, from: replyData)
        guard reply.type == "welcome" else { throw Failure.rejected(reply.message ?? "?") }
        Wire.setReadTimeout(fd, seconds: 0)

        // gniazdo → stdout
        let drained = DispatchSemaphore(value: 0)
        let socketToStdout = Thread {
            var failure: String?
            while true {
                let frame: Data
                do {
                    frame = try Wire.readFrame(from: fd)
                } catch {
                    // Koniec strumienia — aplikacja zamknęła sesję. Inny błąd (np. za duża ramka — strumień jest wtedy
                    // rozsynchronizowany) kończy most z komunikatem i kodem ≠ 0, żeby CLI agenta i użytkownik znali przyczynę.
                    if error as? Wire.Error != .closed { failure = Self.describe(error) }
                    break
                }
                var line = frame
                line.append(0x0A)
                if (try? Wire.writeAll(line, to: output)) == nil { break }
            }
            // `write(contentsOf:)` zgłasza błąd Swift przy zamkniętym stderr (stare `write(_:)` rzucało wyjątek ObjC — awaria).
            if let failure { try? FileHandle.standardError.write(contentsOf: Data("pelikan-mcp: \(failure)\n".utf8)) }
            drained.signal()
            // Aplikacja zamknęła sesję — kończymy proces mostu.
            if exitWhenClosed { exit(failure == nil ? 0 : 1) }
        }
        socketToStdout.start()

        // stdin → gniazdo (linie)
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = read(input, &chunk, chunk.count)
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { break }
            buffer.append(chunk, count: n)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                let trimmed = line.filter { $0 != 0x0D }
                if trimmed.isEmpty { continue }
                // Każda linia (także zakończona w tym samym kawałku) — za długiej aplikacja nie przyjmie.
                if trimmed.count > Wire.maxFrame { throw Failure.connection("za długa wiadomość") }
                try Wire.writeFrame(Data(trimmed), to: fd)
            }
            if buffer.count > Wire.maxFrame { throw Failure.connection("za długa wiadomość") }
        }
        shutdown(fd, SHUT_WR)
        _ = drained.wait(timeout: .now() + drainTimeout)
    }
}
#endif
