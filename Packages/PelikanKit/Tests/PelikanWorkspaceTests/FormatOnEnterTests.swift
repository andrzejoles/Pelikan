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
              mode: IndentMode = .automatic) -> (text: String, plan: FormatOnEnter.Plan?) {
        let caret = (s as NSString).range(of: "|").location
        let text = (s as NSString).replacingCharacters(in: NSRange(location: caret, length: 1), with: "")
        var memory = StatementStartMemory()
        return (text, FormatOnEnter.plan(text: text, caret: caret, kind: kind, options: options, indentMode: mode, unit: "  ",
                                         tabWidth: 2, memory: &memory))
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
        // Makro zapisuje stan, nie przełączenie.
        #expect(r.resolvedArguments?.bool("enabled") == false)
        try await ws.invoke("edit.formatOnEnter", CommandArguments(["enabled": .bool(true)]))
        try await ws.invoke("edit.formatOnEnter", CommandArguments(["enabled": .bool(true)]))
        #expect(ws.settings.beautifier.formatOnEnter)
        #expect(ws.toggleState("edit.beautify") == nil)
        #expect(ToolbarModel.defaultItems.suffix(2) == [ToolbarModel.formatOnEnterItem, "session.logon"])
        #expect(RibbonModel.location(of: "edit.formatOnEnter")?.tab.id == "edit")
    }
}
