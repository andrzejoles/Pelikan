import Foundation

/// Krok makra (UG 25.11): komenda z rejestru, wpisany tekst albo usunięcie znaków przed kursorem.
public enum MacroStep: Sendable, Codable, Hashable {
    case command(CommandID, CommandArguments)
    case text(String)
    case deleteBackward(Int)
}

extension CommandArguments: Codable {
    public init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode([String: JSONValue].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(values)
    }
}

/// Makro w bibliotece: nazwa, opcjonalny skrót klawiszowy (np. `ctrl+shift+1`) i kroki.
public struct Macro: Sendable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var key: String?
    public var steps: [MacroStep]

    public init(id: UUID = UUID(), name: String, key: String? = nil, steps: [MacroStep]) {
        self.id = id; self.name = name; self.key = key; self.steps = steps
    }

    /// Identyfikator komendy odtwarzającej makro z biblioteki (skrót klawiszowy, menu, paleta).
    public var commandID: CommandID { CommandID(rawValue: "edit.macro." + id.uuidString.prefix(8).lowercased()) }
}

/// Nagrywanie makra: komendy użytkownika zmieniające edytor albo interfejs oraz wpisywany tekst. Kolejne znaki
/// wpisywane po sobie łączą się w jeden krok tekstu, kolejne usunięcia — w jeden krok usuwania.
public final class MacroRecorder {
    public private(set) var steps: [MacroStep] = []

    public init() {}

    public func record(_ step: MacroStep) {
        switch (steps.last, step) {
        case (.text(let a)?, .text(let b)):
            steps[steps.count - 1] = .text(a + b)
        case (.deleteBackward(let a)?, .deleteBackward(let b)):
            steps[steps.count - 1] = .deleteBackward(a + b)
        case (.text(let a)?, .deleteBackward(let n)) where n <= a.count:
            // Poprawka literówki w trakcie nagrywania — skraca ostatni tekst zamiast osobnego kroku.
            let rest = String(a.dropLast(n))
            if rest.isEmpty { steps.removeLast() } else { steps[steps.count - 1] = .text(rest) }
        default:
            steps.append(step)
        }
    }
}

/// Biblioteka makr (`macros.json` w katalogu danych).
public struct MacroLibrary: Sendable, Codable, Hashable {
    public var macros: [Macro] = []

    public init(macros: [Macro] = []) { self.macros = macros }

    static func url(_ dir: URL?) -> URL? { dir?.appendingPathComponent("macros.json") }

    public static func load(from dir: URL?) -> MacroLibrary {
        guard let url = url(dir), let data = try? Data(contentsOf: url),
              let lib = try? JSONDecoder.pelikan.decode(MacroLibrary.self, from: data) else { return MacroLibrary() }
        return lib
    }

    public func save(to dir: URL?) {
        guard let dir, let url = Self.url(dir) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let data = try? JSONEncoder.pelikan.encode(self) {
            try? data.write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}

extension Workspace {
    /// Komendy nienagrywane: same makra (nagrywanie w nagrywaniu, odtwarzanie w odtwarzaniu).
    static func isMacroCommand(_ id: CommandID) -> Bool { id.rawValue.hasPrefix("edit.macro") }

    /// Rejestracja wywołania w nagrywanym makrze (tylko komendy użytkownika zmieniające edytor albo interfejs — D-EDYTOR-1).
    func recordMacroInvocation(_ record: CommandInvocationRecord) {
        guard let r = macroRecorder, !isPlayingMacro, record.invoker == .user, case .success = record.outcome, !Self.isMacroCommand(record.command),
              let c = registry.command(record.command), [.modifiesEditor, .uiState].contains(c.descriptor.effect) else { return }
        r.record(.command(record.command, record.arguments))
    }

    /// Tekst wpisany w edytorze (wywołuje edytor aplikacji).
    public func recordTyping(_ text: String) {
        guard !text.isEmpty, !isPlayingMacro else { return }
        macroRecorder?.record(.text(text))
    }

    /// Usunięcie znaku przed kursorem w edytorze (Backspace).
    public func recordDeleteBackward() {
        guard !isPlayingMacro else { return }
        macroRecorder?.record(.deleteBackward(1))
    }

    public var isRecordingMacro: Bool { macroRecorder != nil }

    /// Rozpoczyna albo kończy nagrywanie; po zakończeniu nagranie staje się bieżącym makrem (F12).
    @discardableResult
    public func toggleMacroRecording() -> Bool {
        if let r = macroRecorder {
            macroRecorder = nil
            if !r.steps.isEmpty { currentMacro = Macro(name: L10n.tr("Ostatnie nagranie"), steps: r.steps) }
            return false
        }
        macroRecorder = MacroRecorder()
        return true
    }

    /// Odtwarza kroki makra w aktywnym oknie (komendy przez `invoke`, tekst w miejscu zaznaczenia).
    public func play(_ macro: Macro, times: Int = 1) async throws {
        isPlayingMacro = true
        defer { isPlayingMacro = false }
        for _ in 0..<max(1, times) {
            for step in macro.steps {
                switch step {
                case .command(let id, let args):
                    guard !Self.isMacroCommand(id) else { continue }
                    try await invoke(id, args)
                case .text(let t):
                    try insertInEditor(t)
                case .deleteBackward(let n):
                    guard let d = BuiltinCommands.editable(self) else { throw CommandError.notAvailable(L10n.tr("Brak okna z edytorem")) }
                    let len = (d.text as NSString).length
                    var sel = min(d.selectedRange.lowerBound, len)..<min(d.selectedRange.upperBound, len)
                    if sel.isEmpty { sel = max(0, sel.lowerBound - n)..<sel.lowerBound }
                    d.text = (d.text as NSString).replacingCharacters(in: NSRange(location: sel.lowerBound, length: sel.count), with: "")
                    d.selectedRange = sel.lowerBound..<sel.lowerBound
                }
            }
        }
    }

    /// Zapis biblioteki makr i odświeżenie komend makr ze skrótami.
    public func updateMacros(_ library: MacroLibrary) {
        let removed = macroLibrary.macros.map(\.commandID).filter { id in !library.macros.contains { $0.commandID == id } }
        macroLibrary = library
        library.save(to: dataDirectory)
        unregister(removed)
        registerMacroCommands()
    }

    /// Komendy `edit.macro.<id>` dla makr biblioteki (menu Edycja › Makra, paleta, skróty). Skrót zajęty przez inną
    /// komendę jest pomijany.
    func registerMacroCommands() {
        var commands: [Command] = []
        for m in macroLibrary.macros {
            var key: [String] = []
            if let k = m.key, let chord = KeyChord(string: k), keymap.command(for: chord).map({ Self.isMacroCommand($0) }) ?? true { key = [k] }
            let macro = m
            commands.append(Command(CommandDescriptor(id: m.commandID, title: L10n.tr("Makro: \(m.name)"), category: .edit, submenu: L10n.tr("Makra"),
                                                      pd: key, mac: key, agent: .none, effect: .modifiesEditor,
                                                      summary: L10n.tr("Odtwarza makro „\(m.name)” z biblioteki (\(m.steps.count) kroków)."), feature: "PD-EDIT-015"),
                                    validate: { BuiltinCommands.editable($0) != nil }) { ctx in
                try await ctx.workspace.play(macro)
                return .ok
            })
        }
        register(commands)
    }
}
