import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // `delegate` is a weak reference on NSApplication; keep ours alive for the app's lifetime.
    withExtendedLifetime(delegate) {
        app.run()
    }
}
