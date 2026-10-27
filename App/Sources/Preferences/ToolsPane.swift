import AppKit
import PelikanWorkspace
import SwiftUI

/// Preferencje › Narzędzia: wyszukiwania w sieci (PD-EDIT-027), edytor zewnętrzny (PD-EDIT-028), zewnętrzna
/// przeglądarka różnic (PD-DIFF-002), dokumenty użytkownika (PD-DOC-002), kopie i odzyskiwanie (PD-FILE-001),
/// pytania „Nie pytaj więcej” (PD-PREF-008).
struct ToolsPane: View {
    let workspace: Workspace
    @State private var diffArguments = ""

    var body: some View {
        Form {
            Section(L10n.tr("Szukaj w sieci")) {
                // Wiersze wg identyfikatora (nie indeksu) — usunięcie wiersza nie unieważnia wiązań pozostałych.
                ForEach(workspace.settings.webSearches) { s in
                    // Pola bez etykiet formularza (etykieta w każdym wierszu ucinała nazwę) — opis w podpowiedzi pola.
                    HStack {
                        TextField(L10n.tr("Nazwa"), text: field(\.webSearches, s.id, \.name), prompt: Text(L10n.tr("Nazwa")))
                            .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 200)
                        TextField(L10n.tr("Adres z %s"), text: field(\.webSearches, s.id, \.url), prompt: Text(L10n.tr("Adres z %s")))
                            .labelsHidden().textFieldStyle(.roundedBorder)
                        Button { workspace.settings.webSearches.removeAll { $0.id == s.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                            .iconLabel(L10n.tr("Usuń wyszukiwanie"))
                    }
                }
                HStack {
                    Button(L10n.tr("Dodaj wyszukiwanie")) { workspace.settings.webSearches.append(WebSearch(name: L10n.tr("Nowe"), url: "https://")) }
                    Button(L10n.tr("Przywróć domyślne")) { workspace.settings.webSearches = WebSearch.defaults }
                }
                Text(L10n.tr("%s zastępuje zaznaczony tekst albo słowo pod kursorem; dozwolone tylko adresy http i https.")).font(.uiSecondary).foregroundStyle(.secondary)
            }
            Section(L10n.tr("Edytor zewnętrzny")) {
                TextField(L10n.tr("Aplikacja (nazwa albo ścieżka .app; puste — program skojarzony z plikiem)"),
                          text: Binding(get: { workspace.settings.externalEditor ?? "" }, set: { workspace.settings.externalEditor = $0.isEmpty ? nil : $0 }),
                          prompt: Text("Visual Studio Code"))
                Text(L10n.tr("Po powrocie do Pelikana zmiany pliku są wczytywane do okna. Okno bez pliku trafia do pliku tymczasowego w katalogu danych."))
                    .font(.uiSecondary).foregroundStyle(.secondary)
            }
            Section(L10n.tr("Zewnętrzna przeglądarka różnic")) {
                TextField(L10n.tr("Program (puste — wbudowana przeglądarka)"),
                          text: Binding(get: { workspace.settings.externalDiff?.program ?? "" }, set: { v in
                              if v.isEmpty { workspace.settings.externalDiff = nil } else {
                                  var t = workspace.settings.externalDiff ?? ExternalDiffTool(program: v)
                                  t.program = v
                                  workspace.settings.externalDiff = t
                              }
                          }), prompt: Text("/usr/local/bin/opendiff"))
                TextField(L10n.tr("Argumenty"), text: $diffArguments)
                    .disabled(workspace.settings.externalDiff == nil)
                Text(L10n.tr("%1 i %2 — pliki lewy i prawy, %3 i %4 — ich tytuły. Program jest uruchamiany bez powłoki; argumenty rozdziela spacja, cudzysłów grupuje."))
                    .font(.uiSecondary).foregroundStyle(.secondary)
            }
            Section(L10n.tr("Dokumenty (Narzędzia › Dokumenty)")) {
                ForEach(workspace.settings.userDocuments) { d in
                    HStack {
                        TextField(L10n.tr("Tytuł"), text: field(\.userDocuments, d.id, \.title)).frame(width: 160)
                        TextField(L10n.tr("Plik albo adres http(s)"), text: field(\.userDocuments, d.id, \.location))
                        Button { workspace.settings.userDocuments.removeAll { $0.id == d.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                            .iconLabel(L10n.tr("Usuń dokument"))
                    }
                }
                HStack {
                    Button(L10n.tr("Dodaj adres")) { workspace.settings.userDocuments.append(UserDocument(title: L10n.tr("Nowy dokument"), location: "https://")) }
                    Button(L10n.tr("Dodaj plik…")) { addDocumentFile() }
                }
            }
            Section(L10n.tr("Kopie zapasowe i odzyskiwanie")) {
                Toggle(L10n.tr("Kopia poprzedniej wersji przy zapisie (plik.~ext)"), isOn: setting(workspace, \.backupOnSave))
                Toggle(L10n.tr("Zachowuj niezapisane okna do odzyskania po nieoczekiwanym zamknięciu"), isOn: setting(workspace, \.recoveryEnabled))
                Stepper(L10n.tr("Co \(workspace.settings.recoveryIntervalSeconds) s"), value: setting(workspace, \.recoveryIntervalSeconds), in: 15...600, step: 15)
                    .disabled(!workspace.settings.recoveryEnabled)
                Toggle(L10n.tr("Migawka także przed każdym wykonaniem (F8, kompilacja, test)"), isOn: setting(workspace, \.recoveryOnExecute))
                    .disabled(!workspace.settings.recoveryEnabled)
            }
            Section(L10n.tr("Pytania „Nie pytaj więcej”")) {
                let suppressed = SuppressibleDialog.allCases.filter { workspace.settings.suppressedDialogs[$0.rawValue] != nil }
                if suppressed.isEmpty {
                    Text(L10n.tr("Wszystkie pytania są pokazywane.")).foregroundStyle(.secondary)
                } else {
                    ForEach(suppressed, id: \.self) { d in
                        HStack {
                            Text(d.title)
                            Spacer()
                            Button(L10n.tr("Pokazuj znowu")) { workspace.settings.suppressedDialogs[d.rawValue] = nil }
                        }
                    }
                    Button(L10n.tr("Pokazuj wszystkie")) { workspace.settings.suppressedDialogs = [:] }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { diffArguments = ExternalDiffTool.join(workspace.settings.externalDiff?.arguments ?? ["%1", "%2"]) }
        // Argumenty zapisywane przy każdej zmianie pola (jak reszta Preferencji); zmiana z zestawu lub importu odświeża pole.
        .onChange(of: diffArguments) { applyDiffArguments() }
        .onChange(of: workspace.settings.externalDiff?.arguments) { _, new in
            if let new, ExternalDiffTool.split(diffArguments) != new { diffArguments = ExternalDiffTool.join(new) }
        }
    }

    /// Pole tekstowe elementu listy ustawień wskazanego identyfikatorem.
    private func field<E: Identifiable>(_ list: WritableKeyPath<PelikanWorkspace.Settings, [E]>, _ id: E.ID,
                                        _ key: WritableKeyPath<E, String>) -> Binding<String> {
        Binding(get: { workspace.settings[keyPath: list].first { $0.id == id }?[keyPath: key] ?? "" },
                set: { v in
                    if let i = workspace.settings[keyPath: list].firstIndex(where: { $0.id == id }) { workspace.settings[keyPath: list][i][keyPath: key] = v }
                })
    }

    private func applyDiffArguments() {
        guard var t = workspace.settings.externalDiff else { return }
        let arguments = ExternalDiffTool.split(diffArguments)
        guard arguments != t.arguments else { return }
        t.arguments = arguments
        workspace.settings.externalDiff = t
    }

    private func addDocumentFile() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        guard p.runModal() == .OK else { return }
        for u in p.urls { workspace.settings.userDocuments.append(UserDocument(title: u.deletingPathExtension().lastPathComponent, location: u.path)) }
    }
}
