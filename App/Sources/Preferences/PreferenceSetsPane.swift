import AppKit
import PelikanWorkspace
import SwiftUI

/// Zestawy preferencji (PD-PREF-002), eksport i import (PD-PREF-003) i pasek szybkiego dostępu (PD-UI-006).
struct PreferenceSetsPane: View {
    let workspace: Workspace
    @State private var selection: UUID?
    @State private var newName = ""
    @State private var newKind: PreferenceSet.Kind = .personalConnection
    @State private var newPattern = ""
    @State private var chosenSections: Set<String> = Set(PreferenceSets.sections.map(\.name))
    @State private var message = ""
    @State private var commandFilter = ""

    private var sets: [PreferenceSet] { workspace.allPreferenceSets }
    private var selected: PreferenceSet? { sets.first { $0.id == selection } }

    var body: some View {
        Form {
            Section(L10n.tr("Zestawy preferencji")) {
                List(selection: $selection) {
                    ForEach(sets) { s in
                        HStack {
                            Text(s.name)
                            Text(s.kind.displayName + (s.pattern.map { " · \($0)" } ?? "")).font(.uiSecondary).foregroundStyle(.secondary)
                            Spacer()
                            if workspace.activePreferenceSets.contains(where: { $0.id == s.id }) {
                                Text(L10n.tr("obowiązuje")).font(.uiSecondary).foregroundStyle(.green)
                            }
                        }
                        .tag(s.id)
                    }
                }
                .frame(minHeight: 110)
                Picker(L10n.tr("Zmiany w Preferencjach zapisuj do"), selection: Binding(get: { workspace.preferenceEditTarget ?? Workspace.personalSetID },
                                                                                       set: { workspace.preferenceEditTarget = $0 == Workspace.personalSetID ? nil : $0 })) {
                    ForEach(sets) { Text($0.name).tag($0.id) }
                }
                HStack {
                    TextField(L10n.tr("Nazwa"), text: $newName).frame(width: 140)
                    Picker("", selection: $newKind) {
                        ForEach(PreferenceSet.Kind.allCases.filter { $0 != .personalUser }, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    TextField(L10n.tr("Wzorzec połączeń, np. app@prod*"), text: $newPattern).disabled(!newKind.isConnection)
                    Button(L10n.tr("Dodaj")) { add() }.disabled(newName.isEmpty || (newKind.isConnection && newPattern.isEmpty))
                    Button(L10n.tr("Usuń")) { remove() }.disabled(selected == nil || selected?.kind == .personalUser)
                }
                Text(L10n.tr("Pierwszeństwo: osobisty połączenia, osobisty, domyślny połączenia, domyślny dla wszystkich połączeń."))
                    .font(.uiSecondary).foregroundStyle(.secondary)
            }
            if let s = selected {
                Section(L10n.tr("Wartości zestawu „\(s.name)”")) {
                    if s.values.isEmpty {
                        Text(L10n.tr("Zestaw nie zmienia żadnej wartości — wszystkie są dziedziczone.")).foregroundStyle(.secondary)
                    }
                    ForEach(s.values.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text(key).font(.code)
                            Text(PreferenceSets.section(of: key)).font(.uiSecondary).foregroundStyle(.secondary)
                            Spacer()
                            Text(s.values[key]?.summary ?? "").lineLimit(1)
                            if workspace.preferenceSource(of: key)?.id == s.id {
                                Image(systemName: "checkmark.circle").foregroundStyle(.green).help(L10n.tr("Ta wartość obowiązuje"))
                            } else {
                                Image(systemName: "arrow.down.circle").foregroundStyle(.secondary).help(L10n.tr("Przesłonięta przez zestaw o wyższym pierwszeństwie"))
                            }
                            Button(L10n.tr("Dziedzicz")) {
                                do { try workspace.inheritPreference(key, in: s.id) } catch { message = error.localizedDescription }
                            }
                                .help(L10n.tr("Usuwa wartość z zestawu — obowiązuje wartość z zestawu niższego albo wbudowana"))
                        }
                    }
                }
            }
            Section(L10n.tr("Eksport i import")) {
                ForEach(PreferenceSets.sections.map(\.name), id: \.self) { name in
                    Toggle(name, isOn: Binding(get: { chosenSections.contains(name) }, set: { on in
                        if on { chosenSections.insert(name) } else { chosenSections.remove(name) }
                    }))
                }
                HStack {
                    // Bez zaznaczonych sekcji pusty argument oznaczałby „wszystkie”.
                    Button(L10n.tr("Eksportuj…")) { run("prefs.export") }.disabled(chosenSections.isEmpty)
                    Button(L10n.tr("Importuj…")) { run("prefs.import") }.disabled(chosenSections.isEmpty)
                    Spacer()
                    Text(message).font(.uiSecondary).foregroundStyle(.secondary)
                }
                Text(L10n.tr("Plik nie zawiera haseł (są w Pęku kluczy) ani historii plików; import trafia do zestawu wybranego wyżej."))
                    .font(.uiSecondary).foregroundStyle(.secondary)
            }
            Section(L10n.tr("Pasek szybkiego dostępu")) {
                ForEach(workspace.settings.quickAccessCommands, id: \.self) { id in
                    HStack {
                        Image(systemName: ToolbarModel.symbol(for: id))
                        Text(workspace.registry.command(CommandID(rawValue: id))?.descriptor.title ?? id)
                        Spacer()
                        Button { workspace.settings.quickAccessCommands.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).iconLabel(L10n.tr("Usuń z szybkiego dostępu"))
                    }
                }
                TextField(L10n.tr("Dodaj komendę — szukaj"), text: $commandFilter)
                if !commandFilter.isEmpty {
                    ForEach(matchingCommands, id: \.id) { c in
                        Button(c.title) {
                            workspace.settings.quickAccessCommands = ToolbarModel.adding(c.id.rawValue, to: workspace.settings.quickAccessCommands, in: workspace)
                            commandFilter = ""
                        }
                        .buttonStyle(.link)
                    }
                }
                Button(L10n.tr("Dostosuj pasek narzędzi…")) { workspace.perform("view.customizeToolbar") }
            }
        }
        .formStyle(.grouped)
    }

    private var matchingCommands: [CommandDescriptor] {
        workspace.registry.descriptors.filter { $0.inMenu && $0.title.localizedCaseInsensitiveContains(commandFilter) }.prefix(8).map { $0 }
    }

    private func add() {
        let set = PreferenceSet(name: newName, kind: newKind, pattern: newKind.isConnection ? newPattern : nil)
        do {
            try workspace.savePreferenceSet(set)
            selection = set.id
            newName = ""; newPattern = ""
        } catch { message = error.localizedDescription }
    }

    private func remove() {
        guard let s = selected else { return }
        do {
            try workspace.deletePreferenceSet(s.id)
            selection = nil
        } catch { message = error.localizedDescription }
    }

    private func run(_ id: CommandID) {
        let sections = chosenSections.count == PreferenceSets.sections.count ? "" : chosenSections.sorted().joined(separator: ",")
        Task {
            do {
                let r = try await workspace.invoke(id, CommandArguments(["sections": .string(sections)]))
                message = r.message ?? ""
            } catch { message = error.localizedDescription }
        }
    }
}
