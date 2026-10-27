import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Synchronization
import Testing

@Suite("Narzędzia danych bez bazy")
struct DataTransferOfflineTests {
    @Test("CSV: wykrycie separatora i nagłówka, pola w cudzysłowach z separatorem i nową linią, zakres linii")
    func csv() {
        let text = "id;nazwa;kwota\n1;\"Kowalski; Jan\";12,50\n2;\"wiersz\ndrugi\";7\n\n3;\"cytat \"\"x\"\"\";1\n"
        var f = TextImport.detect(text)
        #expect(f.delimiter == ";" && f.header)
        let (h, rows) = TextImport.parse(text, f)
        #expect(h == ["id", "nazwa", "kwota"] && rows.count == 3)
        #expect(rows[0][1] == "Kowalski; Jan" && rows[1][1] == "wiersz\ndrugi" && rows[2][1] == "cytat \"x\"")
        f.firstLine = 2
        f.lastLine = 2
        #expect(TextImport.parse(text, f).rows.map { $0[0] } == ["2"])
        let tsv = TextImport.detect("a\tb\n1\t2\n3\t4")
        #expect(tsv.delimiter == "\t")
    }

    @Test("Kodowanie: BOM UTF-8, Windows-1250 dla polskich znaków")
    func encoding() {
        #expect(TextImport.decode(Data([0xEF, 0xBB, 0xBF]) + Data("żółw".utf8)).text == "żółw")
        let cp1250 = "Łódź".data(using: .windowsCP1250)!
        #expect(TextImport.decode(cp1250) == ("Łódź", .windowsCP1250))
    }

    @Test("Mapowanie: liczby z przecinkiem, data z liczby Excela, funkcja z #, blok z filtrem i duplikatami, skrypt")
    func mapping() {
        let num = FieldMapping(column: "KWOTA", field: 2, type: .number)
        #expect(TextImport.prepared(" 1 234,50", num) == "1234.50")
        let date = FieldMapping(column: "D", field: 0, type: .date, dateFormat: "DD.MM.YYYY")
        #expect(TextImport.prepared("45292", date) == "2024-01-01 00:00:00")
        #expect(TextImport.prepared("45292.5", date) == "2024-01-01 12:00:00")
        var t = ImportTarget(owner: "S", table: "T", mappings: [FieldMapping(column: "ID", field: 0, type: .number),
                                                               FieldMapping(column: "NAZWA", field: 1, function: "upper(#)"), FieldMapping(column: "X", field: nil)])
        t.filter = ":KWOTA > 5"
        t.duplicates = .overwrite
        let sql = TextImport.rowStatement(t, fieldNames: ["id", "nazwa", "kwota"], keyColumns: ["ID"])
        #expect(sql.contains("insert into S.T (ID, NAZWA) select :ID, upper(:NAZWA) from dual where :KWOTA > 5"))
        #expect(sql.contains("when dup_val_on_index then :n_ := 0; update S.T set NAZWA = upper(:NAZWA) where ID = :ID"))
        let script = TextImport.script([["1", "a'b", "7"]], fieldNames: ["id", "nazwa", "kwota"], target: t)
        #expect(script.contains("select 1, upper('a''b') from dual where '7' > 5;"))
        let (create, maps) = TextImport.createTable(owner: "S", table: "NOWA", fieldNames: ["id", "data", "opis"],
                                                    rows: [["1", "2024-01-02", "abc"], ["2", "2024-02-03", "de"]])
        #expect(create.contains("ID NUMBER") && create.contains("DATA DATE") && create.contains("OPIS VARCHAR2(10 CHAR)"))
        #expect(maps[1].type == .date && maps[1].dateFormat == "YYYY-MM-DD")
    }

