import AppKit
import PelikanWorkspace
import Quartz
import SwiftUI

/// Plik tymczasowy podglądu Quick Look (QLPreviewView pokazuje plik, nie dane w pamięci): właściwe rozszerzenie
/// z rozpoznanego formatu, prawa tylko dla użytkownika, usuwany przy zmianie treści i zamknięciu widoku. Zapis poza
/// wątkiem głównym (wartość może mieć setki MB).
@MainActor
final class QuickLookFile {
    private(set) var url: URL?
    private var key: String?
    private var writing: Task<Void, Never>?

    /// Plik dla treści (`key` — tożsamość treści: bez ponownego zapisu tych samych danych); `ready` dostaje plik po
    /// zapisie, tylko jeśli treść nie zmieniła się w międzyczasie.
    func prepare(_ data: Data, format: LargeDataFormat, key: String, ready: @escaping @MainActor (URL) -> Void) {
        if key == self.key {
            if let url { ready(url) }
            return
        }
        remove()
        self.key = key
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-preview", isDirectory: true)
        let file = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension(format.fileExtension)
        writing = Task { [weak self] in
            let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                return FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600])
            }.value
            guard let self, !Task.isCancelled, self.key == key else { try? FileManager.default.removeItem(at: file); return }
            guard ok else { return }
            self.url = file
            ready(file)
        }
    }

    func remove() {
        writing?.cancel()
        writing = nil
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
        key = nil
    }

    isolated deinit { remove() }
}

/// Podgląd Quick Look (PDF, obrazy, dokumenty Office, archiwa…) — generatory systemu działają poza procesem
/// aplikacji, bez skryptów i sieci (treść z bazy jest niezaufana).
struct QuickLookPreview: NSViewRepresentable {
    let data: Data
    let format: LargeDataFormat
    let id: String

    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal)!
        v.autostarts = true
        return v
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        context.coordinator.file.prepare(data, format: format, key: id) { [weak view] url in
            guard let view, (view.previewItem as? URL) != url else { return }
            view.previewItem = url as NSURL
        }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: Coordinator) {
        view.close()
        coordinator.file.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    @MainActor final class Coordinator { let file = QuickLookFile() }
}
