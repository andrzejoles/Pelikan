import Foundation
import Observation

/// Token śledzenia zmian modelu — śledzenie trwa, dopóki token żyje i nie został anulowany.
final class ObservationToken {
    fileprivate var active = true
    func cancel() { active = false }
}

/// Śledzi właściwości modelu `@Observable` odczytane w `apply` i wywołuje je ponownie po każdej zmianie (na głównym
/// aktorze). Nazwa inna niż `observe`, bo `NSObject` ma metodę KVO o tej nazwie.
/// Ponowne `apply` jest asynchroniczne: flaga ustawiona na czas zmiany modelu z widoku (np. `updating = true … false`)
/// jest już zdjęta, gdy `apply` się wykona — `apply` musi samo rozpoznać, że widok jest aktualny.
@MainActor
@discardableResult
func trackChanges(_ apply: @escaping @MainActor () -> Void) -> ObservationToken {
    let token = ObservationToken()
    track(token, apply)
    return token
}

@MainActor
private func track(_ token: ObservationToken, _ apply: @escaping @MainActor () -> Void) {
    guard token.active else { return }
    withObservationTracking {
        MainActor.assumeIsolated { apply() }
    } onChange: {
        // Token trzymany mocno: śledzenie trwa do `cancel()`. Gdy widok zniknie, `apply` ([weak self]) nie odczyta
        // żadnej właściwości, `withObservationTracking` nic nie zarejestruje i łańcuch kończy się sam.
        Task { @MainActor in track(token, apply) }
    }
}
