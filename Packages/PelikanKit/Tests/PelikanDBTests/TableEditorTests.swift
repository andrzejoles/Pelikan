import Foundation
import PelikanDB
import PelikanODPI
import PelikanWorkspace
import Testing

@MainActor
@Suite("Edytor tabeli na bazie testowej", .enabled(if: TestDatabase.isAvailable), .serialized)
struct TableEditorTests {
    @Test("Nowa tabela, wczytanie, zmiany kolumn, kluczy, warunków i indeksów, ponowne wczytanie")
    func roundTrip() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.instantClient: ODPIDriver()])
        let def = ConnectionDefinition(name: "test", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let m = try #require(ws.metadata())
        let schema = try await m.currentSchema()
        let s = try await ws.sessions.session(ws.sessions.compileKey(connection: def.id))
        for o in ["table pelikan_ed_t purge", "table pelikan_ed_t2 purge", "table pelikan_ed_ref purge"] { _ = try? await s.execute("drop \(o)") }
        _ = try await s.execute("create table pelikan_ed_ref (id number primary key)")

        var t = TableDefinition(owner: schema, name: "PELIKAN_ED_T")
        t.comment = "Tabela testowa"
        var id = TableDefinition.Column(name: "ID", type: "NUMBER(10)", nullable: false)
        id.comment = "Klucz"
        var nazwa = TableDefinition.Column(name: "NAZWA", type: "VARCHAR2(30 CHAR)")
        nazwa.defaultValue = "'brak'"
        var podwojone = TableDefinition.Column(name: "PODWOJONE", type: "NUMBER")
        podwojone.virtualExpression = "ID * 2"
        t.columns = [id, nazwa, podwojone, TableDefinition.Column(name: "STARA", type: "DATE")]
        t.keys = [TableDefinition.Key(name: "PELIKAN_ED_PK", kind: .primary, columns: ["ID"])]
        t.checks = [TableDefinition.Check(name: "PELIKAN_ED_CK", condition: "ID > 0")]
        // Indeks malejący jest funkcyjny — kolumn takiego indeksu Oracle nie pozwala modyfikować (ORA-30556), więc obejmuje tylko ID.
        t.indexes = [TableDefinition.Index(name: "PELIKAN_ED_IX", columns: ["ID DESC"])]
        let created = try await TableDDL.apply(from: nil, to: t, in: ws, connectionID: def.id)
        #expect(created.error == nil, "\(created.failed ?? ""): \(created.error ?? "")")

        var loaded = try await TableDDL.load(owner: schema, name: "PELIKAN_ED_T", metadata: m)
        #expect(loaded.comment == "Tabela testowa")
        #expect(loaded.columns.map(\.name) == ["ID", "NAZWA", "PODWOJONE", "STARA"])
        #expect(loaded.columns[0].type == "NUMBER(10)" && !loaded.columns[0].nullable && loaded.columns[0].comment == "Klucz")
        #expect(loaded.columns[1].type == "VARCHAR2(30 CHAR)" && loaded.columns[1].defaultValue == "'brak'")
        #expect(loaded.columns[2].virtualExpression.contains("ID") && loaded.columns[2].virtualExpression.contains("2"))
        #expect(loaded.keys.map(\.name) == ["PELIKAN_ED_PK"] && loaded.checks.map(\.name) == ["PELIKAN_ED_CK"])
        #expect(loaded.indexes.first?.columns == ["\"ID\" DESC"])
        // Ponowne wygenerowanie bez zmian — brak poleceń.
        #expect(TableDDL.statements(from: loaded, to: loaded).isEmpty)

        var changed = loaded
        changed.name = "PELIKAN_ED_T2"
        changed.columns[1].name = "OPIS"                       // zmiana nazwy
        changed.columns[1].type = "VARCHAR2(100 CHAR)"         // zmiana typu
        changed.columns.removeAll { $0.name == "STARA" }        // usunięcie
        changed.columns.append(TableDefinition.Column(name: "REF_ID", type: "NUMBER"))
        var fk = TableDefinition.Key(name: "PELIKAN_ED_FK", kind: .foreign, columns: ["REF_ID"])
        fk.referencedTable = "PELIKAN_ED_REF"
        fk.onDelete = "CASCADE"
        changed.keys.append(fk)
        changed.checks[0].condition = "ID > 10"                 // zmiana warunku: drop + add
        changed.indexes[0].name = "PELIKAN_ED_IX2"              // tylko nazwa: rename
        let ddl = TableDDL.statements(from: loaded, to: changed)
        #expect(ddl.contains { $0.contains("RENAME TO \"PELIKAN_ED_T2\"") || $0.hasSuffix("RENAME TO PELIKAN_ED_T2") })
        #expect(ddl.contains { $0.contains("RENAME COLUMN NAZWA TO OPIS") })
        #expect(ddl.contains { $0.contains("ALTER INDEX") && $0.contains("RENAME TO PELIKAN_ED_IX2") })
        let r = try await TableDDL.apply(from: loaded, to: changed, in: ws, connectionID: def.id)
        #expect(r.error == nil, "\(r.failed ?? ""): \(r.error ?? "")")
        loaded = try await TableDDL.load(owner: schema, name: "PELIKAN_ED_T2", metadata: m)
        #expect(loaded.columns.map(\.name) == ["ID", "OPIS", "PODWOJONE", "REF_ID"])
        #expect(loaded.columns[1].type == "VARCHAR2(100 CHAR)")
        #expect(loaded.keys.contains { $0.kind == .foreign && $0.referencedTable == "PELIKAN_ED_REF" && $0.onDelete == "CASCADE" })
        #expect(loaded.checks.first?.condition == "ID > 10")
        #expect(loaded.indexes.map(\.name) == ["PELIKAN_ED_IX2"])
        // Błąd w poleceniu: zatrzymanie i komunikat.
        var bad = loaded
        bad.checks.append(TableDefinition.Check(name: "PELIKAN_ED_BAD", condition: "brak_kolumny > 0"))
        let failed = try await TableDDL.apply(from: loaded, to: bad, in: ws, connectionID: def.id)
        #expect(failed.failed?.contains("PELIKAN_ED_BAD") == true && failed.error?.contains("ORA-") == true)
        for o in ["table pelikan_ed_t2 purge", "table pelikan_ed_ref purge"] { _ = try? await s.execute("drop \(o)") }
        await ws.sessions.disconnectAll()
    }
}
