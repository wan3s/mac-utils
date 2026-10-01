#if DEBUG
import AppKit

/// Debug aid: `MacUtils -snapshotDir /path` saves PNGs of the app's own windows
/// (widget, popover, every settings pane) a few seconds after launch.
@MainActor
enum SnapshotRecorder {
    private typealias WindowImageFunction = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    static var directory: URL? {
        UserDefaults.standard.string(forKey: "snapshotDir").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func run(after delay: TimeInterval, steps: [(name: String, prepare: () -> NSWindow?)]) {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var remaining = steps
        func next() {
            guard !remaining.isEmpty else {
                print("snapshots done")
                return
            }
            let step = remaining.removeFirst()
            let window = step.prepare()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if let window {
                    print("\(step.name): frame \(window.frame)")
                    save(window, to: directory.appendingPathComponent("\(step.name).png"))
                } else {
                    print("\(step.name): no window")
                }
                next()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { next() }
    }

    /// Captures one of our own windows; no Screen Recording permission is needed for that.
    private static func save(_ window: NSWindow, to url: URL) {
        // CGWindowListCreateImage is unavailable in the macOS 15 SDK headers but still exported.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return }
        let capture = unsafeBitCast(symbol, to: WindowImageFunction.self)
        let optionIncludingWindow: UInt32 = 1 << 3
        let boundsIgnoreFraming: UInt32 = 1 << 0
        guard let image = capture(.null, optionIncludingWindow, UInt32(window.windowNumber), boundsIgnoreFraming)?
            .takeRetainedValue()
        else { return }
        let bitmap = NSBitmapImageRep(cgImage: image)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
