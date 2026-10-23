import AppKit
import PelikanWorkspace
import SwiftUI

/// Query By Example (PD-SQLW-022): kryterium pod nazwą każdej kolumny wyniku.
struct QueryByExampleView: View {
    let workspace: Workspace
    let tab: ResultTab
    let close: () -> Void
    @State private var criteria: [String: String] = [:]
    @State private var message = ""

    private var columns: [String] { tab.grid?.columns.map(\.name) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("Kryteria: wartość, wzorzec z %, > < >= <= <>, in (…), between … and …, null, not null"))
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                    ForEach(columns, id: \.self) { name in
                        GridRow {
                            Text(name).font(.system(size: 12, design: .monospaced))
                            TextField("", text: Binding(get: { criteria[name] ?? "" }, set: { criteria[name] = $0 }))
                                .textFieldStyle(.roundedBorder).frame(minWidth: 220)
                        }
                    }
                }
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.red) }
            HStack {
                Button(L10n.tr("Wyczyść")) { criteria = [:] }
                Spacer()
                Button(L10n.tr("Anuluj"), role: .cancel) { close() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("Wykonaj")) { apply() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(minWidth: 420, minHeight: 300)
        .onAppear {
            guard let g = tab.grid else { return }
            for (i, v) in tab.qbeCriteria where i < g.columns.count { criteria[g.columns[i].name] = v }
        }
    }

    private func apply() {
        let obj = criteria.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }.mapValues { JSONValue.string($0) }
        Task {
            do {
                try await workspace.invoke("grid.queryByExample", CommandArguments(["criteria": .object(obj)]))
                close()
            } catch { message = error.localizedDescription }
        }
    }
}

/// Filtr kolumn siatki (PD-GRID-011): nazwy (także wklejona lista), typy, obowiązkowe, klucze, historia.
struct ColumnFilterView: View {
    let workspace: Workspace
    let tab: ResultTab
    let close: () -> Void
    @State private var names = ""
    @State private var types: Set<ColumnFilter.TypeGroup> = []
    @State private var mandatory = false
    @State private var keys: Set<ColumnFilter.KeyKind> = []
    @State private var message = ""

    private func typeLabel(_ t: ColumnFilter.TypeGroup) -> String {
        switch t {
        case .text: L10n.tr("Tekst")
        case .number: L10n.tr("Liczby")
        case .date: L10n.tr("Daty")
        case .lob: "LOB"
        case .other: L10n.tr("Inne")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("Fragmenty nazw kolumn (po przecinku albo w liniach — można wkleić listę)")).font(.caption)
            TextEditor(text: $names).font(.system(size: 12, design: .monospaced)).frame(minHeight: 70)
            if !workspace.settings.columnFilterHistory.isEmpty {
                Menu(L10n.tr("Historia")) {
                    ForEach(workspace.settings.columnFilterHistory, id: \.self) { h in Button(h.replacingOccurrences(of: "\n", with: ", ")) { names = h } }
                }.fixedSize()
            }
            HStack {
                ForEach(ColumnFilter.TypeGroup.allCases, id: \.self) { t in
                    Toggle(typeLabel(t), isOn: Binding(get: { types.contains(t) }, set: { if $0 { types.insert(t) } else { types.remove(t) } }))
                }
            }
            HStack {
                Toggle(L10n.tr("Tylko obowiązkowe"), isOn: $mandatory)
                Toggle("PK", isOn: Binding(get: { keys.contains(.primary) }, set: { if $0 { keys.insert(.primary) } else { keys.remove(.primary) } }))
                Toggle("UK", isOn: Binding(get: { keys.contains(.unique) }, set: { if $0 { keys.insert(.unique) } else { keys.remove(.unique) } }))
                Toggle("FK", isOn: Binding(get: { keys.contains(.foreign) }, set: { if $0 { keys.insert(.foreign) } else { keys.remove(.foreign) } }))
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.red) }
            HStack {
                Button(L10n.tr("Pokaż wszystkie kolumny")) { workspace.perform("grid.clearColumnFilter"); close() }
                Spacer()
                Button(L10n.tr("Anuluj"), role: .cancel) { close() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("Filtruj")) { apply() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(minWidth: 460)
        .onAppear {
            guard let f = tab.columnFilter else { return }
            names = f.names.joined(separator: "\n"); types = f.types; mandatory = f.mandatoryOnly; keys = f.keys
        }
    }

    private func apply() {
        let args = CommandArguments(["names": .string(names), "types": .string(types.map(\.rawValue).joined(separator: ",")),
                                     "mandatory": .bool(mandatory), "keys": .string(keys.map(\.rawValue).joined(separator: ","))])
        Task {
            do {
                try await workspace.invoke("grid.columnFilter", args)
                close()
            } catch { message = error.localizedDescription }
        }
    }
}
