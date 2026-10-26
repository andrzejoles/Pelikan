import SwiftUI

extension View {
    /// Przycisk albo menu z samą ikoną: podpowiedź i etykieta VoiceOver z tego samego tekstu (MAC-A11Y-001).
    func iconLabel(_ text: String) -> some View {
        help(text).accessibilityLabel(text)
    }
}

extension View {
    /// Rozmiar startowy okna albo arkusza z SwiftUI, które da się powiększać (D177): podany rozmiar jest minimalnym
    /// i początkowym, bez górnej granicy.
    func windowSize(width: CGFloat, height: CGFloat) -> some View {
        frame(minWidth: width, idealWidth: width, maxWidth: .infinity, minHeight: height, idealHeight: height, maxHeight: .infinity)
    }
}
