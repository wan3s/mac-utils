import Darwin
import Foundation

enum MemoryPressure: Int32 {
    case normal = 1
    case warning = 2
    case critical = 4
}

struct MemoryUsage {
    var total: UInt64
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
    var pressure: MemoryPressure?

    /// "Memory Used" as Activity Monitor reports it.
    var used: UInt64 { app + wired + compressed }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

enum MemorySampler {
    private static let host = mach_host_self()
    private static let pageSize: UInt64 = {
        var size: vm_size_t = 0
        return host_page_size(host, &size) == KERN_SUCCESS ? UInt64(size) : 4096
    }()

    static func sample() -> MemoryUsage? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let appPages = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        let swap = swapUsage()
        return MemoryUsage(
            total: ProcessInfo.processInfo.physicalMemory,
            app: appPages * pageSize,
            wired: UInt64(stats.wire_count) * pageSize,
            compressed: UInt64(stats.compressor_page_count) * pageSize,
            swapUsed: swap.used,
            swapTotal: swap.total,
            pressure: pressure()
        )
    }

    private static func swapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }

    private static func pressure() -> MemoryPressure? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return nil }
        return MemoryPressure(rawValue: level)
    }
}
