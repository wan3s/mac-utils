import Foundation
import IOKit

struct DiskUsage {
    var volumeName: String
    var total: UInt64
    var available: UInt64
    var readRate: Double
    var writeRate: Double

    var used: UInt64 { total - min(available, total) }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct VolumeOption: Identifiable, Hashable {
    var path: String
    var name: String

    var id: String { path }
}

/// Volume capacity plus disk throughput summed over all block storage drivers.
final class DiskSampler {
    /// Computing purgeable space can take a while, so capacity is refreshed less often than I/O.
    private static let capacityRefreshInterval: TimeInterval = 10

    private var previousIO: (read: UInt64, write: UInt64, time: TimeInterval)?
    private var capacity: (path: String, name: String, total: UInt64, available: UInt64, time: TimeInterval)?

    func sample(volumePath: String) -> DiskUsage? {
        let now = ProcessInfo.processInfo.systemUptime
        var readRate = 0.0
        var writeRate = 0.0
        let io = Self.ioTotals()
        if let previous = previousIO, now > previous.time {
            let elapsed = now - previous.time
            readRate = Double(io.read >= previous.read ? io.read - previous.read : 0) / elapsed
            writeRate = Double(io.write >= previous.write ? io.write - previous.write : 0) / elapsed
        }
        previousIO = (io.read, io.write, now)

        if capacity == nil || capacity?.path != volumePath
            || now - (capacity?.time ?? 0) > Self.capacityRefreshInterval {
            if let values = Self.capacity(of: volumePath) ?? Self.capacity(of: "/") {
                capacity = (volumePath, values.name, values.total, values.available, now)
            }
        }
        guard let capacity else { return nil }
        return DiskUsage(
            volumeName: capacity.name,
            total: capacity.total,
            available: capacity.available,
            readRate: readRate,
            writeRate: writeRate
        )
    }

    /// Mounted volumes that Finder shows, the startup disk first.
    static func volumes() -> [VolumeOption] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.volumeIsBrowsable != false else {
                return nil
            }
            return VolumeOption(path: url.path, name: values.volumeLocalizedName ?? url.lastPathComponent)
        }
        .sorted { lhs, rhs in lhs.path == "/" || (rhs.path != "/" && lhs.name < rhs.name) }
    }

    private static func capacity(of path: String) -> (name: String, total: UInt64, available: UInt64)? {
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ]
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0
        else { return nil }
        // "Important usage" counts purgeable space as available, matching Finder.
        let important = values.volumeAvailableCapacityForImportantUsage ?? 0
        let available = important > 0 ? important : Int64(values.volumeAvailableCapacity ?? 0)
        return (values.volumeLocalizedName ?? path, UInt64(total), UInt64(max(available, 0)))
    }

    private static func ioTotals() -> (read: UInt64, write: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS
        else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var write: UInt64 = 0
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any]
            else { continue }
            read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return (read, write)
    }
}
