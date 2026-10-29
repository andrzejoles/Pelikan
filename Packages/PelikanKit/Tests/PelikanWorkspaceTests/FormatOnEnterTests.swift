import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Formatowanie podczas pisania w edytorze (D205, PD-BEAU-003): plan dwóch kroków Entera, cofanie, okna, ustawienie
/// i komenda.
@MainActor
@Suite("Formatowanie przy Enter")
struct FormatOnEnterTests {
    func plan(_ s: String, kind: DocumentKind = .sql, options: BeautifierOptions = BeautifierOptions(),
              mode: IndentMode = .automatic, keywordCase: KeywordCase = .unchanged, autoReplace: [AutoReplaceRule] = [],
              edited: Bool = true) -> (text: String, plan: FormatOnEnter.Plan?) {
        let caret = (s as NSString).range(of: "|").location
        let text = (s as NSString).replacingCharacters(in: NSRange(location: caret, length: 1), with: "")
        var memory = StatementStartMemory()
        return (text, FormatOnEnter.plan(text: text, caret: caret, kind: kind, options: options, indentMode: mode, unit: "  ",
                                         tabWidth: 2, keywordCase: keywordCase, autoReplace: autoReplace, lineEdited: edited,
                                         memory: &memory))
    }

    /// Wszystkie kroki planu jak w edytorze: krok 0, Enter, formatowanie (tylko na oczekiwanym tekście).
    func run(_ text: String, _ p: FormatOnEnter.Plan) -> (afterEnter: String, final: String) {
        var t = p.prepare.map { $0.applied(to: text) } ?? text
        t = p.enter.applied(to: t)
        guard let f = p.format else { return (t, t) }
        #expect((t as NSString).substring(with: NSRange(location: f.range.lowerBound, length: f.range.count)) == p.expected)
        return (t, f.applied(to: t))
    }

    @Test("dwa kroki: zwykły Enter z wcięciem automatycznym, potem formatowanie — każde cofnięcie zdejmuje jeden krok")
    func undoSteps() throws {
        let (text, p) = plan("begin\n  if a>0 then\n    x:=1;\n    end if;|\nend;")
        let steps = try #require(p)
        let afterEnter = steps.enter.applied(to: text)
        // Krok 1 to zwykły Enter edytora (wcięcie jak linia bieżąca w trybie automatycznym).
        #expect(afterEnter == "begin\n  if a>0 then\n    x:=1;\n    end if;\n    \nend;")
        let format = try #require(steps.format)
        let final = format.applied(to: afterEnter)
        #expect(final == "begin\n  if a>0 then\n    x:=1;\n  END IF;\n  \nend;")
        // Kursor na początku nowej linii po wcięciu.
        #expect((final as NSString).substring(to: steps.caret).hasSuffix("END IF;\n  "))
        // Cofanie: grupa formatowania (odwrotna zmiana) przywraca tekst po zwykłym Enterze, grupa Entera — tekst wyjściowy.
        let undoFormat = FormatOnEnter.Edit(range: format.range.lowerBound..<(format.range.lowerBound + (format.text as NSString).length),
                                            text: (afterEnter as NSString).substring(with: NSRange(location: format.range.lowerBound, length: format.range.count)))
        #expect(undoFormat.applied(to: final) == afterEnter)
        let undoEnter = FormatOnEnter.Edit(range: steps.enter.range.lowerBound..<(steps.enter.range.lowerBound + (steps.enter.text as NSString).length), text: "")
        #expect(undoEnter.applied(to: afterEnter) == text)
    }

    @Test("Enter w środku linii: reszta linii w nowej, z wcięciem formatera; bez zmian — tylko krok Entera")
    func splitAndNoop() throws {
        let (text, p) = plan("select a, |b from t")
        let steps = try #require(p)
        let final = try #require(steps.format).applied(to: steps.enter.applied(to: text))
        #expect(final == "SELECT a,\n       b from t")
        // Linia już sformatowana i wcięcie automatyczne zgodne z formaterem — bez drugiego kroku (nic do cofania).
        let same = try #require(plan("BEGIN\n  x := 1;|").plan)
        #expect(same.format == nil)
        #expect(same.enter.text == "\n  ")
    }

