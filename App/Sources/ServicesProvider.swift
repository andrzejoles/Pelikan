import AppKit
import PelikanWorkspace

/// Usługi macOS (MAC-SVC-001; wpisy NSServices w Info.plist): „Formatuj SQL” zamienia zaznaczenie w innej aplikacji,
/// „Otwórz w oknie SQL” i „Otwórz plik” przenoszą tekst albo pliki do Pelikana.
@MainActor
final class ServicesProvider: NSObject {
    private let workspace: Workspace

    init(workspace: Workspace) {
        self.workspace = workspace
    }

    @objc func formatSQL(_ pboard: NSPasteboard, userData: String?, error failure: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else { return }
        do {
            let formatted = try MacServices.formatSQL(text, in: workspace)
            pboard.clearContents()
            pboard.setString(formatted, forType: .string)
        } catch {
            failure.pointee = error.localizedDescription as NSString
        }
    }

    @objc func openInSQLWindow(_ pboard: NSPasteboard, userData: String?, error failure: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else { return }
        MacServices.openInSQLWindow(text, in: workspace)
        NSApp.activate()
    }

    @objc func openFiles(_ pboard: NSPasteboard, userData: String?, error failure: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        for url in urls {
            do { try workspace.openFile(url) } catch { failure.pointee = error.localizedDescription as NSString }
        }
        NSApp.activate()
    }
}
