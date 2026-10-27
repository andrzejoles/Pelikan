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
    /// Logowanie: hasło, Oracle Wallet (magazyn haseł, `/@alias`) albo uwierzytelnianie zewnętrzne (Kerberos, system).
    enum AuthMode: String, CaseIterable { case password, wallet, external, entra, oauthFile }
    var authMode: AuthMode
    var configDirectory: String
    var walletDirectory: String
    var tokenTenant: String
    var tokenClient: String
    var tokenAppURI: String
    var tokenLocation: String
    var managementPacks: ManagementPackLicense?
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
    var sshEnabled: Bool
    var sshHost: String
    var sshPort: Int
    var sshUser: String
    var sshIdentity: String
    var sshJump: String
    /// Hasło SSH zamiast klucza (DB-SSH-001): tylko Pęk kluczy; puste pole — bez zmian.
    var sshUsesPassword: Bool
    var sshPassword = ""
    var isNew: Bool
    var testResult: String?
    var testing = false

    init(_ def: ConnectionDefinition?, isNew: Bool) {
        let d = def ?? ConnectionDefinition(target: ConnectionTarget(user: "", connectString: ""))
        id = d.id; name = d.name; folderID = d.folderID; environment = d.environment
        useCustomColor = d.color != nil
        color = d.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .accentColor
        driver = d.driver; user = d.target.user; savePassword = d.savePassword; connectString = d.target.connectString
        role = d.target.role; proxyClient = d.target.proxyClient ?? ""
        authMode = d.target.tokenAuth?.flow == .azureInteractive ? .entra : d.target.tokenAuth?.flow == .oauthFile ? .oauthFile
            : d.target.walletAuth == true ? .wallet : d.target.externalAuth ? .external : .password
        tokenTenant = d.target.tokenAuth?.tenantID ?? ""; tokenClient = d.target.tokenAuth?.clientID ?? ""
        tokenAppURI = d.target.tokenAuth?.appIDURI ?? ""; tokenLocation = d.target.tokenAuth?.tokenLocation ?? ""
        walletDirectory = d.target.walletDirectory ?? ""
        managementPacks = d.managementPacks
        configDirectory = d.target.configDirectory ?? ""; edition = d.target.edition ?? ""
        workspaceManager = d.workspaceManager ?? ""; currentSchema = d.currentSchema ?? ""
        readOnly = d.readOnly; connectOnStartup = d.connectOnStartup; initScript = d.initScript; logonMessage = d.logonMessage
        agentVisible = d.agent.visibleToAgent; agentAllowChanges = d.agent.allowChanges; agentUser = d.agent.agentUser ?? ""
        maskedColumns = d.agent.maskedColumns.joined(separator: ", ")
        sshEnabled = d.sshTunnel != nil
        sshHost = d.sshTunnel?.host ?? ""
        sshPort = d.sshTunnel?.port ?? 22
        sshUser = d.sshTunnel?.user ?? NSUserName()
        sshIdentity = d.sshTunnel?.identityFile ?? ""
        sshJump = d.sshTunnel?.jumpHost ?? ""
        sshUsesPassword = d.sshTunnel?.usesPassword ?? false
        self.isNew = isNew
    }

    var definition: ConnectionDefinition {
        func opt(_ s: String) -> String? { let t = s.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t }
        var rgb: PelikanWorkspace.RGBColor?
        if useCustomColor, let c = NSColor(color).usingColorSpace(.sRGB) {
            rgb = PelikanWorkspace.RGBColor(red: Double(c.redComponent), green: Double(c.greenComponent), blue: Double(c.blueComponent))
        }
        var def = ConnectionDefinition(
            id: id, name: name.trimmingCharacters(in: .whitespaces), folderID: folderID,
            target: ConnectionTarget(user: user.trimmingCharacters(in: .whitespaces), connectString: connectString.trimmingCharacters(in: .whitespaces),
                                     role: role, proxyClient: opt(proxyClient), externalAuth: authMode == .external,
                                     configDirectory: opt(configDirectory), edition: opt(edition)),
            driver: driver, environment: environment, color: rgb, savePassword: savePassword, readOnly: readOnly,
            connectOnStartup: connectOnStartup, initScript: initScript, logonMessage: logonMessage,
            workspaceManager: opt(workspaceManager),
            agent: AgentConnectionPolicy(visibleToAgent: agentVisible, allowChanges: agentAllowChanges, agentUser: opt(agentUser),
                                         maskedColumns: maskedColumns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }),
            currentSchema: opt(currentSchema))
        def.managementPacks = managementPacks
        def.target.walletAuth = authMode == .wallet ? true : nil
        def.target.tokenAuth = switch authMode {
        case .entra: TokenAuth(flow: .azureInteractive, tenantID: opt(tokenTenant), clientID: opt(tokenClient), appIDURI: opt(tokenAppURI))
        case .oauthFile: TokenAuth(flow: .oauthFile, tokenLocation: opt(tokenLocation))
        default: nil
        }
        def.target.walletDirectory = opt(walletDirectory)
        if sshEnabled, let host = opt(sshHost) {
            def.sshTunnel = SSHTunnel(host: host, port: sshPort, user: sshUser.trimmingCharacters(in: .whitespaces),
                                      identityFile: sshUsesPassword ? nil : opt(sshIdentity), jumpHost: opt(sshJump),
                                      usesPassword: sshUsesPassword)
        }
        return def
    }

    var isValid: Bool {
        !connectString.trimmingCharacters(in: .whitespaces).isEmpty && (authMode != .password || !user.trimmingCharacters(in: .whitespaces).isEmpty)
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

    static func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Portfel z pliku ZIP (np. Autonomous Database): rozpakowany obok archiwum do katalogu o tej samej nazwie (0700);
    /// staje się portfelem TLS połączenia, a jego tnsnames.ora — katalogiem konfiguracji.
    private func importWalletZip() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let zip = panel.url else { return }
        let target = zip.deletingPathExtension()
        let draft = draft
        Task { @MainActor in
            do {
                // Rozpakowanie w tle — duże archiwum nie blokuje interfejsu.
                let status = try await Task.detached {
                    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    p.arguments = ["-x", "-k", zip.path, target.path]
                    try p.run()
                    p.waitUntilExit()
                    return p.terminationStatus
                }.value
                guard status == 0 else {
                    draft.testResult = L10n.tr("Nie udało się rozpakować portfela (ditto, kod \(status))")
                    return
                }
                draft.walletDirectory = target.path
                if FileManager.default.fileExists(atPath: target.appendingPathComponent("tnsnames.ora").path) { draft.configDirectory = target.path }
            } catch {
                draft.testResult = error.localizedDescription
            }
        }
    }

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
                        TextField(L10n.tr("Użytkownik"), text: $draft.user).disabled(draft.authMode != .password)
                        SecureField(L10n.tr("Hasło"), text: $draft.password,
                                    prompt: Text(draft.isNew ? "" : L10n.tr("bez zmian"))).disabled(draft.authMode != .password)
                        Toggle(L10n.tr("Zapamiętaj hasło w Pęku kluczy"), isOn: $draft.savePassword).disabled(draft.authMode != .password)
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
                        Picker(L10n.tr("Uwierzytelnianie"), selection: $draft.authMode) {
                            Text(L10n.tr("Hasło")).tag(ConnectionDraft.AuthMode.password)
                            Text(L10n.tr("Oracle Wallet (magazyn haseł)")).tag(ConnectionDraft.AuthMode.wallet)
                            Text(L10n.tr("Zewnętrzne (Kerberos, system)")).tag(ConnectionDraft.AuthMode.external)
                            Text(L10n.tr("Microsoft Entra ID (przeglądarka)")).tag(ConnectionDraft.AuthMode.entra)
                            Text(L10n.tr("Token OAuth2 z pliku")).tag(ConnectionDraft.AuthMode.oauthFile)
                        }
                        if draft.authMode == .entra {
                            TextField(L10n.tr("Identyfikator dzierżawy (tenant)"), text: $draft.tokenTenant)
                            TextField(L10n.tr("Identyfikator aplikacji klienta"), text: $draft.tokenClient)
                            TextField(L10n.tr("URI aplikacji bazy"), text: $draft.tokenAppURI)
                            Text(L10n.tr("Instant Client 23 otwiera przeglądarkę do logowania w Entra ID i sam przekazuje token bazie; Pelikan nie widzi ani nie zapisuje tokenu. Wymaga połączenia TCPS (portfel TLS w polu poniżej albo w konfiguracji)."))
                                .font(.uiSecondary).foregroundStyle(.secondary)
                        }
                        if draft.authMode == .oauthFile {
                            TextField(L10n.tr("Plik albo katalog tokenu"), text: $draft.tokenLocation)
                            Text(L10n.tr("Token zapisany wcześniej narzędziem zewnętrznym (np. Azure CLI) — klient Oracle czyta go przy łączeniu."))
                                .font(.uiSecondary).foregroundStyle(.secondary)
                        }
                        if draft.authMode == .wallet {
                            Text(L10n.tr("Logowanie /@baza poświadczeniem z portfela wskazanego w Preferencjach › Oracle (Oracle Wallet). Pole „Baza” musi być dokładnie aliasem albo connect stringiem zapisanym w portfelu; alias musi być w konfiguracji Oracle Net z Preferencji."))
                                .font(.uiSecondary).foregroundStyle(.secondary)
                        }
                        Picker(L10n.tr("Sterownik"), selection: $draft.driver) {
                            Text(L10n.tr("Instant Client (zalecany)")).tag(DriverKind.instantClient)
                            Text(L10n.tr("Thin (bez Instant Client)")).tag(DriverKind.thin)
                        }
                        if draft.driver == .thin {
                            Text(L10n.tr("Thin nie obsługuje: TCPS/wallet, uwierzytelniania zewnętrznego, zmiany wygasłego hasła i przerwania wykonania (Przerwij). Do nich przełącz na Instant Client."))
                                .font(.uiSecondary).foregroundStyle(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
                .tabItem { Text(L10n.tr("Ogólne")) }

                Form {
                    Section(L10n.tr("Połączenie")) {
                        TextField(L10n.tr("Proxy: schemat docelowy"), text: $draft.proxyClient, prompt: Text(L10n.tr("użytkownik[schemat]")))
                        TextField(L10n.tr("Katalog konfiguracji (tnsnames.ora)"), text: $draft.configDirectory, prompt: Text("~/Oracle/network/admin"))
                        HStack {
                            TextField(L10n.tr("Portfel TLS (mTLS, np. Autonomous Database)"), text: $draft.walletDirectory, prompt: Text(L10n.tr("katalog z cwallet.sso")))
                            Button(L10n.tr("Wybierz…")) { if let u = Self.chooseDirectory() { draft.walletDirectory = u.path } }
                            Button(L10n.tr("Importuj ZIP…")) { importWalletZip() }
                        }
                        if !draft.walletDirectory.isEmpty {
                            switch OracleNet.walletStatus(draft.walletDirectory) {
                            case .autoLogin: Text(L10n.tr("Portfel z automatycznym logowaniem (cwallet.sso)")).font(.uiSecondary).foregroundStyle(.green)
                            case .passwordOnly: Text(L10n.tr("Tylko ewallet.p12 — potrzebny portfel z automatycznym logowaniem (cwallet.sso)")).font(.uiSecondary).foregroundStyle(.orange)
                            case .missing: Text(L10n.tr("W katalogu nie ma portfela")).font(.uiSecondary).foregroundStyle(.red)
                            }
                        }
                        TextField(L10n.tr("Edition (EBR)"), text: $draft.edition)
                        Picker(L10n.tr("Licencja Diagnostics/Tuning Pack"), selection: $draft.managementPacks) {
                            Text(L10n.tr("Nie określono (pytanie przy pierwszym użyciu)")).tag(ManagementPackLicense?.none)
                            ForEach(ManagementPackLicense.allCases, id: \.self) { Text($0.displayName).tag(ManagementPackLicense?.some($0)) }
                        }
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
                        Toggle(L10n.tr("Łącz przez tunel SSH"), isOn: $draft.sshEnabled)
                        TextField(L10n.tr("Serwer SSH (bastion)"), text: $draft.sshHost, prompt: Text("bastion.example.com"))
                            .disabled(!draft.sshEnabled)
                        TextField(L10n.tr("Port"), value: $draft.sshPort, format: .number.grouping(.never)).disabled(!draft.sshEnabled)
                        TextField(L10n.tr("Użytkownik SSH"), text: $draft.sshUser).disabled(!draft.sshEnabled)
                        HStack {
                            TextField(L10n.tr("Plik klucza prywatnego"), text: $draft.sshIdentity, prompt: Text(L10n.tr("puste — agent SSH i ~/.ssh/config")))
                            Button(L10n.tr("Wybierz…")) {
                                let panel = NSOpenPanel()
                                panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh")
                                panel.showsHiddenFiles = true
                                if panel.runModal() == .OK, let u = panel.url { draft.sshIdentity = u.path }
                            }
                        }
                        .disabled(!draft.sshEnabled)
                        TextField(L10n.tr("Host pośredni (ProxyJump)"), text: $draft.sshJump, prompt: Text(L10n.tr("opcjonalnie")))
                            .disabled(!draft.sshEnabled)
                        Toggle(L10n.tr("Logowanie hasłem SSH (zamiast klucza)"), isOn: $draft.sshUsesPassword).disabled(!draft.sshEnabled)
                        SecureField(L10n.tr("Hasło SSH"), text: $draft.sshPassword, prompt: Text(draft.isNew ? "" : L10n.tr("bez zmian")))
                            .disabled(!draft.sshEnabled || !draft.sshUsesPassword)
                    } footer: {
                        Text(L10n.tr("Tunel używa systemowego ssh: ~/.ssh/config, agenta SSH (klucze w Pęku kluczy: ssh-add --apple-use-keychain) i znanych hostów. Host i port bazy w polu „Baza” podaj tak, jak widzi je serwer SSH. Hasło SSH jest tylko w Pęku kluczy i trafia do ssh przez jednorazową kolejkę, nigdy przez argumenty, środowisko ani pliki."))
                            .font(.uiSecondary).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .tabItem { Text(L10n.tr("Tunel SSH")) }

                Form {
                    Section {
                        Toggle(L10n.tr("Agent widzi to połączenie (tylko alias i środowisko)"), isOn: $draft.agentVisible)
                        Toggle(L10n.tr("Agent może zmieniać dane i obiekty (za zgodą)"), isOn: $draft.agentAllowChanges)
                            .disabled(!draft.agentVisible)
                        TextField(L10n.tr("Osobny użytkownik bazy dla agenta"), text: $draft.agentUser,
                                  prompt: Text(L10n.tr("proxy, zalecane dla produkcji (tylko z SELECT)")))
                        TextField(L10n.tr("Kolumny maskowane dla agenta"), text: $draft.maskedColumns, prompt: Text("PESEL, EMAIL"))
                    } footer: {
                        Text(L10n.tr("Na połączeniach produkcyjnych agent domyślnie tylko czyta. Użytkownik agenta łączy się przez proxy (główny[agent]) — wymaga ALTER USER agent GRANT CONNECT THROUGH główny; bez drugiego hasła. Kolumny maskowane: nazwy kolumn albo SCHEMAT.TABELA.KOLUMNA, rozdzielone przecinkami. Funkcje wywoływane w zapytaniach mogą mieć skutki uboczne — twardą granicą są uprawnienia użytkownika bazy."))
                            .font(.uiSecondary).foregroundStyle(.secondary)
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
                    Text(r).font(.ui).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                }
                Spacer()
                Button(L10n.tr("Anuluj"), role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(L10n.tr("Zapisz"), action: onSave).keyboardShortcut(.defaultAction).disabled(!draft.isValid)
            }
            .padding()
        }
        .windowSize(width: 620, height: 600)
        .onChange(of: draft.environment) { _, env in
            // Przejście na produkcję zawsze wyłącza zmiany agenta (włączenie z powrotem to świadoma decyzja w tej karcie).
            if draft.isNew || env == .production { draft.agentAllowChanges = env != .production }
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
        // Zamknięcie zrywa cykl okno → widok → domknięcie → okno i nie zostawia haseł szkicu w pamięci.
        func close() {
            if let sheet { window?.endSheet(sheet) }
            sheet = nil
            draft.password = ""
            draft.sshPassword = ""
        }
        let view = ConnectionEditorView(
            draft: draft, folders: workspace.connections.folders, tnsAliases: tns,
            onTest: { test(draft, workspace: workspace) },
            onSave: {
                do {
                    try workspace.connections.upsert(draft.definition, password: draft.password.isEmpty ? nil : draft.password)
                    if draft.sshEnabled, draft.sshUsesPassword, !draft.sshPassword.isEmpty {
                        try workspace.connections.setSSHPassword(draft.sshPassword, for: draft.definition.id)
                    } else if !draft.sshEnabled || !draft.sshUsesPassword {
                        try? workspace.connections.setSSHPassword("", for: draft.definition.id)
                    }
                    close()
                } catch {
                    draft.testResult = error.localizedDescription
                }
            },
            onCancel: { close() })
        let host = NSHostingController(rootView: view.interfaceFont())
        let w = NSWindow(contentViewController: host)
        w.title = existing == nil ? L10n.tr("Nowe połączenie") : L10n.tr("Połączenie")
        sheet = w
        if let window { window.beginSheet(w) } else { w.makeKeyAndOrderFront(nil) }
    }

    /// Test połączenia: łączy się wpisanymi danymi (bez zapisu), pokazuje wersję serwera i rozłącza.
    static func test(_ draft: ConnectionDraft, workspace: Workspace) {
        let def = draft.definition
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
            // Hasło jak przy łączeniu (SessionManager, D56): zapisane w Pęku kluczy tylko po potwierdzeniu właściciela.
            var password: String? = draft.password.isEmpty ? workspace.connections.sessionPassword(for: def.id) : draft.password
            if password == nil, workspace.connections.hasStoredPassword(for: def.id) {
                if workspace.settings.requireOwnerForSavedPasswords {
                    guard await workspace.sessions.prompter?.authenticateOwner(reason: L10n.tr("użyć zapisanego hasła połączenia „\(def.displayName)”")) == true else {
                        draft.testResult = L10n.tr("Anulowano")
                        return
                    }
                }
                password = workspace.connections.password(for: def.id)
            }
            var target = def.target
            var tunnel: SSHTunnelManager.Tunnel?
            defer { if let tunnel { workspace.sessions.tunnels.release(tunnel, of: def.id) } }
            do {
                if def.sshTunnel != nil {
                    // Katalogi TNS i hasło SSH jak przy łączeniu: wpisane w oknie albo zapisane (po potwierdzeniu właściciela).
                    let tns = workspace.sessions.tnsEntries(for: def)
                    let secret = draft.sshUsesPassword && !draft.sshPassword.isEmpty ? draft.sshPassword : try await workspace.sessions.tunnelSecret(for: def)
                    let opened = try await workspace.sessions.tunnels.open(for: def, tns: tns, secret: secret)
                    tunnel = opened
                    target.connectString = ConnectStringRewriter.rewrite(def.target.connectString, localPort: opened.localPort, tns: tns) ?? target.connectString
                }
                let module = Bundle.main.object(forInfoDictionaryKey: "PelikanAppName") as? String ?? "Pelikan"
                let s = try await driver.connect(target: target, credentials: Credentials(password: password),
                                                 options: ConnectOptions(tags: SessionTags(module: module, action: "test połączenia")))
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
