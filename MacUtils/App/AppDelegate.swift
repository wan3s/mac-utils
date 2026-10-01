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
        #endif
    }

    #if DEBUG
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
