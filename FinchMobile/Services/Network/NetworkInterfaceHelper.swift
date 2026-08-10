import Foundation
import Network

struct LocalInterfaceInfo: Equatable {
    var interfaceName: String
    var ip: String
    var netmask: String
    var networkAddress: String
    var broadcast: String
    var prefixLength: Int
    var cidr: String { "\(networkAddress)/\(prefixLength)" }
}

enum NetworkInterfaceHelper {
    static func primaryIPv4(preferring names: [String] = ["en0", "en1", "pdp_ip0"]) -> LocalInterfaceInfo? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var candidates: [LocalInterfaceInfo] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard let netmaskAddr = current.pointee.ifa_netmask else { continue }

            let name = String(cString: current.pointee.ifa_name)
            let ip = ipv4String(from: addr)
            let mask = ipv4String(from: netmaskAddr)
            guard let ip, let mask else { continue }
            let prefix = prefixLength(from: mask)
            let network = networkAddress(ip: ip, mask: mask)
            let broadcast = broadcastAddress(ip: ip, mask: mask)
            candidates.append(
                LocalInterfaceInfo(
                    interfaceName: name,
                    ip: ip,
                    netmask: mask,
                    networkAddress: network,
                    broadcast: broadcast,
                    prefixLength: prefix
                )
            )
        }

        for preferred in names {
            if let match = candidates.first(where: { $0.interfaceName == preferred }) {
                return match
            }
        }
        return candidates.first
    }

    /// Best-effort local interface MAC when `ip` matches this device.
    /// iOS does not expose the ARP neighbor table to apps; remote MACs stay nil.
    static func macAddress(forIP ip: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ipToIface: [String: String] = [:]
        var ifaceToMAC: [String: String] = [:]

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let name = String(cString: current.pointee.ifa_name)
            guard let addr = current.pointee.ifa_addr else { continue }
            if addr.pointee.sa_family == UInt8(AF_INET) {
                if let s = ipv4String(from: addr) {
                    ipToIface[s] = name
                }
            } else if addr.pointee.sa_family == UInt8(AF_LINK) {
                if let mac = linkLayerMAC(from: addr), mac != "00:00:00:00:00:00" {
                    ifaceToMAC[name] = mac
                }
            }
        }

        if let iface = ipToIface[ip], let mac = ifaceToMAC[iface] {
            return mac
        }
        return nil
    }

    private static func linkLayerMAC(from addr: UnsafePointer<sockaddr>) -> String? {
        addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { sdl -> String? in
            let nlen = Int(sdl.pointee.sdl_nlen)
            let alen = Int(sdl.pointee.sdl_alen)
            guard alen == 6 else { return nil }
            return withUnsafeBytes(of: sdl.pointee.sdl_data) { raw -> String? in
                guard raw.count >= nlen + alen else { return nil }
                let bytes = raw.dropFirst(nlen).prefix(alen)
                return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
            }
        }
    }

    static func hosts(inCIDR cidr: String, maxHosts: Int = 256) -> (hosts: [String], warnings: [String], effectiveCIDR: String) {
        var warnings: [String] = []
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              let baseIP = ipv4ToUInt32(String(parts[0])) else {
            return ([], ["Invalid CIDR: \(cidr)"], cidr)
        }

        var effectivePrefix = prefix
        var effectiveCIDR = cidr
        if prefix < 24 {
            warnings.append("CIDR larger than /24 — scanning first /24 only for performance.")
            effectivePrefix = 24
            let masked = baseIP & prefixMask(24)
            effectiveCIDR = "\(uInt32ToIPv4(masked))/24"
        }

        let mask = prefixMask(effectivePrefix)
        let network = (baseIP & mask)
        let hostBits = 32 - effectivePrefix
        let count = hostBits >= 32 ? 0 : (1 << hostBits)
        guard count > 2 else {
            return ([uInt32ToIPv4(network)], warnings, effectiveCIDR)
        }

        var result: [String] = []
        let usable = min(count - 2, maxHosts)
        for i in 1...usable {
            result.append(uInt32ToIPv4(network &+ UInt32(i)))
        }
        if count - 2 > maxHosts {
            warnings.append("Host list truncated to \(maxHosts).")
        }
        return (result, warnings, effectiveCIDR)
    }

    // MARK: - Helpers

    private static func ipv4String(from addr: UnsafePointer<sockaddr>) -> String? {
        addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
            var ipv4 = sin.pointee.sin_addr
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &ipv4, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                return nil
            }
            return String(cString: buffer)
        }
    }

    private static func prefixLength(from mask: String) -> Int {
        guard let m = ipv4ToUInt32(mask) else { return 24 }
        return m.nonzeroBitCount
    }

    private static func networkAddress(ip: String, mask: String) -> String {
        guard let a = ipv4ToUInt32(ip), let m = ipv4ToUInt32(mask) else { return ip }
        return uInt32ToIPv4(a & m)
    }

    private static func broadcastAddress(ip: String, mask: String) -> String {
        guard let a = ipv4ToUInt32(ip), let m = ipv4ToUInt32(mask) else { return ip }
        return uInt32ToIPv4(a | ~m)
    }

    static func ipv4ToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    static func uInt32ToIPv4(_ value: UInt32) -> String {
        let a = (value >> 24) & 0xFF
        let b = (value >> 16) & 0xFF
        let c = (value >> 8) & 0xFF
        let d = value & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }

    static func prefixMask(_ prefix: Int) -> UInt32 {
        if prefix <= 0 { return 0 }
        if prefix >= 32 { return UInt32.max }
        return UInt32.max << (32 - prefix)
    }
}
