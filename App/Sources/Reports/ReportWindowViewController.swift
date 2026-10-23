import AppKit
import PelikanWorkspace
import SwiftUI
import WebKit

/// Okno raportu (UG 12, PD-REP-002..004): karty Zapytanie / Układ / Opcje / Wynik; wynik HTML w WebKit.
final class ReportWindowViewController: NSViewController {
    private let document: PelikanWorkspace.Document
    private let workspace: Workspace
    private var editor: CodeEditorView!
    private let web = WKWebView()
    private let container = NSView()
    private var pages: [NSView] = []
    private var tokens: [ObservationToken] = []
    private var shownHTML: String?
    private let selection = ReportTabSelection()

    var preferredFirstResponder: NSView { editor.textView }

    init(document: PelikanWorkspace.Document, workspace: Workspace) {
        self.document = document
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        editor = CodeEditorView(document: document, fontSize: CGFloat(workspace.settings.editorFontSize))
        let locked = NSHostingView(rootView: LockedReportView())
        let editorPage = NSView()
        for v in [editor!, locked] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            editorPage.addSubview(v)
            NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: editorPage.leadingAnchor), v.trailingAnchor.constraint(equalTo: editorPage.trailingAnchor),
                                         v.topAnchor.constraint(equalTo: editorPage.topAnchor), v.bottomAnchor.constraint(equalTo: editorPage.bottomAnchor)])
        }
        pages = [editorPage, NSHostingView(rootView: ReportLayoutView(document: document)),
                 NSHostingView(rootView: ReportOptionsView(document: document, workspace: workspace)), web]
        let bar = NSHostingView(rootView: ReportToolbar(document: document, workspace: workspace, selection: selection))
        let stack = NSStackView(views: [bar, container])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        bar.setContentHuggingPriority(.required, for: .vertical)
        for v in [bar, container] { v.translatesAutoresizingMaskIntoConstraints = false; v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        for p in pages {
            p.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(p)
            NSLayoutConstraint.activate([p.leadingAnchor.constraint(equalTo: container.leadingAnchor), p.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                                         p.topAnchor.constraint(equalTo: container.topAnchor), p.bottomAnchor.constraint(equalTo: container.bottomAnchor)])
        }
        view = stack
        tokens.append(trackChanges { [weak self] in
            guard let self else { return }
            let tab = self.selection.tab
            let isLocked = self.document.report.locked
            for (i, p) in self.pages.enumerated() { p.isHidden = i != tab }
            self.editor.isHidden = isLocked
            locked.isHidden = !isLocked
        })
        tokens.append(trackChanges { [weak self] in
            guard let self else { return }
            let html = self.document.reportHTML
            guard html != self.shownHTML else { return }
            self.shownHTML = html
            self.web.loadHTMLString(html ?? "", baseURL: nil)
            if html != nil { self.selection.tab = 3 }
        })
    }
}

/// Wybrana karta okna raportu.
@MainActor
@Observable
final class ReportTabSelection {
    var tab = 0
}

