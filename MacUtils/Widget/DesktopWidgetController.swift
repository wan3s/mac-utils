import AppKit
import SwiftUI

/// Borderless panel that sits on the desktop: above the wallpaper and icons, below app windows.
///
/// Dragging is handled here rather than in a view: the panel never becomes key and the app is
/// usually inactive, so views may not get the first click, but the window always sees its events.
private final class DesktopWidgetPanel: NSPanel {
    var isDraggable = false
    /// Called after a drag that actually moved the panel.
    var onDragEnded: (() -> Void)?

    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

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

    override func sendEvent(_ event: NSEvent) {
        // Control-click opens the context menu, so leave it alone.
        guard isDraggable, !event.modifierFlags.contains(.control) else {
            dragStart = nil
            super.sendEvent(event)
            return
        }
        switch event.type {
        case .leftMouseDown:
            dragStart = (screenLocation(of: event), frame.origin)
            NSCursor.closedHand.push()
        case .leftMouseDragged:
            guard let start = dragStart else { return super.sendEvent(event) }
            let mouse = screenLocation(of: event)
            setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                   y: start.origin.y + mouse.y - start.mouse.y))
        case .leftMouseUp:
            guard let start = dragStart else { return super.sendEvent(event) }
            dragStart = nil
            NSCursor.pop()
            if frame.origin != start.origin { onDragEnded?() }
        default:
            super.sendEvent(event)
        }
    }

    private func screenLocation(of event: NSEvent) -> NSPoint {
        convertPoint(toScreen: event.locationInWindow)
    }
}

/// Hosting view that reports changes of its SwiftUI content's ideal size.
private final class SizeReportingHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: ((CGSize) -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        // SwiftUI calls this whenever the content's ideal size changes; let the controller resize the panel.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onSizeChange?(self.fittingSize)
        }
    }
}

/// Shows the system monitor widget and keeps its position, look and sampling in sync with settings.
@MainActor
final class DesktopWidgetController: NSObject {
    private static let screenMargin: CGFloat = 20

    private let panel = DesktopWidgetPanel()
    private let hostingView: SizeReportingHostingView<DesktopWidgetView>
    private let monitor: SystemMonitor
    private let settings: AppSettings
    private var contentSize: CGSize = .zero
    private var appliedScreenID: UInt32?

    init(monitor: SystemMonitor, settings: AppSettings, actions: AppActions) {
        self.monitor = monitor
        self.settings = settings
        hostingView = SizeReportingHostingView(rootView: DesktopWidgetView(monitor: monitor, settings: settings, actions: actions))
        super.init()

        hostingView.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hostingView
        contentSize = hostingView.fittingSize
        panel.onDragEnded = { [weak self] in self?.dragEnded() }
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
        panel.isDraggable = !settings.widgetLocked
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
        // Keep the whole widget reachable on the display it was dropped on.
        let screen = panel.screen ?? Self.screen(for: settings.widgetScreenID)
        let topLeft = Self.clamp(panel.frame, to: screen.visibleFrame)
        if topLeft != CGPoint(x: panel.frame.minX, y: panel.frame.maxY) {
            setFrame(topLeft: topLeft)
        }
        // Remember where it was dropped, and which display it's on now. Saving the position
        // before switching placement means the observers see the final state in one pass.
        settings.widgetTopLeft = topLeft
        let id = screen.displayID
        if id != Self.screen(for: settings.widgetScreenID).displayID {
            appliedScreenID = id
            settings.widgetScreenID = id
        }
        // Dragging a corner-pinned widget means people want to place it themselves.
        if settings.widgetPlacement != .free {
            settings.widgetPlacement = .free
        }
    }

    @objc private func screensChanged(_ notification: Notification) {
        applyPosition()
    }

    // MARK: Geometry

    static func screen(for id: UInt32) -> NSScreen {
        NSScreen.screens.first { $0.displayID == id } ?? NSScreen.screens.first ?? NSScreen.main!
    }

    private static func clamp(_ frame: NSRect, to area: NSRect) -> CGPoint {
        let x = min(max(frame.minX, area.minX), max(area.maxX - frame.width, area.minX))
        let maxY = max(min(frame.maxY, area.maxY), min(area.minY + frame.height, area.maxY))
        return CGPoint(x: x, y: maxY)
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

#if DEBUG
extension DesktopWidgetController {
    /// Feeds a synthetic left-button drag through the panel's event handling.
    func simulateDrag(by offset: CGVector) {
        func send(_ type: NSEvent.EventType, _ location: NSPoint) {
            guard let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ) else { return }
            panel.sendEvent(event)
        }
        let grab = NSPoint(x: 20, y: 20)
        let screenGrab = NSPoint(x: panel.frame.minX + grab.x, y: panel.frame.minY + grab.y)
        send(.leftMouseDown, grab)
        var location = grab
        for step in 1...5 {
            let fraction = CGFloat(step) / 5
            // Like real events, each location is relative to where the panel is at that moment.
            location = NSPoint(x: screenGrab.x + offset.dx * fraction - panel.frame.minX,
                               y: screenGrab.y + offset.dy * fraction - panel.frame.minY)
            send(.leftMouseDragged, location)
        }
        send(.leftMouseUp, location)
    }
}
#endif

extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
