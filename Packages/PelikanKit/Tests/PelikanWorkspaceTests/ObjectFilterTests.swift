import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

/// Filtr nazw przeglądarki obiektów: fragment nazwy (domyślnie) albo początek nazwy; jawny `%` bez zmian.
@Suite("Filtr nazw przeglądarki obiektów")
struct ObjectFilterTests {
    @Test("wzorce: %tekst% domyślnie, tekst% po przełączeniu, jawny % i kilka wzorców po przecinku")
    func patterns() {
        #expect(ObjectFilter("emp").namePattern("EMP") == "%EMP%")
        #expect(ObjectFilter("emp", contains: false).namePattern("EMP") == "EMP%")
        #expect(ObjectFilter("e%p").namePattern("E%P") == "E%P")
        var binds: [BindVariable] = []
        let sql = ObjectFilter("emp, DE%, status=invalid").whereClause(binds: &binds)
        #expect(sql.contains("o.object_name like :fn0 or o.object_name like :fn1"))
        #expect(binds.map(\.name) == ["fn0", "fn1", "fst"])
        #expect("\(binds[0].value)".contains("%EMP%") && "\(binds[1].value)".contains("DE%"))
    }

    @Test("foldery użytkowników, ról, profili, katalogów, adnotacji i asercji: ten sam wzorzec co obiekty (D175)")
    func otherFolders() {
        var binds: [BindVariable] = []
        let sql = MetadataProvider.applyNameFilter("select username from all_users where 1 = 1", column: "username",
                                                   filter: ObjectFilter("emp, HR%"), binds: &binds)
        #expect(sql.hasSuffix(" and (username like :fn0 or username like :fn1)"))
        #expect("\(binds[0].value)".contains("%EMP%") && !"\(binds[1].value)".contains("%HR%"))
        binds = []
        _ = MetadataProvider.applyNameFilter("x", column: "role", filter: ObjectFilter("emp", contains: false), binds: &binds)
        #expect("\(binds[0].value)".contains("EMP%") && !"\(binds[0].value)".contains("%EMP"))
    }

    @Test("ustawienie: domyślnie fragment nazwy, starszy zapis bez klucza — też")
    func setting() throws {
        #expect(Settings().browserFilterContains)
        #expect(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)).browserFilterContains)
    }
}
