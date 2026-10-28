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

    @Test("odcinki: pełne linie bez przerw; „/” przy poprzedniej karcie, puste linie i komentarz przed CREATE — przy następnej")
    func segments() throws {
        let tabs = ProgramUnitTabs.tabs(ProgramCompiler.units(in: Self.text), in: Self.text)
        #expect(tabs.map(\.title) == ["kadry (" + L10n.tr("specyfikacja") + ")", "kadry (" + L10n.tr("ciało") + ")"])
        #expect(tabs.map(\.key) == ["KADRY", "KADRY body"])
        #expect(tabs[0].segment == 0..<line(6))
        #expect(tabs[1].segment == line(6)..<(Self.text as NSString).length)
        // Linia 1 jednostki ciała = linia „PACKAGE BODY” (CREATE OR REPLACE w osobnej linii), jak ALL_ERRORS (D189).
        #expect(TextEditing.line(containing: tabs[1].sourceOffset, in: Self.text) == 8)
        #expect(ProgramUnitTabs.index(of: line(6) - 1, in: tabs) == 0)
        #expect(ProgramUnitTabs.index(of: line(6), in: tabs) == 1)
        #expect(ProgramUnitTabs.caretLimit(tabs[0], isLast: false, in: Self.text as NSString) == line(6) - 1)
        // Pozycja słowa typu bez liczenia linii całego dokumentu.
        #expect(tabs[1].sourceOffset == (Self.text as NSString).range(of: "PACKAGE BODY").location)
        #expect(ProgramUnitTabs.find("2", in: tabs) == 1)
        #expect(ProgramUnitTabs.find("KADRY BODY", in: tabs) == 1)
        #expect(ProgramUnitTabs.find("kadry", in: tabs) == 0)
        #expect(ProgramUnitTabs.find("inna", in: tabs) == nil)
        #expect(ProgramUnitTabs.unitLine(documentLine: 8, sourceLine: 8) == 1)
        #expect(ProgramUnitTabs.unitLine(documentLine: 7, sourceLine: 8) == nil)
        // Jedna jednostka — bez kart.
        #expect(ProgramUnitTabs.tabs(ProgramCompiler.units(in: "create procedure p is begin null; end;\n/\n"), in: "x").isEmpty)
    }

    @Test("granice przy pisaniu: zmiana w specyfikacji przesuwa kartę ciała; wstawienie na granicy należy do karty późniejszej")
    func shift() {
        let tabs = ProgramUnitTabs.tabs(ProgramCompiler.units(in: Self.text), in: Self.text)
        let b = tabs[1].segment.lowerBound
        let len = (Self.text as NSString).length
        let s = ProgramUnitTabs.shift(tabs, edited: 5..<8, delta: 3)
        #expect(s[0].segment == 0..<(b + 3) && s[1].segment == (b + 3)..<(len + 3) && s[1].sourceOffset == tabs[1].sourceOffset + 3)
        // Enter albo wklejenie w pierwszej kolumnie pierwszej linii ciała (kursor na granicy) — tekst zostaje w ciele.
        let atBoundary = ProgramUnitTabs.shift(tabs, edited: b..<(b + 2), delta: 2)
        #expect(atBoundary[0].segment.upperBound == b && atBoundary[1].segment == b..<(len + 2))
        // Usunięcie fragmentu obejmującego granicę — granica na końcu wstawionego (tu: pustego) tekstu.
        let deleted = ProgramUnitTabs.shift(tabs, edited: (b - 3)..<(b - 3), delta: -6)
        #expect(deleted[0].segment.upperBound == b - 3 && deleted[1].segment.lowerBound == b - 3)
        // Dopisanie na końcu tekstu — ostatnia karta.
        let appended = ProgramUnitTabs.shift(tabs, edited: len..<(len + 4), delta: 4)
        #expect(appended[1].segment == b..<(len + 4))
    }

    @Test("wstawienie na granicy: Powiel linię z karty przed granicą — o znak wcześniej; To-Do z karty ciała i agent — na karcie ciała")
    func insertionAtBoundary() {
        let tabs = ProgramUnitTabs.tabs(ProgramCompiler.units(in: Self.text), in: Self.text)
        let b = tabs[1].segment.lowerBound
        // Powiel linię „/” (ostatnia linia specyfikacji): najmniejsza różnica — „/\n” w granicy, kursor w kopii.
        #expect(ProgramUnitTabs.appliesBeforeBoundary(tabs, shownTab: 0, location: b, inserted: "/\n", characterBefore: 0x0A, selectionAfter: b + 1))
        // To-Do w pierwszej kolumnie pierwszej linii ciała (widoczna karta ciała).
        #expect(!ProgramUnitTabs.appliesBeforeBoundary(tabs, shownTab: 1, location: b, inserted: "-- TODO\n", characterBefore: 0x0A, selectionAfter: b + 7))
        // Agent dopisuje komentarz przed CREATE ciała, gdy widoczna jest specyfikacja — kursor na początku wstawki.
        #expect(!ProgramUnitTabs.appliesBeforeBoundary(tabs, shownTab: 0, location: b, inserted: "-- x\n", characterBefore: 0x0A, selectionAfter: b))
        // Tekst niekończący się znakiem sprzed granicy albo wstawienie poza granicą — bez przesunięcia.
        #expect(!ProgramUnitTabs.appliesBeforeBoundary(tabs, shownTab: 0, location: b, inserted: "x", characterBefore: 0x0A, selectionAfter: b + 1))
        #expect(!ProgramUnitTabs.appliesBeforeBoundary(tabs, shownTab: 0, location: b - 1, inserted: "/\n", characterBefore: 0x2F, selectionAfter: b))
    }

    @Test("tekst wpisany za „/” specyfikacji skleja ciało w podziale poleceń (jak SQL*Plus) — karty znikają do poprawienia tekstu")
    func tabsVanishWhileTextAfterSlash() {
        let tabs = ProgramUnitTabs.tabs(ProgramCompiler.units(in: Self.text), in: Self.text)
        let b = tabs[1].segment.lowerBound
        let typed = (Self.text as NSString).replacingCharacters(in: NSRange(location: b - 1, length: 0), with: "\nabc")
        #expect(ProgramUnitTabs.tabs(ProgramCompiler.units(in: typed), in: typed).isEmpty)
    }

    @Test("Usuń jednostkę „nazwa body” bez ciała w tekście — błąd argumentu, specyfikacja zostaje")
    func removeBodyDoesNotRemoveSpec() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let spec = "create or replace package kadry as\n  procedure a;\nend;\n/\n"
        let doc = ws.newDocument(.program, text: spec)
        ws.activate(doc.id)
        let c = try #require(ws.registry.command("prog.removeUnit"))
        await #expect(throws: CommandError.invalidArgument("unit", L10n.tr("nie ma takiej jednostki"))) {
            _ = try await c.run(CommandContext(workspace: ws, invoker: .agent(sessionID: "s", agentName: "a"),
                                               arguments: CommandArguments(["unit": .string("kadry body")])))
        }
        #expect(doc.text == spec)
    }

    @Test("komendy edycji i dodatkowe kursory nie wychodzą poza kartę; walidacja z pamięci kart; Usuń jednostkę — jednostka karty")
    func editBounds() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let doc = ws.newDocument(.program, text: Self.text)
        ws.activate(doc.id)
        let tabs = doc.programUnitTabs
        let limit = ProgramUnitTabs.caretLimit(tabs[0], isLast: false, in: Self.text as NSString)
        // „Usuń następne słowo” na końcu karty specyfikacji usunęłoby znak nowej linii przed ciałem.
        doc.selectedRange = limit..<limit
        await #expect(throws: CommandError.notAvailable(L10n.tr("Zmiana wykracza poza kartę jednostki"))) {
            try await ws.invoke("edit.deleteNextWord")
        }
        #expect(doc.text == Self.text)
        // Kursor poniżej ostatniej linii karty — nie dodany.
        try await ws.invoke("edit.addCursorBelow")
        #expect(doc.additionalSelections.isEmpty)
        doc.selectedRange = line(2)..<line(2)
        try await ws.invoke("edit.addCursorBelow")
        #expect(doc.additionalSelections == [line(3)..<line(3)])
        doc.additionalSelections = []
        // Granice z modelu w chwili wywołania: zaznaczenie przeniesione na kartę ciała i od razu komenda edycji
        // (bez pętli zdarzeń, w której widok przełączyłby kartę) — zmiana w ciele dozwolona.
        doc.selectedRange = line(10)..<line(11)
        #expect(doc.unitEditBounds?.lowerBound == tabs[1].segment.lowerBound)
        try await ws.invoke("edit.uppercase")
        #expect(doc.text.contains("  PROCEDURE A IS\n"))
        try await ws.invoke("edit.lowercase")
        doc.text = Self.text
        // Powiel linię w ostatniej linii karty specyfikacji (linia „/”) — dozwolone; kopia i kursor zostają na karcie
        // specyfikacji, także po ponownym podziale (kolejne linie z samym „/” należą do jednostki przed nimi).
        doc.selectedRange = limit..<limit
        try await ws.invoke("edit.duplicateLine")
        #expect((doc.text as NSString).length == (Self.text as NSString).length + 2)
        #expect(doc.activeUnitTab == 0)
        #expect(doc.programUnitTabs[0].segment.upperBound == line(6) + 2)
        doc.text = Self.text
        // Okno z jedną jednostką — bez granic karty (i bez dzielenia tekstu przy komendzie).
        let single = ws.newDocument(.program, text: "create procedure p is begin null; end;\n/\n")
        #expect(single.unitEditBounds == nil)
        ws.activate(doc.id)
        // Pamięć kart: liczba kart bez dzielenia tekstu po zmianie (walidacja wstążki przy każdym znaku).
        #expect(doc.unitTabCount == 2)
        doc.text = "x" + doc.text
        #expect(doc.unitTabCount == 2)
        doc.text = String(doc.text.dropFirst())
        // Kursor na komentarzu „-- ciało” przed CREATE jest na karcie ciała — Usuń jednostkę usuwa ciało.
        doc.selectedRange = line(7)..<line(7)
        try await ws.invoke("prog.removeUnit")
        #expect(!doc.text.contains("PACKAGE BODY") && doc.text.contains("PACKAGE kadry"))
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
        // Agent: zawsze linia dokumentu.
        doc.selectedRange = line(12)..<line(12)
        let goto = try #require(ws.registry.command("edit.gotoLine"))
        _ = try await goto.run(CommandContext(workspace: ws, invoker: .agent(sessionID: "s", agentName: "a"), arguments: CommandArguments(["line": .int(3)])))
        #expect(doc.selectedRange == line(3)..<line(3))
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
        // Sortowanie po nazwie i rodzaju nie zmienia kolejności parametrów (tytuł i podpowiedź podprogramu).
        let two = PLSQLOutline.parse("create procedure p(z number, a number) is b number; begin null; end;\n/")
        for order in CodeContents.Order.allCases {
            #expect(CodeContents.sorted(two, order: order)[0].children.filter { $0.kind == .parameter }.map(\.name) == ["z", "a"])
        }
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
