import Darwin
import Foundation
import IOKit

struct CPUUsage {
    var total: Double
    var user: Double
    var system: Double
    /// Busy fraction per logical core, in logical CPU order.
    var cores: [Double]
}

/// Per-core CPU load from `host_processor_info`, computed as the tick delta between two calls.
final class CPUSampler {
    private let host = mach_host_self()
    private var previous: [UInt32] = []

    init() {
        _ = sample()
    }

    func sample() -> CPUUsage? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info
        else { return nil }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let ticks = (0..<Int(infoCount)).map { UInt32(bitPattern: info[$0]) }
        defer { previous = ticks }
        guard previous.count == ticks.count else { return nil }

        let states = Int(CPU_STATE_MAX)
        var cores: [Double] = []
        var user: UInt64 = 0, system: UInt64 = 0, total: UInt64 = 0
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * states
            // Tick counters are 32-bit and wrap, so subtract with overflow.
            func delta(_ state: Int32) -> UInt64 {
                UInt64(ticks[base + Int(state)] &- previous[base + Int(state)])
            }
            let coreUser = delta(CPU_STATE_USER) + delta(CPU_STATE_NICE)
            let coreSystem = delta(CPU_STATE_SYSTEM)
            let coreTotal = coreUser + coreSystem + delta(CPU_STATE_IDLE)
            cores.append(coreTotal > 0 ? Double(coreUser + coreSystem) / Double(coreTotal) : 0)
            user += coreUser
            system += coreSystem
            total += coreTotal
        }
        guard total > 0 else { return CPUUsage(total: 0, user: 0, system: 0, cores: cores) }
        return CPUUsage(
            total: Double(user + system) / Double(total),
            user: Double(user) / Double(total),
            system: Double(system) / Double(total),
            cores: cores
        )
    }

    static func loadAverage() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        return getloadavg(&values, 3) == 3 ? values : []
    }

    /// Labels such as "E1"…"E4", "P1"…"P4" from the device tree's `cluster-type`
    /// on Apple Silicon; plain numbers where cluster types aren't available (Intel).
    static func coreLabels(count: Int) -> [String] {
        let kinds = clusterTypes()
        var counters: [String: Int] = [:]
        return (0..<count).map { cpu in
            guard let kind = kinds[cpu] else { return "\(cpu + 1)" }
            counters[kind, default: 0] += 1
            return "\(kind)\(counters[kind]!)"
        }
    }

    private static func clusterTypes() -> [Int: String] {
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != IO_OBJECT_NULL else { return [:] }
        defer { IOObjectRelease(cpus) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }

        var result: [Int: String] = [:]
        while case let entry = IOIteratorNext(iterator), entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry) }
            guard let type = property(entry, "cluster-type") as? Data,
                  let letter = type.first.map({ String(UnicodeScalar($0)) }),
                  let id = integer(property(entry, "logical-cpu-id"))
            else { continue }
            result[id] = letter
        }
        return result
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let data = value as? Data, data.count >= 4 {
            return Int(data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        }
        return nil
    }
}
