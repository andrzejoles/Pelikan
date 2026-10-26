import PelikanWorkspace
import SwiftUI

/// Preferencje Object Browsera (PD-OB-025) oraz filtry nazwane i foldery użytkownika (PD-OB-007, PD-OB-008).
struct BrowserPane: View {
    @Bindable var workspace: Workspace
    @State private var customization = BrowserCustomization()
    @State private var message = ""
    static let folderTypes: [DBObjectType] = [.table, .view, .materializedView, .package, .packageBody, .procedure, .function, .type, .typeBody,
                                              .trigger, .sequence, .synonym, .index, .databaseLink, .job, .queue, .mleModule, .domain,
                                              .javaSource, .library, .directory, .user, .role, .profile]

    var body: some View {
        Form {
            Section(L10n.tr("Foldery")) {
                Text(L10n.tr("Zaznaczone foldery w podanej kolejności; nic nie zaznaczone — wszystkie.")).font(.caption).foregroundStyle(.secondary)
                ForEach(ordered, id: \.self) { t in
                    HStack {
                        Toggle(t.folderName, isOn: Binding(get: { workspace.settings.browserFolders.contains(t.rawValue) }, set: { on in
                            if on { workspace.settings.browserFolders.append(t.rawValue) } else { workspace.settings.browserFolders.removeAll { $0 == t.rawValue } }
                        }))
                        Spacer()
                        if let i = workspace.settings.browserFolders.firstIndex(of: t.rawValue) {
                            Button { move(i, -1) } label: { Image(systemName: "arrow.up") }.buttonStyle(.borderless).disabled(i == 0)
                                .iconLabel(L10n.tr("W górę"))
                            Button { move(i, 1) } label: { Image(systemName: "arrow.down") }.buttonStyle(.borderless)
                                .disabled(i == workspace.settings.browserFolders.count - 1).iconLabel(L10n.tr("W dół"))
                        }
                    }
                }
            }
            Section(L10n.tr("Zachowanie")) {
                Stepper(L10n.tr("Ostatnie obiekty: \(workspace.settings.browserRecentLimit)"), value: $workspace.settings.browserRecentLimit, in: 5...100, step: 5)
                Toggle(L10n.tr("Potwierdzaj rekompilację"), isOn: $workspace.settings.confirmRecompile)
                Picker(L10n.tr("Filtr nazw bez %"), selection: $workspace.settings.browserFilterContains) {
                    Text(L10n.tr("Zawiera tekst (%nazwa%)")).tag(true)
                    Text(L10n.tr("Zaczyna się od tekstu (nazwa%)")).tag(false)
                }
                ForEach([DBObjectType.table, .view, .package, .procedure, .function], id: \.self) { t in
                    Picker(L10n.tr("Dwuklik: \(t.folderName)"), selection: Binding(get: { workspace.browserDoubleClickCommand(for: t).rawValue },
                                                                                  set: { workspace.settings.browserDoubleClick[t.rawValue] = $0 })) {
                        Text(L10n.tr("Edytuj")).tag("ob.edit")
                        Text(L10n.tr("Pokaż dane")).tag("ob.queryData")
                        Text(L10n.tr("Opis")).tag("ob.describe")
                        Text("DDL").tag("ob.ddl")
                    }
                }
            }
            Section(L10n.tr("Przeciąganie (UG 23.11)")) {
                Picker(L10n.tr("Upuszczenie w edytorze"), selection: $workspace.settings.browserDropAction) {
                    ForEach(BrowserDropAction.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker(L10n.tr("Upuszczenie na obszarze okien"), selection: $workspace.settings.browserWorkspaceDrop) {
                    ForEach(BrowserWorkspaceDrop.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section(L10n.tr("Filtry nazwane")) {
                ForEach($customization.filters) { $f in
                    VStack(alignment: .leading) {
                        HStack {
                            TextField(L10n.tr("Nazwa"), text: $f.name)
                            Toggle(L10n.tr("Domyślny"), isOn: $f.isDefault)
                            Button { customization.filters.removeAll { $0.id == f.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).iconLabel(L10n.tr("Usuń filtr"))
                        }
                        TextField(L10n.tr("WHERE (alias o; :browser_user, &browser_filter)"), text: $f.whereClause).font(.system(.body, design: .monospaced))
                        HStack {
                            TextField(L10n.tr("ORDER BY"), text: $f.orderBy).font(.system(.body, design: .monospaced))
                            TextField(L10n.tr("Użytkownik bazy (puste — wszyscy)"), text: $f.forUser)
                        }
                    }
                }
                Button(L10n.tr("Dodaj filtr")) { customization.filters.append(BrowserFilter(name: L10n.tr("Nowy filtr"), whereClause: "")) }
            }
            Section(L10n.tr("Foldery użytkownika")) {
                ForEach($customization.folders) { $f in
                    VStack(alignment: .leading) {
                        HStack {
                            TextField(L10n.tr("Nazwa"), text: $f.name)
                            Picker("", selection: Binding(get: { f.color ?? "blue" }, set: { f.color = $0 })) {
                                // Wartości jak w ObjectBrowserViewController.namedColor.
                                ForEach([("blue", L10n.tr("Niebieski")), ("green", L10n.tr("Zielony")), ("yellow", L10n.tr("Żółty")),
                                         ("orange", L10n.tr("Pomarańczowy")), ("red", L10n.tr("Czerwony")), ("purple", L10n.tr("Fioletowy")),
                                         ("gray", L10n.tr("Szary"))], id: \.0) { Text($0.1).tag($0.0) }
                            }.labelsHidden().frame(width: 120)
                            Button { customization.folders.removeAll { $0.id == f.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).iconLabel(L10n.tr("Usuń folder"))
                        }
                        TextField(L10n.tr("Zapytanie: OWNER, OBJECT_NAME, OBJECT_TYPE (opcjonalne)"), text: $f.query).font(.system(.body, design: .monospaced))
                        HStack {
                            TextField(L10n.tr("Połączenia (wzorzec, puste — wszystkie)"), text: $f.connectionPattern)
                            Picker(L10n.tr("Folder nadrzędny"), selection: $f.parentID) {
                                Text(L10n.tr("(brak)")).tag(UUID?.none)
                                ForEach(customization.folders.filter { $0.id != f.id }) { Text($0.name).tag(UUID?.some($0.id)) }
                            }
                        }
                        Text(L10n.tr("Obiekty z listy: \(f.objects.count) (Dodaj do folderu w menu obiektu)")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button(L10n.tr("Dodaj folder")) { customization.folders.append(BrowserFolder(name: L10n.tr("Nowy folder"))) }
            }
            HStack {
                Button(L10n.tr("Zapisz filtry i foldery")) {
                    do { try workspace.saveBrowserCustomization(customization); message = L10n.tr("Zapisano") } catch { message = error.localizedDescription }
                }
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { customization = workspace.browserCustomization }
    }

    private var ordered: [DBObjectType] {
        let chosen = workspace.settings.browserFolders.compactMap(DBObjectType.init(rawValue:))
        return chosen + Self.folderTypes.filter { !chosen.contains($0) }
    }

    private func move(_ i: Int, _ d: Int) {
        let j = i + d
        guard j >= 0, j < workspace.settings.browserFolders.count else { return }
        workspace.settings.browserFolders.swapAt(i, j)
    }
}
