import AppKit
import PelikanWorkspace
import SwiftUI

/// Okno instrukcji użytkownika (PL-INFRA-010): rozdziały z zasobów w języku interfejsu i skróty z rejestru.
struct UserManualView: View {
    let workspace: Workspace
    @State private var chapters: [UserManual.Chapter] = []
    @State private var selection: UserManual.Chapter.ID?

    var body: some View {
        NavigationSplitView {
            List(chapters, selection: $selection) { Text($0.title).tag($0.id) }
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            if let c = chapters.first(where: { $0.id == selection }) {
                HTMLPreview(html: UserManual.page(c))
            } else {
                Text(L10n.tr("Wybierz rozdział")).foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onAppear(perform: load)
    }

    private func load() {
        var list: [UserManual.Chapter] = []
        if let root = Bundle.main.url(forResource: "Manual", withExtension: nil),
           let dir = UserManual.directory(in: root, preferred: Bundle.main.preferredLocalizations + Locale.preferredLanguages) {
            list = UserManual.chapters(in: dir)
        }
        list.append(UserManual.shortcutsChapter(commands: workspace.registry.commands.filter { !$0.isPlanned }.map(\.descriptor),
                                                chords: { workspace.keymap.chords(for: $0) }))
        chapters = list
        selection = selection ?? list.first?.id
    }
}
