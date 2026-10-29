import AppKit
import LocalAuthentication
import PelikanDB
import PelikanLog
import PelikanWorkspace
import SwiftUI

/// Wybrana karta Preferencji — wspólna dla okna, żeby komendy mogły otwierać konkretną kartę (np. Zestawy).
@MainActor
@Observable
final class PreferencesNavigation {
    var pane = "GeneralPane"
}

/// Preferencje (UG 23): najważniejsze opcje wzorca w kartach; zapis natychmiastowy do settings.json (bez przycisku
/// Zastosuj, jak w ustawieniach macOS). Wyszukiwarka przechodzi do karty z pasującym ustawieniem (PD-PREF-001).
struct PreferencesView: View {
    let workspace: Workspace
    @Bindable var navigation: PreferencesNavigation
    @State private var query = ""

    static let panes: [(id: String, title: String, icon: String)] = [
        ("GeneralPane", L10n.tr("Ogólne"), "gearshape"), ("SQLWindowPane", L10n.tr("Okno SQL"), "tablecells"),
        ("EditorPane", L10n.tr("Edytor"), "text.cursor"), ("BeautifierPane", L10n.tr("Formater"), "text.alignleft"),
        ("KeyboardPane", L10n.tr("Klawiatura"), "keyboard"), ("OraclePane", L10n.tr("Oracle"), "cylinder"),
        ("BrowserPane", L10n.tr("Object Browser"), "list.bullet.indent"), ("ToolsPane", L10n.tr("Narzędzia"), "wrench.and.screwdriver"),
        ("AgentsPane", L10n.tr("Agenci"), "cpu"), ("PreferenceSetsPane", L10n.tr("Zestawy"), "square.stack.3d.up"),
    ]

