import AppKit
import PelikanWorkspace
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Pokazanie wyniku raportu (D217, D219): ACTIVE — w oknie Pelikana z pliku w katalogu tymczasowym (skrypty raportu
/// z serwerów Oracle), HTML — podgląd w oknie, tekst i XML — tekst czcionką kodu; zawsze zapis do pliku.
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
                if let file {
                    ActiveReportView(file: file)
                } else {
                    Text(L10n.tr("Nie udało się zapisać raportu do pliku tymczasowego")).foregroundStyle(.orange)
                }
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

/// Raport ACTIVE w oknie Pelikana (D219): WebKit z dostępem do sieci (skrypty przeglądarki raportów z serwerów Oracle)
/// i tylko do pliku tego raportu (nie do innych raportów w katalogu — skrypty są zdalne). Raport otwarty z pliku działa; zewnętrzna przeglądarka albo serwer HTTP kończy się
/// „Błąd podczas pobierania danych” (przeglądarka raportów w ramce nie dostaje danych ze strony).
struct ActiveReportView: NSViewRepresentable {
    let file: URL

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.setAccessibilityLabel(L10n.tr("Raport interaktywny"))
        web.loadFileURL(file, allowingReadAccessTo: file)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}
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