    @Test("wyłączone ustawienie, konsola SQL*Plus i okna bez kodu — zwykły Enter edytora")
    func notApplied() {
        var off = BeautifierOptions()
        off.formatOnEnter = false
        #expect(plan("select a,b from t|", options: off).plan == nil)
        #expect(plan("select a,b from t|", kind: .command).plan == nil)
        #expect(plan("select a,b from t|", kind: .report).plan == nil)
        #expect(plan("select a,b from t|", kind: .program).plan != nil)
        #expect(plan("select a,b from t|", kind: .test).plan != nil)
        #expect(FormatOnEnter.applies(to: .sql, options: BeautifierOptions()))
        // Linia w literale wieloliniowym — formater nie ma zdania: zwykły Enter.
        #expect(plan("x := 'ab\ncd|';").plan == nil)
    }

    @Test("ustawienie domyślnie włączone, odczyt starych ustawień, Przywróć domyślne je zachowuje")
    func setting() throws {
        #expect(BeautifierOptions().formatOnEnter)
        let old = try JSONDecoder().decode(BeautifierOptions.self, from: Data(#"{"indent":4}"#.utf8))
        #expect(old.formatOnEnter && old.indent == 4)
        var o = BeautifierOptions()
        o.formatOnEnter = false
        #expect(try JSONDecoder().decode(BeautifierOptions.self, from: JSONEncoder().encode(o)).formatOnEnter == false)
        #expect(o.restoringDefaults(keepSpecialCase: false).formatOnEnter == false)
    }

    @Test("komenda edit.formatOnEnter: przełącza albo ustawia argumentem, stan w menu i na pasku; agent bez dostępu")
    func command() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let d = try #require(ws.registry.command("edit.formatOnEnter")?.descriptor)
        #expect(d.agentAccess == .none && d.effect == .settings && d.category == .edit && d.inMenu)
        #expect(ws.toggleState("edit.formatOnEnter") == true)
        let r = try await ws.invoke("edit.formatOnEnter")
        #expect(ws.settings.beautifier.formatOnEnter == false && ws.toggleState("edit.formatOnEnter") == false)
        #expect(r.value == .bool(false))
        try await ws.invoke("edit.formatOnEnter", CommandArguments(["enabled": .bool(true)]))
        try await ws.invoke("edit.formatOnEnter", CommandArguments(["enabled": .bool(true)]))
        #expect(ws.settings.beautifier.formatOnEnter)
        #expect(ws.toggleState("edit.beautify") == nil)
        #expect(ToolbarModel.defaultItems.suffix(2) == [ToolbarModel.formatOnEnterItem, "session.logon"])
        #expect(RibbonModel.location(of: "edit.formatOnEnter")?.tab.id == "edit")
    }

    @Test("AutoReplace przy Enter: zamiana przed planem (sf), zamiana z miejscem kursora zużywa Enter (dbo) — zwykły Enter")
    func autoReplace() throws {
        let rules = AutoReplaceRule.defaults
        let (text, p) = plan("begin\n  for r in (sf|", autoReplace: rules)
        let steps = try #require(p)
        #expect(steps.prepare == FormatOnEnter.Edit(range: 6..<20, text: "  for r in (SELECT * FROM "))
        #expect(run(text, steps).final.hasPrefix("begin\n  FOR r IN (SELECT * FROM\n"))
        #expect(plan("begin\n  dbo|", autoReplace: rules).plan == nil)
        // Krok 1 zaczyna się tam, gdzie kończy się krok 0 (edytor sprawdza zaznaczenie przed Enterem).
        #expect(steps.enter.range.lowerBound == steps.prepare!.range.lowerBound + (steps.prepare!.text as NSString).length)
        // Zamiana wieloliniowa — krok 0 i Enter, bez formatowania.
        let multi = [AutoReplaceRule(abbreviation: "hdr", replacement: "-- autor\n-- data ")]
        let (t3, p3) = plan("begin\n  hdr|", autoReplace: multi)
        let m = try #require(p3)
        #expect(m.prepare?.text == "  -- autor\n-- data " && m.format == nil)
        #expect(run(t3, m).final == "begin\n  -- autor\n-- data \n")
        // Skrót w komentarzu — bez zamiany.
        #expect(try #require(plan("begin\n  x := 1; -- sf|", autoReplace: rules).plan).prepare == nil)
        // Wielkość liter słowa kluczowego przed kursorem (Ustawienia › Edytor) — w kroku 0, nie po drodze.
        let (t2, p2) = plan("select a from t where|", keywordCase: .upper)
        let k = try #require(p2)
        #expect(k.prepare?.text == "select a from t WHERE")
        #expect(run(t2, k).final == "SELECT a FROM t WHERE\n       ")
    }

    @Test("linia nieedytowana w tej sesji — bez zmian, tylko wcięcie nowej; Enter na początku linii — zwykły Enter")
    func untouched() throws {
        let (text, p) = plan("begin\n  if a>0 then|", edited: false)
        let steps = try #require(p)
        #expect(run(text, steps).final == "begin\n  if a>0 then\n    ")
        #expect(plan("begin\n|  x := 1;").plan == nil)
        #expect(plan("begin\n  |x := 1;").plan == nil)
        var r = EditedRanges()
        r.record(edited: 10..<11, delta: 1)          // wpisany znak
        r.record(edited: 2..<5, delta: 3)            // wstawienie przed nim przesuwa zakres
        #expect(r.ranges == [2..<5, 13..<14])
        #expect(r.touches(line: 13..<20) && r.touches(line: 0..<3) && !r.touches(line: 6..<12))
        r.record(edited: 4..<4, delta: -2)           // usunięcie łączy nachodzące zakresy
        #expect(r.touches(line: 4..<4))
        r.reset()
        #expect(r.ranges.isEmpty)
        // Enter na końcu linii 0..<5 wstawia od jej końca (znak nowej linii i wcięcie) — linia nie jest edytowana,
        // a usunięcie ostatniego znaku linii — jest.
        var e = EditedRanges()
        e.record(edited: 5..<8, delta: 3, newlineFirst: true)
        #expect(!e.touches(line: 0..<5) && e.touches(line: 6..<8))
        #expect(!e.touches(line: 9..<12))       // zmiana od początku następnej linii nie oznacza bieżącej
        var w = EditedRanges()
        w.record(edited: 4..<5, delta: 1)                       // wpisany ostatni znak linii 0..<5
        w.record(edited: 5..<8, delta: 3, newlineFirst: true)   // Enter na jej końcu
        #expect(w.ranges == [4..<5, 6..<8])
        e.record(edited: 5..<5, delta: -1)
        #expect(e.touches(line: 0..<5))
        // Nowa sesja w zakresie (plik wczytany w oknie pary) — zmiany w nim zapomniane, poza nim zostają.
        var c = EditedRanges()
        c.record(edited: 2..<4, delta: 2)
        c.record(edited: 20..<30, delta: 10)
        c.clear(25..<100)
        #expect(c.ranges == [2..<4, 20..<25])
        // Dokument: zapis albo wczytanie — znacznik nowej sesji całego tekstu.
        let doc = Document(kind: .sql, ordinal: 1, text: "select 1 from dual")
        let mark = doc.editSessionMark.serial
        doc.text = "select 2 from dual"
        #expect(doc.editSessionMark.serial == mark)
        doc.isModified = false
        #expect(doc.editSessionMark.serial == mark + 1 && doc.editSessionMark.range == nil && doc.editSessionMark.revision == doc.textRevision)
        #expect(SmartIndent.followsNewline("ab\n" as NSString, caret: 3) && !SmartIndent.followsNewline("put_line()" as NSString, caret: 9))
    }

    @Test("tryb Smart: END nieedytowanej linii wyrównany do struktury także z formatowaniem")
    func smartIndent() throws {
        let (text, p) = plan("begin\n  if a then\n    x := 1;\n    end if;|", mode: .smart, edited: false)
        let steps = try #require(p)
        #expect(run(text, steps).final == "begin\n  if a then\n    x := 1;\n  end if;\n  ")
    }

    @Test("makro: komenda ustawień nie jest nagrywana")
    func macro() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        ws.toggleMacroRecording()
        try await ws.invoke("edit.formatOnEnter")
        #expect(ws.macroRecorder?.steps.isEmpty == true)
        ws.toggleMacroRecording()
    }
}