    static func matches(_ query: String) -> [(pane: String, label: String)] {
        PreferenceSearch.filter(PreferenceIndex.entries, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L10n.tr("Szukaj ustawienia"), text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
                        .iconLabel(L10n.tr("Wyczyść"))
                }
            }
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            if query.isEmpty {
                TabView(selection: $navigation.pane) {
                    GeneralPane(workspace: workspace).tag("GeneralPane").tabItem { tab("GeneralPane") }
                    SQLWindowPane(workspace: workspace).tag("SQLWindowPane").tabItem { tab("SQLWindowPane") }
                    EditorPane(workspace: workspace).tag("EditorPane").tabItem { tab("EditorPane") }
                    BeautifierPane(workspace: workspace).tag("BeautifierPane").tabItem { tab("BeautifierPane") }
                    KeyboardPane(workspace: workspace).tag("KeyboardPane").tabItem { tab("KeyboardPane") }
                    OraclePane(workspace: workspace).tag("OraclePane").tabItem { tab("OraclePane") }
                    BrowserPane(workspace: workspace).tag("BrowserPane").tabItem { tab("BrowserPane") }
                    ToolsPane(workspace: workspace).tag("ToolsPane").tabItem { tab("ToolsPane") }
                    AgentsPane(workspace: workspace).tag("AgentsPane").tabItem { tab("AgentsPane") }
                    PreferenceSetsPane(workspace: workspace).tag("PreferenceSetsPane").tabItem { tab("PreferenceSetsPane") }
                }
                .padding(.top, 8)
            } else {
                let found = Self.matches(query)
                List {
                    if found.isEmpty { Text(L10n.tr("Nic nie znaleziono")).foregroundStyle(.secondary) }
                    ForEach(Array(found.enumerated()), id: \.offset) { _, f in
                        Button {
                            navigation.pane = f.pane
                            query = ""
                        } label: {
                            HStack {
                                Text(f.label)
                                Spacer()
                                Text(Self.panes.first { $0.id == f.pane }?.title ?? "").foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
            }
        }
        .windowSize(width: 860, height: 600)
    }

    private func tab(_ id: String) -> some View {
        let p = Self.panes.first { $0.id == id }!
        return Label(p.title, systemImage: p.icon)
    }
}

/// Wiązanie do pola ustawień (zapis przy każdej zmianie).
@MainActor
func setting<T>(_ ws: Workspace, _ key: WritableKeyPath<PelikanWorkspace.Settings, T>) -> Binding<T> {
    Binding(get: { ws.settings[keyPath: key] }, set: { ws.settings[keyPath: key] = $0 })
}

/// Wiązanie do pola elementu listy ustawień wskazanego identyfikatorem (nie indeksem): usunięcie wiersza w trakcie
/// edycji pola nie zapisze wartości do sąsiedniego elementu ani poza zakres; elementu już nie ma — zapis pominięty.
@MainActor
func setting<E: Identifiable, T>(_ ws: Workspace, _ list: WritableKeyPath<PelikanWorkspace.Settings, [E]>, _ id: E.ID,
                                 _ key: WritableKeyPath<E, T>, fallback: T) -> Binding<T> {
    Binding(get: { ws.settings[keyPath: list].first { $0.id == id }?[keyPath: key] ?? fallback },
            set: { v in
                if let i = ws.settings[keyPath: list].firstIndex(where: { $0.id == id }) { ws.settings[keyPath: list][i][keyPath: key] = v }
            })
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
            Section(L10n.tr("Wskaźniki połączeń")) {
                Toggle(L10n.tr("Tło edytora w kolorze połączenia"), isOn: setting(workspace, \.colorWindowBackground))
                Text(L10n.tr("Reguły user@baza (* i ?) mają pierwszeństwo przed kolorem połączenia i środowiska; dotyczą kart, listy okien i tła."))
                    .font(.uiSecondary).foregroundStyle(.secondary)
                ForEach(workspace.settings.connectionIndicators) { r in
                    HStack {
                        TextField(L10n.tr("Wzorzec, np. sys@*"), text: setting(workspace, \.connectionIndicators, r.id, \.pattern, fallback: ""))
                        ColorPicker("", selection: Binding(get: {
                            let c = r.color
                            return Color(red: c.red, green: c.green, blue: c.blue)
                        }, set: { c in
                            let n = NSColor(c).usingColorSpace(.sRGB) ?? .systemRed
                            setting(workspace, \.connectionIndicators, r.id, \.color, fallback: r.color).wrappedValue =
                                RGBColor(red: n.redComponent, green: n.greenComponent, blue: n.blueComponent)
                        }), supportsOpacity: false).labelsHidden()
                        Button { workspace.settings.connectionIndicators.removeAll { $0.id == r.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).iconLabel(L10n.tr("Usuń regułę"))
                    }
                }
                Button(L10n.tr("Dodaj regułę")) {
                    workspace.settings.connectionIndicators.append(ConnectionIndicator(pattern: "*@*", color: RGBColor(red: 0.85, green: 0.2, blue: 0.2)))
                }
            }
            Section(L10n.tr("Wygląd (UG 23.16)")) {
                Picker(L10n.tr("Tryb"), selection: setting(workspace, \.appearance)) {
                    Text(L10n.tr("Jak system")).tag(AppearanceMode.system)
                    Text(L10n.tr("Jasny")).tag(AppearanceMode.light)
                    Text(L10n.tr("Ciemny")).tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented)
            }
            Section(L10n.tr("Czcionka interfejsu")) {
                FontFamilyPicker(title: L10n.tr("Krój"), selection: setting(workspace, \.uiFontName),
                                 defaultLabel: L10n.tr("Systemowa (SF Pro)"), families: AppFonts.cachedFamilies)
                FontWeightPicker(selection: setting(workspace, \.uiFontWeight))
                Stepper(value: setting(workspace, \.uiFontSize), in: 10...20, step: 1) {
                    Text(L10n.tr("Wielkość: \(Int(workspace.settings.uiFontSize)) pt"))
                }
                Text(L10n.tr("Etykiety, listy, wstążka, karty okien, pasek stanu, okna narzędzi i Preferencji. Tekst pomocniczy jest o 2 pt mniejszy; menu i tytuły okien rysuje macOS."))
                    .font(.uiSecondary).foregroundStyle(.secondary)
                Text(L10n.tr("Przykład: Okno SQL — SELECT * FROM emp; Połączono z dev_baza_testowa"))
                    .font(Font(AppFonts.font(family: workspace.settings.uiFontName, size: workspace.settings.uiFontSize,
                                             weight: workspace.settings.uiFontWeight) as CTFont))
            }
            Section(L10n.tr("Wstążka")) {
                Toggle(L10n.tr("Pokaż wstążkę z kartami czynności"), isOn: setting(workspace, \.showRibbon))
                Toggle(L10n.tr("Zwiń wstążkę do samych kart"), isOn: setting(workspace, \.ribbonCollapsed))
                    .disabled(!workspace.settings.showRibbon)
                Text(L10n.tr("Karty kontekstowe (Program, Wynik, Diagram…) pojawiają się przy oknie danego rodzaju. Pole „Szukaj czynności” znajduje każdą komendę po nazwie, także bez polskich znaków i po angielskiej nazwie z PL/SQL Developera."))
                    .font(.uiSecondary).foregroundStyle(.secondary)
            }
            Section(L10n.tr("Panele narzędzi")) {
                Picker(L10n.tr("Nowe narzędzia otwieraj"), selection: setting(workspace, \.toolDock.defaultPlacement)) {
                    ForEach(ToolPlacement.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle(L10n.tr("Autoukrywanie paneli, gdy praca wraca do edytora"), isOn: setting(workspace, \.toolDock.autoHide))
                HStack {
                    Text(L10n.tr("Narzędzia z własnym miejscem: \(workspace.settings.toolDock.placements.count)"))
                    Spacer()
                    Button(L10n.tr("Przywróć miejsca domyślne")) { workspace.settings.toolDock.placements = [:] }
                        .disabled(workspace.settings.toolDock.placements.isEmpty)
                }
                Text(L10n.tr("Narzędzie przenosi się przeciągnięciem karty do drugiego panelu albo poza panele (osobne okno), menu karty i przyciskiem na pasku tytułu okna narzędzia. Pelikan zapamiętuje miejsce każdego rodzaju narzędzia."))
                    .font(.uiSecondary).foregroundStyle(.secondary)
            }
            Section(L10n.tr("Język interfejsu")) {
                // AppleLanguages ustawia AppDelegate.applyLanguage po każdej zmianie ustawienia (także z importu i zestawów).
                Picker(L10n.tr("Język"), selection: Binding(get: { workspace.settings.language ?? "" }, set: { v in
                    workspace.settings.language = v.isEmpty ? nil : v
                })) {
                    Text(L10n.tr("Jak system")).tag("")
                    Text("Polski").tag("pl")
                    Text("English").tag("en")
                    Text("Deutsch").tag("de")
                    Text("Español").tag("es")
                    Text("Українська").tag("uk")
                }
                Text(L10n.tr("Zmiana działa po ponownym uruchomieniu Pelikana.")).font(.uiSecondary).foregroundStyle(.secondary)
            }
            Section(L10n.tr("Katalogi startowe i rozszerzenia")) {
                ForEach([("sql", L10n.tr("Skrypty SQL")), ("program", L10n.tr("Programy")), ("test", L10n.tr("Testy")), ("report", L10n.tr("Raporty"))], id: \.0) { key, label in
                    TextField(label, text: Binding(get: { workspace.settings.startDirectories[key] ?? "" },
                                                   set: { workspace.settings.startDirectories[key] = $0.isEmpty ? nil : $0 }),
                              prompt: Text(L10n.tr("katalog projektu albo ostatni")))
                }
                TextField(L10n.tr("Dodatkowe rozszerzenia programów"), text: Binding(get: { workspace.settings.programExtensions.joined(separator: ", ") },
                    set: { workspace.settings.programExtensions = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty } }))
                TextField(L10n.tr("Dodatkowe rozszerzenia testów"), text: Binding(get: { workspace.settings.testExtensions.joined(separator: ", ") },
                    set: { workspace.settings.testExtensions = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty } }))
            }
            // D194: specyfikacja i ciało w osobnych plikach (zapis okna programu, otwieranie pary, eksport obiektów).
            Section(L10n.tr("Specyfikacja i ciało w osobnych plikach")) {
                Toggle(L10n.tr("Otwieraj parę specyfikacja/ciało w jednym oknie"), isOn: setting(workspace, \.openSpecBodyPair))
                TextField(L10n.tr("Rozszerzenie specyfikacji pakietu"), text: setting(workspace, \.specBodyExtensions.packageSpec), prompt: Text("pks"))
                TextField(L10n.tr("Rozszerzenie ciała pakietu"), text: setting(workspace, \.specBodyExtensions.packageBody), prompt: Text("pkb"))
                TextField(L10n.tr("Rozszerzenie specyfikacji typu"), text: setting(workspace, \.specBodyExtensions.typeSpec), prompt: Text("tps"))
                TextField(L10n.tr("Rozszerzenie ciała typu"), text: setting(workspace, \.specBodyExtensions.typeBody), prompt: Text("tpb"))
                if workspace.settings.specBodyExtensions.isInvalid {
                    Text(L10n.tr("Rozszerzenia specyfikacji muszą różnić się od rozszerzeń ciała (pakiet i typ mogą mieć wspólne), składać się z liter, cyfr albo „_” i być inne niż sql, tst, pck, typ, rep, pdd, sqlnb i txt — do czasu poprawki używane są domyślne pks, pkb, tps i tpb."))
                        .font(.uiSecondary).foregroundStyle(.red)
                }
                Text(L10n.tr("Okno programu ze specyfikacją i ciałem zapisuje każdą jednostkę do jej pliku, bez „/”; Zapisz jako tworzy parę plików. Eksport obiektów (plik na obiekt) używa tych rozszerzeń."))
                    .font(.uiSecondary).foregroundStyle(.secondary)
            }
            Section(L10n.tr("Pliki")) {
                Toggle(L10n.tr("Przywracaj okna po ponownym uruchomieniu (także niezapisane)"), isOn: setting(workspace, \.worksetAutosave))
                Toggle(L10n.tr("Autozapis układu okna"), isOn: setting(workspace, \.autosaveLayout))
                Toggle(L10n.tr("Pytaj o zapis zmian przy zamykaniu nowych okien"), isOn: setting(workspace, \.confirmSaveNewWindows))
                // D197: pliki zmienione przez inny program (agent, git) — przy aktywacji okna, karty i aplikacji.
                Toggle(L10n.tr("Wykrywaj zmiany plików na dysku"), isOn: setting(workspace, \.detectExternalFileChanges))
                Toggle(L10n.tr("Wczytuj bez pytania pliki zmienione na zewnątrz, gdy okno nie ma zmian"), isOn: setting(workspace, \.reloadExternalChangesSilently))
                    .disabled(!workspace.settings.detectExternalFileChanges)
            }
            Section(L10n.tr("Dziennik aplikacji")) {
                Picker(L10n.tr("Zapisuj w dzienniku"), selection: setting(workspace, \.logLevel)) {
                    Text(L10n.tr("Ostrzeżenia i błędy")).tag(LogLevel.notice)
                    Text(L10n.tr("Zdarzenia (zalecane)")).tag(LogLevel.info)
                    Text(L10n.tr("Szczegóły — diagnostyka")).tag(LogLevel.debug)
                }
                Toggle(L10n.tr("Nazwy połączeń, obiektów i ścieżki plików jawnie"), isOn: setting(workspace, \.logIncludeNames))
                Text(L10n.tr("Dziennik nigdy nie zawiera haseł, treści poleceń SQL ani danych z bazy. Gdy nazwy nie są jawne, połączenia i serwery są oznaczone skrótem."))
                    .font(.uiSecondary).foregroundStyle(.secondary)
                HStack {
                    Button(L10n.tr("Pokaż dziennik")) { workspace.perform("help.log") }
                    Button(L10n.tr("Eksportuj dziennik…")) { workspace.perform("help.exportLog") }
                }
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
                TextField(L10n.tr("Statystyki po wykonaniu"), text: Binding(get: { workspace.settings.selectedStatistics.joined(separator: ", ") },
                    set: { workspace.settings.selectedStatistics = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }),
                          prompt: Text(L10n.tr("puste — wszystkie niezerowe, np. consistent gets, physical reads")))
                Toggle(L10n.tr("AutoCommit po wykonaniu okna testu"), isOn: setting(workspace, \.autoCommitTestWindow))
                Toggle(L10n.tr("Potwierdzaj COMMIT i ROLLBACK"), isOn: setting(workspace, \.confirmCommitRollback))
                Toggle(L10n.tr("Potwierdzaj polecenia zmieniające na połączeniach produkcyjnych"), isOn: setting(workspace, \.confirmProductionChanges))
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
                Picker(L10n.tr("Układ liczb"), selection: setting(workspace, \.gridNumberLayout)) {
                    ForEach(NumberLayout.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle(L10n.tr("Numer wiersza w kopiowaniu i eksporcie"), isOn: setting(workspace, \.rowNumbersInCopyExport))
                Toggle(L10n.tr("Pobieraj LOB-y na żądanie (podgląd pierwszych 4000 bajtów)"), isOn: setting(workspace, \.fetchLOBsOnDemand))
                Toggle(L10n.tr("Wyrównuj kolumny wg zapisanego szablonu zapytania"), isOn: setting(workspace, \.autoAlign))
                Stepper(value: setting(workspace, \.notifyLongQuerySeconds), in: 0...3600, step: 5) {
                    Text(workspace.settings.notifyLongQuerySeconds == 0 ? L10n.tr("Bez powiadomienia o końcu długiego wykonania")
                         : L10n.tr("Powiadamiaj o końcu wykonania dłuższego niż \(workspace.settings.notifyLongQuerySeconds) s"))
                }
                Toggle(L10n.tr("Large Data Editor: Auto Format (JSON, XML)"), isOn: setting(workspace, \.largeDataAutoFormat))
            }
            Section(L10n.tr("Query By Example")) {
                Toggle(L10n.tr("Bez rozróżniania wielkości liter"), isOn: setting(workspace, \.qbeCaseInsensitive))
                Toggle(L10n.tr("Tekst bez symboli wieloznacznych jako „zawiera”"), isOn: setting(workspace, \.qbeAutoContains))
                Toggle(L10n.tr("Daty bez czasu (porównanie dnia)"), isOn: setting(workspace, \.qbeIgnoreTime))
            }
            Section(L10n.tr("Statystyki")) {
                Toggle(L10n.tr("Karta Statystyki: statystyki sesji z każdego wykonania (wymaga dostępu do V$MYSTAT)"), isOn: setting(workspace, \.sqlWindowStatistics))
            }
            Section(L10n.tr("DBMS_OUTPUT (UG 23.5)")) {
                Toggle(L10n.tr("Włączone"), isOn: setting(workspace, \.dbmsOutputEnabled))
                Toggle(L10n.tr("Czyść przed wykonaniem"), isOn: setting(workspace, \.dbmsOutputClearBeforeExecute))
                Stepper(value: setting(workspace, \.dbmsOutputBufferSize), in: 0...1_000_000, step: 10_000) {
                    Text(workspace.settings.dbmsOutputBufferSize == 0 ? L10n.tr("Rozmiar bufora: bez limitu")
                         : L10n.tr("Rozmiar bufora: \(workspace.settings.dbmsOutputBufferSize) bajtów"))
                }
            }
            Section(L10n.tr("Formaty dat (UG 23.17)")) {
                TextField(L10n.tr("DATE"), text: setting(workspace, \.dateFormat)).font(.code)
                TextField(L10n.tr("TIMESTAMP"), text: setting(workspace, \.timestampFormat)).font(.code)
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
                FontFamilyPicker(title: L10n.tr("Czcionka"), selection: setting(workspace, \.editorFontName),
                                 defaultLabel: "SF Mono", defaultTag: "SF Mono", families: AppFonts.cachedMonospacedFamilies)
                FontWeightPicker(selection: setting(workspace, \.editorFontWeight))
                Stepper(value: setting(workspace, \.editorFontSize), in: 8...40, step: 1) {
                    Text(L10n.tr("Rozmiar: \(Int(workspace.settings.editorFontSize)) pt"))
                }
                Toggle(L10n.tr("Ligatury (np. Fira Code, JetBrains Mono)"), isOn: setting(workspace, \.editorLigatures))
            }
            Section(L10n.tr("Siatka wyników")) {
                FontFamilyPicker(title: L10n.tr("Krój"), selection: setting(workspace, \.gridFontName),
                                 defaultLabel: L10n.tr("Systemowa o stałej szerokości"), families: AppFonts.cachedFamilies)
                FontWeightPicker(selection: setting(workspace, \.gridFontWeight))
                Stepper(value: setting(workspace, \.gridFontSize), in: 8...24, step: 1) {
                    Text(L10n.tr("Siatka wyników: \(Int(workspace.settings.gridFontSize)) pt"))
                }
            }
            Section(L10n.tr("Object Browser")) {
                FontFamilyPicker(title: L10n.tr("Krój"), selection: setting(workspace, \.browserFontName),
                                 defaultLabel: L10n.tr("Jak interfejs"), families: AppFonts.cachedFamilies)
                FontWeightPicker(selection: setting(workspace, \.browserFontWeight))
                Stepper(value: setting(workspace, \.browserFontSize), in: 0...24, step: 1) {
                    Text(workspace.settings.browserFontSize == 0 ? L10n.tr("Object Browser: jak interfejs")
                         : L10n.tr("Object Browser: \(Int(workspace.settings.browserFontSize)) pt"))
                }
            }
            Section(L10n.tr("Kolory czcionek")) {
                colorRow(L10n.tr("Edytor"), \.editorColors)
                colorRow(L10n.tr("Siatka wyników"), \.gridColors)
                colorRow(L10n.tr("Object Browser"), \.browserColors)
                Text(L10n.tr("Bez własnego koloru obowiązują kolory motywu systemu (tryb jasny i ciemny). Własny kolor działa w obu trybach."))
                    .font(.uiSecondary).foregroundStyle(.secondary)
            }
            Section(L10n.tr("Code Assistant")) {
                Toggle(L10n.tr("Automatycznie po kropce"), isOn: setting(workspace, \.codeAssistantAutomatic))
                Stepper(value: setting(workspace, \.codeAssistantDelay), in: 0...2000, step: 100) {
                    Text(L10n.tr("Opóźnienie: \(workspace.settings.codeAssistantDelay) ms"))
                }
                Picker(L10n.tr("Dopasowanie"), selection: setting(workspace, \.codeAssistantMatch)) {
                    Text(L10n.tr("Zaczyna się od")).tag(CompletionMatch.startsWith)
                    Text(L10n.tr("Zawiera")).tag(CompletionMatch.contains)
                }
                Picker(L10n.tr("Wielkość liter"), selection: setting(workspace, \.codeAssistantCase)) {
                    Text(L10n.tr("Jak we wpisanym tekście")).tag(CompletionCase.auto)
                    Text(L10n.tr("WIELKIE")).tag(CompletionCase.upper)
                    Text(L10n.tr("małe")).tag(CompletionCase.lower)
                    Text(L10n.tr("Pierwsza wielka")).tag(CompletionCase.initCap)
                    Text(L10n.tr("Oryginalna")).tag(CompletionCase.original)
                }
                Stepper(value: setting(workspace, \.codeAssistantMinChars), in: 1...5) {
                    Text(L10n.tr("Minimum znaków dla obiektów i słów kluczowych: \(workspace.settings.codeAssistantMinChars)"))
                }
                Toggle(L10n.tr("Funkcje standardowe SQL"), isOn: setting(workspace, \.codeAssistantStandardFunctions))
                Toggle(L10n.tr("„(all)”: każdy element w osobnej linii"), isOn: setting(workspace, \.codeAssistantAllPerLine))
                Toggle(L10n.tr("„(all)”: przecinek na początku linii"), isOn: setting(workspace, \.codeAssistantCommaFirst))
                    .disabled(!workspace.settings.codeAssistantAllPerLine)
            }
            Section(L10n.tr("AutoReplace")) {
                ForEach(workspace.settings.autoReplace) { r in
                    HStack {
                        TextField(L10n.tr("Skrót"), text: setting(workspace, \.autoReplace, r.id, \.abbreviation, fallback: ""))
                            .frame(width: 90)
                        TextField(L10n.tr("Zamiana (| — kursor)"), text: setting(workspace, \.autoReplace, r.id, \.replacement, fallback: ""))
                        Button { workspace.settings.autoReplace.removeAll { $0.id == r.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                            .iconLabel(L10n.tr("Usuń skrót"))
                    }
                }
                Button(L10n.tr("Dodaj skrót")) { workspace.settings.autoReplace.append(AutoReplaceRule(abbreviation: "", replacement: "")) }
            }
            Section(L10n.tr("Analiza i okna")) {
                Toggle(L10n.tr("Analiza kodu w czasie pisania"), isOn: Binding(get: { workspace.settings.liveCodeAnalysis }, set: { on in
                    workspace.settings.liveCodeAnalysis = on
                    if !on { workspace.diagnostics = [:] }   // jak komenda edit.toggleCodeAnalysis
                }))
                Stepper(value: setting(workspace, \.identifierLengthWarning), in: 0...128, step: 1) {
                    Text(workspace.settings.identifierLengthWarning == 0 ? L10n.tr("Ostrzeżenie o długich identyfikatorach: wyłączone")
                         : L10n.tr("Ostrzegaj o identyfikatorach dłuższych niż \(workspace.settings.identifierLengthWarning) bajtów"))
                }
                Toggle(L10n.tr("Zapamiętuj stan okien plików (kursor, zakładki, znaczniki, zmienne)"), isOn: setting(workspace, \.rememberWindowState))
            }
            Section(L10n.tr("Pisanie")) {
                Picker(L10n.tr("Wielkość liter słów kluczowych"), selection: setting(workspace, \.keywordCase)) {
                    Text(L10n.tr("Bez zmian")).tag(KeywordCase.unchanged)
                    Text(L10n.tr("WIELKIE")).tag(KeywordCase.upper)
                    Text(L10n.tr("małe")).tag(KeywordCase.lower)
                    Text(L10n.tr("Pierwsza wielka")).tag(KeywordCase.initCap)
                }
                Toggle(L10n.tr("Podświetlaj bieżącą linię"), isOn: setting(workspace, \.highlightCurrentLine))
                Toggle(L10n.tr("Podświetlaj wystąpienia nazwy pod kursorem i zaznaczonego słowa"), isOn: setting(workspace, \.highlightOccurrences))
                Toggle(L10n.tr("Wyróżniaj polecenia COMMIT, ROLLBACK i SAVEPOINT"), isOn: setting(workspace, \.highlightTransactions))
                Toggle(L10n.tr("Status linii (zmienione i nowe od otwarcia lub zapisu)"), isOn: setting(workspace, \.showLineStatus))
                Toggle(L10n.tr("Zawijaj wiersze"), isOn: setting(workspace, \.wordWrap))
                Stepper(value: setting(workspace, \.lineNumberInterval), in: 1...10) {
                    Text(workspace.settings.lineNumberInterval <= 1 ? L10n.tr("Numer każdej linii")
                         : L10n.tr("Numer co \(workspace.settings.lineNumberInterval) linii"))
                }
                Stepper(value: setting(workspace, \.rightMarginColumn), in: 0...250, step: 10) {
                    Text(workspace.settings.rightMarginColumn == 0 ? L10n.tr("Bez pionowego marginesu")
                         : L10n.tr("Pionowy margines w kolumnie \(workspace.settings.rightMarginColumn)"))
                }
                Toggle(L10n.tr("Pokazuj znaki specjalne (spacje, tabulacje, końce linii)"), isOn: setting(workspace, \.showSpecialCharacters))
                Toggle(L10n.tr("Zawartość kodu"), isOn: setting(workspace, \.showCodeContents))
                Picker(L10n.tr("Kolejność w Zawartości kodu"), selection: setting(workspace, \.codeContentsOrder)) {
                    Text(L10n.tr("Jak w źródle")).tag(CodeContents.Order.source)
                    Text(L10n.tr("Alfabetycznie")).tag(CodeContents.Order.name)
                    Text(L10n.tr("Według rodzaju")).tag(CodeContents.Order.kind)
                }
            }
            Section(L10n.tr("Wcięcia")) {
                Picker(L10n.tr("Wcięcie nowej linii"), selection: setting(workspace, \.indentMode)) {
                    Text(L10n.tr("Brak")).tag(IndentMode.none)
                    Text(L10n.tr("Automatyczne (jak poprzednia linia)")).tag(IndentMode.automatic)
                    Text(L10n.tr("Inteligentne (struktura PL/SQL)")).tag(IndentMode.smart)
                }
                Toggle(L10n.tr("Backspace usuwa wcięcie"), isOn: setting(workspace, \.backspaceUnindents))
                Stepper(value: setting(workspace, \.tabSize), in: 1...8) { Text(L10n.tr("Szerokość tabulacji: \(workspace.settings.tabSize)")) }
                Toggle(L10n.tr("Wstawiaj znak tabulacji zamiast spacji"), isOn: setting(workspace, \.useTabCharacter))
            }
        }
        .formStyle(.grouped)
    }

    /// Kolor tekstu i tła obszaru (PD-PREF-005): wybór koloru albo powrót do koloru systemu.
    private func colorRow(_ title: String, _ key: WritableKeyPath<PelikanWorkspace.Settings, AreaColors>) -> some View {
        func binding(_ part: WritableKeyPath<AreaColors, PelikanWorkspace.RGBColor?>, fallback: NSColor) -> Binding<Color> {
            Binding(get: {
                workspace.settings[keyPath: key][keyPath: part].map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? Color(nsColor: fallback)
            }, set: { c in
                let n = NSColor(c).usingColorSpace(.sRGB) ?? fallback
                workspace.settings[keyPath: key][keyPath: part] = PelikanWorkspace.RGBColor(red: n.redComponent, green: n.greenComponent, blue: n.blueComponent)
            })
        }
        return HStack {
            Text(title)
            Spacer()
            ColorPicker(L10n.tr("Tekst"), selection: binding(\.text, fallback: .textColor), supportsOpacity: false)
            ColorPicker(L10n.tr("Tło"), selection: binding(\.background, fallback: .textBackgroundColor), supportsOpacity: false)
            Button(L10n.tr("Systemowe")) { workspace.settings[keyPath: key] = AreaColors() }
                .disabled(workspace.settings[keyPath: key].isSystem)
        }
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
                    .font(.uiSecondary).foregroundStyle(.secondary)
            }
            Section(L10n.tr("Ustawienia NLS sesji")) {
                ForEach(["NLS_DATE_FORMAT", "NLS_TIMESTAMP_FORMAT", "NLS_NUMERIC_CHARACTERS", "NLS_LANGUAGE", "NLS_TERRITORY", "NLS_SORT", "NLS_COMP"], id: \.self) { name in
                    TextField(name, text: Binding(get: { workspace.settings.sessionNLS[name] ?? "" },
                                                  set: { v in workspace.settings.sessionNLS[name] = v.isEmpty ? nil : v }),
                              prompt: Text(L10n.tr("ustawienie serwera")))
                }
                Text(L10n.tr("Wartości ustawiane poleceniem ALTER SESSION w każdej nowej sesji.")).font(.uiSecondary).foregroundStyle(.secondary)
                Stepper(value: setting(workspace, \.closeIdleSessionsMinutes), in: 0...1440, step: 15) {
                    Text(workspace.settings.closeIdleSessionsMinutes == 0 ? L10n.tr("Nie zamykaj bezczynnych sesji okien")
                         : L10n.tr("Zamykaj sesje okien bezczynne ponad \(workspace.settings.closeIdleSessionsMinutes) min (bez otwartej transakcji)"))
                }
            }
            Section(L10n.tr("Dokumentacja Oracle (F1)")) {
                Picker(L10n.tr("Wersja dokumentacji"), selection: setting(workspace, \.oracleDocsRelease)) {
                    ForEach(OracleDocs.releases, id: \.self) { r in Text(r == "19" ? "19c" : r == "21" ? "21c" : r + "ai").tag(r) }
                }
            }
            Section(L10n.tr("Hasła połączeń")) {
                Toggle(L10n.tr("Wymagaj Touch ID albo hasła Maca przed użyciem zapisanego hasła"), isOn: setting(workspace, \.requireOwnerForSavedPasswords))
                    .disabled(!Self.ownerAuthenticationAvailable && !workspace.settings.requireOwnerForSavedPasswords)
                Text(L10n.tr("Hasła są w Pęku kluczy (pęk logowania, bez synchronizacji z iCloud). Po włączeniu Pelikan pyta o potwierdzenie raz na połączenie w trakcie działania aplikacji — także gdy połączenia użyje agent. Hasła podane bez „Zapamiętaj” zostają tylko w pamięci."))
                    .font(.uiSecondary).foregroundStyle(.secondary)
                if !Self.ownerAuthenticationAvailable {
                    Text(L10n.tr("Ten Mac nie ma skonfigurowanego Touch ID ani hasła logowania do potwierdzania.")).font(.uiSecondary).foregroundStyle(.orange)
                }
            }
            Section(L10n.tr("Oracle Net i Oracle Wallet")) {
                directoryRow(L10n.tr("Konfiguracja Oracle Net (tnsnames.ora, sqlnet.ora)"), \.oracleNetDirectory,
                             placeholder: L10n.tr("TNS_ADMIN albo domyślne miejsca"))
                directoryRow(L10n.tr("Oracle Wallet (magazyn haseł)"), \.walletDirectory, placeholder: L10n.tr("Brak — logowanie hasłem"))
                if let w = workspace.settings.walletDirectory {
                    switch OracleNet.walletStatus(w) {
                    case .autoLogin: Label(L10n.tr("Portfel z automatycznym logowaniem (cwallet.sso)"), systemImage: "checkmark.seal").foregroundStyle(.green)
                    case .passwordOnly: Label(L10n.tr("Tylko ewallet.p12 — klient wymaga portfela z automatycznym logowaniem (cwallet.sso); utwórz go narzędziem orapki/mkstore"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    case .missing: Label(L10n.tr("W katalogu nie ma portfela (cwallet.sso / ewallet.p12)"), systemImage: "xmark.octagon").foregroundStyle(.red)
                    }
                }
                Text(L10n.tr("Połączenia w trybie „Oracle Wallet” logują się poświadczeniami z portfela (/@alias) — alias albo connect string połączenia musi odpowiadać wpisowi w portfelu. Hasła z portfela nie trafiają do Pelikana. Portfel TLS (mTLS, np. Autonomous Database) ustawia się w połączeniu. Zmiana działa po ponownym uruchomieniu aplikacji."))
                    .font(.uiSecondary).foregroundStyle(.secondary)
            }
            Section(L10n.tr("Kompilator (UG 23.3)")) {
                TextField(L10n.tr("Ostrzeżenia PLSQL_WARNINGS"), text: setting(workspace, \.plsqlWarnings), prompt: Text("ENABLE:ALL"))
                Picker(L10n.tr("Poziom optymalizacji PLSQL_OPTIMIZE_LEVEL"), selection: setting(workspace, \.compiler.optimizeLevel)) {
                    Text(L10n.tr("Jak serwer")).tag(Int?.none)
                    ForEach(0...3, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                }
                Picker(L10n.tr("Typ kodu PLSQL_CODE_TYPE"), selection: setting(workspace, \.compiler.codeType)) {
                    Text(L10n.tr("Jak serwer")).tag("")
                    Text("INTERPRETED").tag("INTERPRETED")
                    Text("NATIVE").tag("NATIVE")
                }
                TextField(L10n.tr("PL/Scope PLSCOPE_SETTINGS"), text: setting(workspace, \.compiler.plscope), prompt: Text("IDENTIFIERS:ALL"))
                TextField(L10n.tr("Flagi kompilacji warunkowej PLSQL_CCFLAGS"), text: setting(workspace, \.compiler.ccflags), prompt: Text("debug:TRUE"))
                Text(L10n.tr("Puste pole albo „Jak serwer” — parametr sesji kompilacji nie jest zmieniany. Wartości z apostrofem albo średnikiem są pomijane."))
                    .font(.uiSecondary).foregroundStyle(.secondary)
            }
            Section(L10n.tr("Debuger (UG 23.4)")) {
                Toggle(L10n.tr("Dodawaj informację debugowania przy kompilacji okna programu"), isOn: setting(workspace, \.debugInfoOnCompile))
                TextField(L10n.tr("Zawsze z informacją debugowania"), text: Binding(get: { workspace.settings.debugInfoAlways.joined(separator: ", ") },
                    set: { workspace.settings.debugInfoAlways = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }),
                          prompt: Text(L10n.tr("np. scott@dev*, HR.PKG_*")))
                TextField(L10n.tr("Nigdy z informacją debugowania"), text: Binding(get: { workspace.settings.debugInfoNever.joined(separator: ", ") },
                    set: { workspace.settings.debugInfoNever = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }),
                          prompt: Text(L10n.tr("np. *@prod*")))
                Toggle(L10n.tr("Kompilacja tylko do odczytu plików"), isOn: setting(workspace, \.compileReadOnlyFiles))
                Toggle(L10n.tr("Kończ jednostki okna programu znakiem „/” (tekst z bazy, nowe jednostki)"), isOn: setting(workspace, \.programUnitSlash))
                Toggle(L10n.tr("Podpowiedzi kompilatora (inspekcje kodu po kompilacji; „-- Ignore” wycisza linię)"), isOn: setting(workspace, \.compilerHints))
                Toggle(L10n.tr("Sprawdzaj konwencje nazw"), isOn: setting(workspace, \.namingConventions.enabled))
                if workspace.settings.namingConventions.enabled {
                    HStack {
                        TextField(L10n.tr("Parametry"), text: setting(workspace, \.namingConventions.parameter))
                        TextField(L10n.tr("Lokalne"), text: setting(workspace, \.namingConventions.local))
                        TextField(L10n.tr("Globalne"), text: setting(workspace, \.namingConventions.global))
                    }
                    HStack {
                        TextField(L10n.tr("Stałe"), text: setting(workspace, \.namingConventions.constant))
                        TextField(L10n.tr("Kursory"), text: setting(workspace, \.namingConventions.cursor))
                        TextField(L10n.tr("Typy"), text: setting(workspace, \.namingConventions.type))
                    }
                }
                Toggle(L10n.tr("Pomijaj inicjalizację pakietów przy krokowaniu"), isOn: setting(workspace, \.debuggerSkipPackageInit))
                Toggle(L10n.tr("Pomijaj obiekty SYS przy krokowaniu"), isOn: setting(workspace, \.debuggerSkipSys))
            }
            Section(L10n.tr("Słownik danych")) {
                Toggle(L10n.tr("Używaj widoków DBA_, jeśli dostępne"), isOn: setting(workspace, \.useDBAViews))
            }
        }
        .formStyle(.grouped)
    }

    static var ownerAuthenticationAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    private func directoryRow(_ title: String, _ key: WritableKeyPath<PelikanWorkspace.Settings, String?>, placeholder: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(workspace.settings[keyPath: key] ?? placeholder).font(.uiSecondary)
                    .foregroundStyle(workspace.settings[keyPath: key] == nil ? .secondary : .primary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button(L10n.tr("Wybierz…")) {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.showsHiddenFiles = true
                if panel.runModal() == .OK, let url = panel.url { workspace.settings[keyPath: key] = url.path }
            }
            if workspace.settings[keyPath: key] != nil { Button(L10n.tr("Wyczyść")) { workspace.settings[keyPath: key] = nil } }
        }
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
                    Text(workspace.keymap.chords(for: r.d.id).map(\.displayString).joined(separator: "  ")).font(.code)
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
            if let message { Text(message).font(.uiSecondary).foregroundStyle(.orange) }
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

    private let navigation = PreferencesNavigation()

    /// `pane` — karta do pokazania (nazwa struktury panelu, np. "PreferenceSetsPane").
    static func show(workspace: Workspace, pane: String? = nil) {
        let c = shared ?? PreferencesWindowController(workspace: workspace)
        shared = c
        if let pane { c.navigation.pane = pane }
        c.showWindow(nil)
        c.window?.makeKeyAndOrderFront(nil)
    }

    init(workspace: Workspace) {
        let w = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView(workspace: workspace, navigation: navigation).interfaceFont()))
        w.title = L10n.tr("Preferencje")
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        super.init(window: w)
        w.center()
        w.setFrameAutosaveName("Pelikan.Preferences")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
