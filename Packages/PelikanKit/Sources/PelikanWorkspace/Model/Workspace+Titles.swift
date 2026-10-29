import Foundation

extension Workspace {
    /// Tytuł okna głównego (PD-UI-009): nazwa aplikacji, połączenie główne i workset (inny niż domyślny).
    public func windowTitle(appName: String) -> String {
        var parts = [appName]
        if let c = sessions.mainConnectionID.flatMap({ connections.connection($0) }) { parts.append(c.displayName) }
        if worksets.current != WorksetStore.defaultName { parts.append(worksets.current) }
        return parts.joined(separator: " — ")
    }

    /// Podtytuł: okno aktywne, a gdy ma inne połączenie niż główne — także jego nazwa (nazwa bazy w tytule okna).
    public func windowSubtitle() -> String {
        guard let d = activeDocument else { return "" }
        if let c = effectiveConnection(of: d), c != sessions.mainConnectionID, let def = connections.connection(c) {
            return d.fullTitle + " @ " + def.displayName
        }
        return d.fullTitle
    }

    /// Katalog startowy okien wyboru pliku dla rodzaju (PD-PREF-006): z Preferencji, potem katalog projektu.
    public func startDirectory(for key: String) -> URL? {
        if let p = settings.startDirectories[key], !p.isEmpty {
            let u = URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue { return u }
        }
        return projectURL?.deletingLastPathComponent()
    }

    /// Rodzaj okna dla pliku z rozszerzeniami z Preferencji (programy, testy) i domyślnymi.
    public func documentKind(for url: URL) -> DocumentKind {
        let ext = url.pathExtension.lowercased()
        if settings.programExtensions.contains(ext) || settings.specBodyExtensions.all.contains(ext) { return .program }
        if settings.testExtensions.contains(ext) { return .test }
        return DocumentKind.forFile(url)
    }
}
