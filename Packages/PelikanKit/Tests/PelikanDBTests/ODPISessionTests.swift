import Foundation
import PelikanDB
import PelikanODPI
import Testing

/// Testy integracyjne sterownika Instant Client (ODPI-C) na lokalnej bazie testowej.
@Suite("Sterownik Instant Client (ODPI-C)", .enabled(if: TestDatabase.isAvailable), .serialized)
struct ODPISessionTests {
    @Test("Łączy się i odczytuje wersję serwera oraz schemat")
    func connectAndInfo() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        #expect(s.info.server.major >= 19)
        #expect(s.info.currentSchema == TestDatabase.config!.user)
        #expect(s.info.driver == .instantClient)
        #expect(!s.info.clientVersion.isEmpty)
    }

    @Test("Zapytanie zwraca kolumny z typami i wartości bez utraty precyzji")
    func queryTypes() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let (cols, rows) = try await s.queryAll("""
            SELECT 12345678901234567890.123456789 AS big, 0.5 AS half, 'Zażółć' AS txt, DATE '2024-02-29' AS d,
                   TIMESTAMP '2024-02-29 13:14:15.123456' AS ts, HEXTORAW('CAFE') AS r, CAST(NULL AS VARCHAR2(10)) AS n,
                   TO_BINARY_DOUBLE(1.5) AS bd, INTERVAL '2 03:04:05' DAY TO SECOND AS ids
              FROM dual
            """)
        #expect(cols.map(\.name) == ["BIG", "HALF", "TXT", "D", "TS", "R", "N", "BD", "IDS"])
        #expect(cols[0].type == .number)
        #expect(cols[3].type == .date)
        #expect(cols[4].type == .timestamp)
        let r = rows[0]
        #expect(r[0] == .number("12345678901234567890.123456789"))
        #expect(r[1] == .number("0.5"))
        #expect(r[2] == .text("Zażółć"))
        #expect(r[3].displayText == "2024-02-29 00:00:00")
        #expect(r[4].format(ValueFormat(timestampFormat: "YYYY-MM-DD HH24:MI:SS.FF6")) == "2024-02-29 13:14:15.123456")
        #expect(r[5] == .raw(Data([0xCA, 0xFE])))
        #expect(r[6] == .null)
        #expect(r[7] == .double(1.5))
        #expect(r[8].displayText == "+02 03:04:05.000000")
    }

    @Test("Dociąganie wierszy porcjami z dużej tabeli")
    func fetchInPages() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let r = try await s.execute("SELECT id, txt FROM big_rows ORDER BY id")
        let rs = try #require(r.resultSet)
        let first = try await s.fetch(rs.id, maxRows: 100)
        #expect(first.rows.count == 100)
        #expect(first.hasMore)
        #expect(first.rows[0][0] == .number("1"))
        let second = try await s.fetch(rs.id, maxRows: 100)
        #expect(second.rows[0][0] == .number("101"))
        await s.closeResultSet(rs.id)
    }

    @Test("DML zostaje niezatwierdzone do COMMIT, ROLLBACK wycofuje")
    func transactions() async throws {
        let s = try await TestDatabase.connect()
        let other = try await TestDatabase.connect()
        defer { Task { await s.close(); await other.close() } }
        let upd = try await s.execute("UPDATE emp SET comm = 999 WHERE deptno = 30")
        #expect(upd.kind == .dml)
        #expect(upd.rowsAffected == 3)
        // Inna sesja nie widzi niezatwierdzonej zmiany.
        #expect(try await other.scalar("SELECT COUNT(*) FROM emp WHERE comm = 999") == "0")
        try await s.rollback()
        #expect(try await s.scalar("SELECT COUNT(*) FROM emp WHERE comm = 999") == "0")
    }

    @Test("Zmienne wiązane IN/OUT i blok PL/SQL")
    func bindsAndPLSQL() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let r = try await s.execute("BEGIN :sal := emp_api.get_salary(:id); :msg := 'ok ' || :id; END;", binds: [
            BindVariable(name: "id", type: .number, value: .number("7839")),
            BindVariable(name: "sal", type: .number, direction: .output),
            BindVariable(name: "msg", type: .varchar2, direction: .output, maxSize: 100),
        ])
        #expect(r.kind == .plsql)
        #expect(r.outBinds["sal"] == .number("5000"))
        #expect(r.outBinds["msg"] == .text("ok 7839"))
    }

    @Test("REF CURSOR jako zmienna OUT")
    func refCursor() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let r = try await s.execute("BEGIN :c := emp_api.employees_cursor(10); END;", binds: [
            BindVariable(name: "c", type: .refCursor, direction: .output),
        ])
        guard case .cursor(let id) = r.outBinds["c"] else {
            Issue.record("Brak kursora: \(String(describing: r.outBinds["c"]))")
            return
        }
        let batch = try await s.fetch(id, maxRows: 100)
        #expect(batch.rows.count == 2)
        #expect(batch.rows[0][1] == .text("WÓJCIK") || batch.rows[0][1] == .text("KOWALSKI"))
    }

    @Test("Kursory zagnieżdżone CURSOR(…) w 1500 wierszach: bez ORA-01000, nieotwarte zamykane, otwarte działają")
    func nestedCursors() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let r = try await s.execute("select level n, cursor(select 2 from dual) c from dual connect by level <= 1500")
        let id = try #require(r.resultSet).id
        var rows: [[OracleValue]] = []
        var firstCursor: ResultSetID?
        while true {
            let b = try await s.fetch(id, maxRows: 100)
            rows += b.rows
            if firstCursor == nil, case .cursor(let c)? = b.rows.last?[1] {
                // Otwarty od razu (jak komórka <Cursor> w siatce) — nie podlega zamykaniu najstarszych.
                firstCursor = c
                #expect(try await s.fetch(c, maxRows: 10).rows.first?.first == .number("2"))
            }
            if !b.hasMore { break }
        }
        #expect(rows.count == 1500)
        // Najnowszy kursor nadal otwarty; najstarszy nieotwarty — zamknięty (sesja nie trzyma 1500 kursorów).
        guard case .cursor(let last)? = rows.last?[1], case .cursor(let oldest) = rows[1][1] else { Issue.record("brak kursorów"); return }
        #expect(try await s.fetch(last, maxRows: 10).rows.first?.first == .number("2"))
        await #expect(throws: DatabaseError.self) { try await s.fetch(oldest, maxRows: 10) }
        if let open = try? await s.scalar("select count(*) from v$open_cursor where sid = sys_context('userenv', 'sid')") {
            #expect(Int(open) ?? 0 < 300, "\(open)")
        }
        _ = firstCursor
    }

    @Test("LOB, JSON i ROWID")
    func lobJsonRowid() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let (cols, rows) = try await s.queryAll("SELECT body, data, meta, ROWID FROM docs WHERE id = 1")
        #expect(cols[0].type == .clob)
        #expect(cols[2].type == .json)
        guard case .lob(let clob) = rows[0][0], case .lob(let blob) = rows[0][1] else {
            Issue.record("LOB nie odczytany"); return
        }
        #expect(clob.text == "Zażółć gęślą jaźń")
        #expect(blob.bytes == Data([0xDE, 0xAD, 0xBE, 0xEF]))
        #expect(rows[0][2] == .json(#"{"a":1,"b":[1,2]}"#))
        guard case .rowid(let rid) = rows[0][3] else { Issue.record("Brak ROWID"); return }
        #expect(rid.count == 18)
    }

    @Test("Błąd ORA z kodem i pozycją")
    func oracleError() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        do {
            _ = try await s.execute("SELECT no_such_column FROM dual")
            Issue.record("Oczekiwany błąd")
        } catch let e as OracleError {
            #expect(e.code == 904)
            #expect(e.offset == 7)
            #expect(e.message.contains("ORA-00904"))
        }
    }

    @Test("Kompilacja z błędami zwraca ostrzeżenie ORA-24344, a nie błąd")
    func compilationWarning() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let r = try await s.execute("CREATE OR REPLACE PROCEDURE pelikan_tmp_broken IS BEGIN x := 1; END;")
        #expect(r.kind == .ddl)
        #expect(r.warning?.code == 24344)
        _ = try await s.execute("DROP PROCEDURE pelikan_tmp_broken")
    }

    /// Uwaga: DBMS_SESSION.SLEEP nie reaguje na przerwanie do końca uśpienia (tak samo w SQL*Plus) —
    /// test używa długiego zapytania (docs/research/behaviour.md, „Przerwanie”).
    @Test("Przerwanie długiego zapytania (Break) daje ORA-01013")
    func breakExecution() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let task = Task {
            let r = try await s.execute("SELECT COUNT(*) FROM big_rows a, big_rows b WHERE a.num + b.num < 0")
            return try await s.fetch(r.resultSet!.id, maxRows: 1)
        }
        try await Task.sleep(for: .milliseconds(500))
        let started = ContinuousClock.now
        s.breakExecution()
        do {
            _ = try await task.value
            Issue.record("Oczekiwany ORA-01013")
        } catch let e as OracleError {
            #expect(e.isCancelled)
        }
        #expect(ContinuousClock.now - started < .seconds(5))
        // Sesja nadal działa po przerwaniu.
        #expect(try await s.scalar("SELECT 1 FROM dual") == "1")
    }

    @Test("Przerwanie po zamknięciu sesji nic nie robi; operacje po zamknięciu zwracają błąd")
    func breakAfterClose() async throws {
        let s = try await TestDatabase.connect()
        await s.close()
        s.breakExecution()
        await #expect(throws: DatabaseError.closed) { _ = try await s.execute("SELECT 1 FROM dual") }
    }

    @Test("MODULE i ACTION widoczne w V$SESSION")
    func sessionTags() async throws {
        let s = try await TestDatabase.connect(tags: SessionTags(module: "Pelikan test", action: "tagi"))
        defer { Task { await s.close() } }
        let m = try await s.scalar("SELECT module || '/' || action FROM v$session WHERE sid = SYS_CONTEXT('USERENV','SID')")
        #expect(m == "Pelikan test/tagi")
    }

    @Test("Niejawne wyniki DBMS_SQL.RETURN_RESULT")
    func implicitResults() async throws {
        let s = try await TestDatabase.connect()
        defer { Task { await s.close() } }
        let r = try await s.execute("""
            DECLARE c SYS_REFCURSOR; BEGIN OPEN c FOR SELECT deptno FROM dept ORDER BY deptno; DBMS_SQL.RETURN_RESULT(c); END;
            """)
        #expect(r.implicitResults.count == 1)
        let batch = try await s.fetch(r.implicitResults[0].id, maxRows: 10)
        #expect(batch.rows.map { $0[0] } == [.number("10"), .number("20"), .number("30"), .number("40")])
    }
}
