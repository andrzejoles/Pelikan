import AppKit
import PDFKit
import PelikanWorkspace
import UniformTypeIdentifiers
import WebKit

/// Large Data Editor (UG 27): okno dla komórki LOB/LONG/RAW/długiego tekstu — tekst (z formatowaniem JSON/XML),
/// podgląd szesnastkowy, obraz, PDF; zapis do pliku, wczytanie z pliku, zastosowanie zmian w siatce.
final class LargeDataEditorController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private let model: LargeDataModel
    private let workspace: Workspace
    private let mode = NSSegmentedControl()
    private let textView = NSTextView.scrollableTextView()
    private let imageView = NSImageView()
    private let pdfView = PDFView()
    /// Podgląd HTML (PD-LDE-001): bez JavaScriptu, CSP bez zasobów zewnętrznych.
    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        return WKWebView(frame: .zero, configuration: config)
    }()
    private let autoFormat = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let info = NSTextField(labelWithString: "")
    private let applyButton = NSButton()
    private let content = NSView()
    private var tokens: [ObservationToken] = []
    private var updating = false
    private static var open: [LargeDataEditorController] = []
    private var externalEdit: ExternalLargeDataEdit?
    private var externalTimer: Timer?

    static func show(_ model: LargeDataModel, workspace: Workspace, relativeTo parent: NSWindow?) {
        let c = LargeDataEditorController(model: model, workspace: workspace)
        open.append(c)
        if let parent, let w = c.window {
            let f = parent.frame
            w.setFrameOrigin(NSPoint(x: f.midX - w.frame.width / 2, y: f.midY - w.frame.height / 2))
        }
        c.showWindow(nil)
    }

    init(model: LargeDataModel, workspace: Workspace) {
        self.model = model
        self.workspace = workspace
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600), styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = L10n.tr("Large Data Editor — \(model.columnName)")
        w.minSize = NSSize(width: 480, height: 320)
        super.init(window: w)
        w.delegate = self
        build()
        tokens.append(trackChanges { [weak self] in self?.refresh() })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        mode.segmentCount = 5
        for (i, title) in [L10n.tr("Tekst"), L10n.tr("Hex"), L10n.tr("Obraz"), L10n.tr("PDF"), "HTML"].enumerated() { mode.setLabel(title, forSegment: i) }
        mode.target = self
        mode.action = #selector(modeChanged)
        let tv = textView.documentView as! NSTextView
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.delegate = self
        tv.setAccessibilityLabel(L10n.tr("Treść"))
        imageView.imageScaling = .scaleProportionallyDown
        pdfView.autoScales = true

        func button(_ title: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .rounded
            return b
        }
        applyButton.title = L10n.tr("Zastosuj w siatce")
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        applyButton.target = self
        applyButton.action = #selector(apply)
        let format = button(L10n.tr("Formatuj"), #selector(prettyPrint))
        format.toolTip = L10n.tr("Wcięcia dla JSON i XML")
        autoFormat.title = L10n.tr("Auto Format")
        autoFormat.toolTip = L10n.tr("Formatuje JSON i XML automatycznie po otwarciu")
        autoFormat.state = workspace.settings.largeDataAutoFormat ? .on : .off
        autoFormat.target = self
        autoFormat.action = #selector(toggleAutoFormat)
        let top = NSStackView(views: [mode, format, autoFormat, NSView(), info])
        let external = button(L10n.tr("Edytor zewnętrzny"), #selector(openExternal))
        external.toolTip = L10n.tr("Otwiera treść w programie skojarzonym z formatem; zapis w tym programie wraca do edytora")
        let bottom = NSStackView(views: [button(L10n.tr("Wczytaj z pliku…"), #selector(load)), button(L10n.tr("Zapisz do pliku…"), #selector(save)), external,
                                         NSView(), button(L10n.tr("Zamknij"), #selector(closeWindow)), applyButton])
        for v in [top, content, bottom] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false }
        info.textColor = .secondaryLabelColor
        info.font = .systemFont(ofSize: 11)
        let root = NSView()
        for v in [top, content, bottom] { root.addSubview(v) }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            top.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            bottom.topAnchor.constraint(equalTo: content.bottomAnchor, constant: 8),
            bottom.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            bottom.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            bottom.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
        ])
        window?.contentView = root
        mode.selectedSegment = model.format.isImage ? 2 : model.format == .pdf ? 3 : (model.isBinary && !model.format.isText ? 1 : 0)
        modeChanged()
    }

    /// Auto Format: przełącznik zapamiętany w preferencjach (komenda grid.largeDataAutoFormat).
    @objc private func toggleAutoFormat() {
        Task {
            _ = try? await workspace.invoke("grid.largeDataAutoFormat")
            autoFormat.state = workspace.settings.largeDataAutoFormat ? .on : .off
            applyAutoFormat()
        }
    }

    /// Sformatowany JSON/XML w widoku tekstu; wartość w siatce zmienia się tylko przy edycji.
    private func applyAutoFormat() {
        if mode.selectedSegment == 0 { modeChanged() }
    }

    /// Edytor zewnętrzny (UG 27.2): plik tymczasowy, program skojarzony z rozszerzeniem, wykrywanie zapisu co sekundę.
    @objc private func openExternal() {
        do {
            let edit = externalEdit ?? ExternalLargeDataEdit(model: model)
            let url = try edit.url ?? edit.start()
            externalEdit = edit
            NSWorkspace.shared.open(url)
            externalTimer?.invalidate()
            externalTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let e = self.externalEdit, self.model.isEditable else { return }
                    if e.checkForChanges() { self.modeChanged() }
                }
            }
        } catch {
            workspace.ui?.showError(error.localizedDescription)
        }
    }

    private func refresh() {
        let loading = model.isLoading
        let format = model.format
        _ = model.text
        _ = model.bytes
        var parts = [model.typeName, L10n.tr("format: \(format.rawValue.uppercased())"), L10n.tr("długość: \(model.totalLength)")]
        if model.truncated { parts.append(L10n.tr("obcięte — pełna treść niedostępna (brak ROWID)")) }
        if loading { parts.append(L10n.tr("pobieranie…")) }
        if !model.isEditable { parts.append(L10n.tr("tylko do odczytu")) }
        info.stringValue = parts.joined(separator: "  ·  ")
        applyButton.isEnabled = model.isEditable
        (textView.documentView as? NSTextView)?.isEditable = model.isEditable && mode.selectedSegment == 0
        if !updating { modeChanged() }
        mode.setEnabled(format.isImage, forSegment: 2)
        mode.setEnabled(format == .pdf, forSegment: 3)
        mode.setEnabled(format.isText, forSegment: 4)
    }

    @objc private func modeChanged() {
        content.subviews.forEach { $0.removeFromSuperview() }
        let view: NSView
        let tv = textView.documentView as! NSTextView
        switch mode.selectedSegment {
        case 1:
            updating = true
            tv.string = LargeDataModel.hexDump(model.fileData)
            tv.isEditable = false
            updating = false
            view = textView
        case 2:
            imageView.image = NSImage(data: model.fileData)
            view = imageView
        case 3:
            pdfView.document = PDFDocument(data: model.fileData)
            view = pdfView
        case 4:
            webView.loadHTMLString(LargeDataModel.htmlPreviewDocument(model.text ?? String(decoding: model.fileData, as: UTF8.self)), baseURL: nil)
            view = webView
        default:
            updating = true
            if model.bytes != nil, model.text == nil {
                tv.string = String(data: model.fileData, encoding: .utf8) ?? LargeDataModel.hexDump(model.fileData)
            } else {
                tv.string = model.text ?? ""
            }
            // Auto Format: tylko widok (wartość zmienia się dopiero po edycji).
            if workspace.settings.largeDataAutoFormat, !model.modified, let out = LargeDataModel.autoFormatted(tv.string, format: model.format) {
                tv.string = out
            }
            tv.isEditable = model.isEditable
            updating = false
            view = textView
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: content.topAnchor), view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor), view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
    }

    func textDidChange(_ notification: Notification) {
        guard !updating, mode.selectedSegment == 0, let tv = textView.documentView as? NSTextView else { return }
        updating = true
        if model.isBinary { model.setBytes(Data(tv.string.utf8)) } else { model.setText(tv.string) }
        updating = false
    }

    @objc private func prettyPrint() {
        guard let s = model.text ?? String(data: model.fileData, encoding: .utf8) else { return }
        var out: String?
        switch model.format {
        case .json: out = LargeDataModel.prettyJSON(s)
        case .xml, .html:
            if let doc = try? XMLDocument(xmlString: s, options: [.nodePreserveAll]) { out = doc.xmlString(options: [.nodePrettyPrint]) }
        default: break
        }
        guard let out else { NSSound.beep(); return }
        mode.selectedSegment = 0
        if model.isEditable { model.isBinary ? model.setBytes(Data(out.utf8)) : model.setText(out) }
        (textView.documentView as? NSTextView)?.string = out
    }

    @objc private func load() {
        guard let w = window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: w) { [weak self] r in
            guard r == .OK, let url = panel.url, let self, let data = try? Data(contentsOf: url) else { return }
            if self.model.isBinary {
                self.model.setBytes(data)
            } else {
                self.model.setText(String(decoding: data, as: UTF8.self))
            }
            self.modeChanged()
        }
    }

    @objc private func save() {
        let name = model.columnName + "." + model.format.fileExtension
        Task { _ = await workspace.ui?.saveFile(suggestedName: (name as NSString).deletingPathExtension, fileExtension: model.format.fileExtension, data: model.fileData) }
    }

    @objc private func apply() {
        do {
            try model.apply()
            close()
        } catch {
            workspace.ui?.showError(error.localizedDescription)
        }
    }

    @objc private func closeWindow() { close() }

    func windowWillClose(_ notification: Notification) {
        externalTimer?.invalidate()
        externalEdit?.checkForChanges()
        externalEdit?.finish()
        Self.open.removeAll { $0 === self }
    }
}
