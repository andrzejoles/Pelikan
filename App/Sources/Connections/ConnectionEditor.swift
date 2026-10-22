import AppKit
import PelikanDB
import PelikanWorkspace
import SwiftUI

/// Szkic definicji połączenia edytowany w oknie (UG 19.2). Hasło trzymane tylko w pamięci do zapisu.
@MainActor
@Observable
final class ConnectionDraft {
    var id: UUID
    var name: String
    var folderID: UUID?
    var environment: ConnectionEnvironment
    var useCustomColor: Bool
    var color: Color
    var driver: DriverKind
    var user: String
    var password = ""
    var savePassword: Bool
    var connectString: String
    var role: ConnectRole
    var proxyClient: String
    var externalAuth: Bool
    var configDirectory: String
    var edition: String
    var workspaceManager: String
    var currentSchema: String
    var readOnly: Bool
    var connectOnStartup: Bool
    var initScript: String
    var logonMessage: String
    var agentVisible: Bool
    var agentAllowChanges: Bool
    var agentUser: String
    var maskedColumns: String
    var isNew: Bool
    var testResult: String?
    var testing = false

    init(_ def: ConnectionDefinition?, isNew: Bool) {
        let d = def ?? ConnectionDefinition(target: ConnectionTarget(user: "", connectString: ""))
        id = d.id; name = d.name; folderID = d.folderID; environment = d.environment
        useCustomColor = d.color != nil
        color = d.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .accentColor
        driver = d.driver; user = d.target.user; savePassword = d.savePassword; connectString = d.target.connectString
        role = d.target.role; proxyClient = d.target.proxyClient ?? ""; externalAuth = d.target.externalAuth
        configDirectory = d.target.configDirectory ?? ""; edition = d.target.edition ?? ""
        workspaceManager = d.workspaceManager ?? ""; currentSchema = d.currentSchema ?? ""
        readOnly = d.readOnly; connectOnStartup = d.connectOnStartup; initScript = d.initScript; logonMessage = d.logonMessage
        agentVisible = d.agent.visibleToAgent; agentAllowChanges = d.agent.allowChanges; agentUser = d.agent.agentUser ?? ""
        maskedColumns = d.agent.maskedColumns.joined(separator: ", ")
        self.isNew = isNew
    }

    var definition: ConnectionDefinition {
        func opt(_ s: String) -> String? { let t = s.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t }
        var rgb: PelikanWorkspace.RGBColor?
        if useCustomColor, let c = NSColor(color).usingColorSpace(.sRGB) {
            rgb = PelikanWorkspace.RGBColor(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent))
        }
        return ConnectionDefinition(
            id: id, name: name.trimmingCharacters(in: .whitespaces), folderID: folderID,
            target: ConnectionTarget(user: user.trimmingCharacters(in: .whitespaces), connectString: connectString.trimmingCharacters(in: .whitespaces),
                                     role: role, proxyClient: opt(proxyClient), externalAuth: externalAuth,
                                     configDirectory: opt(configDirectory), edition: opt(edition)),
            driver: driver, environment: environment, color: rgb, savePassword: savePassword, readOnly: readOnly,
            connectOnStartup: connectOnStartup, initScript: initScript, logonMessage: logonMessage,
            workspaceManager: opt(workspaceManager),
            agent: AgentConnectionPolicy(visibleToAgent: agentVisible, allowChanges: agentAllowChanges, agentUser: opt(agentUser),
                                         maskedColumns: maskedColumns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }),
            currentSchema: opt(currentSchema))
    }

    var isValid: Bool {
        !connectString.trimmingCharacters(in: .whitespaces).isEmpty && (externalAuth || !user.trimmingCharacters(in: .whitespaces).isEmpty)
    }
}

