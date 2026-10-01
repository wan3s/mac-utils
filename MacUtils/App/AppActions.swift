import Foundation

enum SettingsPane: Int {
    case general
    case menuBar
    case widget
}

/// App-level commands the UI can trigger without knowing who owns the windows.
@MainActor
struct AppActions {
    var openSettings: (SettingsPane) -> Void
    var quit: () -> Void
}
