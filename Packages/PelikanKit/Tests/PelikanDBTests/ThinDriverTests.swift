import Foundation
import NIOCore
import OracleNIO
import PelikanDB
import PelikanODPI
import PelikanSQL
@testable import PelikanThin
import PelikanWorkspace
import Testing

@Suite("Sterownik thin — dekodowanie formatów Oracle")
struct OracleRawTests {
    @Test("NUMBER: zero, całkowite, ułamki, ujemne, 38 cyfr")
    func numbers() {
        #expect(OracleRaw.number([0x80]) == "0")
        #expect(OracleRaw.number([0xC1, 0x02]) == "1")
        #expect(OracleRaw.number([0xC2, 0x02]) == "100")
        #expect(OracleRaw.number([0xC2, 0x02, 0x18, 0x2E]) == "123.45")
        #expect(OracleRaw.number([0xC0, 0x33]) == "0.5")
        #expect(OracleRaw.number([0x3E, 0x64, 0x66]) == "-1")
        #expect(OracleRaw.number([0x3D, 0x64, 0x4E, 0x38, 0x66]) == "-123.45")
        #expect(OracleRaw.number([0xBF, 0x0B]) == "0.001")
    }

    @Test("Obiekt kompilowany z CREATE: schemat, cudzysłowy, BODY, komentarze; inne polecenia — nil")
    func compiledObject() {
        #expect(ThinSession.compiledObject("create or replace package body hr.emp_api as begin null; end;")! == ("HR", "EMP_API", "PACKAGE BODY"))
        #expect(ThinSession.compiledObject("CREATE EDITIONABLE FUNCTION \"MixedCase\" return number is begin return 1; end;")! == (nil, "MixedCase", "FUNCTION"))
        #expect(ThinSession.compiledObject("-- opis\ncreate force view v_emp as select * from emp")! == (nil, "V_EMP", "VIEW"))
        #expect(ThinSession.compiledObject("create table review_log (id number)") == nil)
        #expect(ThinSession.compiledObject("alter package p compile") == nil)
    }

    @Test("DATE i TIMESTAMP z ułamkiem sekund")
    func dates() {
        let d = OracleRaw.timestamp([120, 124, 10, 23, 14, 31, 60])
        #expect(d == OracleTimestamp(year: 2024, month: 10, day: 23, hour: 13, minute: 30, second: 59))
        let ts = OracleRaw.timestamp([120, 124, 1, 2, 1, 1, 1, 0x07, 0x5B, 0xCD, 0x15])
        #expect(ts?.fsecond == 123_456_789)
    }

    @Test("EZConnect, deskryptor; TCPS — komunikat o Instant Client")
    func endpoints() throws {
        let e = try ThinDriver.endpoint("db.example:1522/ORCL")
        #expect(e.host == "db.example" && e.port == 1522)
        let d = try ThinDriver.endpoint("(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=h)(PORT=1530))(CONNECT_DATA=(SERVICE_NAME=S)))")
        #expect(d.host == "h" && d.port == 1530)
        #expect(throws: DatabaseError.self) { try ThinDriver.endpoint("tcps://adb.example:1522/x") }
        // Deskryptor w zwykłym zapisie Oracle Net, w wielu liniach (R8-04).
        let spaced = try ThinDriver.endpoint("""
            (DESCRIPTION =
              (ADDRESS = (PROTOCOL = TCP)(HOST = db.example.org)(PORT = 1530))
              (CONNECT_DATA = (SID = ORCL)))
            """)
        #expect(spaced.host == "db.example.org" && spaced.port == 1530)
        #expect("\(spaced.service)".contains("ORCL") && "\(spaced.service)".lowercased().contains("sid"))
        #expect(throws: DatabaseError.self) { try ThinDriver.endpoint("(DESCRIPTION = (ADDRESS = (PROTOCOL = TCPS)(HOST = h)(PORT = 2484)))") }
        // EZConnect Plus: parametry po `?` nie trafiają do nazwy usługi.
        let plus = try ThinDriver.endpoint("db.example:1521/usluga?connect_timeout=5&retry_count=2")
        #expect(plus.host == "db.example" && plus.port == 1521 && "\(plus.service)".contains("usluga") && !"\(plus.service)".contains("?"))
        let server = try ThinDriver.endpoint("db.example/usluga:dedicated?connect_timeout=5")
        #expect("\(server.service)".contains("usluga") && !"\(server.service)".contains("dedicated"))
    }

