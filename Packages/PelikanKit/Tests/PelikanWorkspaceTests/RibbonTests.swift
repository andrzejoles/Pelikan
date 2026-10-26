import Foundation
@testable import PelikanWorkspace
import Testing
#if canImport(AppKit)
import AppKit
#endif

/// Wstążka i wyszukiwarka czynności (PD-UI-012, D171).
@MainActor
@Suite("Wstążka")
struct RibbonTests {
    let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])

    @Test("każda komenda wstążki jest w rejestrze, grupy nie są puste i nie powtarzają komend")
    func commandsExist() {
        for tab in RibbonModel.tabs {
            #expect(!tab.groups.isEmpty, "karta \(tab.id)")
            for group in tab.groups {
                #expect(!group.items.isEmpty, "\(tab.id) › \(group.title)")
                let ids = RibbonModel.expand(group.items.flatMap(\.commands), in: ws.registry)
                #expect(Set(ids).count == ids.count, "powtórzenie w \(tab.id) › \(group.title)")
                for id in ids { #expect(ws.registry.command(CommandID(rawValue: id)) != nil, "\(tab.id) › \(group.title): \(id)") }
            }
        }
        #expect(Set(RibbonModel.tabs.map(\.id)).count == RibbonModel.tabs.count)
    }

    @Test("wszystkie komendy z menu są na wstążce (poza listą wyjątków)")
    func coverage() {
        let onRibbon = Set(RibbonModel.expand(RibbonModel.tabs.flatMap(\.commands), in: ws.registry))
        let missing = ws.registry.descriptors
            .filter { $0.inMenu && !$0.id.rawValue.hasPrefix("agent.") }
            .map(\.id.rawValue)
            .filter { !onRibbon.contains($0) && !RibbonModel.notOnRibbon.contains($0) }
        #expect(missing.isEmpty, "brak na wstążce: \(missing.sorted())")
        for id in RibbonModel.notOnRibbon { #expect(ws.registry.command(CommandID(rawValue: id)) != nil, "wyjątek \(id)") }
    }

    @Test("ikony: komendy z rejestru, symbole istnieją w systemie")
    func symbols() {
        for (id, symbol) in CommandSymbols.map {
            #expect(ws.registry.command(CommandID(rawValue: id)) != nil, "ikona nieznanej komendy \(id)")
            #if canImport(AppKit)
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(id): brak symbolu \(symbol)")
            #endif
        }
        #if canImport(AppKit)
        for tab in RibbonModel.tabs {
            for case .menu(let title, let symbol, _, _) in tab.groups.flatMap(\.items) {
                #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(title): brak symbolu \(symbol)")
            }
        }
        #endif
        // Duże przyciski zawsze z własną ikoną.
        for tab in RibbonModel.tabs {
            for case .large(let id, _) in tab.groups.flatMap(\.items) { #expect(CommandSymbols.symbol(for: id) != nil, "\(id) bez ikony") }
        }
    }

    @Test("karty kontekstowe tylko przy oknie swojego rodzaju; domyślna karta rodzaju jest widoczna")
    func contextualTabs() {
        let standard = RibbonModel.visibleTabs(for: nil).map(\.id)
        #expect(standard == ["start", "edit", "database", "debug", "tools", "reports", "view"])
        #expect(RibbonModel.visibleTabs(for: .program).map(\.id) == standard + ["program"])
        #expect(RibbonModel.visibleTabs(for: .sql).map(\.id) == standard + ["result"])
        for kind in DocumentKind.allCases {
            #expect(RibbonModel.visibleTabs(for: kind).map(\.id).contains(RibbonModel.defaultTab(for: kind)), "\(kind)")
            #expect(RibbonModel.visibleTabs(for: kind).filter(\.isContextual).count <= 1)
        }
        #expect(RibbonModel.location(of: "tools.explainPlan")?.tab.id == "tools")
        #expect(RibbonModel.location(of: "prog.addUnit")?.tab.id == "program")
        // Wzorzec listy obejmuje komendy dodane później (formaty kopiowania, raporty).
        let copies = RibbonModel.expand(["edit.specialCopy.*"], in: ws.registry)
        #expect(copies.contains("edit.specialCopy.java") && copies.allSatisfy { $0.hasPrefix("edit.specialCopy.") })
        #expect(!RibbonModel.expand(["reports.*"], in: ws.registry).contains("reports.predefined.run"))
    }

    @Test("wybór karty zapamiętany osobno dla każdego rodzaju okna")
    func selectionMemory() {
        var s = RibbonSelection()
        let program = RibbonModel.visibleTabs(for: .program).map(\.id)
        let sql = RibbonModel.visibleTabs(for: .sql).map(\.id)
        #expect(s.tab(for: .program, visible: program) == "program")
        #expect(s.tab(for: .sql, visible: sql) == "start")
        s.select("debug", for: .program)
        s.select("result", for: .sql)
        #expect(s.tab(for: .program, visible: program) == "debug")
        #expect(s.tab(for: .sql, visible: sql) == "result")
        #expect(s.tab(for: nil, visible: RibbonModel.visibleTabs(for: nil).map(\.id)) == "start")
        // Zapamiętana karta kontekstowa innego rodzaju nie jest widoczna — karta domyślna.
        s.select("result", for: .test)
        #expect(s.tab(for: .test, visible: RibbonModel.visibleTabs(for: .test).map(\.id)) == "debug")
    }

    func top(_ query: String, _ n: Int = 3, alternates: [String: [String]] = [:]) -> [String] {
        let all = ws.registry.descriptors.filter { $0.inMenu && !$0.id.rawValue.hasPrefix("agent.") }
        return CommandSearch.search(query, in: all, limit: n) { alternates[$0.id.rawValue] ?? [] }.map(\.descriptor.id.rawValue)
    }

    @Test("wyszukiwanie: bez polskich znaków, po początkach słów, synonimach i nazwach wzorca")
    func search() {
        #expect(CommandSearch.fold("Źródło ŁÓDŹ") == "zrodlo lodz")
        #expect(top("zrodlem w bazie").first == "prog.compareWithDatabase")
        #expect(top("commit").first == "session.commit")
        #expect(top("explain plan").contains("tools.explainPlan"))
        #expect(top("beautifier").first == "edit.beautify")
        #expect(top("eksport tabel").first == "tools.exportTables")
        #expect(top("find database objects").first == "tools.findObjects")
        #expect(top("kompiluj", 6).contains("sql.execute"))
        #expect(top("kompiluj", 6).contains("tools.compileInvalid"))
        #expect(top("przel zakl").first == "edit.toggleBookmark")
        #expect(top("qqqxyz").isEmpty)
        #expect(top("   ").isEmpty)
        // Tytuł w innym języku (angielski przy interfejsie po polsku).
        #expect(top("snapshot", 1, alternates: ["view.saveLayout": ["Save layout snapshot"]]) == ["view.saveLayout"])
    }

    @Test("komendy wstążki: pokaż/ukryj i szukaj czynności (włącza ukrytą wstążkę)")
    func commands() async throws {
        #expect(ws.settings.showRibbon)
        #expect(!ws.settings.ribbonCollapsed)
        try await ws.invoke("view.ribbon")
        #expect(!ws.settings.showRibbon)
        try await ws.invoke("view.ribbonSearch")
        #expect(ws.settings.showRibbon)
        try await ws.invoke("view.ribbonCollapse")
        #expect(ws.settings.ribbonCollapsed)
        for id in ["view.ribbon", "view.ribbonSearch", "view.ribbonCollapse"] as [CommandID] {
            #expect(ws.registry.command(id)?.descriptor.agentAccess == AgentAccess.none)
        }
    }

    @Test("ustawienia wstążki: zapis i odczyt, domyślne przy starszym pliku")
    func settings() throws {
        var s = Settings()
        s.showRibbon = false
        s.ribbonCollapsed = true
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        #expect(!back.showRibbon && back.ribbonCollapsed)
        let old = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        #expect(old.showRibbon && !old.ribbonCollapsed)
    }
}
