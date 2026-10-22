import Foundation

/// Własne skróty (UG 23.29 Key Configuration): nadpisania zapisywane w ustawieniach jako „skrót → komenda”
/// (pusta komenda usuwa domyślne przypisanie z profilu).
extension Workspace {
    /// Domyślna komenda skrótu w bieżącym profilu (bez nadpisań).
    public func defaultCommand(for chord: KeyChord) -> CommandID? {
        Keymap(commands: registry.descriptors, profile: settings.shortcutProfile).command(for: chord)
    }

    /// Komenda, która ma teraz ten skrót (konflikt przy przypisywaniu).
    public func conflictingCommand(for chord: KeyChord, assigning id: CommandID) -> CommandID? {
        guard let owner = keymap.command(for: chord), owner != id else { return nil }
        return owner
    }

    /// Przypisuje skrót komendzie (zastępuje dotychczasowego właściciela skrótu).
    public func assignShortcut(_ chord: KeyChord, to id: CommandID) {
        var o = settings.keyOverrides
        o[chord.description] = defaultCommand(for: chord) == id ? nil : id.rawValue
        settings.keyOverrides = o
    }

    /// Usuwa skrót (także domyślny z profilu).
    public func removeShortcut(_ chord: KeyChord) {
        var o = settings.keyOverrides
        o[chord.description] = defaultCommand(for: chord) == nil ? nil : ""
        settings.keyOverrides = o
    }

    /// Przywraca domyślne skróty komendy (albo wszystkich, gdy nil).
    public func resetShortcuts(for id: CommandID? = nil) {
        guard let id else { settings.keyOverrides = [:]; return }
        let defaults = Keymap(commands: registry.descriptors, profile: settings.shortcutProfile)
        settings.keyOverrides = settings.keyOverrides.filter { chord, target in
            guard let c = KeyChord(string: chord) else { return false }
            return target != id.rawValue && !(target.isEmpty && defaults.command(for: c) == id)
        }
    }
}
