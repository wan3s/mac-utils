import CoreGraphics
import Foundation
import Observation

enum WidgetSize: String, CaseIterable, Identifiable {
    case compact
    case regular

    var id: String { rawValue }
}

enum WidgetTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

enum WidgetPlacement: String, CaseIterable, Identifiable {
    case free
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }
}

/// All user preferences, persisted in `UserDefaults`. Observable so SwiftUI views and
/// AppKit controllers (via `observeChanges`) update as soon as a value changes.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let speedUnit = "speedUnit"
        static let showFlag = "menuBar.showFlag"
        static let showSpeeds = "menuBar.showSpeeds"
        static let geoRefreshMinutes = "menuBar.geoRefreshMinutes"
        static let widgetVisible = "widget.visible"
        static let widgetInterval = "widget.interval"
        static let showCPU = "widget.cpu"
        static let showCPUCores = "widget.cpu.cores"
        static let showCPUTemperature = "widget.cpu.temperature"
        static let showLoadAverage = "widget.cpu.loadAverage"
        static let showMemory = "widget.memory"
        static let showSwap = "widget.memory.swap"
        static let showMemoryPressure = "widget.memory.pressure"
        static let showDisk = "widget.disk"
        static let diskVolumePath = "widget.disk.volume"
        static let showDiskActivity = "widget.disk.activity"
        static let showSSDTemperature = "widget.disk.temperature"
        static let widgetSize = "widget.size"
        static let widgetTheme = "widget.theme"
        static let widgetOpacity = "widget.opacity"
        static let widgetPlacement = "widget.placement"
        static let widgetScreenID = "widget.screen"
        static let widgetLocked = "widget.locked"
        static let widgetTopLeft = "widget.topLeft"
    }

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: General

    var speedUnit: SpeedUnit { didSet { defaults.set(speedUnit.rawValue, forKey: Key.speedUnit) } }

    // MARK: Menu bar

    var showFlag: Bool { didSet { defaults.set(showFlag, forKey: Key.showFlag) } }
    var showSpeeds: Bool { didSet { defaults.set(showSpeeds, forKey: Key.showSpeeds) } }
    var geoRefreshMinutes: Int { didSet { defaults.set(geoRefreshMinutes, forKey: Key.geoRefreshMinutes) } }

    // MARK: Widget content

    var widgetVisible: Bool { didSet { defaults.set(widgetVisible, forKey: Key.widgetVisible) } }
    var widgetInterval: Double { didSet { defaults.set(widgetInterval, forKey: Key.widgetInterval) } }
    var showCPU: Bool { didSet { defaults.set(showCPU, forKey: Key.showCPU) } }
    var showCPUCores: Bool { didSet { defaults.set(showCPUCores, forKey: Key.showCPUCores) } }
    var showCPUTemperature: Bool { didSet { defaults.set(showCPUTemperature, forKey: Key.showCPUTemperature) } }
    var showLoadAverage: Bool { didSet { defaults.set(showLoadAverage, forKey: Key.showLoadAverage) } }
    var showMemory: Bool { didSet { defaults.set(showMemory, forKey: Key.showMemory) } }
    var showSwap: Bool { didSet { defaults.set(showSwap, forKey: Key.showSwap) } }
    var showMemoryPressure: Bool { didSet { defaults.set(showMemoryPressure, forKey: Key.showMemoryPressure) } }
    var showDisk: Bool { didSet { defaults.set(showDisk, forKey: Key.showDisk) } }
    var diskVolumePath: String { didSet { defaults.set(diskVolumePath, forKey: Key.diskVolumePath) } }
    var showDiskActivity: Bool { didSet { defaults.set(showDiskActivity, forKey: Key.showDiskActivity) } }
    var showSSDTemperature: Bool { didSet { defaults.set(showSSDTemperature, forKey: Key.showSSDTemperature) } }

    // MARK: Widget appearance & position

    var widgetSize: WidgetSize { didSet { defaults.set(widgetSize.rawValue, forKey: Key.widgetSize) } }
    var widgetTheme: WidgetTheme { didSet { defaults.set(widgetTheme.rawValue, forKey: Key.widgetTheme) } }
    var widgetOpacity: Double { didSet { defaults.set(widgetOpacity, forKey: Key.widgetOpacity) } }
    var widgetPlacement: WidgetPlacement { didSet { defaults.set(widgetPlacement.rawValue, forKey: Key.widgetPlacement) } }
    /// `CGDirectDisplayID` of the chosen display; 0 means the main display.
    var widgetScreenID: UInt32 { didSet { defaults.set(Int(widgetScreenID), forKey: Key.widgetScreenID) } }
    var widgetLocked: Bool { didSet { defaults.set(widgetLocked, forKey: Key.widgetLocked) } }
    /// Top-left corner of the widget in screen coordinates when placement is `.free`.
    var widgetTopLeft: CGPoint? {
        didSet {
            if let point = widgetTopLeft {
                defaults.set([point.x, point.y], forKey: Key.widgetTopLeft)
            } else {
                defaults.removeObject(forKey: Key.widgetTopLeft)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        speedUnit = Self.enumValue(defaults, Key.speedUnit, .bytes)

        showFlag = Self.value(defaults, Key.showFlag, true)
        showSpeeds = Self.value(defaults, Key.showSpeeds, true)
        geoRefreshMinutes = Self.value(defaults, Key.geoRefreshMinutes, 5)

        widgetVisible = Self.value(defaults, Key.widgetVisible, true)
        widgetInterval = Self.value(defaults, Key.widgetInterval, 1.0)
        showCPU = Self.value(defaults, Key.showCPU, true)
        showCPUCores = Self.value(defaults, Key.showCPUCores, true)
        showCPUTemperature = Self.value(defaults, Key.showCPUTemperature, true)
        showLoadAverage = Self.value(defaults, Key.showLoadAverage, true)
        showMemory = Self.value(defaults, Key.showMemory, true)
        showSwap = Self.value(defaults, Key.showSwap, true)
        showMemoryPressure = Self.value(defaults, Key.showMemoryPressure, true)
        showDisk = Self.value(defaults, Key.showDisk, true)
        diskVolumePath = Self.value(defaults, Key.diskVolumePath, "/")
        showDiskActivity = Self.value(defaults, Key.showDiskActivity, true)
        showSSDTemperature = Self.value(defaults, Key.showSSDTemperature, true)

        widgetSize = Self.enumValue(defaults, Key.widgetSize, .regular)
        widgetTheme = Self.enumValue(defaults, Key.widgetTheme, .system)
        widgetOpacity = Self.value(defaults, Key.widgetOpacity, 1.0)
        widgetPlacement = Self.enumValue(defaults, Key.widgetPlacement, .topRight)
        widgetScreenID = UInt32(clamping: Self.value(defaults, Key.widgetScreenID, 0))
        widgetLocked = Self.value(defaults, Key.widgetLocked, false)
        if let pair = defaults.array(forKey: Key.widgetTopLeft) as? [Double], pair.count == 2 {
            widgetTopLeft = CGPoint(x: pair[0], y: pair[1])
        } else {
            widgetTopLeft = nil
        }
    }

    /// The menu bar must always show something, so the last visible item can't be turned off.
    var canHideFlag: Bool { showSpeeds }
    var canHideSpeeds: Bool { showFlag }

    private static func value<T>(_ defaults: UserDefaults, _ key: String, _ fallback: T) -> T {
        defaults.object(forKey: key) as? T ?? fallback
    }

    private static func enumValue<T: RawRepresentable>(
        _ defaults: UserDefaults, _ key: String, _ fallback: T
    ) -> T where T.RawValue == String {
        defaults.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }
}
