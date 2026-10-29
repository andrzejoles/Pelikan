import PelikanWorkspace
import SwiftUI

/// Ustawienia › Agenci (PROMPT §7.1–7.4): lista CLI agentów, tryb ścisły, limit wywołań i limity `run_query`.
struct AgentsPane: View {
    let workspace: Workspace

    /// Pole profilu wskazanego identyfikatorem (nie indeksem): usunięcie wiersza przy fokusie w polu nie zapisze
    /// wartości do sąsiedniego profilu ani poza zakres (jak R5-02).
    private func field<T>(_ p: AgentProfile, _ key: WritableKeyPath<AgentProfile, T>) -> Binding<T> {
        setting(workspace, \.agent.profiles, p.id, key, fallback: p[keyPath: key])
    }

    var body: some View {
        Form {
            Section {
                ForEach(workspace.settings.agent.profiles) { p in
                    HStack {
                        TextField(L10n.tr("Nazwa"), text: field(p, \.name)).frame(width: 150)
                        TextField(L10n.tr("Polecenie"), text: field(p, \.executable)).font(.code).frame(width: 130)
                        Picker(L10n.tr("Konfiguracja MCP jak"), selection: field(p, \.flavor)) {
                            ForEach(AgentFlavor.allCases, id: \.self) { Text(flavorName($0)).tag($0) }
                        }
                        .frame(width: 260)
                        Button(role: .destructive) {
                            workspace.settings.agent.profiles.removeAll { $0.id == p.id }
                        } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .iconLabel(L10n.tr("Usuń z listy"))
                    }
                }
                HStack {
                    Button(L10n.tr("Dodaj CLI")) {
                        workspace.settings.agent.profiles.append(AgentProfile(id: "cli-\(UUID().uuidString.prefix(6).lowercased())",
                                                                              name: L10n.tr("Nowy agent"), executable: "agent", flavor: .claude))
                    }
                    Button(L10n.tr("Przywróć domyślne")) { workspace.settings.agent.profiles = AgentProfile.builtIn }
                }
            } header: {
                Text(L10n.tr("Agenci (CLI)"))
            } footer: {
                Text(L10n.tr("Polecenie szukane jest w PATH powłoki logowania. „Konfiguracja MCP jak” wybiera sposób przekazania serwera MCP Pelikana tylko dla jednej sesji."))
                    .font(.uiSecondary).foregroundStyle(.secondary)
            }
            Section(L10n.tr("Bezpieczeństwo")) {
                Toggle(L10n.tr("Tryb ścisły — CLI bez własnej powłoki i edycji plików, tylko narzędzia Pelikana (gdzie CLI na to pozwala)"),
                       isOn: setting(workspace, \.agent.strictMode))
                Stepper(value: setting(workspace, \.agent.callsPerMinute), in: 10...AgentSettings.callsPerMinuteRange.upperBound, step: 10) {
                    Text(L10n.tr("Limit wywołań narzędzi: \(workspace.settings.agent.callsPerMinute) na minutę"))
                }
            }
            Section(L10n.tr("Zapytania agenta (run_query)")) {
                Stepper(value: setting(workspace, \.agent.queryMaxRows), in: AgentSettings.queryMaxRowsRange, step: 100) {
                    Text(L10n.tr("Najwięcej wierszy: \(workspace.settings.agent.queryMaxRows)"))
                }
                Stepper(value: setting(workspace, \.agent.queryTimeoutSeconds), in: AgentSettings.queryTimeoutRange, step: 5) {
                    Text(L10n.tr("Limit czasu: \(workspace.settings.agent.queryTimeoutSeconds) s"))
                }
                Stepper(value: setting(workspace, \.agent.queryMaxBytes), in: AgentSettings.queryMaxBytesRange, step: 100_000) {
                    Text(L10n.tr("Największy wynik: \(workspace.settings.agent.queryMaxBytes / 1000) kB"))
                }
            }
        }
        .formStyle(.grouped)
    }

    private func flavorName(_ f: AgentFlavor) -> String {
        switch f {
        case .claude: L10n.tr("Claude Code (--mcp-config)")
        case .codex: L10n.tr("Codex (-c mcp_servers)")
        case .grok: L10n.tr("Grok (GROK_CONFIG)")
        case .antigravity: L10n.tr("Antigravity (rejestracja za zgodą)")
        }
    }
}
