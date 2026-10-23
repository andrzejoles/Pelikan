import SwiftUI

extension View {
    /// Przycisk albo menu z samą ikoną: podpowiedź i etykieta VoiceOver z tego samego tekstu (MAC-A11Y-001).
    func iconLabel(_ text: String) -> some View {
        help(text).accessibilityLabel(text)
    }
}
