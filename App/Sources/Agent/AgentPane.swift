import AppKit
import PelikanAgent
import PelikanWorkspace
import SwiftTerm

/// Panel agenta (PROMPT §7.1): terminal z natywnym interfejsem CLI (SwiftTerm), ostrzeżenia trybu, panel aktywności
/// (wywołania narzędzi: parametry, wynik, czas, decyzja) i oczekujące prośby o zgodę. Kilka sesji — wybór z listy.
final class AgentPane: NSView {
    let controller: AgentController
    var onUndo: ((String) -> Void)?
    var onClose: ((String) -> Void)?
    var onShowLog: (() -> Void)?

    private final class SessionView {
        let id: String
        let profile: AgentProfile
        let terminal: AgentTerminalView
        var ended = false
        let warnings: [String]
        let command: String
        init(id: String, profile: AgentProfile, terminal: AgentTerminalView, warnings: [String], command: String) {
            self.id = id
            self.profile = profile
            self.terminal = terminal
            self.warnings = warnings
            self.command = command
        }
    }

    private var sessions: [SessionView] = []
    private let picker = NSPopUpButton()
    private let warningLabel = NSTextField(wrappingLabelWithString: "")
    private let pendingLabel = NSTextField(labelWithString: "")
    private let terminalContainer = NSView()
    private let activityTable = NSTableView()
    private var rows: [AgentActivity] = []
    private var token: ObservationToken?
    private let split = NSSplitView()

    var selectedSessionID: String? {
        let i = picker.indexOfSelectedItem
        return i >= 0 && i < sessions.count ? sessions[i].id : nil
    }

