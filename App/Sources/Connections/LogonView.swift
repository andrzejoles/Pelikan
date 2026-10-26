import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Okno logowania (UG 3): wybór połączenia z listy (z wyszukiwaniem), połączenie jako główne albo nowe połączenie.
struct LogonView: View {
    let workspace: Workspace
    let onClose: () -> Void
    @State private var query = ""
    @State private var selection: UUID?
    @State private var connecting = false
    @State private var error: String?
    @FocusState private var searchFocused: Bool

    private var items: [ConnectionDefinition] {
        let all = workspace.connections.connections.sorted {
            ($0.lastUsed ?? .distantPast, $1.displayName) > ($1.lastUsed ?? .distantPast, $0.displayName)
        }
        guard !query.isEmpty else { return all }
        return all.filter { "\($0.displayName) \($0.connectionString)".localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("Zaloguj")).font(.title2.bold())
            TextField(L10n.tr("Szukaj połączenia"), text: $query).textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { connect() }
                .onChange(of: query) { _, _ in selection = items.first?.id }
            List(items, selection: $selection) { c in
                HStack {
                    Circle().fill(c.effectiveColor.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .secondary.opacity(0.3))
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading) {
                        Text(c.displayName)
                        Text(c.connectionString + "  ·  " + c.environment.displayName).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .tag(c.id)
                .contextMenu { Button(L10n.tr("Edytuj…")) { edit(c.id) } }
            }
            .frame(minHeight: 220)
            .onAppear {
                selection = items.first?.id
                // Fokus po tym, jak arkusz stanie się oknem kluczowym.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { searchFocused = true }
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
            if workspace.connections.connections.isEmpty {
                Text(L10n.tr("Brak zdefiniowanych połączeń — utwórz pierwsze.")).foregroundStyle(.secondary)
            }
            HStack {
                Button(L10n.tr("Nowe połączenie…")) { edit(nil) }
                Spacer()
                if connecting { ProgressView().controlSize(.small) }
                Button(L10n.tr("Anuluj"), role: .cancel, action: onClose).keyboardShortcut(.cancelAction)
                Button(L10n.tr("Połącz")) { connect() }.keyboardShortcut(.defaultAction).disabled(selection == nil || connecting)
            }
        }
        .padding(20)
        .windowSize(width: 520, height: 420)
    }

    private func edit(_ id: UUID?) {
        onClose()
        workspace.ui?.showConnectionEditor(connectionID: id)
    }

    private func connect() {
        guard let id = selection else { return }
        connecting = true
        error = nil
        Task { @MainActor in
            defer { connecting = false }
            do {
                try await workspace.invoke("connection.connectAsMain", CommandArguments(["connection": .string(id.uuidString)]))
                onClose()
            } catch CommandError.cancelledByUser {
            } catch let e as OracleError {
                error = e.message
            } catch let DatabaseError.driverUnavailable(m) {
                error = m
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
