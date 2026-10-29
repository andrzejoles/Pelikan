import AppKit
import PelikanWorkspace

/// Przycisk lewej kolumny na lewym końcu paska tytułu, tuż za przyciskami okna (D204) — jak przycisk paska bocznego
/// w Mailu i Notatkach: zawsze w tym samym miejscu, także przy schowanej kolumnie. Dodatek paska tytułu (`.leading`),
/// nie element paska narzędzi: element paska stoi za tytułem okna, a przy schowanej kolumnie przeskakiwał na prawo.
/// Wywołuje komendę `view.toggleSidebar` (⌃⌘S); ten sam przycisk można dodatkowo wstawić do paska (Dostosuj pasek).
final class SidebarToggleAccessory: NSTitlebarAccessoryViewController {
    /// Wysokość nie większa niż pasek tytułu bez paska narzędzi (28 pt) — dodatek nie podnosi paska tytułu.
    static let height: CGFloat = 28
    private let workspace: Workspace
    private let isVisible: () -> Bool
    private let button = NSButton()
    private var token: ObservationToken?

    init(workspace: Workspace, isVisible: @escaping () -> Bool) {
        self.workspace = workspace
        self.isVisible = isVisible
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .leading
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let title = L10n.tr("Pokaż lub ukryj panel po lewej")
        button.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: title)
        button.target = self
        button.action = #selector(toggle)
        // Przełącznik ze stanem (VoiceOver: „przycisk przełączający”, wartość „widoczny”/„ukryty”). Sam symbol jak
        // przycisk nawigatora w Xcode — szkło dodatku paska tytułu nie rysuje się w zrzutach w tle (D196).
        button.setButtonType(.pushOnPushOff)
        button.isBordered = false
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel(L10n.tr("Panel po lewej"))
        button.translatesAutoresizingMaskIntoConstraints = false
        // Szerokość widoku dodatku paska tytułu bierze się z ramki (bez niej przycisk byłby ściśnięty do zera).
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 44, height: Self.height))
        root.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            button.widthAnchor.constraint(equalToConstant: 30),
            button.heightAnchor.constraint(equalToConstant: 24),
            button.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        view = root
        // Podpowiedź ze skrótem z bieżącej mapy klawiszy (zmiana w Ustawieniach › Klawiatura odświeża ją od razu).
        token = trackChanges { [weak self] in
            guard let self else { return }
            let chord = self.workspace.keymap.chords(for: "view.toggleSidebar").first.map { " (\($0.displayString))" } ?? ""
            self.button.toolTip = title + chord
        }
        refresh()
    }

    /// Stan przycisku i wartość dostępności według widoczności lewej kolumny.
    func refresh() {
        guard isViewLoaded else { return }
        let visible = isVisible()
        button.state = visible ? .on : .off
        button.setAccessibilityValue(visible ? L10n.tr("widoczny") : L10n.tr("ukryty"))
    }

    @objc private func toggle() {
        // Przełączenie zmienia stan przycisku od razu; właściwy stan ustawia komenda (refresh po zmianie podziału).
        refresh()
        workspace.perform("view.toggleSidebar")
    }
}
