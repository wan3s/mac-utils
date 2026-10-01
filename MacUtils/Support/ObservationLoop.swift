import Observation

/// Runs `body` now and again every time an observable property it read changes.
/// Lets AppKit controllers react to `@Observable` models the way SwiftUI views do.
@MainActor
func observeChanges(_ body: @escaping @MainActor () -> Void) {
    withObservationTracking {
        body()
    } onChange: {
        Task { @MainActor in observeChanges(body) }
    }
}
