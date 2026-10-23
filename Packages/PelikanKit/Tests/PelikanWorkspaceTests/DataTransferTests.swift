import Foundation
import PelikanDB
@testable import PelikanWorkspace
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
}
