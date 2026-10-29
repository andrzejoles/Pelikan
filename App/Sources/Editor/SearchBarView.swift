import AppKit
import PelikanWorkspace
import SwiftUI

/// Search Bar (PD-CA-015): tekst, zakres (bieżący edytor, wszystkie edytory, pliki w katalogach), opcje i lista
/// wyników z przejściem do miejsca (lista jak w Find Usages).
struct SearchBarView: View {
    let workspace: Workspace
    @State private var query = ""
    @State private var scope = 1
    @State private var directories = ""
    @State private var options = TextSearchOptions()
    @State private var hits: [UsageHit] = []
    @State private var searched = false
    /// Numer wyszukiwania — spóźniony wynik wcześniejszego wyszukiwania w plikach nie zastępuje nowszego.
    @State private var generation = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(L10n.tr("Szukany tekst"), text: $query).textFieldStyle(.roundedBorder).onSubmit(search)
                Button(L10n.tr("Szukaj"), action: search).disabled(query.isEmpty).keyboardShortcut(.defaultAction)
            }
            HStack {
                Picker(L10n.tr("Zakres"), selection: $scope) {
                    Text(L10n.tr("Bieżący edytor")).tag(0)
                    Text(L10n.tr("Wszystkie edytory")).tag(1)
                    Text(L10n.tr("Pliki w katalogach")).tag(2)
                }
                .fixedSize()
                Toggle(L10n.tr("Wielkość liter"), isOn: $options.caseSensitive)
                Toggle(L10n.tr("Całe słowa"), isOn: $options.wholeWord)
                Toggle(L10n.tr("Wyrażenie regularne"), isOn: $options.regex)
            }
            if scope == 2 {
                TextField(L10n.tr("Katalogi rozdzielone ; (puste — lokalizacje Przeglądarki plików)"), text: $directories).textFieldStyle(.roundedBorder)
            }
            if searched {
                Text(L10n.tr("Trafień: \(hits.count)")).font(.uiSecondary).foregroundStyle(.secondary)
                UsagesView(workspace: workspace, title: query, hits: hits)
            } else {
                Spacer()
            }
        }
        .padding(10)
        .frame(minWidth: 640, minHeight: 360)
    }

    private func search() {
        guard !query.isEmpty else { return }
        let s: TextSearchScope
        switch scope {
        case 0: s = .currentEditor
        case 2:
            let dirs = directories.split(separator: ";").map { URL(fileURLWithPath: (String($0).trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath) }
            let roots = dirs.isEmpty ? workspace.fileBrowser.locations.map { URL(fileURLWithPath: ($0.path as NSString).expandingTildeInPath) } : dirs
            // Pliki czytane w tle — duże katalogi nie zawieszają interfejsu; wynik tylko dla ostatniego wyszukiwania.
            let (q, o, enc) = (query, options, workspace.projectEncodingResolver())
            generation += 1
            let current = generation
            Task {
                let found = await Task.detached { EditorSearch.searchFiles(q, in: roots, options: o, encoding: enc) }.value
                guard current == generation else { return }
                hits = found
                searched = true
            }
            return
        default: s = .allEditors
        }
        generation += 1
        hits = EditorSearch.search(query, scope: s, options: options, in: workspace)
        searched = true
    }
}
