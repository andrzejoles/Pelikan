import AppKit
import PelikanWorkspace

/// PROTOTYP kolorowych ikon (gałąź proto/kolorowe-ikony): styl z `PELIKAN_ICON_STYLE` (color | accent | mono, domyślnie
/// mono). Docelowo: ustawienie Wyglądu.
enum IconStyle: String {
    case mono, accent, color

    static let current: IconStyle = ProcessInfo.processInfo.environment["PELIKAN_ICON_STYLE"].flatMap(IconStyle.init(rawValue:)) ?? .mono

    /// Kolor ikony komendy w bieżącym stylu (nil — jak etykieta).
    static func color(for id: String) -> NSColor? {
        let tint = CommandTint.tint(for: id)
        switch current {
        case .mono: return nil
        case .accent: return tint.isAccent ? tint.nsColor : nil
        case .color: return tint.nsColor
        }
    }
}

extension CommandTint {
    /// Barwy systemowe macOS — same dopasowują się do trybu jasnego, ciemnego i zwiększonego kontrastu.
    var nsColor: NSColor? {
        switch self {
        case .run: .systemGreen
        case .stop: .systemRed
        case .revert: .systemOrange
        case .document: .systemBlue
        case .debug: .systemPurple
        case .data: .systemTeal
        case .insight: .systemPink
        case .ai: .systemMint
        case .mark: .systemYellow
        case .neutral: nil
        }
    }
}
