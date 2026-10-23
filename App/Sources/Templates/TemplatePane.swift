import AppKit
import PelikanWorkspace
import SwiftUI

/// Template Window (UG 31.1): szablony w folderach z filtrem; dwuklik wstawia w aktywnym edytorze (formularz
/// zmiennych), menu kontekstowe: wstaw, nowe okno, usuń szablon użytkownika, zapisz zaznaczenie jako szablon.
struct TemplatePane: View {
    let workspace: Workspace
    @State private var filter = ""
    @State private var selection: String?

    private var folders: [(String, [CodeTemplate])] {
        _ = workspace.templatesGeneration
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let list = workspace.templates.all.filter { f.isEmpty || $0.name.lowercased().contains(f) || $0.folder.lowercased().contains(f) }
        return Dictionary(grouping: list, by: \.folder).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(spacing: 6) {
            TextField(L10n.tr("Filtr szablonów"), text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)
            List(selection: $selection) {
                ForEach(folders, id: \.0) { folder, templates in
                    Section(folder) {
                        ForEach(templates) { t in
                            Label(t.name, systemImage: t.isBuiltIn ? "doc.text" : "doc.text.fill")
                                .tag(t.id)
                                .help(t.text)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let t = workspace.templates.template(id) {
                    Button(L10n.tr("Wstaw")) { insert(id) }
                    Button(L10n.tr("Nowe okno z szablonu")) { workspace.perform("file.newFromTemplate", CommandArguments(["template": .string(id)])) }
                    if !t.isBuiltIn {
                        Divider()
                        Button(L10n.tr("Usuń szablon")) { workspace.perform("templates.delete", CommandArguments(["template": .string(id)])) }
                    }
                }
                Divider()
                Button(L10n.tr("Zapisz zaznaczenie jako szablon…")) { workspace.perform("templates.save") }
            } primaryAction: { ids in
                if let id = ids.first { insert(id) }
            }
        }
        .padding(.bottom, 6)
    }

    private func insert(_ id: String) {
        workspace.perform("edit.insertTemplate", CommandArguments(["template": .string(id)]))
    }
}

final class TemplatePaneController: NSViewController {
    private let workspace: Workspace
    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() { view = NSHostingView(rootView: TemplatePane(workspace: workspace)) }
}
