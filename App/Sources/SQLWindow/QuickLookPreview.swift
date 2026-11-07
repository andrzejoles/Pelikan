import AppKit
import CryptoKit
import PelikanWorkspace
import Quartz
import SwiftUI

/// Plik tymczasowy podglądu Quick Look (QLPreviewView pokazuje plik, nie dane w pamięci): właściwe rozszerzenie
/// z rozpoznanego formatu, prawa tylko dla użytkownika, usuwany przy zmianie treści i zamknięciu widoku.
@MainActor
final class QuickLookFile {
    private(set) var url: URL?
    private var key: String?

    /// Plik dla treści (`key` — tożsamość treści: bez ponownego zapisu tych samych danych).
    func file(for data: Data, format: LargeDataFormat, key: String) -> URL? {
        if key == self.key, let url { return url }
        remove()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension(format.fileExtension)
        guard FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return nil }
        url = file
        self.key = key
        return file
    }

    /// Tożsamość treści (skrót SHA-256 — `Data.hashValue` obejmuje tylko początek danych).
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func remove() {
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
        guard let url = context.coordinator.file.file(for: data, format: format, key: id) else { return }
        if (view.previewItem as? URL) != url { view.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: Coordinator) {
        view.close()
        coordinator.file.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    @MainActor final class Coordinator { let file = QuickLookFile() }
}
