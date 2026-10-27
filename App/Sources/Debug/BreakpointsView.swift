import AppKit
import PelikanWorkspace
import SwiftUI

/// Punkty przerwania (UG 5.10 „Modify Breakpoints”): lista z włączeniem, licznikiem przejść, warunkiem, komunikatem
/// (`{zmienna}`), „nie zatrzymuj” (logpoint) i usuwaniem; znacznik punktu niezastosowanego; punkty na kodach błędów.
struct BreakpointsView: View {
    @Bindable var workspace: Workspace
    @State private var codes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Table($workspace.breakpoints) {
                TableColumn(L10n.tr("Włączony")) { $b in Toggle("", isOn: $b.enabled).labelsHidden() }.width(60)
                TableColumn(L10n.tr("Miejsce")) { $b in
                    HStack(spacing: 4) {
                        if workspace.unappliedBreakpoints.contains(b.id) {
                            Image(systemName: "circle").foregroundStyle(.red)
                                .help(L10n.tr("Punkt niezastosowany: brak jednostki, informacji debugowania albo kodu w tej linii"))
                        }
                        Text(place(b)).font(.code)
                    }
                }
                TableColumn(L10n.tr("Linia")) { $b in Text("\(b.line)") }.width(50)
                TableColumn(L10n.tr("Liczba przejść")) { $b in
                    TextField("", value: $b.passCount, format: .number).frame(width: 60)
                }.width(100)
                TableColumn(L10n.tr("Warunek")) { $b in
                    TextField(L10n.tr("np. i > 3"), text: Binding(get: { b.condition ?? "" }, set: { b.condition = $0.isEmpty ? nil : $0 }))
                }
                TableColumn(L10n.tr("Komunikat")) { $b in
                    TextField(L10n.tr("np. i={i}"), text: Binding(get: { b.message ?? "" }, set: { b.message = $0.isEmpty ? nil : $0 }))
                }
                TableColumn(L10n.tr("Nie zatrzymuj")) { $b in
                    Toggle("", isOn: Binding(get: { b.dontBreak ?? false }, set: { b.dontBreak = $0 ? true : nil })).labelsHidden()
                }.width(90)
                TableColumn("") { $b in
                    Button { workspace.perform("debug.removeBreakpoint", CommandArguments(["id": .string(b.id.uuidString)])) } label: { Image(systemName: "trash") }.iconLabel(L10n.tr("Usuń")).buttonStyle(.borderless)
                }.width(30)
            }
            HStack {
                Button(L10n.tr("Włącz wszystkie")) { workspace.perform("debug.enableAllBreakpoints") }
                Button(L10n.tr("Wyłącz wszystkie")) { workspace.perform("debug.disableAllBreakpoints") }
                Button(L10n.tr("Usuń wszystkie")) { workspace.perform("debug.removeAllBreakpoints") }
                Spacer()
                Button(L10n.tr("Zapisz…")) { workspace.perform("debug.saveBreakpoints") }
                Button(L10n.tr("Wczytaj…")) { workspace.perform("debug.loadBreakpoints") }
            }
            Divider()
            HStack {
                Text(L10n.tr("Zatrzymaj na błędach ORA-:"))
                TextField(L10n.tr("np. 1403, 20001"), text: $codes).onSubmit(saveCodes)
                Button(L10n.tr("Zapisz")) { saveCodes() }
            }
        }
        .padding(12)
        .frame(minWidth: 860, minHeight: 300)
        .onFirstAppear { codes = workspace.errorBreakpoints.map(String.init).joined(separator: ", ") }
    }

    private func place(_ b: Breakpoint) -> String {
        if let d = b.document { return workspace.documents.first { $0.id.raw == d }.map { L10n.tr("Okno testu „\($0.title)”") } ?? L10n.tr("Okno testu (zamknięte)") }
        return "\(b.owner.map { "\($0)." } ?? "")\(b.unit ?? "") (\(b.type?.rawValue.lowercased() ?? ""))"
    }

    private func saveCodes() {
        workspace.errorBreakpoints = codes.split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Int($0.replacingOccurrences(of: "ORA-", with: "").replacingOccurrences(of: "-", with: "")) }.filter { $0 > 0 }
    }
}
