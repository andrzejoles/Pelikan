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

/// Jak `trackChanges`, ale śledzi tylko `read` (dane wejściowe), a `apply` wykonuje poza śledzeniem — odczyty w `apply`
/// (np. stan wszystkich przycisków przy przebudowie) nie wywołują ponownego `apply`. `read` zwraca nil, gdy właściciel
/// zniknął — łańcuch się kończy.
@MainActor
@discardableResult
func trackChanges<Input: Sendable>(of read: @escaping @MainActor () -> Input?, apply: @escaping @MainActor (Input) -> Void) -> ObservationToken {
    let token = ObservationToken()
    trackInput(token, read, apply)
    return token
}

@MainActor
private func trackInput<Input: Sendable>(_ token: ObservationToken, _ read: @escaping @MainActor () -> Input?,
                               _ apply: @escaping @MainActor (Input) -> Void) {
    guard token.active else { return }
    let input = withObservationTracking {
        MainActor.assumeIsolated { read() }
    } onChange: {
        Task { @MainActor in trackInput(token, read, apply) }
    }
    if let input { apply(input) }
}
