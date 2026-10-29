#if canImport(Darwin)
import Darwin
import Foundation
import PelikanRemote
import PelikanWorkspace

/// Wynik jednego sprawdzenia „Testuj”.
public struct SSHTestCheck: Sendable, Hashable, Identifiable {
    public enum Status: String, Sendable, Hashable { case ok, warning, failed }
    public var title: String
    public var status: Status
    public var detail: String
    public var id: String { title }
}

/// Stan katalogu na serwerze.
public enum RemoteDirectoryState: String, Sendable, Hashable { case writable, readOnly, missing }

/// „Testuj” dla celu SSH (zadanie Pro*C): system, wersja serwera SSH, `make`, `git`, gałąź i czystość working copy,
/// `compress`/`gzip`, katalogi bazowy, `src`, `bin` i backupów. Polecenia ksh88: `cd` zamiast `git -C`, `LC_ALL=C`
/// dla parsowanych wyników, kod wyjścia sprawdzany jawnie, wartości przez `shellQuote`.
public enum SSHTargetTester {
    /// Konfiguracja sesji `ssh` dla celu (`configFile`/`knownHostsFile` — testy na lokalnym sshd).
    public static func sessionConfig(_ t: PelikanSSHTarget, configFile: String? = nil, knownHostsFile: String? = nil) -> SSHSession.Config {
        SSHSession.Config(host: t.host, port: t.port == 22 ? nil : t.port, user: t.user, keyFile: t.auth == .keyFile ? t.keyFile : "",
                          legacyAlgorithms: t.legacyAlgorithms, encoding: t.nameEncoding, configFile: configFile, knownHostsFile: knownHostsFile)
    }

