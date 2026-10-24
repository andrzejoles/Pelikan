import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Lista okien i wskaźniki połączeń (PD-UI-002, PD-CONN-005)")
struct WindowListTests {
    @Test("Reguła user@baza ma pierwszeństwo przed kolorem środowiska; bez reguły — kolor połączenia")
    func indicators() throws {
        let ws = Workspace()
        let prod = ConnectionDefinition(name: "PRD", target: ConnectionTarget(user: "sys", connectString: "prdhost/orcl"), environment: .production)
        let dev = ConnectionDefinition(name: "DEV", target: ConnectionTarget(user: "scott", connectString: "devdb"), environment: .development)
        try ws.connections.upsert(prod, password: nil)
        try ws.connections.upsert(dev, password: nil)
        let a = ws.newDocument(.sql), b = ws.newDocument(.sql)
        a.connectionID = prod.id
        b.connectionID = dev.id
        #expect(ws.indicatorColor(for: a) == .production && ws.indicatorColor(for: b) == nil)
        let blue = RGBColor(red: 0, green: 0, blue: 1)
        ws.settings.connectionIndicators = [ConnectionIndicator(pattern: "scott@dev*", color: blue)]
        #expect(ws.indicatorColor(for: b) == blue)
        ws.settings.connectionIndicators = [ConnectionIndicator(pattern: "sys@*", color: blue)]
        #expect(ws.indicatorColor(for: a) == blue)
    }

    @Test("Sortowanie i krótkie nazwy; zmiana nazwy i ponowne połączenie z menu")
    func listCommands() async throws {
        let ws = Workspace()
        let t = ws.newDocument(.test), s = ws.newDocument(.sql), p = ws.newDocument(.program)
        t.customTitle = "zeta"; s.customTitle = "alfa"; p.customTitle = "beta"
        #expect(ws.windowListDocuments.map(\.id) == [t.id, s.id, p.id])
        _ = try await ws.invoke("window.listSort", CommandArguments(["order": .string("name")]))
        #expect(ws.windowListDocuments.map(\.title) == ["alfa", "beta", "zeta"])
        _ = try await ws.invoke("window.listSort", CommandArguments(["order": .string("type")]))
        #expect(ws.windowListDocuments.map(\.kind).map(\.rawValue) == [p, s, t].map(\.kind.rawValue).sorted())
        await #expect(throws: (any Error).self) { try await ws.invoke("window.listSort", CommandArguments(["order": .string("x")])) }
        _ = try await ws.invoke("window.listShortTitles", CommandArguments())
        #expect(ws.windowListTitle(s) == s.title)
        _ = try await ws.invoke("window.rename", CommandArguments(["document": .string(s.id.description), "title": .string("raport dzienny")]))
        #expect(s.title == "raport dzienny")
        _ = try await ws.invoke("window.rename", CommandArguments(["document": .string(s.id.description), "title": .string("")]))
        #expect(s.customTitle == nil)
        s.transactionOpen = true
        s.connectionID = UUID()
        await #expect(throws: (any Error).self) { try await ws.invoke("window.reconnect", CommandArguments(["document": .string(s.id.description)])) }
    }
}

@Suite("Tunel SSH z hasłem — bez serwera (DB-SSH-001)")
struct SSHTunnelPasswordTests {
    @Test("Argumenty bez hasła i bez BatchMode=yes; środowisko askpass bez sekretu; kolejka oddaje hasło raz")
    func askpass() throws {
        let t = SSHTunnel(host: "bastion", port: 22, user: "u", usesPassword: true)
        let args = SSHTunnelManager.arguments(t, localPort: 5000, remote: .init(host: "db", port: 1521), extra: [])
        #expect(args.contains("BatchMode=no") && !args.contains("BatchMode=yes") && args.contains("PubkeyAuthentication=no"))
        #expect(SSHTunnelManager.arguments(SSHTunnel(host: "b", user: "u"), localPort: 1, remote: .init(host: "d", port: 1), extra: []).contains("BatchMode=yes"))
        let secret = "tajne-\(UUID().uuidString.prefix(6))"
        let a = try SSHTunnelManager.askpass(secret: secret)
        defer { a.cleanup() }
        #expect(!a.environment.values.contains { $0.contains(secret) })
        let script = try String(contentsOfFile: a.environment["SSH_ASKPASS"]!, encoding: .utf8)
        #expect(!script.contains(secret))
        let fifo = a.environment["PELIKAN_ASKPASS_FIFO"]!
        let h = try #require(FileHandle(forReadingAtPath: fifo))
        let read = String(decoding: h.readDataToEndOfFile(), as: UTF8.self)
        try? h.close()
        #expect(read == secret + "\n")
        // Wątek zapisu usuwa kolejkę zaraz po zapisie — jednorazowa.
        for _ in 0..<50 where FileManager.default.fileExists(atPath: fifo) { usleep(20_000) }
        #expect(!FileManager.default.fileExists(atPath: fifo))
    }
}
