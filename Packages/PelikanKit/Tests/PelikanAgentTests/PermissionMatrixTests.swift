import Foundation
@testable import PelikanAgent
import PelikanWorkspace
import Testing

@MainActor
@Suite("Macierz uprawnień sesji przy starcie (AI-PERM-001)")
struct PermissionMatrixTests {
    @Test("Wiersze z katalogu narzędzi z poziomem obniżonym ustawieniami; tylko obniżenia trafiają do sesji")
    func matrix() throws {
        let ws = Workspace()
        var settings = AgentSettings()
        let all = PermissionMatrix.rows(registry: ws.registry, settings: settings)
        #expect(!all.isEmpty && all.allSatisfy { $0.base > .none && $0.chosen == $0.base })
        let target = try #require(all.first { $0.base == .approval || $0.base == .full })
        settings.accessOverrides[target.command.rawValue] = .read
        let lowered = PermissionMatrix.rows(registry: ws.registry, settings: settings)
        #expect(lowered.first { $0.command == target.command }?.base == .read)
        settings.accessOverrides[target.command.rawValue] = AgentAccess.none
        #expect(!PermissionMatrix.rows(registry: ws.registry, settings: settings).contains { $0.command == target.command })
        #expect(PermissionMatrix.overrides(all).isEmpty)
        let ro = PermissionMatrix.readOnly(all)
        #expect(ro.allSatisfy { $0.chosen <= .read })
        let o = PermissionMatrix.overrides(ro)
        #expect(o.count == all.filter { $0.base > .read }.count && o.values.allSatisfy { $0 == .read })
    }

    @Test("Obniżenie z macierzy obowiązuje w sesji: poziom wywołania = minimum")
    func sessionMinimum() throws {
        let ws = Workspace()
        let rows = PermissionMatrix.rows(registry: ws.registry, settings: AgentSettings())
        let row = try #require(rows.first { $0.base == .approval || $0.base == .full })
        let store = SessionRegistry()
        var chosen = rows
        let i = try #require(chosen.firstIndex { $0.command == row.command })
        chosen[i].chosen = .read
        let (session, _) = store.create(profile: AgentProfile.builtIn[0], directory: "", accessOverrides: PermissionMatrix.overrides(chosen))
        let d = try #require(ws.registry.command(row.command)?.descriptor)
        #expect(AgentPolicy.effectiveAccess(command: d, session: session, settings: AgentSettings()) == .read)
    }
}
