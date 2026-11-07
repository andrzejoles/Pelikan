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
        let dir = Self.directory
        let file = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension(format.fileExtension)
        writing = Task { [weak self] in
            let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
                // Katalog główny i katalog procesu tylko dla użytkownika (wartości z bazy).
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: QuickLookFile.root.path)
                return FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600])
            }.value
            guard let self, !Task.isCancelled, self.key == key else { try? FileManager.default.removeItem(at: file); return }
            // Nieudany zapis (brak miejsca, uprawnienia) — bez klucza, żeby następne odświeżenie spróbowało ponownie.
            guard ok else { self.key = nil; return }
            self.url = file
            ready(file)
        }
    }

    nonisolated static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-preview", isDirectory: true)
    }

    /// Katalog podglądów tego procesu (druga uruchomiona kopia aplikacji ma własny).
    nonisolated static var directory: URL {
        root.appendingPathComponent(String(ProcessInfo.processInfo.processIdentifier), isDirectory: true)
    }

    /// Start aplikacji: pliki podglądów po awarii albo wymuszonym zamknięciu (treść z bazy nie zostaje na dysku) —
    /// katalogi procesów, które już nie działają.
    nonisolated static func removeStaleFiles() {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
            guard let pid = Int32(name), pid != ProcessInfo.processInfo.processIdentifier, kill(pid, 0) != 0 else { continue }
            try? fm.removeItem(at: root.appendingPathComponent(name))
        }
    }

    /// Widok podglądu z tymi samymi ustawieniami w panelu wartości i w Large Data Editor.
    static func makeView() -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal)!
        v.autostarts = true
        return v
    }

    /// Treść w widoku: plik zapisany w tle, przypisany po zapisie (bez ponownego ładowania tego samego pliku).
    func show(_ data: Data, format: LargeDataFormat, key: String, in view: QLPreviewView) {
        // Nowa treść: poprzedni podgląd znika od razu (jego plik jest usuwany) — do zapisu nowego pliku widok pusty.
        if key != self.key { view.previewItem = nil }
        prepare(data, format: format, key: key) { [weak view] url in
            guard let view, (view.previewItem as? URL) != url else { return }
            view.previewItem = url as NSURL
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

    func makeNSView(context: Context) -> QLPreviewView { QuickLookFile.makeView() }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        context.coordinator.file.show(data, format: format, key: id, in: view)
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: Coordinator) {
        view.close()
        coordinator.file.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    @MainActor final class Coordinator { let file = QuickLookFile() }
}
