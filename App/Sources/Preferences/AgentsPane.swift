import PelikanWorkspace
import SwiftUI

/// Preferencje › Agenci (PROMPT §7.1–7.4): lista CLI agentów, tryb ścisły, limit wywołań i limity `run_query`.
struct AgentsPane: View {
    let workspace: Workspace

    private var profiles: Binding<[AgentProfile]> { setting(workspace, \.agent.profiles) }

    var body: some View {
        Form {
            Section {
                ForEach(profiles) { $p in
                    HStack {
                        TextField(L10n.tr("Nazwa"), text: $p.name).frame(width: 150)
                        TextField(L10n.tr("Polecenie"), text: $p.executable).font(.code).frame(width: 130)
                        Picker(L10n.tr("Konfiguracja MCP jak"), selection: $p.flavor) {
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
                Stepper(value: setting(workspace, \.agent.callsPerMinute), in: 10...1000, step: 10) {
                    Text(L10n.tr("Limit wywołań narzędzi: \(workspace.settings.agent.callsPerMinute) na minutę"))
                }
            }
            Section(L10n.tr("Zapytania agenta (run_query)")) {
                Stepper(value: setting(workspace, \.agent.queryMaxRows), in: 10...100_000, step: 100) {
                    Text(L10n.tr("Najwięcej wierszy: \(workspace.settings.agent.queryMaxRows)"))
                }
                Stepper(value: setting(workspace, \.agent.queryTimeoutSeconds), in: 1...600, step: 5) {
                    Text(L10n.tr("Limit czasu: \(workspace.settings.agent.queryTimeoutSeconds) s"))
                }
                Stepper(value: setting(workspace, \.agent.queryMaxBytes), in: 10_000...50_000_000, step: 100_000) {
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
