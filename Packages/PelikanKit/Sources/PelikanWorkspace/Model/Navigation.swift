import Foundation

/// Punkt historii skoków (UG 25.20): okno i pozycja kursora.
public struct NavigationPoint: Sendable, Hashable {
    public var document: DocumentID
    public var offset: Int
}

extension Workspace {
    /// Zapamiętuje bieżącą pozycję przed skokiem (przejście do deklaracji, otwarcie obiektu, błąd, Zawartość kodu).
    public func recordJump() {
        guard let d = activeDocument else { return }
        let p = NavigationPoint(document: d.id, offset: d.selectedRange.lowerBound)
        if navigationBack.last != p { navigationBack.append(p) }
        if navigationBack.count > 100 { navigationBack.removeFirst() }
        navigationForward.removeAll()
    }

    /// Wstecz (`back: true`) albo naprzód; pomija punkty zamkniętych okien. false — brak dokąd.
    @discardableResult
    func navigate(back: Bool) -> Bool {
        while let p = back ? navigationBack.popLast() : navigationForward.popLast() {
            guard let doc = documents.first(where: { $0.id == p.document }) else { continue }
            if let cur = activeDocument {
                let here = NavigationPoint(document: cur.id, offset: cur.selectedRange.lowerBound)
                if back { navigationForward.append(here) } else { navigationBack.append(here) }
            }
            activate(doc.id)
            let o = min(p.offset, (doc.text as NSString).length)
            doc.selectedRange = o..<o
            return true
        }
        return false
    }
}

enum NavigationCommands {
    @MainActor static var all: [Command] {
        [
            Command(CommandDescriptor(id: "edit.navigateBack", title: L10n.tr("Wstecz"), category: .edit, submenu: L10n.tr("Nawigacja"),
                                      pd: ["ctrl+alt+left"], mac: ["ctrl+cmd+left"], agent: .full, effect: .uiState,
                                      summary: L10n.tr("Wraca do pozycji sprzed ostatniego skoku (deklaracja, obiekt, błąd)."), feature: "PD-CA-013"),
                    validate: { !$0.navigationBack.isEmpty }) { ctx in
                ctx.workspace.navigate(back: true) ? .ok : CommandResult(message: L10n.tr("Brak wcześniejszych pozycji"))
            },
            Command(CommandDescriptor(id: "edit.navigateForward", title: L10n.tr("Naprzód"), category: .edit, submenu: L10n.tr("Nawigacja"),
                                      pd: ["ctrl+alt+right"], mac: ["ctrl+cmd+right"], agent: .full, effect: .uiState,
                                      summary: L10n.tr("Przechodzi do pozycji, z której wrócono poleceniem Wstecz."), feature: "PD-CA-013"),
                    validate: { !$0.navigationForward.isEmpty }) { ctx in
                ctx.workspace.navigate(back: false) ? .ok : CommandResult(message: L10n.tr("Brak dalszych pozycji"))
            },
        ]
    }
}