    /// Baner serwera SSH (`SSH-2.0-OpenSSH_5.8…`) z gniazda TCP — przed logowaniem, bez sekretów. `timeout` — łączny
    /// limit na połączenie (wszystkie adresy z `getaddrinfo`) i osobno na odczyt baneru.
    public static func serverBanner(host: String, port: Int, timeout: TimeInterval = 5) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0, ai_addrlen: 0,
                             ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &res) == 0, let first = res else { return nil }
        defer { freeaddrinfo(res) }
        var ai: UnsafeMutablePointer<addrinfo>? = first
        while let a = ai {
            let fd = socket(a.pointee.ai_family, a.pointee.ai_socktype, a.pointee.ai_protocol)
            if fd >= 0 {
                var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - timeout.rounded(.down)) * 1_000_000))
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                var on: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                if connect(fd, a.pointee.ai_addr, a.pointee.ai_addrlen, until: deadline) {
                    var buf = [UInt8](repeating: 0, count: 512)
                    let n = read(fd, &buf, buf.count)
                    close(fd)
                    guard n > 0 else { return nil }
                    let text = String(decoding: buf[0..<n], as: UTF8.self)
                    return text.split(whereSeparator: \.isNewline).first { $0.hasPrefix("SSH-") }.map { String($0).trimmingCharacters(in: .whitespaces) }
                }
                close(fd)
            }
            ai = a.pointee.ai_next
        }
        return nil
    }

    /// `connect` z limitem: gniazdo nieblokujące i `poll` — SO_SNDTIMEO na Darwinie nie ogranicza blokującego `connect`
    /// (host „czarna dziura” za zaporą bez RST: ok. 75 s na adres). Po połączeniu gniazdo wraca do trybu blokującego.
    static func connect(_ fd: Int32, _ address: UnsafeMutablePointer<sockaddr>?, _ length: socklen_t, until deadline: Date) -> Bool {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { return false }
        defer { _ = fcntl(fd, F_SETFL, flags) }
        if Darwin.connect(fd, address, length) == 0 { return true }
        guard errno == EINPROGRESS || errno == EINTR else { return false }
        var p = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        while true {
            let ms = Int32(min(max(deadline.timeIntervalSinceNow * 1000, 0), Double(Int32.max)))
            guard ms > 0 else { return false }
            let r = poll(&p, 1, ms)
            if r < 0, errno == EINTR { continue }
            guard r > 0 else { return false }
            var error: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            return getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0 && error == 0
        }
    }

    static func q(_ s: String) -> String { SSHSession.shellQuote(s) }

    static func text(_ r: Spawn.Result, _ enc: NameEncoding) -> String {
        (String(data: r.output, encoding: enc.encoding) ?? String(decoding: r.output, as: UTF8.self)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Polecenie sprawdzające katalog (`W` zapisywalny, `R` tylko do odczytu, `M` brak) — test(1) z ksh88.
    static func directoryCommand(_ path: String) -> String {
        "if [ -d \(q(path)) ]; then if [ -w \(q(path)) ]; then echo W; else echo R; fi; else echo M; fi"
    }

    public static func directoryState(_ path: String, session: SSHSession) throws -> RemoteDirectoryState {
        switch text(try session.run(directoryCommand(path), timeout: 30), session.config.encoding) {
        case "W": .writable
        case "R": .readOnly
        default: .missing
        }
    }

    /// Wszystkie sprawdzenia; pierwszy błąd logowania przerywa (wtedy jedno sprawdzenie z przyczyną).
    public static func run(_ t: PelikanSSHTarget, session: SSHSession) -> [SSHTestCheck] {
        var checks: [SSHTestCheck] = []
        let enc = t.nameEncoding
        if let banner = serverBanner(host: t.host, port: t.port) {
            checks.append(SSHTestCheck(title: L10n.tr("Serwer SSH"), status: .ok, detail: banner))
        } else {
            checks.append(SSHTestCheck(title: L10n.tr("Serwer SSH"), status: .warning, detail: L10n.tr("Nie odczytano wersji serwera")))
        }
        // Klucz nowego serwera zapisuje wcześniej interfejs po potwierdzeniu odcisku (`trustHostKeys`) — nieznany
        // serwer kończy się tu błędem logowania, bez zaufania po cichu.
        do {
            try session.connect()
        } catch {
            checks.append(SSHTestCheck(title: L10n.tr("Logowanie"), status: .failed, detail: describe(error)))
            return checks
        }
        checks.append(SSHTestCheck(title: L10n.tr("Logowanie"), status: .ok, detail: "\(t.user)@\(t.host)"))
        func simple(_ title: String, _ command: String, required: Bool) {
            do {
                let r = try session.run(command, timeout: 30)
                let out = text(r, enc)
                if r.status == 0, !out.isEmpty {
                    checks.append(SSHTestCheck(title: title, status: .ok, detail: out))
                } else {
                    checks.append(SSHTestCheck(title: title, status: required ? .failed : .warning, detail: out.isEmpty ? r.errorText : out))
                }
            } catch {
                checks.append(SSHTestCheck(title: title, status: .failed, detail: describe(error)))
            }
        }
        simple("uname -a", "uname -a", required: true)
        simple("oslevel -s", "oslevel -s 2>/dev/null", required: false)
        simple("make", "which make", required: true)
        simple("git --version", "git --version", required: true)
        simple("compress", "which compress", required: false)
        simple("gzip", "which gzip", required: false)
        // Working copy: gałąź (porównanie dokładne) i czystość — bez `git -C` (git 1.8.5+).
        do {
            let wc = t.effectiveWorkingCopy
            let r = try session.run("LC_ALL=C; export LC_ALL; cd \(q(wc)) || exit 3; git rev-parse --abbrev-ref HEAD || exit 4; echo @@STATUS; git status --porcelain || exit 5",
                                    timeout: 60)
            let out = text(r, enc)
            if r.status != 0 {
                checks.append(SSHTestCheck(title: L10n.tr("Kopia robocza"), status: .failed,
                                           detail: L10n.tr("\(wc): kod \(r.status) \(r.errorText)")))
            } else {
                let parts = out.components(separatedBy: "@@STATUS")
                let branch = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let status = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                checks.append(SSHTestCheck(title: L10n.tr("Gałąź"), status: branch == t.branch ? .ok : .warning,
                                           detail: branch == t.branch ? branch : L10n.tr("\(branch) (oczekiwana \(t.branch))")))
                checks.append(SSHTestCheck(title: L10n.tr("Czystość kopii roboczej"), status: status.isEmpty ? .ok : .warning,
                                           detail: status.isEmpty ? L10n.tr("bez zmian") : status))
            }
        } catch {
            checks.append(SSHTestCheck(title: L10n.tr("Kopia robocza"), status: .failed, detail: describe(error)))
        }
        for (title, path) in [(L10n.tr("Katalog bazowy"), t.baseDirectory), (L10n.tr("Katalog src"), t.sourceDirectory),
                              (L10n.tr("Katalog bin"), t.binaryDirectory), (L10n.tr("Katalog kopii zapasowych"), t.backupDirectory)] {
            do {
                switch try directoryState(path, session: session) {
                case .writable: checks.append(SSHTestCheck(title: title, status: .ok, detail: path))
                case .readOnly: checks.append(SSHTestCheck(title: title, status: .failed, detail: L10n.tr("\(path) — brak prawa zapisu")))
                case .missing: checks.append(SSHTestCheck(title: title, status: .failed, detail: L10n.tr("\(path) — nie istnieje")))
                }
            } catch {
                checks.append(SSHTestCheck(title: title, status: .failed, detail: describe(error)))
            }
        }
        return checks
    }

    /// Utworzenie katalogu backupów (po potwierdzeniu w interfejsie).
    public static func createBackupDirectory(_ t: PelikanSSHTarget, session: SSHSession) throws {
        let r = try session.run("mkdir -p \(q(t.backupDirectory)) && mkdir -p \(q(t.pelikanDirectory))", timeout: 30)
        guard r.status == 0 else { throw SSHError.io(code: r.status, detail: r.errorText) }
    }

    /// Tekst błędu SSH dla użytkownika (warstwa interfejsu — D61).
    public static func describe(_ error: any Error) -> String {
        guard let e = error as? SSHError else { return error.localizedDescription }
        switch e {
        case .negotiationFailed: return L10n.tr("Brak wspólnych algorytmów z serwerem — włącz „Stare algorytmy” (np. AIX 6.1)")
        case .permissionDenied: return L10n.tr("Odmowa dostępu — sprawdź użytkownika, klucz albo hasło")
        case .hostKeyChanged: return L10n.tr("Klucz serwera inny niż zapamiętany w known_hosts — możliwa podmiana serwera; sprawdź z administratorem")
        case .hostKeyUnknown: return L10n.tr("Nieznany klucz serwera — sprawdź cel (Testuj) w definicji i potwierdź odcisk klucza")
        case .timeout: return L10n.tr("Przekroczony limit czasu")
        case .cancelled: return L10n.tr("Przerwano")
        case .io(_, let detail): return detail
        case .invalidName(let n): return L10n.tr("Niedozwolona nazwa: \(n)")
        case .unencodable(let s): return L10n.tr("Tekstu nie da się zapisać w kodowaniu serwera: \(s)")
        }
    }
}
#endif
