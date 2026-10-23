import AppKit
import PelikanWorkspace
import SwiftUI

/// Preferencje (UG 23): najważniejsze opcje wzorca w kartach; zapis natychmiastowy do settings.json.
struct PreferencesView: View {
    let workspace: Workspace

    var body: some View {
        TabView {
            GeneralPane(workspace: workspace).tabItem { Label(L10n.tr("Ogólne"), systemImage: "gearshape") }
            SQLWindowPane(workspace: workspace).tabItem { Label(L10n.tr("Okno SQL"), systemImage: "tablecells") }
            EditorPane(workspace: workspace).tabItem { Label(L10n.tr("Edytor"), systemImage: "text.cursor") }
            BeautifierPane(workspace: workspace).tabItem { Label(L10n.tr("Formater"), systemImage: "text.alignleft") }
            KeyboardPane(workspace: workspace).tabItem { Label(L10n.tr("Klawiatura"), systemImage: "keyboard") }
            OraclePane(workspace: workspace).tabItem { Label(L10n.tr("Oracle"), systemImage: "cylinder") }
        }
        .frame(width: 860, height: 560)
        .padding(.top, 8)
    }
}

/// Wiązanie do pola ustawień (zapis przy każdej zmianie).
@MainActor
func setting<T>(_ ws: Workspace, _ key: WritableKeyPath<PelikanWorkspace.Settings, T>) -> Binding<T> {
    Binding(get: { ws.settings[keyPath: key] }, set: { ws.settings[keyPath: key] = $0 })
}

struct GeneralPane: View {
    let workspace: Workspace
    var body: some View {
        Form {
            Section(L10n.tr("Sesje (UG 23.1)")) {
                Picker(L10n.tr("Tryb sesji"), selection: setting(workspace, \.sessionMode)) {
                    Text(L10n.tr("Multi — osobna sesja dla każdego okna")).tag(SessionMode.multi)
                    Text(L10n.tr("Dual — sesja wspólna i sesja kompilacji")).tag(SessionMode.dual)
                    Text(L10n.tr("Single — jedna sesja")).tag(SessionMode.single)
                }
                Picker(L10n.tr("Wylogowanie z otwartą transakcją"), selection: setting(workspace, \.logoffWithOpenTransaction)) {
                    Text(L10n.tr("Pytaj")).tag(OpenTransactionAction.ask)
                    Text(L10n.tr("Zatwierdź (COMMIT)")).tag(OpenTransactionAction.commit)
                    Text(L10n.tr("Wycofaj (ROLLBACK)")).tag(OpenTransactionAction.rollback)
                }
                Stepper(value: setting(workspace, \.checkConnectionIntervalSeconds), in: 0...3600, step: 30) {
                    Text(L10n.tr("Sprawdzanie połączenia co \(workspace.settings.checkConnectionIntervalSeconds) s (0 — wyłączone)"))
                }
                Toggle(L10n.tr("Przypinaj połączenie nowych okien"), isOn: setting(workspace, \.pinWindowConnectionsByDefault))
            }
            Section(L10n.tr("Wygląd (UG 23.16)")) {
                Picker(L10n.tr("Tryb"), selection: setting(workspace, \.appearance)) {
                    Text(L10n.tr("Jak system")).tag(AppearanceMode.system)
                    Text(L10n.tr("Jasny")).tag(AppearanceMode.light)
                    Text(L10n.tr("Ciemny")).tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented)
            }
            Section(L10n.tr("Pliki")) {
                Toggle(L10n.tr("Pytaj o zapis zmian przy zamykaniu nowych okien"), isOn: setting(workspace, \.confirmSaveNewWindows))
            }
        }
        .formStyle(.grouped)
    }
}