struct LockedReportView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.system(size: 28)).foregroundStyle(.secondary)
            Text(L10n.tr("Definicja raportu jest zablokowana — raport można tylko wykonywać.")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ReportToolbar: View {
    @Bindable var document: PelikanWorkspace.Document
    let workspace: Workspace
    @Bindable var selection: ReportTabSelection

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $selection.tab) {
                Text(L10n.tr("Zapytanie")).tag(0)
                Text(L10n.tr("Układ")).tag(1)
                Text(L10n.tr("Opcje")).tag(2)
                Text(L10n.tr("Wynik")).tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button { workspace.perform("report.execute") } label: { Label(L10n.tr("Wykonaj"), systemImage: "play.fill") }
                .disabled(document.isExecuting)
            Spacer()
            if let e = document.reportError { Text(e).foregroundStyle(.red).font(.caption).lineLimit(1) }
            Button { workspace.perform("report.print") } label: { Image(systemName: "printer") }.iconLabel(L10n.tr("Drukuj raport…")).disabled(document.reportHTML == nil)
            Button { workspace.perform("report.saveHTML") } label: { Image(systemName: "square.and.arrow.down") }.iconLabel(L10n.tr("Zapisz raport jako HTML…")).disabled(document.reportHTML == nil)
            Menu(L10n.tr("Eksport")) {
                ForEach(["csv", "tsv", "xml", "xlsx"], id: \.self) { f in
                    Button(f.uppercased()) { workspace.perform("report.export", CommandArguments(["format": .string(f)])) }
                }
            }
            .fixedSize()
            .disabled(document.reportData == nil)
            Button(L10n.tr("Do menu Raporty")) { workspace.perform("report.addToMenu") }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

/// Układ raportu (UG 12.4–12.5): tytuł, styl, nagłówek, układ, formaty kolumn.
struct ReportLayoutView: View {
    @Bindable var document: PelikanWorkspace.Document

    private var columnNames: [String] {
        var names = document.reportData?.columns ?? []
        for c in document.report.columns where !names.contains(c.column) { names.append(c.column) }
        return names
    }

    private func binding(_ name: String) -> Binding<ReportColumnFormat> {
        Binding(get: { document.report.format(of: name) }, set: { f in
            if let i = document.report.columns.firstIndex(where: { $0.column == f.column }) { document.report.columns[i] = f } else { document.report.columns.append(f) }
            document.isModified = true
        })
    }

    var body: some View {
        if document.report.locked {
            LockedReportView()
        } else {
            Form {
                Section(L10n.tr("Raport")) {
                    TextField(L10n.tr("Tytuł"), text: $document.report.title)
                    Picker(L10n.tr("Styl"), selection: $document.report.styleName) {
                        ForEach(ReportStyle.library) { Text($0.name).tag($0.name) }
                    }
                    Picker(L10n.tr("Układ"), selection: $document.report.layout) {
                        Text(L10n.tr("Tabela")).tag(ReportDefinition.Layout.table)
                        Text(L10n.tr("Formularz")).tag(ReportDefinition.Layout.form)
                    }
                    TextField(L10n.tr("Nagłówek (#title, #date, #user, #connection, #zmienna)"), text: $document.report.header)
                    Toggle(L10n.tr("Nowa strona po każdej grupie"), isOn: $document.report.pageBreakOnGroup)
                    TextField(L10n.tr("Tło (kolor CSS)"), text: $document.report.background)
                    TextField(L10n.tr("Dodatkowy CSS"), text: $document.report.extraCSS, axis: .vertical).font(.system(size: 11, design: .monospaced)).lineLimit(2...6)
                }
                Section(L10n.tr("Kolumny (po wykonaniu raportu)")) {
                    if columnNames.isEmpty { Text(L10n.tr("Wykonaj raport, żeby ustawić formaty kolumn.")).foregroundStyle(.secondary) }
                    ForEach(columnNames, id: \.self) { name in ReportColumnRow(format: binding(name)) }
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct ReportColumnRow: View {
    @Binding var format: ReportColumnFormat

    var body: some View {
        HStack {
            Text(format.column).font(.system(.body, design: .monospaced)).frame(width: 140, alignment: .leading)
            TextField(L10n.tr("Nagłówek"), text: Binding(get: { format.heading ?? "" }, set: { format.heading = $0.isEmpty ? nil : $0 })).frame(width: 140)
            Picker("", selection: $format.alignment) {
                Text(L10n.tr("auto")).tag(ReportColumnFormat.Alignment.automatic)
                Text(L10n.tr("do lewej")).tag(ReportColumnFormat.Alignment.left)
                Text(L10n.tr("środek")).tag(ReportColumnFormat.Alignment.center)
                Text(L10n.tr("do prawej")).tag(ReportColumnFormat.Alignment.right)
            }
            .labelsHidden().frame(width: 100)
            TextField(L10n.tr("Liczba, np. #,##0.00"), text: Binding(get: { format.numberFormat ?? "" }, set: { format.numberFormat = $0.isEmpty ? nil : $0 })).frame(width: 120)
            TextField(L10n.tr("Data, np. yyyy-MM-dd"), text: Binding(get: { format.dateFormat ?? "" }, set: { format.dateFormat = $0.isEmpty ? nil : $0 })).frame(width: 120)
            Toggle(L10n.tr("Grupa"), isOn: $format.breakGroup)
            Toggle(L10n.tr("Suma"), isOn: $format.sum)
            Toggle(L10n.tr("Ukryj"), isOn: $format.hidden)
        }
        .toggleStyle(.checkbox)
    }
}

/// Opcje raportu (UG 12.6): połączenie, limit wierszy, blokada definicji.
struct ReportOptionsView: View {
    @Bindable var document: PelikanWorkspace.Document
    let workspace: Workspace

    var body: some View {
        Form {
            Picker(L10n.tr("Połączenie"), selection: $document.report.connection) {
                Text(L10n.tr("Połączenie okna albo główne")).tag("")
                ForEach(workspace.connections.connections) { Text($0.displayName).tag($0.displayName) }
            }
            .disabled(document.report.locked)
            Stepper(L10n.tr("Limit wierszy: \(document.report.maxRows)"), value: $document.report.maxRows, in: 100...100_000, step: 100)
                .disabled(document.report.locked)
            HStack {
                Text(document.report.locked ? L10n.tr("Definicja zablokowana") : L10n.tr("Definicja odblokowana"))
                Spacer()
                if document.report.locked {
                    Button(L10n.tr("Odblokuj…")) { workspace.perform("report.unlock") }
                } else {
                    Button(L10n.tr("Zablokuj")) { workspace.perform("report.lock") }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Druk HTML przez WebKit (okno druku pozwala też zapisać PDF).
@MainActor
final class HTMLPrinter: NSObject, WKNavigationDelegate {
    private static var active: [HTMLPrinter] = []
    private let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 1000))
    private let title: String

    init(html: String, title: String) {
        self.title = title
        super.init()
        web.navigationDelegate = self
        Self.active.append(self)
        web.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .spool
        let op = webView.printOperation(with: info)
        op.jobTitle = title
        op.view?.frame = webView.bounds
        op.runModal(for: NSApp.keyWindow ?? NSApp.mainWindow ?? NSWindow(), delegate: nil, didRun: nil, contextInfo: nil)
        // Widok WebKit musi żyć do końca druku (arkusz jest asynchroniczny).
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { Self.active.removeAll { $0 === self } }
    }
}