    init(controller: AgentController) {
        self.controller = controller
        super.init(frame: .zero)
        build()
        token = trackChanges { [weak self] in
            guard let self else { return }
            _ = self.controller.activities.count
            _ = self.controller.pending.count
            _ = self.controller.sessions.count
            self.refreshActivity()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        picker.target = self
        picker.action = #selector(pickSession)
        picker.controlSize = .small
        let undo = NSButton(title: L10n.tr("Cofnij sesję…"), target: self, action: #selector(undo))
        let end = NSButton(title: L10n.tr("Zakończ"), target: self, action: #selector(end))
        let log = NSButton(title: L10n.tr("Dziennik"), target: self, action: #selector(showLog))
        for b in [undo, end, log] { b.controlSize = .small; b.bezelStyle = .accessoryBarAction; b.refusesFirstResponder = true }
        warningLabel.font = InterfaceFonts.shared.small
        warningLabel.textColor = .systemOrange
        warningLabel.maximumNumberOfLines = 3
        warningLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pendingLabel.font = AppFonts.font(family: InterfaceFonts.shared.family, size: max(9, InterfaceFonts.shared.size - 2), weight: .semibold)
        pendingLabel.textColor = .systemOrange
        let icon = NSImageView(image: NSImage(systemSymbolName: "cpu", accessibilityDescription: L10n.tr("Agent AI"))!)
        let header = NSStackView(views: [icon, picker, NSView(), pendingLabel, undo, end, log])
        header.spacing = 8
        header.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        let warnings = NSStackView(views: [warningLabel])
        warnings.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 3, right: 8)

        for (id, title, width) in [("time", L10n.tr("Czas"), 60.0), ("tool", L10n.tr("Narzędzie"), 120.0),
                                   ("status", L10n.tr("Stan"), 110.0), ("args", L10n.tr("Parametry / wynik"), 300.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title
            c.width = width
            activityTable.addTableColumn(c)
        }
        activityTable.dataSource = self
        activityTable.setAccessibilityLabel(L10n.tr("Aktywność agenta"))
        activityTable.delegate = self
        activityTable.rowHeight = 18
        activityTable.usesAlternatingRowBackgroundColors = true
        activityTable.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let activityScroll = NSScrollView()
        activityScroll.documentView = activityTable
        activityScroll.hasVerticalScroller = true

        // Terminal nad aktywnością (prawa kolumna jest wąska).
        split.isVertical = false
        split.dividerStyle = .thin
        split.addArrangedSubview(terminalContainer)
        split.addArrangedSubview(activityScroll)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0)

        let stack = NSStackView(views: [header, warnings, split])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for v in stack.arrangedSubviews { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            // Pod paskiem narzędzi okna (pełnowymiarowa treść okna — nagłówek chował się pod tytułem, D145).
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            activityScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            terminalContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
    }

    /// Dodaje sesję i zwraca terminal, w którym aplikacja uruchomi CLI.
    func addSession(session: AgentSession, warnings: [String], command: String, onExit: @escaping @MainActor () -> Void) -> LocalProcessTerminalView {
        let tv = AgentTerminalView(frame: .zero)
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.nativeBackgroundColor = .textBackgroundColor
        tv.nativeForegroundColor = .textColor
        let view = SessionView(id: session.id, profile: session.profile, terminal: tv, warnings: warnings, command: command)
        tv.onExit = { [weak self, weak view] in
            view?.ended = true
            onExit()
            self?.rebuildPicker()
        }
        tv.processDelegate = tv.exitDelegate
        sessions.append(view)
        rebuildPicker()
        picker.selectItem(at: sessions.count - 1)
        show(view)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.split.subviews.count == 2 else { return }
            self.split.setPosition(self.split.bounds.height * 0.62, ofDividerAt: 0)
        }
        return tv
    }

    /// Kończy CLI jak zamknięcie okna terminala: SIGHUP do całej grupy procesów (powłoka i CLI — część CLI
    /// przechwytuje SIGTERM), po 2 s SIGKILL, jeśli coś jeszcze działa.
    func terminateSession(_ id: String) {
        guard let s = sessions.first(where: { $0.id == id }), !s.ended else { return }
        let pid = s.terminal.process.shellPid
        guard pid > 0 else {
            s.terminal.terminate()
            return
        }
        kill(-pid, SIGHUP)
        kill(pid, SIGHUP)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard kill(pid, 0) == 0 else { return }
            kill(-pid, SIGKILL)
            kill(pid, SIGKILL)
        }
    }

    /// Czy działa jeszcze jakaś sesja poza `excluding`.
    func hasRunningSessions(excluding id: String? = nil) -> Bool {
        sessions.contains { !$0.ended && $0.id != id }
    }

    /// Kończy wszystkie działające sesje (zamknięcie aplikacji). Aplikacja kończy się przed opóźnionym SIGKILL
    /// z `terminateSession`, więc tu czekamy na miejscu (najwyżej 1 s) i dobijamy grupy procesów, które jeszcze działają.
    func terminateAll() {
        var alive = sessions.filter { !$0.ended }.map { $0.terminal.process.shellPid }.filter { $0 > 0 }
        for s in sessions where !s.ended { terminateSession(s.id) }
        let deadline = Date().addingTimeInterval(1)
        while !alive.isEmpty {
            alive.removeAll { pid in
                var status: Int32 = 0
                _ = waitpid(pid, &status, WNOHANG)  // powłoka to proces potomny — bez tego zostaje zombie w grupie
                return kill(-pid, 0) != 0
            }
            guard !alive.isEmpty, Date() < deadline else { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        for pid in alive {
            kill(-pid, SIGKILL)
            kill(pid, SIGKILL)
        }
    }

    private func rebuildPicker() {
        let selected = picker.indexOfSelectedItem
        picker.removeAllItems()
        for s in sessions {
            picker.addItem(withTitle: "\(s.profile.name) · \(s.id)\(s.ended ? " — " + L10n.tr("zakończona") : "")")
        }
        if selected >= 0, selected < sessions.count { picker.selectItem(at: selected) }
    }

    private func show(_ s: SessionView) {
        terminalContainer.subviews.forEach { $0.removeFromSuperview() }
        s.terminal.translatesAutoresizingMaskIntoConstraints = false
        terminalContainer.addSubview(s.terminal)
        NSLayoutConstraint.activate([
            s.terminal.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
            s.terminal.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
            s.terminal.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
            s.terminal.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor),
        ])
        warningLabel.stringValue = s.warnings.joined(separator: " ")
        warningLabel.isHidden = s.warnings.isEmpty
        warningLabel.toolTip = s.command
        refreshActivity()
    }

    @objc private func pickSession() {
        let i = picker.indexOfSelectedItem
        guard i >= 0, i < sessions.count else { return }
        show(sessions[i])
    }

    @objc private func undo() { if let id = selectedSessionID { onUndo?(id) } }
    @objc private func end() { if let id = selectedSessionID { onClose?(id) } }
    @objc private func showLog() { onShowLog?() }

    private func refreshActivity() {
        let id = selectedSessionID
        rows = controller.activities.filter { $0.sessionID == id }.reversed()
        activityTable.reloadData()
        let pending = controller.pending.count
        pendingLabel.stringValue = pending > 0 ? L10n.tr("Czeka na zgodę: \(pending)") : ""
    }
}

extension AgentPane: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let a = rows[row]
        let text: String
        var color = NSColor.labelColor
        switch tableColumn?.identifier.rawValue {
        case "time":
            text = Self.time.string(from: a.started)
        case "tool":
            text = a.tool
        case "status":
            switch a.status {
            case .running: text = L10n.tr("w toku")
            case .waitingForApproval: text = L10n.tr("czeka na zgodę"); color = .systemOrange
            case .succeeded: text = "✓ " + (a.duration.map { String(format: "%.0f ms", $0 * 1000) } ?? ""); color = .systemGreen
            case .denied(let why): text = "✕ " + why; color = .systemRed
            case .failed: text = L10n.tr("błąd"); color = .systemRed
            }
        default:
            switch a.status {
            case .failed(let m): text = a.arguments + "  ⟶  " + m
            default: text = a.arguments + (a.result.map { "  ⟶  " + $0 } ?? "")
            }
        }
        let field = NSTextField(labelWithString: text)
        field.font = InterfaceFonts.shared.small
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = text
        return field
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

/// Terminal procesu CLI agenta z powiadomieniem o zakończeniu.
final class AgentTerminalView: LocalProcessTerminalView {
    var onExit: (@MainActor () -> Void)? {
        didSet { exitDelegate.onExit = onExit }
    }
    let exitDelegate = TerminalExitDelegate()
}

final class TerminalExitDelegate: NSObject, LocalProcessTerminalViewDelegate {
    var onExit: (@MainActor () -> Void)?

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in self.onExit?() }
    }
}

/// Przeglądarka dziennika agentów (pliki JSONL w agent-logs/, PROMPT §7.6): lista plików, wpisy w tabeli
/// (czas, narzędzie, decyzja, argumenty, wynik), surowy wiersz pod tabelą.
final class AgentLogWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let directory: URL
    private let files = NSTableView()
    private let entries = NSTableView()
    private let raw = NSTextView()
    private var urls: [URL] = []
    private var lines: [[String: Any]] = []
    private var rawLines: [String] = []

