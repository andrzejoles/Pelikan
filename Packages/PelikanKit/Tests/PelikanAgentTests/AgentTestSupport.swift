#if canImport(Darwin)
import Foundation
import PelikanBridgeKit
@testable import PelikanAgent
@testable import PelikanWorkspace

/// Atrapa okna zatwierdzania.
@MainActor
final class MockApprover: ApprovalPresenter {
    var answer = true
    var requests: [ApprovalRequest] = []
    func requestApproval(_ request: ApprovalRequest) async -> Bool {
        requests.append(request)
        return answer
    }
}

/// Środowisko testu kanału: model bez bazy i bez katalogu danych, serwer na krótkiej ścieżce gniazda.
@MainActor
struct AgentEnv {
    let workspace: Workspace
    let controller: AgentController
    let approver: MockApprover
    let socket: URL
    let runDir: URL
    let logDir: URL

    init() throws {
        // Ścieżka gniazda musi być krótka (limit sun_path = 104 bajty).
        runDir = URL(fileURLWithPath: "/tmp/pat-\(UUID().uuidString.prefix(8))", isDirectory: true)
        socket = runDir.appendingPathComponent("agent.sock")
        logDir = runDir.appendingPathComponent("logs", isDirectory: true)
        workspace = Workspace()
        controller = AgentController(workspace: workspace, socketURL: socket, logDirectory: logDir)
        approver = MockApprover()
        controller.approvals = approver
        try controller.start()
    }

    func shutdown() {
        controller.stop()
        try? FileManager.default.removeItem(at: runDir)
    }

    /// Sesja, której „procesem CLI” jest proces testów (most jest jego potomkiem).
    func session(cliPID: pid_t = getpid()) -> (AgentSession, String) {
        let (s, token) = controller.createSession(profile: AgentProfile.builtIn[0], directory: runDir.path)
        s.cliPID = cliPID
        return (s, token)
    }
}

/// Ścieżka zbudowanego mostu `pelikan-mcp` (obok pakietu testów).
func bridgeExecutable() -> URL {
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
        let candidate = bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("pelikan-mcp")
        if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    for sub in [".build/debug/pelikan-mcp", ".build/arm64-apple-macosx/debug/pelikan-mcp"] {
        let c = root.appendingPathComponent(sub)
        if FileManager.default.isExecutableFile(atPath: c.path) { return c }
    }
    return root.appendingPathComponent(".build/debug/pelikan-mcp")
}

/// Klient MCP przez prawdziwy proces mostu (stdio JSON-RPC).
final class BridgeClient: @unchecked Sendable {
    let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private var nextID = 1
    private var buffer = Data()

    init(socket: URL, token: String?) throws {
        process.executableURL = bridgeExecutable()
        process.arguments = ["--socket", socket.path]
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: Bridge.tokenVariable)
        if let token { env[Bridge.tokenVariable] = token }
        process.environment = env
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
    }

    var stderr: String {
        String(decoding: errors.fileHandleForReading.availableData, as: UTF8.self)
    }

    func waitForExit(timeout: Double = 8) async -> Int32? {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        return process.isRunning ? nil : process.terminationStatus
    }

    func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    /// Wysyła żądanie i czeka (poza głównym aktorem) na odpowiedź o tym samym id.
    func request(_ method: String, _ params: [String: Any] = [:], timeout: Double = 10) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        try send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let line = try await readLine(), let obj = try JSONSerialization.jsonObject(with: line) as? [String: Any], obj["id"] as? Int == id {
                return obj
            }
        }
        throw URLError(.timedOut)
    }

    private func readLine() async throws -> Data? {
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                return Data(line)
            }
            let handle = output.fileHandleForReading
            let chunk = await Task.detached { handle.availableData }.value
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }

    func initialize() async throws {
        _ = try await request("initialize", [
            "protocolVersion": "2025-06-18", "capabilities": [:] as [String: Any],
            "clientInfo": ["name": "test", "version": "1"],
        ])
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])
    }

    func tools() async throws -> [[String: Any]] {
        let r = try await request("tools/list")
        return (r["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
    }

    /// Zwraca (tekst, isError).
    func call(_ tool: String, _ args: [String: Any] = [:]) async throws -> (String, Bool) {
        let r = try await request("tools/call", ["name": tool, "arguments": args], timeout: 30)
        guard let result = r["result"] as? [String: Any] else { return ("\(r["error"] ?? "?")", true) }
        let text = (result["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
        return (text, result["isError"] as? Bool ?? false)
    }

    func terminate() {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}
#endif
