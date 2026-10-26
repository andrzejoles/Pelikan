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

    @Test("ustawienie: domyślnie fragment nazwy, starszy zapis bez klucza — też")
    func setting() throws {
        #expect(Settings().browserFilterContains)
        #expect(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)).browserFilterContains)
    }
}
