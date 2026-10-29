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
    /// Liczenie w toku — anulowane przy następnej zmianie i przy zwolnieniu panelu (zamknięcie okna).
    private var analysis: AnalysisHandle?
    /// Rewizja tekstu (`Document.textRevision`) ostatniego zarysu w panelu i zarysu w trakcie liczenia.
    private var analyzedRevision = -1
    private var pendingRevision = -1
    /// Panel był widoczny przy poprzednim przebiegu śledzenia tekstu — po pokazaniu analiza od razu, bez opóźnienia.
    private var sawVisible = false

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
            // Nazwa elementu; blok i struktura sterująca — słowo otwierające (D203).
            self.document.selectedRange = CodeContents.selection(of: n, in: self.document.text)
            if focus, let tv = self.editor?.textView { self.split.window?.makeFirstResponder(tv) }
        }
        tokens.append(trackChanges { [weak self] in self?.applyVisibility() })
        if analyzesText {
            // Obserwuje tekst i widoczność; każda inna zmiana Ustawień też tu trafia, ale bez zmiany rewizji tekstu
            // nic nie liczy.
            tokens.append(trackChanges { [weak self] in
                guard let self else { return }
                guard self.workspace.showsCodeContents(self.document) else { self.sawVisible = false; return }
                _ = self.document.text
                let immediate = !self.sawVisible || (self.analyzedRevision < 0 && self.pendingRevision < 0)
                self.sawVisible = true
                self.scheduleAnalysis(immediate: immediate)
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
        b.image = NSImage(systemSymbolName: "list.bullet.indent", accessibilityDescription: nil)
        b.imagePosition = .imageOnly
        b.toolTip = L10n.tr("Pokaż/ukryj Zawartość kodu")
        b.setAccessibilityLabel(L10n.tr("Zawartość kodu"))
        buttons.append(b)
        updateButtons()
        return b
    }

    /// Pierwsze pokazanie okna: szerokość początkowa panelu po pierwszym układzie (wcześniej podział dzieli po połowie).
    func viewDidAppear() {
        guard !appeared else { return }
        appeared = true
        if isVisible { positionLater() }
    }

    /// Zarys policzony przez okno (okno programu); `omitted` — polecenia SQL pominięte ponad limit (dopisek w panelu).
    func update(_ nodes: [OutlineNode], omitted: Int = 0) {
        self.nodes = nodes
        contents.note = omitted > 0
            ? L10n.tr("Poleceń SQL w skrypcie: \(omitted) — pokazane są tylko jednostki i bloki PL/SQL.") : nil
        contents.update(nodes)
        caretMoved()
    }

    /// Stan przycisków: wciśnięty przy widocznym panelu; VoiceOver — „Zawartość kodu”, wartość: widoczna albo ukryta.
    private func updateButtons() {
        for b in buttons {
            b.state = isVisible ? .on : .off
            b.setAccessibilityValue(isVisible ? L10n.tr("widoczna") : L10n.tr("ukryta"))
        }
    }

    /// Kursor przesunięty — drzewo zaznacza element zawierający pozycję.
    func caretMoved() {
        guard isVisible else { return }
        contents.track(offset: document.selectedRange.lowerBound)
    }

    private func applyVisibility() {
        // Każda zmiana Ustawień uruchamia ten przebieg — bez zmiany widoczności i kolejności nic się nie dzieje.
        let show = workspace.showsCodeContents(document)
        let order = workspace.settings.codeContentsOrder
        let flow = workspace.settings.codeContentsControlFlow
        if contents.order != order || contents.showsControlFlow != flow {
            contents.order = order
            contents.showsControlFlow = flow
            // Drzewo przebudowane — zaznaczenie wraca do elementu z kursorem.
            caretMoved()
        }
        guard show != shown else { return }
        if shown == true, contents.frame.width >= 120 { width = contents.frame.width }
        shown = show
        updateButtons()
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

    /// Zarys z tekstu okna w tle (R4-01): 0,4 s po ostatniej zmianie (po pokazaniu panelu i za pierwszym razem — od
    /// razu); nowsza zmiana anuluje liczenie w toku, a tekst bez zmiany rewizji nie jest liczony ponownie.
    private func scheduleAnalysis(immediate: Bool) {
        let revision = document.textRevision
        guard revision != analyzedRevision, revision != pendingRevision else { return }
        pendingRevision = revision
        let text = document.text
        let kind = document.kind
        // Zastąpienie uchwytu anuluje poprzednie liczenie.
        analysis = AnalysisHandle(Task.detached(priority: .userInitiated) { [weak self] in
            if !immediate { try? await Task.sleep(for: .milliseconds(400)) }
            guard !Task.isCancelled else { return }
            // Zawsze ze strukturami sterującymi — przełącznik panelu tylko je ukrywa, bez ponownej analizy.
            let result = CodeContents.analyze(text, kind: kind, controlFlow: true) { Task.isCancelled }
            guard !Task.isCancelled else { return }
            await self?.finishAnalysis(result, revision: revision)
        })
    }

    private func finishAnalysis(_ result: PLSQLOutline.ScriptOutline, revision: Int) {
        if pendingRevision == revision { pendingRevision = -1 }
        guard document.textRevision == revision else { return }
        analyzedRevision = revision
        update(result.nodes, omitted: result.omittedStatements)
    }
}

/// Uchwyt zadania w tle anulujący je przy zwolnieniu (zastąpienie nowym liczeniem, zamknięcie okna) — bez `deinit`
/// izolowanego na głównym aktorze w panelu.
private final class AnalysisHandle {
    let task: Task<Void, Never>
    init(_ task: Task<Void, Never>) { self.task = task }
    deinit { task.cancel() }
}
