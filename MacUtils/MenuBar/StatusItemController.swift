import AppKit
import SwiftUI

/// Owns the menu bar item: the flag + speed label, the details popover and the right-click menu.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    fileprivate let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    fileprivate let popover = NSPopover()
    private let network: NetworkMonitor
    private let settings: AppSettings
    private let actions: AppActions

    init(network: NetworkMonitor, settings: AppSettings, actions: AppActions) {
        self.network = network
        self.settings = settings
        self.actions = actions
        super.init()

        popover.behavior = .transient
        popover.delegate = self

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let label = ClickThroughHostingView(rootView: StatusItemLabel(network: network, settings: settings))
        label.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            label.topAnchor.constraint(equalTo: button.topAnchor),
            label.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])

        observeChanges { [weak self] in
            guard let self else { return }
            self.statusItem.length = StatusItemLabel.width(settings: self.settings)
        }
        observeChanges { [weak self] in
            self?.updateAccessibility()
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(from: sender)
        } else {
            togglePopover(from: sender)
        }
    }

    fileprivate func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // A fresh view per opening, so nothing renders while the popover is closed.
        let content = NetworkPopoverView(network: network, settings: settings, actions: actions) { [weak self] in
            self?.popover.performClose(nil)
        }
        let host = NSHostingController(rootView: content)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
    }

    private func showMenu(from button: NSStatusBarButton) {
        popover.performClose(nil)
        let menu = NSMenu()
        let settingsItem = menu.addItem(withTitle: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: String(localized: "Quit Mac Utils"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func openSettings() { actions.openSettings(.general) }
    @objc private func quit() { actions.quit() }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
        popover.contentViewController = nil
    }

    private func updateAccessibility() {
        let location = network.geo?.countryName ?? String(localized: "Location unknown")
        let download = Format.speed(network.downloadRate, unit: settings.speedUnit)
        let upload = Format.speed(network.uploadRate, unit: settings.speedUnit)
        statusItem.button?.setAccessibilityLabel(
            String(format: String(localized: "%@, download %@, upload %@"), location, download, upload)
        )
    }
}

#if DEBUG
extension StatusItemController {
    func showPopoverForSnapshot() -> NSWindow? {
        guard let button = statusItem.button else { return nil }
        if !popover.isShown { togglePopover(from: button) }
        return popover.contentViewController?.view.window
    }

    var buttonWindow: NSWindow? { statusItem.button?.window }

    func closePopover() {
        popover.performClose(nil)
    }
}
#endif

/// Hosting view that lets clicks fall through to the status bar button underneath.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The menu bar label: the exit-country flag next to upload and download speeds stacked vertically.
struct StatusItemLabel: View {
    let network: NetworkMonitor
    let settings: AppSettings

    private static let speedFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
    private static let flagWidth: CGFloat = 18
    private static let spacing: CGFloat = 4
    private static let padding: CGFloat = 5

    /// Width of the widest possible speed line, so the item never changes width as values change.
    static func speedsWidth(unit: SpeedUnit) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: speedFont]
        let widest = Format.speedUnits(unit)
            .map { ("↓ 999 \($0)" as NSString).size(withAttributes: attributes).width }
            .max() ?? 50
        return ceil(widest) + 2
    }

    static func width(settings: AppSettings) -> CGFloat {
        var width = padding * 2
        if settings.showFlag { width += flagWidth }
        if settings.showSpeeds { width += speedsWidth(unit: settings.speedUnit) }
        if settings.showFlag && settings.showSpeeds { width += spacing }
        return width
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            if settings.showFlag || !settings.showSpeeds {
                flag.frame(width: Self.flagWidth)
            }
            if settings.showSpeeds {
                speeds
            }
        }
        .padding(.horizontal, Self.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var flag: some View {
        if network.local.isOnline, let flag = network.geo?.flag {
            Text(flag).font(.system(size: 14))
        } else {
            Image(systemName: "globe").font(.system(size: 13, weight: .medium))
        }
    }

    private var speeds: some View {
        VStack(spacing: -1) {
            speedLine("↑", network.uploadRate)
            speedLine("↓", network.downloadRate)
        }
        .font(Font(Self.speedFont))
        .frame(width: Self.speedsWidth(unit: settings.speedUnit))
    }

    private func speedLine(_ arrow: String, _ rate: Double) -> some View {
        HStack(spacing: 0) {
            Text(arrow)
            Spacer(minLength: 2)
            Text(Format.speed(rate, unit: settings.speedUnit))
        }
        .lineLimit(1)
    }
}
