import AppKit
import PelikanWorkspace
import SwiftUI

/// Punkty przerwania (UG 5.10 „Modify Breakpoints”): lista z włączeniem, licznikiem przejść i usuwaniem; punkty na
/// kodach błędów Oracle; włącz / wyłącz wszystkie.
struct BreakpointsView: View {
    @Bindable var workspace: Workspace
    @State private var codes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Table($workspace.breakpoints) {
                TableColumn(L10n.tr("Włączony")) { $b in Toggle("", isOn: $b.enabled).labelsHidden() }.width(60)
                TableColumn(L10n.tr("Miejsce")) { $b in Text(place(b)).font(.system(.body, design: .monospaced)) }
                TableColumn(L10n.tr("Linia")) { $b in Text("\(b.line)") }.width(50)
                TableColumn(L10n.tr("Liczba przejść")) { $b in
                    TextField("", value: $b.passCount, format: .number).frame(width: 60)
                }.width(100)
                TableColumn("") { $b in
                    Button { workspace.breakpoints.removeAll { $0.id == b.id } } label: { Image(systemName: "trash") }.iconLabel(L10n.tr("Usuń")).buttonStyle(.borderless)
                }.width(30)
            }
            HStack {
                Button(L10n.tr("Włącz wszystkie")) { for i in workspace.breakpoints.indices { workspace.breakpoints[i].enabled = true } }
                Button(L10n.tr("Wyłącz wszystkie")) { for i in workspace.breakpoints.indices { workspace.breakpoints[i].enabled = false } }
                Button(L10n.tr("Usuń wszystkie")) { workspace.breakpoints.removeAll() }
            }
            Divider()
            HStack {
                Text(L10n.tr("Zatrzymaj na błędach ORA-:"))
                TextField(L10n.tr("np. 1403, 20001"), text: $codes).onSubmit(saveCodes)
                Button(L10n.tr("Zapisz")) { saveCodes() }
            }
        }
        .padding(12)
        .frame(minWidth: 560, minHeight: 300)
        .onAppear { codes = workspace.errorBreakpoints.map(String.init).joined(separator: ", ") }
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
