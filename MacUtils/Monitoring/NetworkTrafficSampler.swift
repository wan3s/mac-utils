import Darwin

struct TrafficCounters: Equatable {
    var received: UInt64 = 0
    var sent: UInt64 = 0
}

/// Reads 64-bit per-interface byte counters via `sysctl(NET_RT_IFLIST2)`.
///
/// Only physical interfaces are counted. VPN tunnels (utun, ipsec, ppp) carry the same
/// traffic that also crosses the physical interface, so adding them would double it.
final class NetworkTrafficSampler {
    private var previous: [String: TrafficCounters] = [:]

    /// Bytes received and sent since the previous call. The first call returns zero.
    func delta() -> TrafficCounters {
        let current = Self.readCounters()
        var delta = TrafficCounters()
        for (name, now) in current {
            guard let before = previous[name] else { continue }
            // A counter that went backwards means the interface was reset; skip that sample.
            if now.received >= before.received { delta.received += now.received - before.received }
            if now.sent >= before.sent { delta.sent += now.sent - before.sent }
        }
        previous = current
        return delta
    }

    /// Ethernet and Wi-Fi are `en*`, cellular modems are `pdp_ip*`. Excludes AWDL/llw/bridge.
    static func isPhysical(_ name: String) -> Bool {
        name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }

    private static func readCounters() -> [String: TrafficCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return [:] }

        var result: [String: TrafficCounters] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if message.ifm_flags & IFF_LOOPBACK == 0,
                       let name = interfaceName(index: message.ifm_index),
                       isPhysical(name) {
                        result[name] = TrafficCounters(
                            received: message.ifm_data.ifi_ibytes,
                            sent: message.ifm_data.ifi_obytes
                        )
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return result
    }

    private static func interfaceName(index: UInt16) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(UInt32(index), &buffer) != nil else { return nil }
        return String(cString: buffer)
    }
}
