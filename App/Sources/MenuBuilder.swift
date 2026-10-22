import AppKit
import PelikanWorkspace

/// Buduje menu główne z rejestru komend (PROMPT §4.2 p.1). Skróty pochodzą z aktywnego profilu (`Workspace.keymap`);
/// dostępność pozycji — z `Workspace.isEnabled`.
final class MenuBuilder: NSObject, NSMenuItemValidation {
    private let workspace: Workspace

    init(workspace: Workspace) {
        self.workspace = workspace
    }

    func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenuItem(appMenu()))
        for category in CommandCategory.allCases {
            let menu = NSMenu(title: category.displayName)
            if category == .edit { addStandardEditItems(to: menu) }
            if category == .window { addStandardWindowItems(to: menu) }
            addCommands(of: category, to: menu)
            if category == .window { NSApp.windowsMenu = menu }
            if category == .help { NSApp.helpMenu = menu }
            guard menu.numberOfItems > 0 else { continue }
            main.addItem(submenuItem(menu))
        }
        return main
    }

    private func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func appMenu() -> NSMenu {
        let name = Bundle.main.object(forInfoDictionaryKey: "PelikanAppName") as? String ?? "Pelikan"
        let menu = NSMenu(title: name)
        menu.addItem(withTitle: L10n.tr("O programie \(name)"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: L10n.tr("Ustawienia…"), action: nil, keyEquivalent: ",")
        settings.isEnabled = false   // Etap 1 (PD-PREF-001)
        menu.addItem(.separator())
        let services = NSMenuItem(title: L10n.tr("Usługi"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.tr("Ukryj \(name)"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(withTitle: L10n.tr("Ukryj pozostałe"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: L10n.tr("Pokaż wszystkie"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.tr("Zakończ \(name)"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func addStandardEditItems(to menu: NSMenu) {
        menu.addItem(withTitle: L10n.tr("Cofnij"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: L10n.tr("Ponów"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.tr("Wytnij"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: L10n.tr("Kopiuj"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: L10n.tr("Wklej"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: L10n.tr("Zaznacz wszystko"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
    }

    private func addStandardWindowItems(to menu: NSMenu) {
        menu.addItem(withTitle: L10n.tr("Minimalizuj"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: L10n.tr("Powiększ"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
    }

    private func addCommands(of category: CommandCategory, to menu: NSMenu) {
        var submenus: [String: NSMenu] = [:]
        for command in workspace.registry.commands where command.descriptor.category == category && command.descriptor.inMenu {
            let d = command.descriptor
            let item = NSMenuItem(title: d.title, action: #selector(performCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = d.id.rawValue
            item.toolTip = d.summary
            if let chord = workspace.keymap.chords(for: d.id).first(where: { Self.keyEquivalent(for: $0) != nil }),
               let (key, mask) = Self.keyEquivalent(for: chord) {
                item.keyEquivalent = key
                item.keyEquivalentModifierMask = mask
            }
            if let sub = d.submenu {
                if submenus[sub] == nil {
                    let m = NSMenu(title: sub)
                    submenus[sub] = m
                    menu.addItem(submenuItem(m))
                }
                submenus[sub]!.addItem(item)
            } else {
                menu.addItem(item)
            }
        }
    }

    @objc func performCommand(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        workspace.perform(CommandID(rawValue: raw))
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let raw = menuItem.representedObject as? String else { return true }
        return workspace.isEnabled(CommandID(rawValue: raw))
    }

    /// Skróty spoza menu (menu pokazuje tylko pierwszy skrót komendy, np. Ctrl+F8; drugi — ⇧⌘↩ — obsługujemy tu).
    /// Zwraca true, gdy zdarzenie wywołało komendę. Tylko w oknie głównym bez arkusza (logowanie, zmienne).
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let window = event.window, window.attachedSheet == nil, !window.isSheet, window.isMainWindow,
              let chord = Self.chord(for: event), let id = workspace.keymap.command(for: chord) else { return false }
        // Pierwszy skrót obsługuje menu (podświetlenie tytułu menu) — tu tylko pozostałe.
        if workspace.keymap.chords(for: id).first(where: { Self.keyEquivalent(for: $0) != nil }) == chord { return false }
        guard workspace.isEnabled(id) else { return false }
        workspace.perform(id)
        return true
    }

    /// NSEvent → KeyChord (nazwy klawiszy jak w opisach komend).
    static func chord(for event: NSEvent) -> KeyChord? {
        var mods: KeyModifiers = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.shift) { mods.insert(.shift) }
        guard let chars = event.charactersIgnoringModifiers, let scalar = chars.unicodeScalars.first else { return nil }
        let key: String
        switch Int(scalar.value) {
        case NSF1FunctionKey...NSF20FunctionKey: key = "f\(Int(scalar.value) - NSF1FunctionKey + 1)"
        case 0x0D, 0x03: key = "enter"
        case 0x1B: key = "escape"
        case 0x09, 0x19: key = "tab"
        case 0x7F, 0x08: key = "backspace"
        case NSDeleteFunctionKey: key = "delete"
        case NSUpArrowFunctionKey: key = "up"
        case NSDownArrowFunctionKey: key = "down"
        case NSLeftArrowFunctionKey: key = "left"
        case NSRightArrowFunctionKey: key = "right"
        case 0x20: key = "space"
        case NSHomeFunctionKey: key = "home"
        case NSEndFunctionKey: key = "end"
        case NSPageUpFunctionKey: key = "pageup"
        case NSPageDownFunctionKey: key = "pagedown"
        case NSInsertFunctionKey, NSHelpFunctionKey: key = "insert"
        default: key = chars.lowercased()
        }
        return KeyChord(key: key, modifiers: mods)
    }

    /// KeyChord → keyEquivalent NSMenuItem (F-klawisze przez NSF1FunctionKey…).
    static func keyEquivalent(for chord: KeyChord) -> (String, NSEvent.ModifierFlags)? {
        var mask: NSEvent.ModifierFlags = []
        if chord.modifiers.contains(.command) { mask.insert(.command) }
        if chord.modifiers.contains(.control) { mask.insert(.control) }
        if chord.modifiers.contains(.option) { mask.insert(.option) }
        if chord.modifiers.contains(.shift) { mask.insert(.shift) }
        let key: String
        switch chord.key {
        case let k where chord.isFunctionKey:
            guard let n = Int(k.dropFirst()), n >= 1, n <= 20,
                  let scalar = UnicodeScalar(NSF1FunctionKey + n - 1) else { return nil }
            key = String(Character(scalar))
        case "enter": key = "\r"
        case "escape": key = "\u{1b}"
        case "tab": key = "\t"
        case "backspace": key = "\u{8}"
        case "delete": key = String(Character(UnicodeScalar(NSDeleteFunctionKey)!))
        case "up": key = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        case "down": key = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        case "left": key = String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        case "right": key = String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        case "space": key = " "
        case "home": key = String(Character(UnicodeScalar(NSHomeFunctionKey)!))
        case "end": key = String(Character(UnicodeScalar(NSEndFunctionKey)!))
        case "pageup": key = String(Character(UnicodeScalar(NSPageUpFunctionKey)!))
        case "pagedown": key = String(Character(UnicodeScalar(NSPageDownFunctionKey)!))
        case "insert": key = String(Character(UnicodeScalar(NSInsertFunctionKey)!))
        default:
            guard chord.key.count == 1 else { return nil }
            key = chord.key
        }
        return (key, mask)
    }
}
