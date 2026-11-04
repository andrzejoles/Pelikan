import AppKit
import PelikanWorkspace
import SwiftUI
import UniformTypeIdentifiers

/// Pokazanie wyniku raportu (D217): ACTIVE — plik w katalogu tymczasowym otwierany w przeglądarce (skrypty raportu
/// pobierane z serwerów Oracle), HTML — podgląd w oknie, tekst i XML — tekst czcionką kodu; zawsze zapis do pliku.
@MainActor
enum PerfReportPresenter {
    static var directory: URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("Pelikan-raporty", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Plik raportu w katalogu tymczasowym (nazwa z tytułu, bez znaków spoza nazw plików).
    static func write(_ out: PerfReportOutput) -> URL? {
        let safe = out.suggestedName.map { "/:\\?*\"<>|".contains($0) ? "_" : $0 }
        let url = directory.appendingPathComponent(String(safe))
        do {
            try Data(out.content.utf8).write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }

    static func present(_ out: PerfReportOutput) {
        let file = write(out)
        if out.format == .active, let file, !AppDelegate.scriptSkipsDialog("perfReportBrowser") { NSWorkspace.shared.open(file) }
        ToolWindowController.show(key: "perfResult-" + UUID().uuidString, title: out.title, size: NSSize(width: 980, height: 700)) {
            PerfReportResultView(output: out, file: file)
        }
    }
}

struct PerfReportResultView: View {
    let output: PerfReportOutput
    let file: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(output.title).font(.uiHeadline).lineLimit(1)
                Text(output.format.displayName).font(.uiSecondary).foregroundStyle(.secondary)
                Spacer()
                if output.format != .text, let file {
                    Button(L10n.tr("Otwórz w przeglądarce")) { NSWorkspace.shared.open(file) }
                }
                Button(L10n.tr("Kopiuj")) {
                    (NSApp.delegate as? AppDelegate)?.copyToClipboard(output.content, html: output.format == .html ? output.content : nil)
                }
                Button(L10n.tr("Zapisz…")) { save() }
            }
            switch output.format {
            case .active:
                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n.tr("Raport interaktywny (ACTIVE) otwarto w przeglądarce — pobiera skrypty z serwerów Oracle, więc wymaga internetu przy oglądaniu."),
                          systemImage: "safari").fixedSize(horizontal: false, vertical: true)
                    if let file { Text(file.path).font(.code).foregroundStyle(.secondary).textSelection(.enabled) }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .html:
                HTMLPreview(html: output.content)
            case .text, .xml:
                ScrollView([.horizontal, .vertical]) {
                    Text(output.content).font(.code).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
            }
        }
        .padding(8)
        .frame(minWidth: 640, minHeight: 420)
    }

    private func save() {
        let p = NSSavePanel()
        p.nameFieldStringValue = output.suggestedName
        p.allowedContentTypes = [UTType(filenameExtension: output.format.fileExtension) ?? .data]
        p.canCreateDirectories = true
        let write: (NSApplication.ModalResponse) -> Void = { r in
            guard r == .OK, let url = p.url else { return }
            do { try Data(output.content.utf8).write(to: url, options: .atomic) } catch { NSAlert(error: error).runModal() }
        }
        if let w = NSApp.keyWindow { p.beginSheetModal(for: w, completionHandler: write) } else { write(p.runModal()) }
    }
}

/// Ostatnio zaznaczony w tabeli wiersz z SQL_ID/hash (D217) — dla komendy wołanej ze wstążki, menu albo skrótu, gdy
/// fokus jest w tej tabeli.
@MainActor
final class SQLTargetRegistry {
    static let shared = SQLTargetRegistry()
    private(set) var target: SQLReportTarget?
    private(set) var window: Int?
    private(set) var at = Date.distantPast

    func note(_ t: SQLReportTarget?) {
        target = t
        window = NSApp.keyWindow?.windowNumber
        at = Date()
    }

    /// Cel z tabeli w oknie z fokusem, gdy zaznaczono go w ciągu ostatnich 10 minut.
    func current() -> SQLReportTarget? {
        guard let target, window == NSApp.keyWindow?.windowNumber, Date().timeIntervalSince(at) < 600 else { return nil }
        return target
    }
}

/// Połączenie tabeli narzędzia (sesje, SQL Monitor…) — raporty SQL z wiersza na tym połączeniu (D217).
struct ReportConnectionKey: EnvironmentKey { static let defaultValue: UUID? = nil }

extension EnvironmentValues {
    var reportConnection: UUID? {
        get { self[ReportConnectionKey.self] }
        set { self[ReportConnectionKey.self] = newValue }
    }
}

/// Otwarcie raportów SQL dla celu z wiersza tabeli.
@MainActor
enum SQLReportLauncher {
    static func open(_ t: SQLReportTarget) {
        guard let ws = (NSApp.delegate as? AppDelegate)?.workspace else { return }
        var args: [String: JSONValue] = [:]
        switch t.target {
        case .sqlID(let s): args["sqlId"] = .string(s)
        case .hash(let h): args["hash"] = .int(Int64(h))
        }
        if let c = t.connection { args["connection"] = .string(c.uuidString) }
        ws.perform("perf.sqlReports", CommandArguments(args))
    }
}
