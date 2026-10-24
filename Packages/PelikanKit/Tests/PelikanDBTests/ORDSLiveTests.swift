import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PelikanDB
import PelikanODPI
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// SD-ORDS-001 na żywym ORDS (scripts/testdb.sh ords-up): skrypty z komend Pelikana wykonane jak w oknie SQL,
/// lista modułów i obiektów AutoREST z bazy oraz wywołanie usług REST przez HTTP. Bez kontenera ORDS — pominięte.
@MainActor
@Suite("ORDS na żywym serwerze", .enabled(if: TestDatabase.isAvailable && TestDatabase.config?.ordsURL != nil), .serialized)
struct ORDSLiveTests {
    static let alias = "dev_pelikan_rest"

    /// GET z limitem czasu; (status HTTP, treść).
    nonisolated static func get(_ url: String) async throws -> (Int, String) {
        var request = URLRequest(url: URL(string: url)!)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data, as: UTF8.self))
    }

    /// ORDS buforuje metadane kilka sekund — po zmianie w bazie czekamy na oczekiwany status (do 20 s).
    nonisolated static func poll(_ url: String, status: Int) async throws -> (Int, String) {
        var last = (0, "")
        for _ in 0..<40 {
            last = try await get(url)
            if last.0 == status { return last }
            try await Task.sleep(for: .milliseconds(500))
        }
        return last
    }

    /// Wykonuje skrypt z okna SQL wygenerowany przez komendę (bloki PL/SQL zakończone `/`).
    static func run(_ script: String, in s: any DatabaseSession) async throws {
        for stmt in ScriptSplitter.split(script) where stmt.sqlplusCommand == nil {
            _ = try await s.execute(stmt.text)
        }
    }

    @Test("Wykrycie ORDS, ENABLE_SCHEMA/ENABLE_OBJECT z komend, moduły i AutoREST, wywołanie REST przez HTTP")
    func liveORDS() async throws {
        let c = TestDatabase.config!
        let base = c.ordsURL!
        // Kontener ORDS zatrzymany (ords-down) — nie ma z czym rozmawiać.
        guard let (code, _) = try? await Self.get(base + "/"), code > 0 else { return }

        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        ws.ui = TestUI()
        let def = ConnectionDefinition(name: "dev_ords", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let s = try await ws.sessions.session(SessionKey(connectionID: def.id, purpose: .main))
        #expect(try await ORDSTools.isInstalled(s))

        // Skrypty z komend (te same, które trafiają do nowego okna SQL), wykonane jak w oknie SQL.
        let schemaResult = try await ws.invoke("tools.ordsEnableSchema", CommandArguments(["alias": .string(Self.alias)]))
        guard case .string(let enableSchema)? = schemaResult.value else { Issue.record("brak skryptu schematu"); return }
        #expect(enableSchema.contains("p_url_mapping_pattern => '\(Self.alias)'"))
        try await Self.run(enableSchema, in: s)
        let objectResult = try await ws.invoke("tools.ordsEnableObject", CommandArguments(["object": .string("dept"), "alias": .string("dzialy")]))
        guard case .string(let enableObject)? = objectResult.value else { Issue.record("brak skryptu obiektu"); return }
        #expect(enableObject.contains("p_object_type => 'TABLE'"))
        try await Self.run(enableObject, in: s)
        // Komendy domyślnie wymagają autoryzacji: bez poświadczeń ORDS odmawia (401) — skrypt naprawdę chroni dane.
        let (denied, _) = try await Self.poll("\(base)/\(Self.alias)/dzialy/10", status: 401)
        #expect(denied == 401)
        // Do wywołania bez OAuth w teście — wariant bez autoryzacji z tego samego generatora.
        try await Self.run(ORDSTools.enableSchemaScript(schema: c.user, urlAlias: Self.alias, requireAuthorization: false), in: s)
        try await Self.run(ORDSTools.enableObjectScript(schema: c.user, object: "DEPT", type: "TABLE", alias: "dzialy",
                                                        requireAuthorization: false), in: s)

        // Moduł z szablonem i handlerem GET (zdefiniowany wprost w PL/SQL, jak zrobiłby to użytkownik).
        _ = try await s.execute("""
            begin
              ords.define_service(p_module_name => 'dev_pelikan.mod', p_base_path => 'pelikan/', p_pattern => 'dzial/:id',
                                  p_method => 'GET', p_source_type => ords.source_type_collection_item,
                                  p_source => 'select deptno, dname from dept where deptno = :id');
              commit;
            end;
            """)
        let modules = try await ORDSTools.modules(s)
        let mod = modules.first { $0.name == "dev_pelikan.mod" }
        #expect(mod?.uriPrefix == "/pelikan/" && mod?.templates == ["dzial/:id"] && mod?.status == "PUBLISHED")
        let enabled = try await ORDSTools.enabledObjects(s)
        #expect(enabled.contains { $0.count == 4 && $0[0] == "DEPT" && $0[1] == "TABLE" && $0[2] == "dzialy" && $0[3] == "ENABLED" })
        // Komenda listy: te same moduły w wyniku dla agenta i raportu.
        let listed = try await ws.invoke("tools.ordsModules", CommandArguments())
        guard case .array(let items)? = listed.value else { Issue.record("brak listy modułów"); return }
        #expect(items.contains(.object(["name": .string("dev_pelikan.mod"), "uriPrefix": .string("/pelikan/"), "status": .string("PUBLISHED")])))

        // Wywołania REST przez HTTP: AutoREST tabeli i handler modułu.
        let (auto, body) = try await Self.poll("\(base)/\(Self.alias)/dzialy/10", status: 200)
        #expect(auto == 200 && body.contains("\"deptno\":10"))
        let (item, itemBody) = try await Self.poll("\(base)/\(Self.alias)/pelikan/dzial/20", status: 200)
        #expect(item == 200 && itemBody.contains("\"deptno\":20"))

        // Wyłączenie AutoREST skryptem Pelikana — usługa znika (404); sprzątanie modułu.
        try await Self.run(ORDSTools.disableObjectScript(schema: c.user, object: "DEPT"), in: s)
        let (gone, _) = try await Self.poll("\(base)/\(Self.alias)/dzialy/10", status: 404)
        #expect(gone == 404)
        _ = try await s.execute("begin ords.delete_module(p_module_name => 'dev_pelikan.mod'); commit; end;")
        #expect(try await ORDSTools.modules(s).contains { $0.name == "dev_pelikan.mod" } == false)
        await ws.sessions.disconnectAll()
    }
}
