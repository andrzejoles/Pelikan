import Foundation
import PelikanDB
@testable import PelikanWorkspace
import Testing

@MainActor
@Suite("Test Window — bez bazy (PD-TEST-002, PD-TEST-005)")
struct TestWindowUnitTests {
    @Test("Substitution: :nazwa zastąpione tekstem wartości, inne zmienne bez zmian, napisy i komentarze nietknięte")
    func substitution() {
        let vars = [TestVariable(name: "tab", type: .substitution, value: "emp", isNull: false), TestVariable(name: "x", type: .integer, value: "1", isNull: false)]
        let text = "begin select count(*) into :x from :tab where ':tab' <> 'a'; -- :tab\nend;"
        #expect(TestRunner.substitute(text, vars) == "begin select count(*) into :x from emp where ':tab' <> 'a'; -- :tab\nend;")
        #expect(TestRunner.substitute(text, [vars[1]]) == text)
    }

    @Test("BFile: blok obudowany zmienną lokalną w pierwszej linii, :nazwa zastąpiona, wiązania katalogu i pliku")
    func bfileWrap() {
        let v = TestVariable(name: "plik", type: .bfile, value: "KAT:a.txt", isNull: false)
        let w = TestRunner.bfileWrap("begin\n  :plik := bfilename('X', 'b'); -- :plik\nend;", [v, TestVariable(name: "n", type: .integer)])
        #expect(w.sql.hasPrefix("declare pelikan$bf1 bfile := case when :pelikan_bf1_d is null"))
        #expect(w.sql.components(separatedBy: "\n")[0].hasSuffix("begin begin"))
        #expect(w.sql.contains("pelikan$bf1 := bfilename('X', 'b'); -- :plik") && w.sql.contains("dbms_lob.filegetname(pelikan$bf1, :pelikan_bf1_d, :pelikan_bf1_f)"))
        #expect(w.binds.map(\.value) == [.text("KAT"), .text("a.txt")])
        #expect(TestRunner.bfileWrap("begin null; end;", [TestVariable(name: "x")]).sql == "begin null; end;")
    }

    @Test("Plik .tst z obserwowanymi wyrażeniami; stary plik bez nich; obserwowane debugera to lista dokumentu")
    func watches() throws {
        let f = TestScriptFile(block: "begin null; end;", variables: [TestVariable(name: "a")], watches: ["v_total", "r.ename"])
        let back = TestScriptFile.decode(String(decoding: try f.encoded(), as: UTF8.self))
        #expect(back == f && back.watches == ["v_total", "r.ename"])
        let old = #"{"format":"pelikan-test","version":1,"block":"begin null; end;","variables":[]}"#
        #expect(TestScriptFile.decode(old).watches == nil)
        let ws = Workspace()
        let doc = ws.newDocument(.test, text: "begin null; end;")
        let d = ws.debugger(for: doc)
        d.watches = ["a", "b"]
        #expect(doc.testWatches == ["a", "b"])
        d.removeWatch("a")
        #expect(doc.testWatches == ["b"])
    }

    @Test("Zapis i wczytanie okna testu z obserwowanymi")
    func saveLoad() throws {
        let ws = Workspace()
        let doc = ws.newDocument(.test, text: "begin :a := 1; end;")
        TestRunner.synchronize(doc)
        doc.testWatches = ["i"]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("w-\(UUID().uuidString.prefix(6)).tst")
        defer { try? FileManager.default.removeItem(at: url) }
        try ws.save(doc, to: url)
        ws.close(doc.id)
        let loaded = try ws.openFile(url)
        #expect(loaded.testWatches == ["i"] && loaded.testVariables.map(\.name) == ["a"])
    }
}
