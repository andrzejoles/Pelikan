import AppKit
import PelikanWorkspace

/// Przycisk lewej kolumny na lewym końcu paska tytułu, tuż za przyciskami okna (D204) — jak przycisk paska bocznego
/// w Mailu i Notatkach: zawsze w tym samym miejscu, także przy schowanej kolumnie. Dodatek paska tytułu (`.leading`),
/// nie element paska narzędzi: element paska stoi za tytułem okna, a przy schowanej kolumnie przeskakiwał na prawo.
/// Wywołuje komendę `view.toggleSidebar` (⌃⌘S); ten sam przycisk można dodatkowo wstawić do paska (Dostosuj pasek).
final class SidebarToggleAccessory: NSTitlebarAccessoryViewController {
    private let workspace: Workspace

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .leading
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let title = L10n.tr("Pokaż lub ukryj panel po lewej")
        let button = NSButton(image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: title) ?? NSImage(),
                              target: self, action: #selector(toggle))
        // Sam symbol jak przycisk nawigatora w Xcode — szkło dodatku paska tytułu nie rysuje się w zrzutach w tle (D196).
        button.isBordered = false
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        button.contentTintColor = .secondaryLabelColor
        let chord = workspace.keymap.chords(for: "view.toggleSidebar").first.map { " (\($0.displayString))" } ?? ""
        button.toolTip = title + chord
        button.setAccessibilityLabel(title)
        button.translatesAutoresizingMaskIntoConstraints = false
        // Szerokość widoku dodatku paska tytułu bierze się z ramki (bez niej przycisk byłby ściśnięty do zera).
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 38))
        root.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36),
            button.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        view = root
    }

    @objc private func toggle() {
        workspace.perform("view.toggleSidebar")
    }
}
