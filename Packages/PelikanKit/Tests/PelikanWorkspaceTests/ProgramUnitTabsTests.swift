import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Karty jednostek okna programu (D192): odcinki tekstu, karta z kursora, komendy prog.selectUnit/nextUnit/previousUnit,
/// „Przejdź do linii” względem jednostki, filtr i opis elementów Code Contents.
@MainActor
@Suite("Okno programu: karty jednostek")
struct ProgramUnitTabsTests {
    static let text = """
    -- nagłówek pliku
    CREATE OR REPLACE PACKAGE kadry AS
      PROCEDURE a;
    END kadry;
    /

    -- ciało
    CREATE OR REPLACE
    PACKAGE BODY kadry AS
      PROCEDURE a IS
      BEGIN
        NULL;
      END a;
    END kadry;
    /

    """

    func line(_ n: Int, _ text: String = Self.text) -> Int { TextEditing.offset(ofLine: n, in: text) }

    @Test("odcinki: pełne linie bez przerw; „/” i puste linie przy poprzedniej karcie, komentarz przed CREATE — przy następnej")
    func segments() throws {
        let tabs = ProgramUnitTabs.tabs(ProgramCompiler.units(in: Self.text), in: Self.text)
        #expect(tabs.map(\.title) == ["kadry (" + L10n.tr("specyfikacja") + ")", "kadry (" + L10n.tr("ciało") + ")"])
        #expect(tabs.map(\.key) == ["KADRY", "KADRY body"])
        #expect(tabs[0].segment == 0..<line(7))
        #expect(tabs[1].segment == line(7)..<(Self.text as NSString).length)
        // Linia 1 jednostki ciała = linia „PACKAGE BODY” (CREATE OR REPLACE w osobnej linii), jak ALL_ERRORS (D189).
        #expect(TextEditing.line(containing: tabs[1].sourceOffset, in: Self.text) == 8)
        #expect(ProgramUnitTabs.index(of: line(7) - 1, in: tabs) == 0)
        #expect(ProgramUnitTabs.index(of: line(7), in: tabs) == 1)
        #expect(ProgramUnitTabs.caretLimit(tabs[0], isLast: false, in: Self.text as NSString) == line(7) - 1)
        #expect(ProgramUnitTabs.find("2", in: tabs) == 1)
        #expect(ProgramUnitTabs.find("KADRY BODY", in: tabs) == 1)
        #expect(ProgramUnitTabs.find("kadry", in: tabs) == 0)
        #expect(ProgramUnitTabs.find("inna", in: tabs) == nil)
        #expect(ProgramUnitTabs.unitLine(documentLine: 8, sourceLine: 8) == 1)
        #expect(ProgramUnitTabs.unitLine(documentLine: 7, sourceLine: 8) == nil)
        // Jedna jednostka — bez kart.
        #expect(ProgramUnitTabs.tabs(ProgramCompiler.units(in: "create procedure p is begin null; end;\n/\n"), in: "x").isEmpty)
    }

    @Test("granice przesuwane przy pisaniu: zmiana w specyfikacji przesuwa kartę ciała, tekst na granicy należy do wcześniejszej")
    func shift() {
        let tabs = ProgramUnitTabs.tabs(ProgramCompiler.units(in: Self.text), in: Self.text)
        let b = tabs[1].segment.lowerBound
        let s = ProgramUnitTabs.shift(tabs, edited: 5..<8, delta: 3)
        #expect(s[0].segment == 0..<(b + 3) && s[1].segment.lowerBound == b + 3 && s[1].sourceOffset == tabs[1].sourceOffset + 3)
        let atBoundary = ProgramUnitTabs.shift(tabs, edited: b..<(b + 2), delta: 2)
        #expect(atBoundary[0].segment.upperBound == b + 2 && atBoundary[1].segment.lowerBound == b + 2)
        let deleted = ProgramUnitTabs.shift(tabs, edited: (b - 3)..<(b - 3), delta: -6)
        #expect(deleted[0].segment.upperBound == b - 3 && deleted[1].segment.lowerBound == b - 3)
    }

