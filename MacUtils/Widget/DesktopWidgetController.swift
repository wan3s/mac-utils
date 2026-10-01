import AppKit
import SwiftUI

/// Borderless panel that sits on the desktop: above the wallpaper and icons, below app windows.
private final class DesktopWidgetPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that starts a window drag on mouse down when dragging is allowed.
private final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    var isDraggable = false
    var onDragEnded: (() -> Void)?
    var onSizeChange: ((CGSize) -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        // SwiftUI calls this whenever the content's ideal size changes; let the controller resize the panel.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onSizeChange?(self.fittingSize)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isDraggable, let window {
            // Runs its own tracking loop and returns once the mouse is released.
            window.performDrag(with: event)
            onDragEnded?()
        } else {
            super.mouseDown(with: event)
        }
    }
}

/// Shows the system monitor widget and keeps its position, look and sampling in sync with settings.
@MainActor
final class DesktopWidgetController: NSObject {
    private static let screenMargin: CGFloat = 20

    private let panel = DesktopWidgetPanel()
    private let hostingView: DraggableHostingView<DesktopWidgetView>
    private let monitor: SystemMonitor
    private let settings: AppSettings
    private var contentSize: CGSize = .zero
    private var appliedScreenID: UInt32?

    init(monitor: SystemMonitor, settings: AppSettings, actions: AppActions) {
        self.monitor = monitor
        self.settings = settings
        hostingView = DraggableHostingView(rootView: DesktopWidgetView(monitor: monitor, settings: settings, actions: actions))
        super.init()

        hostingView.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hostingView
        contentSize = hostingView.fittingSize
        hostingView.onDragEnded = { [weak self] in self?.dragEnded() }
        hostingView.onSizeChange = { [weak self] size in self?.contentSizeChanged(size) }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )

        observeChanges { [weak self] in self?.applyVisibility() }
        observeChanges { [weak self] in self?.applyAppearance() }
        observeChanges { [weak self] in self?.applyPosition() }
    }

    var window: NSWindow { panel }

    // MARK: Settings → window

    private func applyVisibility() {
        let visible = settings.widgetVisible
        let interval = settings.widgetInterval
        if visible {
            monitor.start(interval: interval)
            panel.orderFront(nil)
        } else {
            monitor.stop()
            panel.orderOut(nil)
        }
    }

    private func applyAppearance() {
        switch settings.widgetTheme {
        case .system: panel.appearance = nil
        case .light: panel.appearance = NSAppearance(named: .aqua)
        case .dark: panel.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func applyPosition() {
        let placement = settings.widgetPlacement
        let screenID = settings.widgetScreenID
        let locked = settings.widgetLocked
        hostingView.isDraggable = placement == .free && !locked
        let screen = Self.screen(for: screenID)
        let screenChanged = appliedScreenID != nil && appliedScreenID != screenID
        appliedScreenID = screenID

        let topLeft: CGPoint
        if placement == .free {
            if !screenChanged, let saved = settings.widgetTopLeft, Self.isOnScreen(saved) {
                topLeft = saved
            } else {
                topLeft = Self.cornerTopLeft(.topRight, size: contentSize, on: screen)
            }
        } else {
            topLeft = Self.cornerTopLeft(placement, size: contentSize, on: screen)
        }
        setFrame(topLeft: topLeft)
    }

    private func contentSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != contentSize else { return }
        contentSize = size
        if settings.widgetPlacement == .free {
            // Grow and shrink downward from the top-left corner people placed it at.
            setFrame(topLeft: CGPoint(x: panel.frame.minX, y: panel.frame.maxY))
        } else {
            applyPosition()
        }
    }

    private func setFrame(topLeft: CGPoint) {
        let frame = NSRect(x: topLeft.x, y: topLeft.y - contentSize.height,
                           width: contentSize.width, height: contentSize.height)
        panel.setFrame(frame.integral, display: true)
        panel.invalidateShadow()
    }

    // MARK: Window → settings

    private func dragEnded() {
        guard settings.widgetPlacement == .free else { return }
        // Remember where it was dropped, and which display it's on now.
        if let id = panel.screen?.displayID, id != Self.screen(for: settings.widgetScreenID).displayID {
            appliedScreenID = id
            settings.widgetScreenID = id
        }
        settings.widgetTopLeft = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }

    @objc private func screensChanged(_ notification: Notification) {
        applyPosition()
    }

    // MARK: Geometry

    static func screen(for id: UInt32) -> NSScreen {
        NSScreen.screens.first { $0.displayID == id } ?? NSScreen.screens.first ?? NSScreen.main!
    }

    private static func isOnScreen(_ topLeft: CGPoint) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(topLeft) }
    }

    private static func cornerTopLeft(_ placement: WidgetPlacement, size: CGSize, on screen: NSScreen) -> CGPoint {
        let area = screen.visibleFrame.insetBy(dx: screenMargin, dy: screenMargin)
        switch placement {
        case .topLeft, .free:
            return CGPoint(x: area.minX, y: area.maxY)
        case .topRight:
            return CGPoint(x: area.maxX - size.width, y: area.maxY)
        case .bottomLeft:
            return CGPoint(x: area.minX, y: area.minY + size.height)
        case .bottomRight:
            return CGPoint(x: area.maxX - size.width, y: area.minY + size.height)
        }
    }
}

extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