    @Test("Excel: odczyt xlsx zapisanego przez Pelikana i archiwum z wpisem deflate")
    func xlsx() throws {
        let data = ExportData(title: "Arkusz", columns: [ColumnInfo(name: "ID", type: .number, typeName: "NUMBER"), ColumnInfo(name: "NAZWA", type: .varchar2, typeName: "VARCHAR2")],
                              rows: [[.number("1"), .text("Żółw")], [.number("2"), .null], [.number("3"), .text("ok & <tak>")]])
        let wb = try XlsxWorkbook(ResultExporter.xlsx([data]))
        #expect(wb.sheets.map(\.name) == ["Arkusz"])
        let rows = try wb.rows(sheet: 0)
        #expect(rows == [["ID", "NAZWA"], ["1", "Żółw"], ["2", ""], ["3", "ok & <tak>"]])
        #if canImport(Darwin)
        // Wpis „deflate” (metoda 8) z sharedStrings — tak zapisuje Excel.
        let shared = Data(#"<sst xmlns="x"><si><t>alfa</t></si><si><r><t>be</t></r><r><t>ta</t></r></si></sst>"#.utf8)
        let sheet = Data(#"<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row><row r="3"><c r="B3"><v>4.5</v></c></row></sheetData></worksheet>"#.utf8)
        let wbXML = Data(#"<workbook xmlns:r="r"><sheets><sheet name="Dane" sheetId="1" r:id="rId1"/></sheets></workbook>"#.utf8)
        let rels = Data(#"<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>"#.utf8)
        let zip = Self.zip([("xl/workbook.xml", wbXML), ("xl/_rels/workbook.xml.rels", rels), ("xl/sharedStrings.xml", shared), ("xl/worksheets/sheet1.xml", sheet)])
        let wb2 = try XlsxWorkbook(zip)
        #expect(try wb2.rows(sheet: 0) == [["alfa", "", "beta"], ["", "", ""], ["", "4.5", ""]])
        #endif
    }

    #if canImport(Darwin)
    /// Archiwum ZIP z wpisami skompresowanymi DEFLATE (test czytnika).
    static func zip(_ files: [(String, Data)]) -> Data {
        var out = Data(), central = Data()
        for (name, content) in files {
            let packed = try! (content as NSData).compressed(using: .zlib) as Data
            let n = Data(name.utf8), crc = CRC32.checksum(content), offset = UInt32(out.count)
            out.append(le32: 0x0403_4B50); out.append(le16: 20); out.append(le16: 0); out.append(le16: 8); out.append(le16: 0); out.append(le16: 0x21)
            out.append(le32: crc); out.append(le32: UInt32(packed.count)); out.append(le32: UInt32(content.count))
            out.append(le16: UInt16(n.count)); out.append(le16: 0); out.append(n); out.append(packed)
            central.append(le32: 0x0201_4B50); central.append(le16: 20); central.append(le16: 20); central.append(le16: 0); central.append(le16: 8)
            central.append(le16: 0); central.append(le16: 0x21); central.append(le32: crc); central.append(le32: UInt32(packed.count))
            central.append(le32: UInt32(content.count)); central.append(le16: UInt16(n.count)); central.append(le16: 0); central.append(le16: 0)
            central.append(le16: 0); central.append(le16: 0); central.append(le32: 0); central.append(le32: offset); central.append(n)
        }
        let co = UInt32(out.count)
        out.append(central)
        out.append(le32: 0x0605_4B50); out.append(le16: 0); out.append(le16: 0); out.append(le16: UInt16(files.count)); out.append(le16: UInt16(files.count))
        out.append(le32: UInt32(central.count)); out.append(le32: co); out.append(le16: 0)
        return out
    }
    #endif

    @Test("Generator: wzorce, powtórzenia, literały, funkcje, zbiory, master/detail i powtarzalność ziarna")
    func generator() async throws {
        let parts = DataGenerator.parse("Klient [A(1)a(3..5)'-'0(2)] Random(1, 9)")
        #expect(parts.count == 4)
        let master = GeneratorTable(name: "M", minRecords: 3, maxRecords: 3, fields: [
            .init(name: "ID", type: "NUMBER", definition: "Sequence(10, 5)"),
            .init(name: "KOD", type: "VARCHAR2", definition: "[A(2)0(3)]"),
            .init(name: "FIRSTNAME", type: "VARCHAR2", definition: "Firstname"),
            .init(name: "LASTNAME", type: "VARCHAR2", definition: "Lastname"),
            .init(name: "EMAIL", type: "VARCHAR2", definition: "Email"),
            .init(name: "STAN", type: "VARCHAR2", definition: "List('A'(9), 'B'(1))"),
            .init(name: "DATA", type: "DATE", definition: "Random('2024-01-01', '2024-01-31')"),
            .init(name: "OPIS", type: "VARCHAR2", definition: "Uppercase([a(3)])"),
        ])
        let detail = GeneratorTable(name: "D", minRecords: 1, maxRecords: 2, fields: [
            .init(name: "M_ID", type: "NUMBER", definition: "Parent(ID)"),
            .init(name: "LP", type: "NUMBER", definition: "Sequence(1, 1, WithinParent)"),
        ], parent: "M")
        var g1 = DataGenerator(seed: 42)
        let a = try await g1.generate([master, detail])
        var g2 = DataGenerator(seed: 42)
        let b = try await g2.generate([master, detail])
        #expect(a == b)
        let m = a["M"]!
        #expect(m.map { $0["ID"]! } == ["10", "15", "20"])
        #expect(m.allSatisfy { $0["KOD"]!.range(of: #"^[A-Z]{2}[0-9]{3}$"#, options: .regularExpression) != nil })
        #expect(m.allSatisfy { $0["EMAIL"]!.contains("@") && $0["DATA"]!.hasPrefix("2024-01-") && $0["OPIS"]! == $0["OPIS"]!.uppercased() })
        let d = a["D"]!
        #expect(d.count >= 3 && d.count <= 6 && d.allSatisfy { r in m.contains { $0["ID"] == r["M_ID"] } })
        #expect(d.first?["LP"] == "1")
        let script = DataGenerator.script(a, tables: [master, detail], owner: "S", commitEvery: 2)
        #expect(script.contains("insert into S.M (ID, KOD, FIRSTNAME, LASTNAME, EMAIL, STAN, DATA, OPIS) values (10, '") && script.contains("TO_DATE('2024-01-"))
    }

    @Test("Format własny: kompresja i odczyt; porównanie danych: polecenia wyrównujące")
    func nativeAndCompare() throws {
        let file = PelikanTableFile(created: "2026-10-23", tables: [PelikanTableData(owner: "S", name: "T", ddl: "create table t (id number)",
                                                                                     columns: [.init(name: "ID", type: "NUMBER")], rows: [["1"], [nil]])])
        let packed = try TableTransfer.packNative(file)
        #expect(try TableTransfer.unpackNative(packed) == file)
        #expect(throws: (any Error).self) { try TableTransfer.unpackNative(Data("xyz".utf8)) }
        let diff = TableDataDiff(table: "T", columns: ["ID", "N"], keyColumns: ["ID"], inserts: [[.number("3"), .text("c")]],
                                 updates: [[.number("2"), .text("b'")]], deletes: [[.number("9"), .null]])
        var o = DataCompareOptions()
        o.ownerInScript = true
        #expect(TableDataCompare.statements(diff, targetOwner: "X", options: o) == [
            "delete from X.T where ID = 9", "update X.T set N = 'b''' where ID = 2", "insert into X.T (ID, N) values (3, 'c')",
        ])
        o.delete = false
        #expect(TableDataCompare.statements(diff, targetOwner: "X", options: o).count == 2)
    }

    @Test("CSV: końce wierszy CRLF (jeden znak w Swifcie), CRLF w polu w cudzysłowie, separator wieloznakowy bez awarii")
    func crlf() {
        let text = "id,nazwa\r\n1,\"a\r\nb\"\r\n2,c\r\n"
        let f = TextImport.detect(text)
        #expect(f.delimiter == "," && f.header)
        let (header, rows) = TextImport.parse(text, f)
        #expect(header == ["id", "nazwa"] && rows == [["1", "a\r\nb"], ["2", "c"]])
        var multi = TextFormat()
        multi.header = false
        multi.delimiter = ";;"
        #expect(TextImport.parse("1;2\n3;4", multi).rows == [["1", "2"], ["3", "4"]])
        // Niepoprawne UTF-8 bez BOM: kodowanie jednobajtowe, bez utraty znaków.
        #expect(TextImport.decode(Data([0x41, 0xB1, 0x0A])).text == "Aą\n")
    }

    @Test("Nazwy zmiennych pól: słowa zastrzeżone z przyrostkiem (ORA-01745), kolumna nowej tabeli bez zmian")
    func reservedBindNames() {
        #expect(TextImport.bindName("date", index: 0) == "DATE_" && TextImport.bindName("Level", index: 1) == "LEVEL_")
        #expect(TextImport.bindName("kwota", index: 2) == "KWOTA" && TextImport.bindName("1x", index: 3) == "POLE4")
        let t = ImportTarget(owner: "S", table: "T", mappings: [FieldMapping(column: "D", field: 0), FieldMapping(column: "SIZE", field: 1)])
        let sql = TextImport.rowStatement(t, fieldNames: ["date", "size"], keyColumns: [])
        #expect(sql.contains("select :DATE_, :SIZE_ from dual"))
        #expect(TextImport.createTable(owner: "S", table: "T", fieldNames: ["date"], rows: [["x"]]).mappings[0].column == "DATE")
    }

    #if canImport(Darwin)
    @Test("Excel: uszkodzony katalog ZIP i komórka na końcu arkusza — błąd zamiast awarii; wiersz spoza arkusza pominięty")
    func xlsxCorrupted() throws {
        let wbXML = Data(#"<workbook xmlns:r="r"><sheets><sheet name="Dane" sheetId="1" r:id="rId1"/></sheets></workbook>"#.utf8)
        let rels = Data(#"<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>"#.utf8)
        func book(_ sheet: String) -> Data {
            Self.zip([("xl/workbook.xml", wbXML), ("xl/_rels/workbook.xml.rels", rels), ("xl/worksheets/sheet1.xml", Data(sheet.utf8))])
        }
        // Długość nazwy wpisu w katalogu centralnym poza końcem pliku.
        var broken = book("<worksheet/>")
        let central = try #require(broken.lastRange(of: Data([0x50, 0x4B, 0x01, 0x02])))
        broken[central.lowerBound + 28] = 0xFF
        broken[central.lowerBound + 29] = 0xFF
        #expect(throws: ZipReader.Failure.self) { _ = try ZipReader(broken) }
        let huge = try XlsxWorkbook(book(#"<worksheet><sheetData><row r="1"><c r="A1"><v>1</v></c><c r="XFD1048576"><v>2</v></c></row></sheetData></worksheet>"#))
        #expect(throws: CommandError.self) { _ = try huge.rows(sheet: 0) }
        let odd = try XlsxWorkbook(book(#"<worksheet><sheetData><row r="0"><c><v>x</v></c></row><row r="1"><c r="A0"><v>y</v></c><c r="B1"><v>2</v></c></row></sheetData></worksheet>"#))
        #expect(try odd.rows(sheet: 0) == [["y", "2"]])     // wiersz r="0" pominięty, adres A0 — pozycja w wierszu
        #expect(XlsxWorkbook.cellIndex("AAAAAAAAAAAAAAAA1") == nil && XlsxWorkbook.cellIndex("XFE1") == nil)
    }
    #endif

    func blob(_ byte: UInt8, count: Int = 3000, truncated: Bool = false) -> OracleValue {
        .lob(LOBValue(kind: .blob, bytes: Data(repeating: byte, count: count), length: UInt64(count), truncated: truncated))
    }

    @Test("Porównanie danych: BLOB-y ponad limit literału po treści, obcięty LOB i obiekt — błąd, nie „równe”")
    func compareLOBs() throws {
        let cols = ["ID", "B"]
        let d = try TableDataCompare.diff(table: "T", columns: cols, keyColumns: ["ID"],
                                          source: [[.number("1"), blob(1)], [.number("2"), blob(2)]],
                                          target: [[.number("1"), blob(9)], [.number("2"), blob(2)]])
        #expect(d.updates.count == 1 && d.updates.first?.first == .number("1") && d.inserts.isEmpty && d.deletes.isEmpty)
        #expect(throws: CommandError.self) {
            try TableDataCompare.diff(table: "T", columns: cols, keyColumns: ["ID"], source: [[.number("1"), blob(1, truncated: true)]],
                                      target: [[.number("1"), blob(1, truncated: true)]])
        }
        #expect(throws: CommandError.self) {
            try TableDataCompare.diff(table: "T", columns: cols, keyColumns: ["ID"], source: [[.number("1"), .object(typeName: "S.ADR_T", description: "x")]],
                                      target: [[.number("1"), .object(typeName: "S.ADR_T", description: "x")]])
        }
    }

    @Test("Wyrównanie na bazie: LOB-y i RAW jako zmienne wiązane, zawsze w schemacie celu; wartość nieprzenoszalna przerywa przed zmianami")
    func applyBindsLOBs() async throws {
        let diff = TableDataDiff(table: "T", columns: ["ID", "B", "R"], keyColumns: ["ID"], inserts: [[.number("3"), blob(7), .raw(Data([1, 2]))]],
                                 updates: [[.number("2"), blob(8), .null]], deletes: [])
        var o = DataCompareOptions()
        o.ownerInScript = false
        let s = RecordingSession()
        let r = try await TableDataCompare.apply([diff], targetOwner: "X", options: o, in: s)
        #expect(r.inserted == 1 && r.updated == 1 && r.errors.isEmpty)
        let run = s.executed.withLock { $0 }
        #expect(run.map(\.sql) == ["update X.T set B = :v0, R = NULL where ID = 2", "insert into X.T (ID, B, R) values (3, :v0, :v1)"])
        if case .lob(let l) = run[1].binds[0].value { #expect(l.bytes?.count == 3000 && run[1].binds[0].type == .blob) } else { Issue.record("BLOB bez wiązania") }
        #expect(run[1].binds[1].type == .raw)
        // Skrypt: bez schematu (opcja), z ostrzeżeniem o wartościach bez literału.
        let script = TableDataCompare.script([diff], targetOwner: "X", options: o)
        #expect(script.contains("insert into T (ID, B, R)") && script.contains("UWAGA"))
        let bad = TableDataDiff(table: "T", columns: ["ID", "B"], keyColumns: ["ID"], inserts: [[.number("1"), blob(1)], [.number("2"), blob(1, truncated: true)]],
                                updates: [], deletes: [])
        let s2 = RecordingSession()
        await #expect(throws: CommandError.self) { _ = try await TableDataCompare.apply([bad], targetOwner: "X", options: o, in: s2) }
        #expect(s2.executed.withLock { $0 }.isEmpty)
    }

    @Test("Przenoszenie danych: BLOB jako zmienna wiązana; LOB obcięty przerywa; kolumna obiektowa — błąd przed TRUNCATE")
    func transferBindsLOBs() async throws {
        var job = DataTransferJob()
        job.sourceOwner = "S"; job.sourceTable = "SRC"; job.targetOwner = "T"; job.targetTable = "DST"
        job.mappings = [TransferColumnMapping(target: "ID", source: "ID"), TransferColumnMapping(target: "B", source: "B")]
        let cols = [ColumnInfo(name: "ID", type: .number, typeName: "NUMBER"), ColumnInfo(name: "B", type: .blob, typeName: "BLOB")]
        let target = RecordingSession()
        let r = try await DataTransferRunner.run(job, source: RecordingSession(columns: cols, rows: [[.number("1"), blob(5)]]), target: target)
        let run = target.executed.withLock { $0 }
        #expect(r.inserted == 1 && run.map(\.sql) == ["insert into T.DST (ID, B) values (1, :v0)"] && run.first?.binds.first?.type == .blob)
        let target2 = RecordingSession()
        await #expect(throws: CommandError.self) {
            _ = try await DataTransferRunner.run(job, source: RecordingSession(columns: cols, rows: [[.number("1"), blob(5, truncated: true)]]), target: target2)
        }
        #expect(target2.executed.withLock { $0 }.isEmpty)
        job.mode = .truncate
        let target3 = RecordingSession()
        let objCols = [cols[0], ColumnInfo(name: "B", type: .object, typeName: "S.ADR_T")]
        await #expect(throws: CommandError.self) {
            _ = try await DataTransferRunner.run(job, source: RecordingSession(columns: objCols, rows: []), target: target3)
        }
        #expect(target3.executed.withLock { $0 }.isEmpty)
    }

    @Test("Import formatu własnego: RAW, BLOB i CLOB wiązane bez tekstu szesnastkowego (limit 4000 B)")
    func nativeBinds() {
        let big = Data(repeating: 0xAB, count: 5000)
        #expect(TableTransfer.valueExpression("BLOB", bind: "c0") == ":c0" && TableTransfer.valueExpression("DATE", bind: "c1").hasPrefix("TO_DATE("))
        let b = TableTransfer.bindValue("BLOB", name: "c0", value: big.base64EncodedString())
        if case .lob(let l) = b.value { #expect(b.type == .blob && l.bytes == big) } else { Issue.record("BLOB bez LOB-a") }
        #expect(TableTransfer.bindValue("RAW", name: "c1", value: Data([1, 2]).base64EncodedString()).value == .raw(Data([1, 2])))
        #expect(TableTransfer.bindValue("CLOB", name: "c2", value: "tekst").type == .clob)
        #expect(TableTransfer.bindValue("NUMBER", name: "c3", value: "1.5").value == .number("1.5"))
        #expect(TableTransfer.bindValue("VARCHAR2", name: "c4", value: nil).value == .null)
    }

    @Test("Format własny: TIMESTAMP WITH TIME ZONE z przesunięciem (także ujemnym poniżej godziny) i TO_TIMESTAMP_TZ przy imporcie (R7-03)")
    func nativeTimeZone() {
        let t = OracleTimestamp(year: 2024, month: 1, day: 2, hour: 10, minute: 5, second: 6, fsecond: 7, tzHourOffset: 5, tzMinuteOffset: 30)
        #expect(TableTransfer.encode(.timestamp(t, .timestampTZ)) == "2024-01-02 10:05:06.000000007 +05:30")
        var neg = t
        neg.tzHourOffset = 0
        neg.tzMinuteOffset = -30
        #expect(TableTransfer.encode(.timestamp(neg, .timestampTZ))?.hasSuffix(" -00:30") == true)
        #expect(TableTransfer.encode(.timestamp(t, .timestamp)) == "2024-01-02 10:05:06.000000007")
        #expect(TableTransfer.valueExpression("TIMESTAMP(6) WITH TIME ZONE", bind: "c0") == "TO_TIMESTAMP_TZ(:c0, 'YYYY-MM-DD HH24:MI:SS.FF9 TZH:TZM')")
        #expect(TableTransfer.valueExpression("TIMESTAMP(6) WITH LOCAL TIME ZONE", bind: "c0").hasPrefix("TO_TIMESTAMP(:c0"))
        #expect(TableTransfer.valueExpression("TIMESTAMP(3)", bind: "c0").hasPrefix("TO_TIMESTAMP(:c0"))
    }

    @Test("Import formatu własnego z „Utwórz”: tylko DDL tej tabeli — CREATE TABLE/INDEX, ALTER TABLE, COMMENT (R7-10)")
    func nativeDDLAllowList() {
        let ok = [
            "CREATE TABLE \"PELIKAN_T\" (\"ID\" NUMBER, CONSTRAINT \"PK\" PRIMARY KEY (\"ID\"))",
            "CREATE GLOBAL TEMPORARY TABLE pelikan_t (id number) ON COMMIT PRESERVE ROWS",
            "CREATE TABLE HR.PELIKAN_T (v number generated always as (id / 2) virtual)",
            "CREATE UNIQUE INDEX \"PELIKAN_T_IX\" ON \"PELIKAN_T\" (\"ID\")",
            "CREATE BITMAP INDEX hr.pelikan_t_bx ON hr.pelikan_t (id)",
            "ALTER TABLE \"PELIKAN_T\" ADD CONSTRAINT \"FK\" FOREIGN KEY (\"ID\") REFERENCES \"INNA\" (\"ID\") ENABLE",
            "COMMENT ON TABLE pelikan_t IS 'opis; z średnikiem'",
            "COMMENT ON COLUMN \"PELIKAN_T\".\"ID\" IS 'x'",
        ]
        for sql in ok { #expect(TableTransfer.isTableDDL(sql, table: "PELIKAN_T", owner: "HR"), "\(sql)") }
        let bad = [
            "GRANT DBA TO PUBLIC",
            "BEGIN EXECUTE IMMEDIATE 'DROP TABLE X'; END",
            "DROP TABLE PELIKAN_T",
            "CREATE TABLE INNA (id number)",
            "CREATE TABLE SYS.PELIKAN_T (id number)",
            "CREATE TABLE PELIKAN_T AS SELECT * FROM HR.SALARIES",
            "CREATE INDEX IX ON INNA (ID)",
            "ALTER TABLE INNA ADD (X NUMBER)",
            "ALTER TABLE PELIKAN_T DROP COLUMN ID",
            "ALTER USER HR ACCOUNT UNLOCK",
            "COMMENT ON TABLE INNA IS 'x'",
            "CREATE OR REPLACE PROCEDURE PELIKAN_T IS BEGIN NULL; END",
        ]
        for sql in bad { #expect(!TableTransfer.isTableDDL(sql, table: "PELIKAN_T", owner: "HR"), "\(sql)") }
    }

    @Test("Eksport obiektów: bezpieczne nazwy plików, kolizje nazw rozróżnione, specyfikacja z ciałem w jednym pliku")
    func objectExportFiles() {
        var o = ObjectExportOptions()
        o.layout = .filePerObject
        let parts: [(DBObject, String)] = [(DBObject(owner: "S", name: "../Evil/x", type: .view), "v1"), (DBObject(owner: "S", name: "Foo", type: .view), "v2"),
                                           (DBObject(owner: "S", name: "FOO", type: .view), "v3"), (DBObject(owner: "S", name: "PKG", type: .package), "spec"),
                                           (DBObject(owner: "S", name: "PKG", type: .packageBody), "body")]
        let files = ObjectExport.files(parts, options: o, header: "")
        #expect(files.map { ($0.name as NSString).deletingPathExtension } == ["___evil_x", "foo", "foo_2", "pkg"])
        #expect(files.allSatisfy { !$0.name.contains("/") } && Set(files.map(\.name)).count == 4)
        #expect(files.first { $0.name.hasPrefix("pkg.") }.map { $0.content.contains("spec") && $0.content.contains("body") } == true)
        #expect(files.first { $0.name.hasPrefix("foo_2.") }?.content.contains("v3") == true)
    }

    @Test("Eksport obiektów: nieudane pobranie listy uprawnień nie jest ponawiane dla każdego obiektu")
    func objectExportGrantsOnce() async throws {
        let s = OldDictionarySession(missing: ["tab_privs": 942])
        let objects = (1...3).map { DBObject(owner: "S", name: "V\($0)", type: .view) }
        _ = try await ObjectExport.export(objects, options: ObjectExportOptions(), in: s)
        #expect(s.executed.withLock { $0 }.filter { $0.contains("tab_privs") }.count == 2)
    }

    @Test("Generator: liczba powtórzeń ujemna nie przerywa, apostrof w dacie podwojony")
    func generatorEdgeCases() async throws {
        #expect(DataGenerator.parsePattern("a(-1)").first?.min == 0)
        var g = DataGenerator(seed: 1, session: nil)
        let rows = try await g.generate([GeneratorTable(name: "T", minRecords: 1, maxRecords: 1, fields: [.init(name: "A", type: "VARCHAR2", definition: "[a(-1)]x")])])
        #expect(rows["T"]?.first?["A"] == "x")
        #expect(DataGenerator.literal("2024-01-01' x", type: "DATE") == "TO_DATE('2024-01-01'' x', 'YYYY-MM-DD HH24:MI:SS')")
    }
}

/// Sesja zapisująca polecenia ze zmiennymi wiązanymi; zapytanie (select) zwraca `rows` o kolumnach `columns`.
final class RecordingSession: DatabaseSession, @unchecked Sendable {
    let info = SessionInfo(driver: .instantClient, driverVersion: "fake", clientVersion: "0", server: ServerVersion(major: 19, minor: 0),
                           capabilities: [], currentSchema: "U", sessionUser: "U")
    let columns: [ColumnInfo]
    let rows: [[OracleValue]]
    let executed = Mutex<[(sql: String, binds: [BindVariable])]>([])
    init(columns: [ColumnInfo] = [], rows: [[OracleValue]] = []) { self.columns = columns; self.rows = rows }
    func execute(_ sql: String, binds: [BindVariable], options: ExecuteOptions) async throws -> ExecutionResult {
        if sql.hasPrefix("select") { return ExecutionResult(kind: .query, resultSet: ResultSetDescriptor(id: ResultSetID(1), columns: columns)) }
        executed.withLock { $0.append((sql, binds)) }
        return ExecutionResult(kind: .dml, rowsAffected: 1)
    }
    func fetch(_ resultSet: ResultSetID, maxRows: Int) async throws -> RowBatch { RowBatch(rows: rows, hasMore: false) }
    func closeResultSet(_ resultSet: ResultSetID) async {}
    func commit() async throws {}
    func rollback() async throws {}
    func breakExecution() {}
    func ping() async throws {}
    func setTags(_ tags: SessionTags) async throws {}
    func close() async {}
}