struct SQLWindowPane: View {
    let workspace: Workspace
    var body: some View {
        Form {
            Section(L10n.tr("Wykonywanie (UG 23.20)")) {
                Toggle(L10n.tr("AutoSelect — bez zaznaczenia wykonuj polecenie pod kursorem"), isOn: setting(workspace, \.autoSelectStatement))
                Toggle(L10n.tr("AutoCommit poleceń SQL"), isOn: setting(workspace, \.autoCommitSQL))
                Toggle(L10n.tr("Potwierdzaj COMMIT i ROLLBACK"), isOn: setting(workspace, \.confirmCommitRollback))
            }
            Section(L10n.tr("Wyniki")) {
                Picker(L10n.tr("Wierszy na stronę"), selection: Binding(
                    get: { recordsTag(workspace.settings.recordsPerPage) },
                    set: { workspace.settings.recordsPerPage = $0 == 0 ? .automatic : $0 < 0 ? .all : .fixed($0) })) {
                    Text(L10n.tr("Automatycznie (strona)")).tag(0)
                    Text("100").tag(100)
                    Text("500").tag(500)
                    Text("1000").tag(1000)
                    Text(L10n.tr("Wszystkie")).tag(-1)
                }
                Stepper(value: setting(workspace, \.maximumResultSetMegabytes), in: 16...8192, step: 64) {
                    Text(L10n.tr("Maksymalny rozmiar wyniku: \(workspace.settings.maximumResultSetMegabytes) MB"))
                }
            }
            Section(L10n.tr("DBMS_OUTPUT (UG 23.5)")) {
                Toggle(L10n.tr("Włączone"), isOn: setting(workspace, \.dbmsOutputEnabled))
                Toggle(L10n.tr("Czyść przed wykonaniem"), isOn: setting(workspace, \.dbmsOutputClearBeforeExecute))
            }
            Section(L10n.tr("Formaty dat (UG 23.17)")) {
                TextField(L10n.tr("DATE"), text: setting(workspace, \.dateFormat)).font(.body.monospaced())
                TextField(L10n.tr("TIMESTAMP"), text: setting(workspace, \.timestampFormat)).font(.body.monospaced())
            }
        }
        .formStyle(.grouped)
    }

    func recordsTag(_ r: RecordsPerPage) -> Int {
        switch r {
        case .automatic: 0
        case .fixed(let n): n
        case .all: -1
        }
    }
}

struct EditorPane: View {
    let workspace: Workspace
    var body: some View {
        Form {
            Section(L10n.tr("Czcionka (UG 23.12)")) {
                Picker(L10n.tr("Czcionka"), selection: setting(workspace, \.editorFontName)) {
                    ForEach(["SF Mono", "Menlo", "Monaco", "Courier New", "JetBrains Mono"].filter { NSFont(name: $0, size: 12) != nil }, id: \.self) { Text($0).tag($0) }
                }
                Stepper(value: setting(workspace, \.editorFontSize), in: 8...32, step: 1) {
                    Text(L10n.tr("Rozmiar: \(Int(workspace.settings.editorFontSize)) pt"))
                }
            }
            Section(L10n.tr("Pisanie")) {
                Picker(L10n.tr("Wielkość liter słów kluczowych"), selection: setting(workspace, \.keywordCase)) {
                    Text(L10n.tr("Bez zmian")).tag(KeywordCase.unchanged)
                    Text(L10n.tr("WIELKIE")).tag(KeywordCase.upper)
                    Text(L10n.tr("małe")).tag(KeywordCase.lower)
                    Text(L10n.tr("Pierwsza wielka")).tag(KeywordCase.initCap)
                }
                Toggle(L10n.tr("Podświetlaj bieżącą linię"), isOn: setting(workspace, \.highlightCurrentLine))
            }
            Section(L10n.tr("Wcięcia")) {
                Stepper(value: setting(workspace, \.tabSize), in: 1...8) { Text(L10n.tr("Szerokość tabulacji: \(workspace.settings.tabSize)")) }
                Toggle(L10n.tr("Wstawiaj znak tabulacji zamiast spacji"), isOn: setting(workspace, \.useTabCharacter))
            }
        }
        .formStyle(.grouped)
    }
}

