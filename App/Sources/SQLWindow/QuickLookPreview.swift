import AppKit
import PelikanWorkspace
import Quartz
import SwiftUI
import Synchronization

/// Plik tymczasowy podglądu Quick Look (QLPreviewView pokazuje plik, nie dane w pamięci): właściwe rozszerzenie
/// z rozpoznanego formatu, prawa tylko dla użytkownika, usuwany przy zmianie treści i zamknięciu widoku. Zapis poza
/// wątkiem głównym (wartość może mieć setki MB).
@MainActor
final class QuickLookFile {
    private(set) var url: URL?
    private var key: String?
    /// Klucz bieżącej treści (zapisanej albo zapisywanej).
    var currentKey: String? { key }
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
        let name = UUID().uuidString + "." + format.fileExtension
        writing = Task { [weak self] in
            // Plik 0600 od chwili utworzenia (PrivateFile, D186) w katalogu procesu 0700; inny system plików — bez podglądu.
            let file = await Task.detached(priority: .userInitiated) { () -> URL? in
                guard let dir = QuickLookFile.processDirectory() else { return nil }
                let file = dir.appendingPathComponent(name)
                guard (try? PrivateFile.write(data, to: file)) == true else { try? FileManager.default.removeItem(at: file); return nil }
                return file
            }.value
            guard let self, !Task.isCancelled, self.key == key else {
                if let file { try? FileManager.default.removeItem(at: file) }
                return
            }
            // Nieudany zapis (brak miejsca, uprawnienia) — bez klucza, żeby następne odświeżenie spróbowało ponownie.
            guard let file else { self.key = nil; return }
            self.url = file
            ready(file)
        }
    }

    nonisolated static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pelikan-preview", isDirectory: true)
    }

    /// Katalog podglądów tego uruchomienia (0700) z plikiem blokady trzymanym do końca procesu (`flock`): druga kopia
    /// aplikacji ma własny, a katalog po awarii rozpoznaje się po zwolnionej blokadzie (bez zgadywania po numerze
    /// procesu, który system mógł już przydzielić innemu programowi). Katalog usunięty w trakcie pracy (sprzątanie
    /// katalogu tymczasowego przy wielodniowej pracy) — odtworzony z nową blokadą. nil — katalogu nie da się utworzyć.
    nonisolated static func processDirectory() -> URL? {
        directoryState.withLock { state -> URL? in
            let fm = FileManager.default
            if let dir = state.url, fm.fileExists(atPath: dir.appendingPathComponent(".lock").path) { return dir }
            if state.lock >= 0 { close(state.lock); state.lock = -1 }
            state.url = nil
            try? fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            _ = chmod(root.path, 0o700)
            let dir = root.appendingPathComponent("\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString.prefix(8))", isDirectory: true)
            guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])) != nil else { return nil }
            let fd = open(dir.appendingPathComponent(".lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            guard fd >= 0, flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                if fd >= 0 { close(fd) }
                try? fm.removeItem(at: dir)
                return nil
            }
            state.url = dir
            state.lock = fd     // deskryptor otwarty do końca procesu (albo odtworzenia katalogu) — trzyma blokadę
            return dir
        }
    }

    private nonisolated static let directoryState = Mutex<(url: URL?, lock: Int32)>((nil, -1))

    /// Start aplikacji: katalogi podglądów po awarii albo wymuszonym zamknięciu (treść z bazy nie zostaje na dysku) —
    /// te, których blokady nikt nie trzyma. W tle (pliki mogą mieć setki MB).
    nonisolated static func removeStaleFiles() {
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            for name in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] {
                let dir = root.appendingPathComponent(name)
                let fd = open(dir.appendingPathComponent(".lock").path, O_RDWR | O_CLOEXEC)
                // Katalog innej kopii aplikacji tworzony właśnie teraz (blokada jeszcze niezałożona) — pominięty.
                if let m = (try? fm.attributesOfItem(atPath: dir.path))?[.modificationDate] as? Date, Date().timeIntervalSince(m) < 60 {
                    if fd >= 0 { close(fd) }
                    continue
                }
                if fd >= 0 {
                    let free = flock(fd, LOCK_EX | LOCK_NB) == 0
                    close(fd)
                    guard free else { continue }
                }
                try? fm.removeItem(at: dir)
            }
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
