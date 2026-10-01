import AppKit
import SwiftUI

/// The Settings window (⌘,) with toolbar-style panes, as macOS apps conventionally present it.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let tabs = SettingsTabViewController()

    init(settings: AppSettings, monitor: SystemMonitor, loginItem: LoginItem) {
        tabs.tabStyle = .toolbar
        tabs.addPane(GeneralSettingsView(settings: settings, loginItem: loginItem),
                     title: String(localized: "General"), symbol: "gearshape")
        tabs.addPane(MenuBarSettingsView(settings: settings),
                     title: String(localized: "Menu Bar"), symbol: "menubar.rectangle")
        tabs.addPane(WidgetSettingsView(settings: settings, monitor: monitor),
                     title: String(localized: "Widget"), symbol: "gauge.with.dots.needle.33percent")

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.setFrameAutosaveName("SettingsWindow")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ pane: SettingsPane) {
        tabs.selectedTabViewItemIndex = pane.rawValue
        if window?.isVisible != true { window?.center() }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class SettingsTabViewController: NSTabViewController {
    func addPane(_ view: some View, title: String, symbol: String) {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let controller = tabViewItem?.viewController, let window = view.window else { return }
        window.title = controller.title ?? ""
        // Resize to the pane, keeping the title bar where it is.
        let size = controller.view.fittingSize
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        let origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(NSRect(origin: origin, size: frame.size), display: true, animate: window.isVisible)
    }
}
