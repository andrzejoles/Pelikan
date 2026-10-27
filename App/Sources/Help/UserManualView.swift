import AppKit
import PelikanWorkspace
import SwiftUI

/// Okno instrukcji użytkownika (PL-INFRA-010): rozdziały z zasobów w języku interfejsu i skróty z rejestru.
struct UserManualView: View {
    let workspace: Workspace
    @State private var chapters: [UserManual.Chapter] = []
    @State private var selection: UserManual.Chapter.ID?

    var body: some View {
        // HSplitView zamiast NavigationSplitView: ten dokłada pasek narzędzi okna, a w panelu okna głównego (D183)
        // zapętlał układ okna.
        HSplitView {
            List(chapters, selection: $selection) { Text($0.title).tag($0.id) }
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
            Group {
                if let c = chapters.first(where: { $0.id == selection }) {
                    HTMLPreview(html: UserManual.page(c))
                } else {
                    Text(L10n.tr("Wybierz rozdział")).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 520)
        .onFirstAppear(perform: load)
    }

    private func load() {
        var list: [UserManual.Chapter] = []
        // Folder z docs/manual trafia do zasobów jako „manual”; wyszukiwanie zasobów rozróżnia wielkość liter.
        if let root = Bundle.main.url(forResource: "manual", withExtension: nil) ?? Bundle.main.url(forResource: "Manual", withExtension: nil),
           let dir = UserManual.directory(in: root, preferred: Bundle.main.preferredLocalizations + Locale.preferredLanguages) {
            // Rozdział bez tłumaczenia — wersja polska (katalog źródłowy instrukcji).
            list = UserManual.chapters(in: dir, fallback: root.appendingPathComponent("pl", isDirectory: true))
        }
        list.append(UserManual.shortcutsChapter(commands: workspace.registry.commands.map(\.descriptor),
                                                chords: { workspace.keymap.chords(for: $0) }))
        chapters = list
        selection = selection ?? list.first?.id
    }
}