    @Test("Konfiguracja OracleNIO bez OOB (oracle-nio #124: 19c z OOB bez FastAuth), rola i limit czasu")
    func configuration() {
        let c = ThinDriver.configuration(("h", 1521, .serviceName("s")), target: ConnectionTarget(user: "u", connectString: "h/s", role: .sysdba), password: "x")
        #expect(c.disableOOB && c.mode == .sysDBA && c.options.connectTimeout == .seconds(20))
    }

    @Test("TIMESTAMP WITH TIME ZONE: przesunięcie przeliczone na czas lokalny; strefa nazwana jako czas UTC z oznaczeniem")
    func timestampTZ() {
        // 2026-07-26 10:00:00 UTC, przesunięcie +02:00 (bajty 11–12: godzina + 20, minuta + 60).
        let offset = OracleRaw.timestamp([120, 126, 7, 26, 11, 1, 1, 0, 0, 0, 0, 22, 60])
        #expect(offset?.hour == 12 && offset?.tzHourOffset == 2 && offset?.tzRegion == nil)
        #expect(offset?.formatted("YYYY-MM-DD HH24:MI:SS", zone: true) == "2026-07-26 12:00:00 +02:00")
        // Bit 0x80: identyfikator regionu (np. Europe/Warsaw) — czas zostaje w UTC i jest tak opisany.
        let region = OracleRaw.timestamp([120, 126, 7, 26, 11, 1, 1, 0, 0, 0, 0, 0x80 | 0x2A, 0x5C])
        #expect(region?.hour == 10 && region?.tzRegion == "UTC")
        #expect(region?.formatted("YYYY-MM-DD HH24:MI:SS", zone: true) == "2026-07-26 10:00:00 UTC")
    }

    @Test("Tekst CLOB: UTF-16BE (AL16UTF16) albo UTF-8 według liczby odczytanych znaków")
    func clobText() {
        func utf16(_ s: String) -> Data { Data(s.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }) }
        #expect(ThinSession.clobText(utf16("abc"), characters: 3) == "abc")
        #expect(ThinSession.clobText(utf16("żż"), characters: 2) == "żż")       // bez bajtu zerowego
        #expect(ThinSession.clobText(Data("żż".utf8), characters: 2) == "żż")    // UTF-8, też 4 bajty
        #expect(ThinSession.clobText(Data("zażółć".utf8), characters: 6) == "zażółć")
        #expect(ThinSession.clobText(Data(), characters: 0) == "")
    }
}

@Suite("Sterownik thin na bazie testowej", .enabled(if: TestDatabase.config != nil), .serialized)
struct ThinSessionTests {
    func connect() async throws -> any DatabaseSession {
        let c = TestDatabase.config!
        return try await ThinDriver().connect(target: ConnectionTarget(user: c.user, connectString: c.connectString),
                                              credentials: Credentials(password: c.password), options: ConnectOptions(tags: SessionTags(module: "Pelikan thin")))
    }

    @Test("Połączenie: użytkownik, schemat, wersja serwera; capabilities bez break")
    func info() async throws {
        let s = try await connect()
        #expect(s.info.driver == .thin)
        #expect(s.info.sessionUser == TestDatabase.config!.user.uppercased())
        #expect(s.info.server.major >= 23)
        #expect(!s.info.capabilities.contains(.breakExecution))
        await s.close()
    }