/// Okno definicji połączenia.
struct ConnectionEditorView: View {
    @Bindable var draft: ConnectionDraft
    let folders: [ConnectionFolder]
    let tnsAliases: [String]
    let onTest: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                Form {
                    Section(L10n.tr("Wyświetlanie")) {
                        TextField(L10n.tr("Nazwa"), text: $draft.name, prompt: Text(L10n.tr("użytkownik@baza")))
                        Picker(L10n.tr("Folder"), selection: $draft.folderID) {
                            Text(L10n.tr("(brak)")).tag(UUID?.none)
                            ForEach(folders) { f in Text(f.name).tag(Optional(f.id)) }
                        }
                        Picker(L10n.tr("Środowisko"), selection: $draft.environment) {
                            ForEach(ConnectionEnvironment.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        HStack {
                            Toggle(L10n.tr("Własny kolor wskaźnika"), isOn: $draft.useCustomColor)
                            if draft.useCustomColor { ColorPicker("", selection: $draft.color, supportsOpacity: false).labelsHidden() }
                        }
                    }
                    Section(L10n.tr("Logowanie")) {
                        TextField(L10n.tr("Użytkownik"), text: $draft.user).disabled(draft.externalAuth)
                        SecureField(L10n.tr("Hasło"), text: $draft.password,
                                    prompt: Text(draft.isNew ? "" : L10n.tr("bez zmian"))).disabled(draft.externalAuth)
                        Toggle(L10n.tr("Zapamiętaj hasło w Pęku kluczy"), isOn: $draft.savePassword).disabled(draft.externalAuth)
                        HStack {
                            TextField(L10n.tr("Baza"), text: $draft.connectString, prompt: Text(L10n.tr("alias TNS albo host:port/usługa")))
                            if !tnsAliases.isEmpty {
                                Menu(L10n.tr("TNS")) {
                                    ForEach(tnsAliases, id: \.self) { a in Button(a) { draft.connectString = a } }
                                }.fixedSize()
                            }
                        }
                        Picker(L10n.tr("Połącz jako"), selection: $draft.role) {
                            ForEach(ConnectRole.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        Toggle(L10n.tr("Uwierzytelnianie zewnętrzne (wallet, Kerberos, system)"), isOn: $draft.externalAuth)
                        Picker(L10n.tr("Sterownik"), selection: $draft.driver) {
                            Text(L10n.tr("Instant Client (zalecany)")).tag(DriverKind.instantClient)
                            Text(L10n.tr("Thin (bez Instant Client)")).tag(DriverKind.thin)
                        }
                    }
                }
                .formStyle(.grouped)
                .tabItem { Text(L10n.tr("Ogólne")) }

                Form {
                    Section(L10n.tr("Połączenie")) {
                        TextField(L10n.tr("Proxy: schemat docelowy"), text: $draft.proxyClient, prompt: Text(L10n.tr("użytkownik[schemat]")))
                        TextField(L10n.tr("Katalog konfiguracji (TNS_ADMIN, wallet)"), text: $draft.configDirectory, prompt: Text("~/Oracle/network/admin"))
                        TextField(L10n.tr("Edition (EBR)"), text: $draft.edition)
                        TextField(L10n.tr("Workspace (DBMS_WM)"), text: $draft.workspaceManager)
                        TextField(L10n.tr("Bieżący schemat"), text: $draft.currentSchema)
                    }
                    Section(L10n.tr("Zachowanie")) {
                        Toggle(L10n.tr("Tylko do odczytu (blokada zmian danych i obiektów)"), isOn: $draft.readOnly)
                        Toggle(L10n.tr("Połącz przy starcie aplikacji"), isOn: $draft.connectOnStartup)
                    }
                    Section(L10n.tr("Skrypt inicjalizacji sesji")) {
                        TextEditor(text: $draft.initScript).font(.system(.body, design: .monospaced)).frame(minHeight: 80)
                    }
                    Section(L10n.tr("Komunikat przy logowaniu")) {
                        TextEditor(text: $draft.logonMessage).frame(minHeight: 50)
                    }
                }
                .formStyle(.grouped)
                .tabItem { Text(L10n.tr("Zaawansowane")) }

                Form {
                    Section {
                        Toggle(L10n.tr("Agent widzi to połączenie (tylko alias i środowisko)"), isOn: $draft.agentVisible)
                        Toggle(L10n.tr("Agent może zmieniać dane i obiekty (za zgodą)"), isOn: $draft.agentAllowChanges)
                            .disabled(!draft.agentVisible)
                        TextField(L10n.tr("Osobny użytkownik bazy dla agenta"), text: $draft.agentUser,
                                  prompt: Text(L10n.tr("zalecane dla produkcji (np. proxy tylko z SELECT)")))
                        TextField(L10n.tr("Kolumny maskowane dla agenta"), text: $draft.maskedColumns, prompt: Text("PESEL, EMAIL"))
                    } footer: {
                        Text(L10n.tr("Na połączeniach produkcyjnych agent domyślnie tylko czyta. Funkcje wywoływane w zapytaniach mogą mieć skutki uboczne — twardą granicą są uprawnienia użytkownika bazy."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .tabItem { Text(L10n.tr("Agent AI")) }
            }
            .padding([.top, .horizontal])

            HStack {
                Button(L10n.tr("Testuj"), action: onTest).disabled(!draft.isValid || draft.testing)
                if draft.testing { ProgressView().controlSize(.small) }
                if let r = draft.testResult {
                    Text(r).font(.callout).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                }
                Spacer()
                Button(L10n.tr("Anuluj"), role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(L10n.tr("Zapisz"), action: onSave).keyboardShortcut(.defaultAction).disabled(!draft.isValid)
            }
            .padding()
        }
        .frame(width: 620, height: 600)
        .onChange(of: draft.environment) { _, env in
            if draft.isNew { draft.agentAllowChanges = env != .production }
        }
    }
}

/// Prezentacja okna definicji połączenia jako arkusza okna głównego.
@MainActor
enum ConnectionEditorPresenter {
    static func present(workspace: Workspace, connectionID: UUID?, in window: NSWindow?) {
        let existing = connectionID.flatMap { workspace.connections.connection($0) }
        let draft = ConnectionDraft(existing, isNew: existing == nil)
        let tns = TNSNames.load(directories: TNSNames.searchDirectories(
            configured: existing?.target.configDirectory,
            instantClientDirectory: workspace.settings.instantClientDirectory)).flatMap(\.aliases).sorted()
        var sheet: NSWindow?
        let view = ConnectionEditorView(
            draft: draft, folders: workspace.connections.folders, tnsAliases: tns,
            onTest: { test(draft, workspace: workspace) },
            onSave: {
                do {
                    try workspace.connections.upsert(draft.definition, password: draft.password.isEmpty ? nil : draft.password)
                    if let sheet { window?.endSheet(sheet) }
                } catch {
                    draft.testResult = error.localizedDescription
                }
            },
            onCancel: { if let sheet { window?.endSheet(sheet) } })
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = existing == nil ? L10n.tr("Nowe połączenie") : L10n.tr("Połączenie")
        sheet = w
        if let window { window.beginSheet(w) } else { w.makeKeyAndOrderFront(nil) }
    }

    /// Test połączenia: łączy się wpisanymi danymi (bez zapisu), pokazuje wersję serwera i rozłącza.
    static func test(_ draft: ConnectionDraft, workspace: Workspace) {
        let def = draft.definition
        let password = draft.password.isEmpty ? workspace.connections.password(for: def.id) : draft.password
        guard let driver = workspace.sessions.driver(for: def.driver) else {
            draft.testResult = L10n.tr("Sterownik niedostępny")
            return
        }
        draft.testing = true
        draft.testResult = nil
        Task { @MainActor in
            defer { draft.testing = false }
            if case .failure(let e) = driver.availability() {
                draft.testResult = Self.message(e)
                return
            }
            do {
                let s = try await driver.connect(target: def.target, credentials: Credentials(password: password),
                                                 options: ConnectOptions(tags: SessionTags(module: "Pelikan", action: "test połączenia")))
                let banner = s.info.server.banner.split(separator: "\n").first.map(String.init) ?? s.info.server.description
                draft.testResult = "✓ " + banner + " · " + s.info.sessionUser
                await s.close()
            } catch {
                draft.testResult = "✗ " + Self.message(error)
            }
        }
    }

    static func message(_ error: any Error) -> String {
        if let e = error as? OracleError { return e.message }
        if case DatabaseError.driverUnavailable(let m) = error { return m }
        return error.localizedDescription
    }
}
