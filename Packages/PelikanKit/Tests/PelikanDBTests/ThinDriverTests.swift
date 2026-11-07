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

    @Test("CLOB powyżej 32 600 znaków (kolumna i OUT) jak w Instant Client; limit LOB daje znacznik obcięcia", .enabled(if: TestDatabase.isAvailable))
    func longCLOB() async throws {
        // Najpierw Instant Client: gdy go brak, test kończy się przed otwarciem połączenia thin (OracleNIO zgłasza
        // asercję przy zwolnieniu niezamkniętego połączenia).
        let odpi = try await TestDatabase.connect()
        let thin = try await connect()
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

    @Test("Obcięty LOB z lokatora w całości (CLOB > 65 535 znaków, BLOB) po zamknięciu wyniku — thin i Instant Client", .enabled(if: TestDatabase.isAvailable))
    func fullLOBFromLocator() async throws {
        // Najpierw Instant Client: gdy go brak, test kończy się przed otwarciem połączenia thin (OracleNIO zgłasza
        // asercję przy zwolnieniu niezamkniętego połączenia).
        let odpi = try await TestDatabase.connect()
        let thin = try await connect()
        let clob = "select xmlagg(xmlelement(e, 'żółć' || lpad(level, 6, '0'))).getclobval() from dual connect by level <= 6000"
        let blob = "select xmlagg(xmlelement(e, lpad(level, 6, '0'))).getblobval(nls_charset_id('AL32UTF8')) from dual connect by level <= 6000"
        let reference = try #require(try await odpi.queryAll(clob).rows.first?.first)
        guard case .lob(let ref) = reference, let refText = ref.text else { Issue.record("CLOB \(reference)"); return }
        #expect(refText.count > 65_535 && !ref.truncated)
        for s in [thin, odpi] as [any DatabaseSession] {
            for (sql, isText) in [(clob, true), (blob, false)] {
                let r = try await s.execute(sql, binds: [], options: ExecuteOptions(lobLimit: 4000))
                let id = try #require(r.resultSet).id
                let batch = try await s.fetch(id, maxRows: 1)
                await s.closeResultSet(id)
                guard case .lob(let l) = batch.rows.first?.first else { Issue.record("LOB \(s.info.driver)"); continue }
                #expect(l.truncated && l.locator != nil)
                let full = try await s.fullLOB(l)
                #expect(!full.truncated)
                if isText {
                    #expect(full.text == refText, "\(s.info.driver): \(full.text?.count ?? 0) z \(refText.count)")
                } else {
                    #expect(full.bytes.map { String(decoding: $0, as: UTF8.self) } == refText.replacingOccurrences(of: "żółć", with: ""))
                }
                // Strumień porcjami (zapis do pliku) — ta sama treść.
                var streamed = Data()
                try await s.streamLOB(l, chunk: 10_000) { part in streamed.append(part.bytes ?? Data((part.text ?? "").utf8)) }
                #expect(streamed == (full.bytes ?? Data((full.text ?? "").utf8)))
                // Zwolniony lokator (wynik zamknięty) — odczyt kończy się błędem, nie odczytem zwolnionego uchwytu.
                await s.releaseLOBs([try #require(l.locator)])
                await #expect(throws: DatabaseError.self) { _ = try await s.readLOB(l.locator!, offset: 1, amount: 10) }
            }
        }
        await thin.close()
        await odpi.close()
    }

    @Test("INTERVAL YEAR TO MONTH, UROWID (także tabel IOT, ponad 253 bajty) i BFILE (ponad 1 MB, porcjami) jak w Instant Client", .enabled(if: TestDatabase.isAvailable))
    func extraTypesLikeInstantClient() async throws {
        let odpi = try await TestDatabase.connect()
        let thin = try await connect()
        for ddl in ["drop table pelikan_thin_iot purge", "drop table pelikan_thin_iot2 purge"] { _ = try? await odpi.execute(ddl) }
        _ = try await odpi.execute("create table pelikan_thin_iot (id number primary key, v varchar2(20)) organization index")
        _ = try await odpi.execute("insert into pelikan_thin_iot select level, 'w' || level from dual connect by level <= 3")
        _ = try await odpi.execute("create table pelikan_thin_iot2 (k varchar2(1000) primary key, v varchar2(20)) organization index")
        _ = try await odpi.execute("insert into pelikan_thin_iot2 values (rpad('k', 900, 'x'), 'długi')")
        _ = try await odpi.execute("commit")
        // Plik 46 × 25 600 bajtów (wzór 0…255) — ponad największą porcję odczytu BFILE (1 MB).
        let expected = Data((0..<46 * 25_600).map { UInt8($0 % 256) })
        _ = try await odpi.execute("""
            declare
              f utl_file.file_type;
              b raw(256) := hextoraw('00');
              r raw(25600);
            begin
              for i in 1 .. 255 loop b := utl_raw.concat(b, hextoraw(to_char(i, 'FM0X'))); end loop;
              for i in 1 .. 100 loop r := utl_raw.concat(r, b); end loop;
              f := utl_file.fopen('DATA_PUMP_DIR', 'pelikan_thin.bin', 'wb', 32767);
              for i in 1 .. 46 loop utl_file.put_raw(f, r, true); end loop;
              utl_file.fclose(f);
            end;
            """)

        // INTERVAL YEAR TO MONTH: dodatnie, ujemne, z większą precyzją, NULL; kolumna po nim odczytana poprawnie.
        let interval = """
            select interval '1-2' year to month a, interval '-3-4' year to month b, interval '123-11' year(3) to month c,
                   cast(null as interval year to month) d, 'po' e from dual
            """
        let (ivCols, ivThin) = try await thin.queryAll(interval)
        let (ivOdpiCols, ivOdpi) = try await odpi.queryAll(interval)
        #expect(ivThin == ivOdpi && ivCols.map(\.type) == ivOdpiCols.map(\.type))
        #expect(ivThin.first == [.intervalYM(years: 1, months: 2), .intervalYM(years: -3, months: -4),
                                 .intervalYM(years: 123, months: 11), .null, .text("po")])

        // UROWID: fizyczny (tabela zwykła) i logiczny (IOT; długi klucz — postać z porcjami).
        for sql in ["select rowid r, cast(rowid as urowid) u, 'po' e from dept where deptno = 10",
                    "select rowid, id, v from pelikan_thin_iot order by id",
                    "select rowid, v from pelikan_thin_iot2"] {
            let (tc, t) = try await thin.queryAll(sql)
            let (oc, o) = try await odpi.queryAll(sql)
            #expect(!t.isEmpty && t == o && tc.map(\.type) == oc.map(\.type), "\(sql)")
        }
        let (_, physical) = try await thin.queryAll("select rowid r, cast(rowid as urowid) u from dept where deptno = 10")
        #expect(physical.first?[0] == physical.first?[1])
        let (_, logical) = try await thin.queryAll("select rowid, v from pelikan_thin_iot2")
        let rid = try #require(logical.first?.first?.displayText)
        #expect(rid.hasPrefix("*") && rid.utf8.count > 253)
        let (_, found) = try await thin.queryAll("select v from pelikan_thin_iot2 where rowid = :r",
                                                 binds: [BindVariable(name: "r", value: .text(rid))])
        #expect(found.first?.first == .text("długi"))

        // BFILE: obcięty do limitu z lokatorem, całość i strumień porcjami (odczyt od miejsca) — thin i Instant Client.
        for s in [thin, odpi] as [any DatabaseSession] {
            let r = try await s.execute("select bfilename('DATA_PUMP_DIR', 'pelikan_thin.bin') b, 'po' e from dual",
                                        binds: [], options: ExecuteOptions(lobLimit: 4000))
            let id = try #require(r.resultSet).id
            let batch = try await s.fetch(id, maxRows: 1)
            await s.closeResultSet(id)
            guard case .lob(let l) = batch.rows.first?.first else { Issue.record("BFILE \(s.info.driver)"); continue }
            #expect(batch.rows.first?[1] == .text("po"))
            #expect(l.kind == .bfile && l.length == UInt64(expected.count) && l.truncated && l.locator != nil, "\(s.info.driver)")
            #expect(l.bytes == expected.prefix(4000), "\(s.info.driver)")
            let full = try await s.fullLOB(l)
            #expect(full.bytes == expected && !full.truncated, "\(s.info.driver): \(full.bytes?.count ?? 0) z \(expected.count)")
            var streamed = Data()
            try await s.streamLOB(l, chunk: 300_000) { part in streamed.append(part.bytes ?? Data()) }
            #expect(streamed == expected, "\(s.info.driver): \(streamed.count)")
            await s.releaseLOBs([try #require(l.locator)])
        }
        // BFILE do katalogu (ORA-22288 w komórce), do brakującego pliku i NULL — jak Instant Client.
        let odd = """
            select n, case n when 1 then bfilename('DATA_PUMP_DIR', '.')
                             when 2 then bfilename('DATA_PUMP_DIR', 'pelikan_nie_ma_takiego_pliku.bin') end b
              from (select level n from dual connect by level <= 3) order by n
            """
        let (_, oddThin) = try await thin.queryAll(odd)
        let (_, oddOdpi) = try await odpi.queryAll(odd)
        #expect(oddThin.count == 3 && oddThin.map { $0[0] } == oddOdpi.map { $0[0] })
        for (t, o) in zip(oddThin, oddOdpi) {
            switch (t[1], o[1]) {
            case (.lob(let a), .lob(let b)):
                #expect(a.kind == b.kind && a.length == b.length && (a.readError == nil) == (b.readError == nil),
                        "thin \(a.length) \(a.readError ?? "-") / Instant Client \(b.length) \(b.readError ?? "-")")
                #expect(a.readError.map { $0.hasPrefix("ORA-22288") } ?? true, "\(a.readError ?? "")")
            default:
                #expect(t[1] == o[1], "\(t[1]) / \(o[1])")
            }
        }

        // Sesja dalej działa: obsługiwane typy, zmienne wiązane i błąd składni (z wykonania).
        let (_, rows) = try await thin.queryAll("select 1 n, :x t, systimestamp ts, interval '1' day id from dual",
                                                binds: [BindVariable(name: "x", value: .text("a"))])
        #expect(rows.first?.first == .number("1") && rows.first?[1] == .text("a"))
        await #expect(throws: OracleError.self) { _ = try await thin.execute("select nieistniejaca_kolumna from dual") }

        _ = try? await odpi.execute("begin utl_file.fremove('DATA_PUMP_DIR', 'pelikan_thin.bin'); end;")
        for ddl in ["drop table pelikan_thin_iot purge", "drop table pelikan_thin_iot2 purge"] { _ = try? await odpi.execute(ddl) }
        await thin.close()
        await odpi.close()
    }

    @Test("Kolumna typu REF przez thin: utrata połączenia z wyjaśnieniem zamiast końca procesu; nowe połączenie działa", .enabled(if: TestDatabase.isAvailable))
    func refColumnClosesConnection() async throws {
        let odpi = try await TestDatabase.connect()
        for ddl in ["drop table pelikan_thin_ot purge", "drop type pelikan_thin_t force"] { _ = try? await odpi.execute(ddl) }
        _ = try await odpi.execute("create type pelikan_thin_t as object (n number)")
        _ = try await odpi.execute("create table pelikan_thin_ot of pelikan_thin_t")
        _ = try await odpi.execute("insert into pelikan_thin_ot values (pelikan_thin_t(1))")
        _ = try await odpi.execute("commit")
        let thin = try await connect()
        do {
            _ = try await thin.queryAll("select ref(o) r, 'po' e from pelikan_thin_ot o")
            Issue.record("REF bez błędu")
        } catch let e as OracleError {
            #expect(e.isConnectionLost && e.message.contains("typu danych REF") && !e.message.contains("payload"), "\(e.message)")
        }
        #expect(thin.connectionLost)
        await thin.close()
        let again = try await connect()
        #expect(try await again.queryAll("select 1 from dual").rows.first?.first == .number("1"))
        await again.close()
        for ddl in ["drop table pelikan_thin_ot purge", "drop type pelikan_thin_t force"] { _ = try? await odpi.execute(ddl) }
        await odpi.close()
    }

    @Test("Niepełny wynik nie blokuje sesji: inne polecenie, COMMIT i odczyt dalszych wierszy z bufora (D240)")
    func partialResultDoesNotBlock() async throws {
        let s = try await connect()
        let r = try await s.execute("select level n from dual connect by level <= 10000", binds: [],
                                    options: ExecuteOptions(fetchArraySize: 100))
        let id = try #require(r.resultSet).id
        var rows = try await s.fetch(id, maxRows: 100).rows
        #expect(rows.count == 100)
        // Wcześniej: kolejne polecenie czekało w OracleNIO na koniec strumienia — w nieskończoność.
        #expect(try await s.queryAll("select 1 from dual").rows.first?.first == .number("1"))
        try await s.commit()
        try await s.ping()
        while true {
            let b = try await s.fetch(id, maxRows: 3000)
            rows += b.rows
            #expect(b.limitedTo == nil)
            if !b.hasMore { break }
        }
        #expect(rows.count == 10000 && rows.first?.first == .number("1") && rows.last?.first == .number("10000"))
        await s.close()
    }

    @Test("CLOB w wyniku ponad porcję pobierania (300 wierszy po 50): treść LOB-ów bez zakleszczenia (D240)")
    func lobsAcrossFetchBatches() async throws {
        let s = try await connect()
        let r = try await s.execute("select level n, rpad(to_clob('x'), 5000, 'x') c from dual connect by level <= 300",
                                    binds: [], options: ExecuteOptions(fetchArraySize: 50))
        let id = try #require(r.resultSet).id
        var rows: [[OracleValue]] = []
        while true {
            let b = try await s.fetch(id, maxRows: 100)
            rows += b.rows
            if !b.hasMore { break }
        }
        #expect(rows.count == 300 && rows.last?.first == .number("300"))
        #expect(rows.allSatisfy { if case .lob(let l) = $0[1] { l.text?.count == 5000 && !l.truncated } else { false } })
        await s.close()
    }

    @Test("Dobieranie wyniku przed innym poleceniem: najwyżej 100 000 wierszy, wynik oznaczony jako ucięty (D240)")
    func settleLimit() async throws {
        let s = try await connect()
        let r = try await s.execute("select level n from dual connect by level <= 100050", binds: [],
                                    options: ExecuteOptions(fetchArraySize: 5000))
        let id = try #require(r.resultSet).id
        var count = try await s.fetch(id, maxRows: 10).rows.count
        _ = try await s.queryAll("select 1 from dual")
        var last: RowBatch?
        while true {
            let b = try await s.fetch(id, maxRows: 20_000)
            count += b.rows.count
            last = b
            if !b.hasMore { break }
        }
        #expect(count == ThinSession.settleRowLimit && last?.limitedTo == ThinSession.settleRowLimit)
        // Bez innego polecenia w trakcie — wynik pełny (strumień czytany na bieżąco).
        let full = try await s.queryAll("select level n from dual connect by level <= 100050", limit: 200_000).rows
        #expect(full.count == 100050)
        await s.close()
    }

    @Test("Pusty wynik z opisem kolumn jak w Instant Client (wcześniej siatka bez nagłówków)", .enabled(if: TestDatabase.isAvailable))
    func emptyResultColumns() async throws {
        let odpi = try await TestDatabase.connect()
        let thin = try await connect()
        let sql = "select deptno, dname, sysdate d from dept where 1 = 0"
        let (tc, t) = try await thin.queryAll(sql)
        let (oc, o) = try await odpi.queryAll(sql)
        #expect(t.isEmpty && o.isEmpty && tc.map(\.name) == ["DEPTNO", "DNAME", "D"] && tc.map(\.name) == oc.map(\.name)
                && tc.map(\.type) == oc.map(\.type))
        await thin.close()
        await odpi.close()
    }

    @Test("Zamknięte niepełne wyniki zamykają kursory serwera: 350 wyników (ponad OPEN_CURSORS) bez ORA-01000")
    func closedPartialResultsReleaseCursors() async throws {
        let s = try await connect()
        for _ in 0..<350 {
            let r = try await s.execute("select level n from dual connect by level <= 10000", binds: [],
                                        options: ExecuteOptions(fetchArraySize: 100))
            let id = try #require(r.resultSet).id
            #expect(try await s.fetch(id, maxRows: 10).rows.count == 10)
            await s.closeResultSet(id)
        }
        #expect(try await s.queryAll("select 1 from dual").rows.first?.first == .number("1"))
        await s.close()
    }

    @Test("Polecenie po zamknięciu połączenia: błąd od razu zamiast czekania bez końca", .timeLimit(.minutes(1)))
    func operationAfterClose() async throws {
        let s = try await connect()
        await s.close()
        await #expect(throws: (any Error).self) { _ = try await s.execute("select 1 from dual") }
        await #expect(throws: (any Error).self) { try await s.commit() }
        #expect(s.connectionLost)
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

    @Test("DBMS_OUTPUT ponad 65 535 znaków: obcięty ze znacznikiem zamiast awarii OracleNIO (odpowiedź z 3-bajtową długością)")
    func largeOutput() async throws {
        let s = try await connect()
        try await LargeOutputCheck.run(s, complete: false)
        await s.close()
    }

    @Test("VECTOR (23ai) dekodowany jak w Instant Client")
    func vector() async throws {
        let s = try await connect()
        if s.info.server.major >= 23 {
            let (_, v) = try await s.queryAll("""
                SELECT TO_VECTOR('[1.5,2,3]', 3, FLOAT32), TO_VECTOR('[1.25,-2]', 2, FLOAT64), TO_VECTOR('[1,-2,3]', 3, INT8) FROM dual
                """)
            #expect(v.first == [.vector([1.5, 2, 3]), .vector([1.25, -2]), .vector([1, -2, 3])])
        }
        await s.close()
    }
}


/// Wyjście DBMS_OUTPUT większe niż domyślny limit LOB (1 Mi znaków): całe (liczba linii i ostatnia linia się zgadzają)
/// albo — w sterowniku thin — ucięte z jawną informacją w ostatniej linii.
enum LargeOutputCheck {
    static func run(_ s: any DatabaseSession, complete: Bool = true) async throws {
        try await SessionUtilities.enableOutput(s, bufferSize: 0)
        _ = try await s.execute("""
            begin
              for i in 1 .. 1200 loop dbms_output.put_line(lpad(to_char(i), 1000, 'x')); end loop;
              dbms_output.put_line('koniec');
            end;
            """)
        let lines = try await SessionUtilities.readOutput(s)
        #expect(lines.first == String(repeating: "x", count: 999) + "1")
        guard complete else {
            #expect(lines.last == "*** DBMS_OUTPUT: \(ThinSession.maxCLOBRead) / \(1200 * 1001 + 6) ***")
            return
        }
        #expect(lines.count == 1201)
        #expect(lines[1199] == String(repeating: "x", count: 996) + "1200")
        #expect(lines.last == "koniec")
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
        // Wynik ponad porcję pobierania: DBMS_OUTPUT po zapytaniu nie czeka na koniec strumienia (D240), siatka
        // dociąga resztę.
        doc.text = "select level n from dual connect by level <= 5000"
        try await ws.invoke("sql.execute")
        let big = try #require(doc.results.first?.grid)
        await big.fetchAll()
        #expect(big.rowCount == 5000 && big.driverRowLimit == nil)
        doc.text = "select count(*) from big_rows a, big_rows b where rownum < 2000000"
        let run = Task { try await ws.invoke("sql.execute") }
        while !doc.isExecuting { await Task.yield() }
        try await Task.sleep(for: .milliseconds(200))
        #expect(!ws.isEnabled("sql.break"))
        _ = try? await run.value
        await ws.sessions.disconnectAll()
    }
}
