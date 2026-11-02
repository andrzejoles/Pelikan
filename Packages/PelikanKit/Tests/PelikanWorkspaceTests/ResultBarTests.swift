import Foundation
import PelikanSQL
@testable import PelikanWorkspace
import Testing

/// Pasek ikon nad wynikiem zapytania (D207).
@MainActor
@Suite("Pasek wyniku")
struct ResultBarTests {
    let ws = Workspace(secrets: MemorySecretStore(), drivers: [:])

    @Test("wszystkie komendy wyniku z menu są na pasku; bez wykonania, przerwania i transakcji")
    func coverage() {
        let onBar = Set(RibbonModel.expand(ResultBarModel.commands, in: ws.registry))
        let missing = ws.registry.descriptors.filter(\.inMenu).map(\.id.rawValue).filter { $0.hasPrefix("grid.") && !onBar.contains($0) }
        #expect(missing.isEmpty, "brak na pasku wyniku: \(missing.sorted())")
        for id in ["sql.refreshResult", "sql.autoRefresh", "sql.pinResult", "sql.clearResults", "sql.exportQuery"] {
            #expect(onBar.contains(id), "\(id)")
        }
        #expect(onBar.isDisjoint(with: ResultBarModel.excluded))
        for id in onBar { #expect(ws.registry.command(CommandID(rawValue: id)) != nil, "\(id)") }
        #expect(Set(onBar).count == RibbonModel.expand(ResultBarModel.commands, in: ws.registry).count, "powtórzenia")
    }

    @Test("menu formatów paska: wszystkie formaty z parametru komendy (Kopiuj jako — także TSV i lista IN)")
    func formats() {
        for id in ["grid.copyAs", "grid.export"] {
            let allowed = ws.registry.command(CommandID(rawValue: id))?.descriptor.parameters.first { $0.name == "format" }?.allowedValues ?? []
            #expect(!allowed.isEmpty && allowed.allSatisfy { ExportFormat(rawValue: $0) != nil }, "\(id)")
        }
        #expect(GridCommands.copyAsFormats.contains(.tsv) && GridCommands.copyAsFormats.contains(.expressionList))
    }

    @Test("stan przełączników z rejestru komend: edycja danych, panel wartości, formatowanie przy Enter")
    func toggleStates() {
        #expect(ws.toggleState("grid.edit") == false)
        #expect(ws.toggleState("grid.valuePanel") == ws.valuePanelVisible)
        ws.valuePanelVisible.toggle()
        #expect(ws.toggleState("grid.valuePanel") == ws.valuePanelVisible)
        #expect(ws.toggleState("edit.formatOnEnter") == ws.settings.beautifier.formatOnEnter)
        #expect(ws.toggleState("grid.export") == nil)
    }

    @Test("same ikony: każdy przycisk paska ma symbol, grupy jak na karcie Wynik")
    func icons() {
        for case .small(let id, _) in ResultBarModel.groups.flatMap(\.items) {
            #expect(CommandSymbols.symbol(for: id) != nil, "\(id) bez ikony")
        }
        let ribbon = RibbonModel.result.groups.map(\.title)
        let bar = ResultBarModel.groups.map(\.title)
        #expect(bar.allSatisfy(ribbon.contains) && bar == ribbon.filter(bar.contains))
        #expect(!bar.contains(L10n.tr("Transakcja")))
        #expect(ResultBarModel.groups.allSatisfy { !$0.items.isEmpty })
    }

    @Test("przepełnienie: elementy mieszczące się obok „»”, bez separatora na końcu")
    func fit() {
        let widths: [Double] = [20, 20, 1, 20, 20, 1, 20]
        let sep: (Int) -> Bool = { widths[$0] == 1 }
        #expect(ResultBarModel.fit(widths: widths, available: 200, overflowWidth: 24, isSeparator: sep) == 7)
        #expect(ResultBarModel.fit(widths: widths, available: 95, overflowWidth: 24, isSeparator: sep) == 4)
        // Miejsce kończy się tuż za separatorem — separator odcięty.
        #expect(ResultBarModel.fit(widths: widths, available: 66, overflowWidth: 24, isSeparator: sep) == 2)
        #expect(ResultBarModel.fit(widths: widths, available: 30, overflowWidth: 24, isSeparator: sep) == 0)
        #expect(ResultBarModel.fit(widths: [], available: 10, overflowWidth: 24) == 0)
    }
}