    init(directory: URL) {
        self.directory = directory
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 640), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = L10n.tr("Dziennik agentów")
        window.setFrameAutosaveName((Bundle.main.object(forInfoDictionaryKey: "PelikanAppName") as? String ?? "Pelikan") + ".agentLog")
        super.init(window: window)
        let fileColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        fileColumn.title = L10n.tr("Plik")
        fileColumn.width = 240
        files.addTableColumn(fileColumn)
        files.dataSource = self
        files.setAccessibilityLabel(L10n.tr("Pliki dziennika"))
        files.delegate = self
        for (id, title, width) in [("time", L10n.tr("Czas"), 150.0), ("tool", L10n.tr("Narzędzie / zdarzenie"), 160.0),
                                   ("decision", L10n.tr("Decyzja"), 110.0), ("details", L10n.tr("Argumenty / wynik"), 420.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title
            c.width = width
            entries.addTableColumn(c)
        }
        entries.dataSource = self
        entries.setAccessibilityLabel(L10n.tr("Wpisy dziennika"))
        entries.delegate = self
        entries.usesAlternatingRowBackgroundColors = true
        entries.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let left = NSScrollView()
        left.documentView = files
        left.hasVerticalScroller = true
        let middle = NSScrollView()
        middle.documentView = entries
        middle.hasVerticalScroller = true
        raw.isEditable = false
        raw.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        raw.autoresizingMask = [.width]
        let bottom = NSScrollView()
        bottom.documentView = raw
        bottom.hasVerticalScroller = true
        let rightSplit = NSSplitView()
        rightSplit.isVertical = false
        rightSplit.addArrangedSubview(middle)
        rightSplit.addArrangedSubview(bottom)
        let split = NSSplitView()
        split.isVertical = true
        split.addArrangedSubview(left)
        split.addArrangedSubview(rightSplit)
        window.contentView = split
        split.setPosition(260, ofDividerAt: 0)
        rightSplit.setPosition(460, ofDividerAt: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func reload() {
        urls = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        files.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { tableView === files ? urls.count : lines.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text: String
        if tableView === files {
            text = urls[row].lastPathComponent
        } else {
            let e = lines[row]
            func s(_ k: String) -> String? { e[k].map { "\($0)" } }
            switch tableColumn?.identifier.rawValue {
            case "time": text = s("time") ?? ""
            case "tool": text = s("tool") ?? s("approval").map { L10n.tr("zgoda: \($0)") } ?? s("event") ?? ""
            case "decision": text = s("decision") ?? s("approved").map { $0 == "1" || $0 == "true" ? L10n.tr("zatwierdzone") : L10n.tr("odrzucone") } ?? s("reason") ?? ""
            default: text = [s("arguments"), s("result").map { "⟶ " + $0 }, s("error").map { "✕ " + $0 }, s("preview")].compactMap { $0 }.joined(separator: "  ")
            }
        }
        let field = NSTextField(labelWithString: text)
        field.font = InterfaceFonts.shared.small
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = text
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        if table === files {
            guard files.selectedRow >= 0 else { return }
            rawLines = ((try? String(contentsOf: urls[files.selectedRow], encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
            lines = rawLines.map { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] ?? [:] }
            entries.reloadData()
            raw.string = ""
        } else if entries.selectedRow >= 0, entries.selectedRow < rawLines.count {
            raw.string = rawLines[entries.selectedRow]
        }
    }
}
