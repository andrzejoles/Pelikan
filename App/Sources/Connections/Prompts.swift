import AppKit
import PelikanWorkspace

/// Pytania menedżera sesji: hasło (z „Zapamiętaj”) i nowe hasło po ORA-28001.
@MainActor
final class ConnectionPrompts: ConnectionPrompter {
    weak var window: NSWindow?

    func askPassword(for connection: ConnectionDefinition, reason: String?) async -> (password: String, remember: Bool)? {
        let alert = NSAlert()
        alert.messageText = L10n.tr("Hasło dla \(connection.displayName)")
        alert.informativeText = reason ?? L10n.tr("Podaj hasło użytkownika bazy.")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 28, width: 300, height: 24))
        let remember = NSButton(checkboxWithTitle: L10n.tr("Zapamiętaj w Pęku kluczy"), target: nil, action: nil)
        remember.frame = NSRect(x: 0, y: 0, width: 300, height: 20)
        remember.state = connection.savePassword ? .on : .off
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 54))
        box.addSubview(field)
        box.addSubview(remember)
        alert.accessoryView = box
        alert.addButton(withTitle: L10n.tr("Połącz"))
        alert.addButton(withTitle: L10n.tr("Anuluj"))
        alert.window.initialFirstResponder = field
        let response = await run(alert)
        guard response == .alertFirstButtonReturn else { return nil }
        return (field.stringValue, remember.state == .on)
    }

    func askNewPassword(for connection: ConnectionDefinition, message: String) async -> String? {
        let alert = NSAlert()
        alert.messageText = L10n.tr("Hasło wygasło — \(connection.displayName)")
        alert.informativeText = message + "\n" + L10n.tr("Podaj nowe hasło (dwa razy).")
        let first = NSSecureTextField(frame: NSRect(x: 0, y: 30, width: 300, height: 24))
        let second = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        first.placeholderString = L10n.tr("Nowe hasło")
        second.placeholderString = L10n.tr("Powtórz nowe hasło")
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 54))
        box.addSubview(first)
        box.addSubview(second)
        alert.accessoryView = box
        alert.addButton(withTitle: L10n.tr("Zmień hasło"))
        alert.addButton(withTitle: L10n.tr("Anuluj"))
        alert.window.initialFirstResponder = first
        while true {
            let response = await run(alert)
            guard response == .alertFirstButtonReturn else { return nil }
            if !first.stringValue.isEmpty, first.stringValue == second.stringValue { return first.stringValue }
            alert.informativeText = L10n.tr("Hasła się różnią albo są puste. Spróbuj ponownie.")
        }
    }

    private func run(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        // Arkusz na najgłębszym otwartym arkuszu (np. nad oknem logowania) — inaczej czekałby w kolejce za nim.
        var target = window
        while let sheet = target?.attachedSheet { target = sheet }
        if let window = target {
            return await withCheckedContinuation { cont in
                alert.beginSheetModal(for: window) { cont.resume(returning: $0) }
            }
        }
        return alert.runModal()
    }
}
