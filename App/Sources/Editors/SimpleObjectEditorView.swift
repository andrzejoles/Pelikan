import AppKit
import PelikanWorkspace
import SwiftUI

/// Prosty edytor obiektu (UG 9.2–9.11): formularz z pól modelu, podgląd DDL (hasło maskowane), Zastosuj / Odśwież.
struct SimpleObjectEditorView: View {
    let workspace: Workspace
    let connectionID: UUID
    @State var editor: SimpleObjectEditor
    @State private var message = ""
    @State private var running = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Form {
                    ForEach(editor.fields) { f in field(f) }
                }
                .formStyle(.grouped)
                .frame(minWidth: 380)
                VStack(alignment: .leading, spacing: 6) {
                    Text("SQL").font(.callout.bold()).padding(.horizontal, 8).padding(.top, 8)
                    ScrollView {
                        Text(preview).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading).padding(8)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .accessibilityLabel(L10n.tr("Podgląd DDL"))
                }
                .frame(minWidth: 300)
            }
            Divider()
            HStack {
                if running { ProgressView().controlSize(.small) }
                Text(message).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button(L10n.tr("Odśwież")) { refresh() }.disabled(editor.isNew || running)
                Button(L10n.tr("Zastosuj")) { apply() }.keyboardShortcut(.defaultAction).disabled(editor.statements().isEmpty || running)
            }
            .padding(10)
        }
        .frame(minWidth: 720, minHeight: 380)
    }

    private var preview: String {
        let s = editor.statements(masked: true)
        return s.isEmpty ? L10n.tr("-- Brak zmian") : s.map { $0 + ";" }.joined(separator: "\n\n")
    }

    @ViewBuilder private func field(_ f: EditorField) -> some View {
        let disabled = f.createOnly && !editor.isNew
        let binding = Binding(get: { editor.values[f.key] ?? "" }, set: { editor.values[f.key] = $0 })
        switch f.kind {
        case .bool:
            Toggle(f.label, isOn: Binding(get: { binding.wrappedValue == "Y" }, set: { binding.wrappedValue = $0 ? "Y" : "N" })).disabled(disabled)
        case .choice(let options):
            Picker(f.label, selection: binding) { ForEach(options, id: \.self) { Text($0).tag($0) } }.disabled(disabled)
        case .secret:
            SecureField(f.label, text: binding).disabled(disabled)
        case .multiline, .list:
            TextField(f.label, text: binding, axis: .vertical).lineLimit(1...4).disabled(disabled)
        case .text:
            TextField(f.label, text: Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = f.key == "dblink" ? $0 : $0.uppercased() }))
                .disabled(disabled)
        case .number:
            TextField(f.label, text: binding).disabled(disabled)
        }
    }

    private func apply() {
        running = true
        message = ""
        Task {
            do {
                let r = try await editor.apply(in: workspace, connectionID: connectionID)
                if let e = r.error {
                    message = L10n.tr("Błąd: \(e)")
                } else {
                    message = L10n.tr("Zastosowano poleceń: \(r.executed.count)")
                    if let m = workspace.metadata(for: connectionID) {
                        editor = try await SimpleObjectEditor.load(editor.kind, owner: editor.owner, name: editor.value("name").uppercased(), metadata: m)
                    }
                }
            } catch CommandError.cancelledByUser {
                message = L10n.tr("Anulowano")
            } catch {
                message = error.localizedDescription
            }
            running = false
        }
    }

    private func refresh() {
        guard let m = workspace.metadata(for: connectionID), let name = editor.original?["name"] else { return }
        Task {
            do {
                editor = try await SimpleObjectEditor.load(editor.kind, owner: editor.owner, name: name, metadata: m)
                message = L10n.tr("Wczytano z bazy")
            } catch { message = error.localizedDescription }
        }
    }
}