    @Test("Typy: NUMBER z 38 cyframi, DATE, TIMESTAMP, VARCHAR2 z polskimi znakami, NULL, CLOB, BLOB, RAW, ROWID")
    func types() async throws {
        let s = try await connect()
        let (cols, rows) = try await s.queryAll("""
            select 12345678901234567890123456789012345678 big, -0.000123 small, date '2024-02-29' + 13.5/24 d,
                   timestamp '2024-01-02 03:04:05.123456' ts, 'Zażółć gęślą jaźń' txt, cast(null as varchar2(10)) nul,
                   (select body from docs where id = 1) c, (select data from docs where id = 1) b, hextoraw('0A0B') r,
                   (select rowid from dept where deptno = 10) rid
            from dual
            """)
        let r = try #require(rows.first)
        #expect(cols[0].type == .number)
        #expect(r[0] == .number("12345678901234567890123456789012345678"))
        #expect(r[1] == .number("-0.000123"))
        #expect(r[2] == .timestamp(OracleTimestamp(year: 2024, month: 2, day: 29, hour: 13, minute: 30), .date))
        if case .timestamp(let t, _) = r[3] { #expect(t.fsecond == 123_456_000) } else { Issue.record("TIMESTAMP") }
        #expect(r[4] == .text("Zażółć gęślą jaźń"))
        #expect(r[5].isNull)
        if case .lob(let l) = r[6] { #expect(l.text == "Zażółć gęślą jaźń") } else { Issue.record("CLOB \(r[6])") }
        if case .lob(let l) = r[7] { #expect(l.bytes == Data([0xDE, 0xAD, 0xBE, 0xEF])) } else { Issue.record("BLOB \(r[7])") }
        #expect(r[8] == .raw(Data([0x0A, 0x0B])))
        if case .rowid(let id) = r[9] { #expect(id.count == 18) } else { Issue.record("ROWID \(r[9])") }
        await s.close()
    }

    @Test("Zmienne wiązane IN i OUT, DML z liczbą wierszy, ROLLBACK, dociąganie porcjami")
    func bindsAndFetch() async throws {
        let s = try await connect()
        let (_, r1) = try await s.queryAll("select ename from emp where empno = :id", binds: [BindVariable(name: "id", value: .number("7839"))])
        #expect(r1.first?.first == .text("KOWALSKI"))
        let out = try await s.execute("begin :x := :a * 2; :t := 'ok ' || :a; end;",
                                      binds: [BindVariable(name: "x", type: .number, direction: .output),
                                              BindVariable(name: "a", value: .number("21")),
                                              BindVariable(name: "t", type: .varchar2, direction: .output, maxSize: 100)])
        #expect(out.outBinds["x"] == .number("42"))
        #expect(out.outBinds["t"] == .text("ok 21"))
        let upd = try await s.execute("update emp set comm = nvl(comm, 0) where deptno = 30")
        #expect(upd.kind == .dml && upd.rowsAffected == 3)
        try await s.rollback()
        let q = try await s.execute("select id from big_rows order by id")
        let rs = try #require(q.resultSet)
        let b1 = try await s.fetch(rs.id, maxRows: 100)
        let b2 = try await s.fetch(rs.id, maxRows: 100)
        #expect(b1.rows.count == 100 && b1.hasMore)
        #expect(b2.rows.first?.first == .number("101"))
        await s.closeResultSet(rs.id)
        await s.close()
    }

    @Test("CLOB powyżej 32 600 znaków (kolumna i OUT) jak w Instant Client; limit LOB daje znacznik obcięcia")
    func longCLOB() async throws {
        let thin = try await connect()
        let odpi = try await TestDatabase.connect()
        let ascii = "select xmlagg(xmlelement(e, lpad(level, 6, '0'))).getclobval() from dual connect by level <= 3000"
        let polish = "select xmlagg(xmlelement(e, 'żółć' || lpad(level, 6, '0'))).getclobval() from dual connect by level <= 3000"
        for sql in [ascii, polish] {
            let t = try #require(try await thin.queryAll(sql).rows.first?.first)
            let o = try #require(try await odpi.queryAll(sql).rows.first?.first)
            guard case .lob(let tl) = t, case .lob(let ol) = o else { Issue.record("CLOB \(t)"); continue }
            #expect(tl.text?.count ?? 0 >= 39_000 && tl.text == ol.text && !tl.truncated && tl.length == ol.length)
            #expect(tl.text?.hasSuffix("003000</E>") == true)
        }
        // Zmienna OUT.
        let block = "begin select xmlagg(xmlelement(e, lpad(level, 6, '0'))).getclobval() into :c from dual connect by level <= 3000; end;"
        let out = try await thin.execute(block, binds: [BindVariable(name: "c", type: .clob, direction: .output)])
        if case .lob(let l) = out.outBinds["c"] { #expect(l.text?.count == 39_000 && !l.truncated) } else { Issue.record("OUT \(String(describing: out.outBinds["c"]))") }
        // Limit LOB w znakach: obcięte i oznaczone (strażnik narzędzi danych, D168).
        let r = try await thin.execute(polish, binds: [], options: ExecuteOptions(lobLimit: 1000))
        let batch = try await thin.fetch(try #require(r.resultSet).id, maxRows: 1)
        if case .lob(let l) = batch.rows.first?.first { #expect(l.text?.count == 1000 && l.truncated && l.text?.hasPrefix("<E>żółć") == true) }
        else { Issue.record("limit") }
        await thin.close()
        await odpi.close()
    }

    @Test("Równoległe pobieranie z jednego wyniku: wiersze bez powtórzeń i braków")
    func concurrentFetch() async throws {
        let s = try await connect()
        let r = try await s.execute("select level n from dual connect by level <= 3000")
        let id = try #require(r.resultSet).id
        let batches = try? await withThrowingTaskGroup(of: [Int].self) { group in
            for _ in 0..<6 {
                group.addTask {
                    var got: [Int] = []
                    while true {
                        let b: RowBatch
                        // Wynik do końca pobrany przez inne zadanie jest już zamknięty (jak w ODPI).
                        do { b = try await s.fetch(id, maxRows: 100) } catch DatabaseError.unknownResultSet { return got }
                        got += b.rows.compactMap { $0.first?.displayText.flatMap { Int($0) } }
                        if !b.hasMore { return got }
                    }
                }
            }
            var all: [Int] = []
            for try await part in group { all += part }
            return all
        }
        await s.close()
        #expect(batches?.sorted() == Array(1...3000))
    }

    @Test("Błąd ORA z kodem; DBMS_OUTPUT przez narzędzia sesji")
    func errorsAndOutput() async throws {
        let s = try await connect()
        do {
            _ = try await s.execute("select * from tabela_ktorej_nie_ma")
            Issue.record("brak błędu")
        } catch let e as OracleError {
            #expect(e.code == 942)
            #expect(e.message.contains("ORA-00942"))
        }
        try await SessionUtilities.enableOutput(s, bufferSize: 0)
        _ = try await s.execute("begin dbms_output.put_line('Pelikan thin ✓'); dbms_output.put_line('druga'); end;")
        #expect(try await SessionUtilities.readOutput(s) == ["Pelikan thin ✓", "druga"])
        await s.close()
    }
}

@MainActor
@Suite("SQL Window przez sterownik thin", .enabled(if: TestDatabase.config != nil), .serialized)
struct ThinSQLWindowTests {
    @Test("Zapytanie w siatce, DML i transakcja, DBMS_OUTPUT, błąd ORA, Przerwij wyszarzone")
    func sqlWindow() async throws {
        let c = TestDatabase.config!
        let ws = Workspace(drivers: [.thin: ThinDriver()])
        var def = ConnectionDefinition(name: "dev_thin", target: ConnectionTarget(user: c.user, connectString: c.connectString))
        def.driver = .thin
        try ws.connections.upsert(def, password: c.password)
        ws.sessions.setMainConnection(def.id)
        let doc = ws.newDocument(.sql)
        doc.text = "select empno, ename, hiredate from emp order by empno"
        try await ws.invoke("sql.execute")
        let grid = try #require(doc.results.first?.grid)
        #expect(grid.rowCount == 8)
        #expect(grid.text(row: 0, column: 1) == "SZYMAŃSKA")
        doc.text = "update emp set comm = 5 where empno = 7369"
        try await ws.invoke("sql.execute")
        #expect(doc.transactionOpen)
        try await ws.invoke("session.rollback")
        #expect(!doc.transactionOpen)
        doc.text = "begin dbms_output.put_line('thin ąę'); end;\n/"
        try await ws.invoke("sql.execute")
        #expect(doc.output == ["thin ąę"])
        doc.text = "select brak from dual"
        try await ws.invoke("sql.execute")
        #expect(doc.results.first?.message?.contains("ORA-00904") == true)
        doc.text = "select count(*) from big_rows a, big_rows b where rownum < 2000000"
        let run = Task { try await ws.invoke("sql.execute") }
        while !doc.isExecuting { await Task.yield() }
        try await Task.sleep(for: .milliseconds(200))
        #expect(!ws.isEnabled("sql.break"))
        _ = try? await run.value
        await ws.sessions.disconnectAll()
    }
}
