import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Struktury sterujące w Zawartości kodu (D203): tytuły i podpowiedzi węzłów, filtr, kolejność, zaznaczenie po
/// przejściu, komenda `codeContents.controlFlow` i ustawienie, komendy menu elementu na strukturach.
@MainActor
@Suite("Zawartość kodu — struktury sterujące")
struct CodeContentsControlFlowTests {
    static let source = """
    create or replace package body pk is
      g number;
      procedure zeta is
      begin
        <<glowna>>
        for r in (select e.empno, e.ename, e.sal, e.comm, e.deptno, e.hiredate from emp e where e.deptno = 10) loop
          if r.sal > 1000
             and r.comm is null then
            null;
          elsif r.sal < 0 then null;
          else null;
          end if;
        end loop glowna;
      exception
        when no_data_found then null;
      end zeta;
      procedure alfa is
      begin
        declare
          x number;
        begin
          while x < 10 loop x := x + 1; end loop;
        end;
      end alfa;
    end pk;
    """

    static func flat(_ nodes: [OutlineNode]) -> [OutlineNode] { nodes.flatMap { [$0] + flat($0.children) } }

    @Test("tytuły: krótki nagłówek w jednej linii, etykieta, słowo kończące pętlę; podpowiedź — pełny nagłówek")
    func titles() {
        let all = Self.flat(PLSQLOutline.parse(Self.source, controlFlow: true))
        let loop = all.first { $0.kind == .loop && $0.name == "FOR" }!
        let title = CodeContents.controlTitle(loop)
        #expect(title.hasPrefix("<<glowna>> FOR r in (select e.empno"))
        #expect(title.hasSuffix("… LOOP") && !title.contains("\n"))
        #expect(title.count <= "<<glowna>> FOR ".count + CodeContents.controlTitleLimit + " LOOP".count + 1)
        #expect(CodeContents.signature(of: loop).hasSuffix("e.deptno = 10) LOOP"))
        let ifNode = all.first { $0.kind == .ifStatement }!
        #expect(CodeContents.controlTitle(ifNode) == "IF r.sal > 1000 and r.comm is null")
        #expect(CodeContents.signature(of: ifNode) == "IF r.sal > 1000 and r.comm is null THEN")
        #expect(all.filter { $0.kind == .elsifBranch || $0.kind == .elseBranch }.map(CodeContents.controlTitle) == ["ELSIF r.sal < 0", "ELSE"])
        #expect(CodeContents.controlTitle(all.first { $0.kind == .exceptionHandler }!) == "WHEN no_data_found")
        #expect(CodeContents.controlTitle(all.first { $0.kind == .exceptionSection }!) == "EXCEPTION")
        #expect(CodeContents.controlTitle(all.first { $0.kind == .loop && $0.name == "WHILE" }!) == "WHILE x < 10 LOOP")
        #expect(CodeContents.controlTitle(all.first { $0.kind == .block }!) == "BEGIN")
        let bare = PLSQLOutline.parse("begin loop exit; end loop; case when a then null; end case; end;", controlFlow: true)[0].children
        #expect(bare.map(CodeContents.controlTitle) == ["LOOP", "CASE"])
    }

    @Test("filtr: po słowie, warunku i etykiecie; kolejność alfabetyczna nie przestawia struktur")
    func filterAndSort() {
        let nodes = PLSQLOutline.parse(Self.source, controlFlow: true)
        let byCondition = Self.flat(CodeContents.filtered(nodes, matching: "comm is null"))
        #expect(byCondition.map(\.kind) == [.packageBody, .procedure, .loop, .ifStatement])
        let byLabel = Self.flat(CodeContents.filtered(nodes, matching: "glowna"))
        #expect(byLabel.last?.kind == .loop)
        #expect(Self.flat(CodeContents.filtered(nodes, matching: "while")).last?.name == "WHILE")
        let sorted = CodeContents.sorted(nodes, order: .name)
        #expect(sorted[0].children.map(\.name) == ["alfa", "g", "zeta"])
        let zeta = sorted[0].children[2]
        #expect(zeta.children.map(\.kind) == [.loop, .exceptionSection])
        #expect(zeta.children[0].children[0].children.map(\.kind) == [.elsifBranch, .elseBranch])
        // Bez struktur — zagnieżdżony blok należy do procedury.
        let plain = PLSQLOutline.withoutControlFlow(nodes)
        #expect(plain[0].children[2].children.map(\.kind) == [.block])
    }

    @Test("przejście: blok — słowo DECLARE albo BEGIN, struktura — słowo otwierające, element — nazwa")
    func selection() {
        let src = Self.source
        let ns = src as NSString
        let all = Self.flat(PLSQLOutline.parse(src, controlFlow: true))
        let block = all.first { $0.kind == .block }!
        #expect(ns.substring(with: NSRange(CodeContents.selection(of: block, in: src))) == "declare")
        let elsif = all.first { $0.kind == .elsifBranch }!
        #expect(ns.substring(with: NSRange(CodeContents.selection(of: elsif, in: src))) == "elsif")
        let zeta = all.first { $0.name == "zeta" }!
        #expect(ns.substring(with: NSRange(CodeContents.selection(of: zeta, in: src))) == "zeta")
    }

