import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let loginItem = LoginItem()
    private lazy var network = NetworkMonitor(settings: settings)
    private lazy var system = SystemMonitor(settings: settings)
    private var statusItem: StatusItemController?
    private var widget: DesktopWidgetController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()

        let actions = AppActions(
            openSettings: { [weak self] pane in self?.showSettings(pane) },
            quit: { NSApp.terminate(nil) }
        )
        network.start()
        statusItem = StatusItemController(network: network, settings: settings, actions: actions)
        widget = DesktopWidgetController(monitor: system, settings: settings, actions: actions)
        #if DEBUG
        recordSnapshotsIfRequested()
        runDragTestIfRequested()
        #endif
    }

    #if DEBUG
    /// `MacUtils -dragTest YES` drags the widget with synthetic events and prints the outcome.
    private func runDragTestIfRequested() {
        guard UserDefaults.standard.bool(forKey: "dragTest"), let widget else { return }
        func report(_ label: String) {
            NSLog("%@ frame: %@ placement: %@ saved: %@ locked: %d", label, NSStringFromRect(widget.window.frame),
                  settings.widgetPlacement.rawValue, settings.widgetTopLeft.map { "\($0)" } ?? "nil", settings.widgetLocked)
        }
        let steps: [(String, () -> Void)] = [
            ("start", {}),
            ("drag -300,-200", { widget.simulateDrag(by: CGVector(dx: -300, dy: -200)) }),
            ("drag +5000,+5000 (clamped)", { widget.simulateDrag(by: CGVector(dx: 5000, dy: 5000)) }),
            ("lock + drag -400,0 (no move)", {
                self.settings.widgetLocked = true
                DispatchQueue.main.async { widget.simulateDrag(by: CGVector(dx: -400, dy: 0)) }
            }),
            ("unlock", { self.settings.widgetLocked = false }),
        ]
        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3 + Double(index)) {
                step.1()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { report(step.0) }
            }
        }
    }

    private func recordSnapshotsIfRequested() {
        let panes: [(String, SettingsPane)] = [("settings-general", .general), ("settings-menubar", .menuBar), ("settings-widget", .widget)]
        SnapshotRecorder.run(after: 4, steps: [
            ("widget", { [weak self] in self?.widget?.window }),
            ("statusitem", { [weak self] in self?.statusItem?.buttonWindow }),
            ("popover", { [weak self] in self?.statusItem?.showPopoverForSnapshot() }),
        ] + panes.map { name, pane in
            (name, { [weak self] in
                self?.statusItem?.closePopover()
                self?.showSettings(pane)
                return self?.settingsWindow?.window
            })
        })
    }
    #endif

    /// Opening the app again from Finder or Spotlight shows Settings, since there is no Dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(.general)
        return false
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        showSettings(.general)
    }

    private func showSettings(_ pane: SettingsPane) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings, monitor: system, loginItem: loginItem)
        }
        settingsWindow?.show(pane)
    }
}
