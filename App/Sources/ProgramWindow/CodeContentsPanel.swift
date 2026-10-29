import AppKit
import PelikanSQL
import PelikanWorkspace

/// Panel Zawartość kodu obok edytora okna programu, SQL i testu (D199): podział pionowy — drzewo po lewej, treść okna
/// po prawej. Widoczność według okna (`Workspace.showsCodeContents`: wybór w oknie albo domyślne z Ustawień),
/// kolejność z Ustawień, śledzenie kursora i przejście do elementu (klik, Enter, strzałki).
/// Zarys liczony w tle z opóźnieniem po zmianie tekstu i tylko przy widocznym panelu (R4-01); okno programu podaje
/// zarys samo (`update`), bo liczy go razem z kartami jednostek.
@MainActor
final class CodeContentsPanel {
    let contents = CodeContentsView()
    let split = NSSplitView()
    private let document: Document
    private let workspace: Workspace
    private weak var editor: CodeEditorView?
    private let analyzesText: Bool
    private(set) var nodes: [OutlineNode] = []
    private var tokens: [ObservationToken] = []
    private var buttons: [NSButton] = []
    private var shown: Bool?
    private var appeared = false
    /// Szerokość panelu przed ukryciem — przywracana przy ponownym pokazaniu.
    private var width: CGFloat = 220
    private var analysisWork: DispatchWorkItem?
    private var analyzedOnce = false

    /// `content` — reszta okna (edytor z paskiem okna); `analyzesText` — panel sam liczy zarys z tekstu okna.
    init(document: Document, workspace: Workspace, editor: CodeEditorView, content: NSView, analyzesText: Bool) {
        self.document = document
        self.workspace = workspace
        self.editor = editor
        self.analyzesText = analyzesText
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(contents)
        split.addArrangedSubview(content)
        contents.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        split.setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)
        split.setHoldingPriority(NSLayoutConstraint.Priority(240), forSubviewAt: 1)
        // Klik albo Enter — kursor na nazwie elementu i fokus w edytorze; strzałki w drzewie — kursor idzie za
        // zaznaczeniem, fokus zostaje w drzewie. Element innej jednostki przełącza kartę okna programu (D192).
        contents.onSelect = { [weak self] n, focus in
            guard let self else { return }
            self.workspace.recordJump()
            self.document.selectedRange = n.nameOffset..<(n.nameOffset + (n.name as NSString).length)
            if focus, let tv = self.editor?.textView { self.split.window?.makeFirstResponder(tv) }
        }
        tokens.append(trackChanges { [weak self] in self?.applyVisibility() })
        if analyzesText {
            tokens.append(trackChanges { [weak self] in
                guard let self, self.workspace.showsCodeContents(self.document) else { return }
                self.scheduleAnalysis(self.document.text)
            })
        }
    }

    var isVisible: Bool { shown == true }

    /// Przycisk paska okna „Pokaż/ukryj Zawartość kodu” — komenda rejestru `view.codeContents` dla tego okna.
    func makeToggleButton() -> NSButton {
        let b = ClosureButton(title: "") { [weak self] in
            guard let self else { return }
            // Komenda działa na aktywnym oknie — klik w pasku tego okna najpierw je aktywuje.
            self.workspace.activate(self.document.id)
            self.workspace.perform("view.codeContents")
        }
        b.bezelStyle = .accessoryBarAction
        b.setButtonType(.pushOnPushOff)
        b.isBordered = true
        b.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: L10n.tr("Zawartość kodu"))
        b.imagePosition = .imageOnly
        b.toolTip = L10n.tr("Pokaż/ukryj Zawartość kodu")
        b.setAccessibilityLabel(L10n.tr("Pokaż/ukryj Zawartość kodu"))
        b.state = isVisible ? .on : .off
        buttons.append(b)
        return b
    }

    /// Pierwsze pokazanie okna: szerokość początkowa panelu po pierwszym układzie (wcześniej podział dzieli po połowie).
    func viewDidAppear() {
        guard !appeared else { return }
        appeared = true
        if isVisible { positionLater() }
    }

    /// Zarys policzony przez okno (okno programu).
    func update(_ nodes: [OutlineNode]) {
        self.nodes = nodes
        contents.update(nodes)
        caretMoved()
    }

    /// Kursor przesunięty — drzewo zaznacza element zawierający pozycję.
    func caretMoved() {
        guard isVisible else { return }
        contents.track(offset: document.selectedRange.lowerBound)
    }

    private func applyVisibility() {
        let show = workspace.showsCodeContents(document)
        contents.order = workspace.settings.codeContentsOrder
        for b in buttons { b.state = show ? .on : .off }
        guard show != shown else { return }
        if shown == true, contents.frame.width >= 120 { width = contents.frame.width }
        shown = show
        contents.isHidden = !show
        split.adjustSubviews()
        guard show else { return }
        if appeared { positionLater() }
        caretMoved()
    }

    private func positionLater() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            self.split.layoutSubtreeIfNeeded()
            self.split.setPosition(min(self.width, max(120, self.split.bounds.width * 0.45)), ofDividerAt: 0)
        }
    }

    /// Zarys z tekstu okna w tle, z opóźnieniem po zmianie (pierwszy raz od razu) — bez analizy przy każdym znaku na
    /// wątku głównym (R4-01).
    private func scheduleAnalysis(_ text: String) {
        analysisWork?.cancel()
        let kind = document.kind
        let work = DispatchWorkItem { [weak self] in
            Task.detached(priority: .userInitiated) {
                let outline = CodeContents.outline(text, kind: kind)
                await MainActor.run { [weak self] in
                    guard let self, self.document.text == text else { return }
                    self.update(outline)
                }
            }
        }
        analysisWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (analyzedOnce ? 0.4 : 0), execute: work)
        analyzedOnce = true
    }
}
