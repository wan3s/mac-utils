import Darwin
import Foundation
import SystemConfiguration

struct LocalNetworkInfo: Equatable {
    /// Physical interface carrying traffic, e.g. "en0".
    var interfaceName: String?
    /// Localized name of that interface, e.g. "Wi-Fi".
    var interfaceDisplayName: String?
    var localAddress: String?
    /// Tunnel interface of an active VPN, e.g. "utun6".
    var vpnInterface: String?
    /// Changes whenever interfaces or addresses change; used to detect network/VPN switches.
    var fingerprint = ""

    var isOnline: Bool { interfaceName != nil }
    var isVPNActive: Bool { vpnInterface != nil }
}

/// Describes the local network: active interface, its IPv4 address and VPN state.
final class NetworkInfoProvider {
    private let store = SCDynamicStoreCreate(nil, "MacUtils" as CFString, nil, nil)
    private var displayNames: [String: String] = [:]

    func current() -> LocalNetworkInfo {
        let addresses = Self.ipv4Addresses()
        let primary = primaryInterface()
        let names = addresses.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let physical = names.filter(NetworkTrafficSampler.isPhysical)
        let tunnels = names.filter(Self.isTunnel)

        var info = LocalNetworkInfo()
        let interface = primary.flatMap { physical.contains($0) ? $0 : nil } ?? physical.first
        info.interfaceName = interface
        info.localAddress = interface.flatMap { addresses[$0]?.first }
        info.interfaceDisplayName = interface.flatMap(displayName(for:))
        info.vpnInterface = primary.flatMap { Self.isTunnel($0) ? $0 : nil } ?? tunnels.first
        info.fingerprint = ([primary ?? "-"] + names.map { "\($0)=\(addresses[$0, default: []].joined(separator: ","))" })
            .joined(separator: ";")
        return info
    }

    static func isTunnel(_ name: String) -> Bool {
        ["utun", "ipsec", "ppp", "tun", "tap", "wg"].contains { name.hasPrefix($0) }
    }

    private func primaryInterface() -> String? {
        guard let store,
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return value["PrimaryInterface"] as? String
    }

    private func displayName(for bsdName: String) -> String? {
        if let name = displayNames[bsdName] { return name }
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        for interface in interfaces {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
            else { continue }
            displayNames[bsd] = name
        }
        return displayNames[bsdName]
    }

    /// IPv4 addresses of interfaces that are up, excluding loopback and link-local addresses.
    private static func ipv4Addresses() -> [String: [String]] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(head) }

        var result: [String: [String]] = [:]
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let ip = String(cString: host)
            guard !ip.hasPrefix("169.254.") else { continue }
            result[String(cString: entry.pointee.ifa_name), default: []].append(ip)
        }
        return result
    }
}
