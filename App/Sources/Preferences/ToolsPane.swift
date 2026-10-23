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
                ForEach(workspace.settings.webSearches.indices, id: \.self) { i in
                    HStack {
                        TextField(L10n.tr("Nazwa"), text: Binding(get: { workspace.settings.webSearches[i].name },
                                                                 set: { workspace.settings.webSearches[i].name = $0 })).frame(width: 160)
                        TextField(L10n.tr("Adres z %s"), text: Binding(get: { workspace.settings.webSearches[i].url },
                                                                      set: { workspace.settings.webSearches[i].url = $0 }))
                        Button { workspace.settings.webSearches.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                HStack {
                    Button(L10n.tr("Dodaj wyszukiwanie")) { workspace.settings.webSearches.append(WebSearch(name: L10n.tr("Nowe"), url: "https://")) }
                    Button(L10n.tr("Przywróć domyślne")) { workspace.settings.webSearches = WebSearch.defaults }
                }
                Text(L10n.tr("%s zastępuje zaznaczony tekst albo słowo pod kursorem; dozwolone tylko adresy http i https.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.tr("Edytor zewnętrzny")) {
                TextField(L10n.tr("Aplikacja (nazwa albo ścieżka .app; puste — program skojarzony z plikiem)"),
                          text: Binding(get: { workspace.settings.externalEditor ?? "" }, set: { workspace.settings.externalEditor = $0.isEmpty ? nil : $0 }),
                          prompt: Text("Visual Studio Code"))
                Text(L10n.tr("Po powrocie do Pelikana zmiany pliku są wczytywane do okna. Okno bez pliku trafia do pliku tymczasowego w katalogu danych."))
                    .font(.caption).foregroundStyle(.secondary)
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
                    .onSubmit { applyDiffArguments() }
                    .disabled(workspace.settings.externalDiff == nil)
                Text(L10n.tr("%1 i %2 — pliki lewy i prawy, %3 i %4 — ich tytuły. Program jest uruchamiany bez powłoki; argumenty rozdziela spacja, cudzysłów grupuje."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.tr("Dokumenty (Narzędzia › Dokumenty)")) {
                ForEach(workspace.settings.userDocuments.indices, id: \.self) { i in
                    HStack {
                        TextField(L10n.tr("Tytuł"), text: Binding(get: { workspace.settings.userDocuments[i].title },
                                                                 set: { workspace.settings.userDocuments[i].title = $0 })).frame(width: 160)
                        TextField(L10n.tr("Plik albo adres http(s)"), text: Binding(get: { workspace.settings.userDocuments[i].location },
                                                                                  set: { workspace.settings.userDocuments[i].location = $0 }))
                        Button { workspace.settings.userDocuments.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
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
        .onDisappear { applyDiffArguments() }
    }

    private func applyDiffArguments() {
        guard var t = workspace.settings.externalDiff else { return }
        t.arguments = ExternalDiffTool.split(diffArguments)
        workspace.settings.externalDiff = t
    }

    private func addDocumentFile() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        guard p.runModal() == .OK else { return }
        for u in p.urls { workspace.settings.userDocuments.append(UserDocument(title: u.deletingPathExtension().lastPathComponent, location: u.path)) }
    }
}