    @Test("komendy kart: wybór nazwą, numerem i z listy, następna/poprzednia w kółko, powrót w zapamiętane miejsce, historia skoków")
    func commands() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let doc = ws.newDocument(.program, text: Self.text)
        ws.activate(doc.id)
        doc.selectedRange = line(3) + 2..<line(3) + 2
        #expect(doc.activeUnitTab == 0)
        let r = try await ws.invoke("prog.selectUnit", CommandArguments(["unit": .string("kadry body")]))
        #expect(r.value == .int(2))
        #expect(doc.activeUnitTab == 1)
        // Pierwsze wejście na kartę — początek linii nagłówka jednostki.
        #expect(doc.selectedRange == line(9)..<line(9))
        doc.selectedRange = line(12)..<line(12)
        try await ws.invoke("prog.previousUnit")
        #expect(doc.selectedRange == line(3) + 2..<line(3) + 2)
        try await ws.invoke("prog.nextUnit")
        #expect(doc.selectedRange == line(12)..<line(12))
        try await ws.invoke("prog.nextUnit")
        #expect(doc.activeUnitTab == 0)
        try await ws.invoke("prog.selectUnit", CommandArguments(["unit": .int(2)]))
        #expect(doc.activeUnitTab == 1)
        // Wstecz wraca na poprzednią kartę.
        try await ws.invoke("edit.navigateBack")
        #expect(doc.activeUnitTab == 0)
        await #expect(throws: CommandError.invalidArgument("unit", L10n.tr("nie ma takiej jednostki"))) {
            try await ws.invoke("prog.selectUnit", CommandArguments(["unit": .string("brak")]))
        }
        // Agent bez argumentu — błąd argumentu (komenda poza poziomem agenta i tak, ale bez okna wyboru).
        await #expect(throws: CommandError.missingArgument("unit")) {
            let c = try #require(ws.registry.command("prog.selectUnit"))
            _ = try await c.run(CommandContext(workspace: ws, invoker: .agent(sessionID: "s", agentName: "a"), arguments: .empty))
        }
        // Okno z jedną jednostką — komendy niedostępne.
        let single = ws.newDocument(.program, text: "create procedure p is begin null; end;\n/\n")
        ws.activate(single.id)
        #expect(ws.registry.command("prog.nextUnit")?.validate?(ws) == false)
    }

    @Test("Przejdź do linii: w oknie z kartami — linia jednostki bieżącej karty (jak ALL_ERRORS), bez kart — linia dokumentu")
    func gotoLine() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let doc = ws.newDocument(.program, text: Self.text)
        ws.activate(doc.id)
        doc.selectedRange = line(12)..<line(12)
        try await ws.invoke("edit.gotoLine", CommandArguments(["line": .int(2)]))
        // Linia 1 ciała = „PACKAGE BODY kadry AS” (linia 9 dokumentu), linia 2 — „PROCEDURE a IS”.
        #expect(doc.selectedRange == line(10)..<line(10))
        // Poza końcem jednostki — ostatnia linia karty, bez przejścia na inną kartę.
        doc.selectedRange = line(2)..<line(2)
        try await ws.invoke("edit.gotoLine", CommandArguments(["line": .int(50)]))
        #expect(doc.activeUnitTab == 0)
        let plain = ws.newDocument(.sql, text: "a\nb\nc")
        ws.activate(plain.id)
        try await ws.invoke("edit.gotoLine", CommandArguments(["line": .int(3)]))
        #expect(plain.selectedRange == 4..<4)
    }

    @Test("Code Contents: filtr nazw zostawia przodków pasujących elementów; opis z parametrami i widocznością")
    func contentsFilterAndSignature() throws {
        let nodes = PLSQLOutline.parse(PLSQLOutlinePackageText.text)
        let f = CodeContents.filtered(nodes, matching: "OBLI")
        #expect(f.map(\.name) == ["kadry"])
        #expect(f[0].kind == .packageBody)
        #expect(f[0].children.filter { $0.kind != .parameter }.map(\.name) == ["podwyzka"])
        #expect(f[0].children[0].children.filter { $0.kind != .parameter }.map(\.name) == ["oblicz"])
        #expect(CodeContents.filtered(nodes, matching: " ").count == nodes.count)
        let pensja = try #require(nodes[0].children.first { $0.name == "pensja" })
        #expect(CodeContents.signature(of: pensja) == "FUNCTION pensja(p_empno in number) RETURN number — " + L10n.tr("publiczny"))
        let priv = try #require(nodes[1].children.first { $0.name == "g_x" })
        #expect(CodeContents.signature(of: priv) == "g_x number — " + L10n.tr("prywatny"))
    }
}

enum PLSQLOutlinePackageText {
    static let text = """
    create or replace package kadry as
      function pensja(p_empno in number) return number;
      procedure podwyzka(p_empno number);
    end;
    /
    create or replace package body kadry as
      g_x number;
      function pensja(p_empno in number) return number is begin return 1; end;
      procedure podwyzka(p_empno number) is
        function oblicz return number is begin return 1; end;
      begin null; end;
    end;
    /
    """
}