    @Test("komenda przełącza ustawienie (domyślnie włączone), makro zapisuje stan; menu elementu działa na strukturach")
    func command() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        #expect(ws.settings.codeContentsControlFlow)
        let off = try await ws.invoke("codeContents.controlFlow")
        #expect(!ws.settings.codeContentsControlFlow && off.resolvedArguments?.bool("visible") == false)
        try await ws.invoke("codeContents.controlFlow", CommandArguments(["visible": .bool(true)]))
        try await ws.invoke("codeContents.controlFlow", CommandArguments(["visible": .bool(true)]))
        #expect(ws.settings.codeContentsControlFlow)
        #expect(ws.registry.command("codeContents.controlFlow")?.descriptor.agentAccess == AgentAccess.none)

        let doc = ws.newDocument(.program)
        doc.text = Self.source
        ws.activate(doc.id)
        let ifOffset = (Self.source as NSString).range(of: "if r.sal").location
        try await ws.invoke("codeContents.select", CommandArguments(["offset": .int(Int64(ifOffset))]))
        let selected = (doc.text as NSString).substring(with: NSRange(doc.selectedRange))
        #expect(selected.hasPrefix("      if r.sal") && selected.hasSuffix("end if;\n"))
        // Bez struktur — element pod pozycją to procedura.
        ws.settings.codeContentsControlFlow = false
        try await ws.invoke("codeContents.select", CommandArguments(["offset": .int(Int64(ifOffset))]))
        #expect((doc.text as NSString).substring(with: NSRange(doc.selectedRange)).hasPrefix("  procedure zeta"))
    }

    @Test("komendy elementu bez pozycji — element z zarysu bez struktur; z pozycją — węzeł panelu; Testuj — najbliższy podprogram")
    func commandsWithoutOffset() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let doc = ws.newDocument(.program)
        doc.text = Self.source
        ws.activate(doc.id)
        let ns = Self.source as NSString
        // Kursor w gałęzi ELSE: bez argumentu zaznaczana cała procedura (jak przed D203).
        let inElse = ns.range(of: "else null").location + 5
        doc.selectedRange = inElse..<inElse
        let r = try await ws.invoke("codeContents.copy")
        #expect(r.value?.stringValue?.hasPrefix("  procedure zeta") == true && r.value?.stringValue?.hasSuffix("end zeta;\n") == true)
        // Kursor w bloku zagnieżdżonym — blok.
        let inBlock = ns.range(of: "while x < 10").location
        doc.selectedRange = inBlock..<inBlock
        #expect(try await ws.invoke("codeContents.copy").value?.stringValue?.hasPrefix("    declare") == true)
        // Testuj: najbliższa procedura także z bloku zagnieżdżonego i struktury.
        #expect(CodeContents.testTarget(at: inBlock, in: Self.source, kind: .program)?.member == "alfa")
        #expect(CodeContents.testTarget(at: inElse, in: Self.source, kind: .program).map { "\($0.object).\($0.member ?? "")" } == "pk.zeta")
        #expect(CodeContents.testTarget(at: ns.range(of: "g number").location, in: Self.source, kind: .program) == nil)
    }

    @Test("Wytnij strukturę z etykietą w osobnej linii — razem z etykietą")
    func cutWithLabel() async throws {
        let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])
        let doc = ws.newDocument(.program)
        doc.text = Self.source
        ws.activate(doc.id)
        let forOffset = (Self.source as NSString).range(of: "for r in").location
        let r = try await ws.invoke("codeContents.cut", CommandArguments(["offset": .int(Int64(forOffset))]))
        let cut = r.value?.stringValue ?? ""
        #expect(cut.hasPrefix("    <<glowna>>\n    for r in") && cut.hasSuffix("end loop glowna;\n"))
        #expect(!doc.text.contains("glowna") && doc.text.contains("  begin\n  exception"))
    }

    @Test("sortowanie: bloki zagnieżdżone jak struktury — w kolejności źródła")
    func sortBlocks() {
        let src = "create procedure p is\n  z number;\n  a number;\nbegin\n  begin null; end;\n  if x then null; end if;\n  <<b2>> begin null; end;\nend;"
        let sorted = CodeContents.sorted(PLSQLOutline.parse(src, controlFlow: true), order: .name)[0].children
        #expect(sorted.map(\.kind) == [.variable, .variable, .block, .ifStatement, .block])
        #expect(sorted.map(\.name).prefix(2) == ["a", "z"] && sorted[4].label == "b2")
    }

    @Test("ustawienie: zapis bez pola — domyślnie włączone")
    func settingsDefault() throws {
        var s = Settings()
        s.codeContentsControlFlow = false
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(Settings.self, from: data).codeContentsControlFlow == false)
        #expect(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)).codeContentsControlFlow)
    }
}