struct OraclePane: View {
    let workspace: Workspace
    var body: some View {
        Form {
            Section(L10n.tr("Oracle Instant Client")) {
                HStack {
                    Text(workspace.settings.instantClientDirectory ?? L10n.tr("Wykrywany automatycznie (Homebrew, /opt/oracle, Pobrane)"))
                        .foregroundStyle(workspace.settings.instantClientDirectory == nil ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(L10n.tr("Wybierz…")) { choose() }
                    if workspace.settings.instantClientDirectory != nil {
                        Button(L10n.tr("Automatycznie")) { workspace.settings.instantClientDirectory = nil }
                    }
                }
                Text(L10n.tr("Zmiana działa po ponownym uruchomieniu aplikacji. Pelikan nie dołącza Instant Client (licencja Oracle) — pobierz go ze strony Oracle."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.tr("Debuger (UG 23.4)")) {
                Toggle(L10n.tr("Dodawaj informację debugowania przy kompilacji okna programu"), isOn: setting(workspace, \.debugInfoOnCompile))
            }
            Section(L10n.tr("Słownik danych")) {
                Toggle(L10n.tr("Używaj widoków DBA_, jeśli dostępne"), isOn: setting(workspace, \.useDBAViews))
            }
        }
        .formStyle(.grouped)
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = L10n.tr("Wybierz katalog z biblioteką libclntsh.dylib")
        if panel.runModal() == .OK, let url = panel.url {
            workspace.settings.instantClientDirectory = url.path
        }
    }
}

/// Karta Klawiatura (UG 23.29): profil skrótów, lista komend z wyszukiwaniem, nagrywanie skrótu z wykrywaniem konfliktu.
struct KeyboardPane: View {
    let workspace: Workspace
    @State private var search = ""
    @State private var selection: String?
    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?

    struct Row: Identifiable {
        let d: CommandDescriptor
        var id: String { d.id.rawValue }
    }

    var rows: [Row] {
        workspace.registry.descriptors.filter { d in
            search.isEmpty || d.title.localizedCaseInsensitiveContains(search) || d.id.rawValue.localizedCaseInsensitiveContains(search)
        }.map(Row.init)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker(L10n.tr("Profil skrótów"), selection: setting(workspace, \.shortcutProfile)) {
                    Text(L10n.tr("PL/SQL Developer")).tag(ShortcutProfile.plsqlDeveloper)
                    Text(L10n.tr("macOS")).tag(ShortcutProfile.macOS)
                }
                .frame(width: 320)
                Spacer()
                TextField(L10n.tr("Szukaj komendy"), text: $search).frame(width: 220)
            }
            Table(rows, selection: $selection) {
                TableColumn(L10n.tr("Komenda")) { (r: Row) in Text(r.d.submenu.map { "\($0) › \(r.d.title)" } ?? r.d.title) }
                TableColumn(L10n.tr("Menu")) { (r: Row) in Text(r.d.category.displayName).foregroundStyle(.secondary) }.width(110)
                TableColumn(L10n.tr("Skróty")) { (r: Row) in
                    Text(workspace.keymap.chords(for: r.d.id).map(\.displayString).joined(separator: "  ")).font(.body.monospaced())
                }.width(170)
            }
            .onChange(of: selection) { _, _ in message = nil }
            HStack {
                Button(recording ? L10n.tr("Naciśnij skrót… (Esc — anuluj)") : L10n.tr("Dodaj skrót…")) { record() }
                    .disabled(selection == nil || recording)
                Button(L10n.tr("Usuń skróty komendy")) {
                    guard let id = selection else { return }
                    for c in workspace.keymap.chords(for: CommandID(rawValue: id)) { workspace.removeShortcut(c) }
                }.disabled(selection == nil)
                Button(L10n.tr("Domyślne dla komendy")) { if let id = selection { workspace.resetShortcuts(for: CommandID(rawValue: id)) } }
                    .disabled(selection == nil)
                Spacer()
                Button(L10n.tr("Przywróć wszystkie domyślne")) { workspace.resetShortcuts() }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.orange) }
        }
        .padding(16)
        .onDisappear { stopRecording() }
    }

    func record() {
        guard let id = selection else { return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                stopRecording()
                return nil
            }
            guard let chord = MenuBuilder.chord(for: event) else { return nil }
            let cmd = CommandID(rawValue: id)
            if let other = workspace.conflictingCommand(for: chord, assigning: cmd) {
                let title = workspace.registry.command(other)?.descriptor.title ?? other.rawValue
                message = L10n.tr("Skrót \(chord.displayString) przeniesiono z komendy „\(title)”.")
            }
            workspace.assignShortcut(chord, to: cmd)
            stopRecording()
            return nil
        }
    }

    func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

/// Okno Preferencji (jedno na aplikację).
@MainActor
final class PreferencesWindowController: NSWindowController {
    private static var shared: PreferencesWindowController?

    static func show(workspace: Workspace) {
        let c = shared ?? PreferencesWindowController(workspace: workspace)
        shared = c
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
    }

    init(workspace: Workspace) {
        let w = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView(workspace: workspace)))
        w.title = L10n.tr("Preferencje")
        w.styleMask = [.titled, .closable]
        super.init(window: w)
        w.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
