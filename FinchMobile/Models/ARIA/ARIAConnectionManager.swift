import Foundation
import Network
import Observation
import SystemConfiguration.CaptiveNetwork

/// Tri-state connection status (spec §2). Never conflate "not on ARIA network" with
/// "device not responding" — they drive different UI and guidance.
enum ARIAConnectionState: Equatable {
    case notOnARIANetwork        // phone isn't joined to ARIA-Setup
    case deviceUnreachable       // on a network, but device HTTP timed out
    case connected               // on ARIA-Setup and device responded

    var isConnected: Bool { self == .connected }
}

/// Detects whether the phone is joined to the ARIA-Setup AP and whether the device answers.
@Observable
final class ARIAConnectionManager {
    private(set) var state: ARIAConnectionState = .notOnARIANetwork
    private(set) var currentSSID: String?
    private(set) var lastSuccessfulPoll: Date?

    /// The SSID prefix the ARIA handheld advertises.
    static let ssidPrefix = "ARIA-Setup"

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "aria.connection.monitor")
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let onWiFi = path.usesInterfaceType(.wifi) && path.status == .satisfied
            let ssid = Self.copyCurrentSSID()
            Task { @MainActor in
                self.currentSSID = ssid
                if !onWiFi || !(ssid?.hasPrefix(Self.ssidPrefix) ?? false) {
                    // Not on ARIA Wi-Fi: hard-reset to not-on-network (don't keep "connected").
                    if self.state != .connected || !(ssid?.hasPrefix(Self.ssidPrefix) ?? false) {
                        self.state = .notOnARIANetwork
                    }
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
        started = false
    }

    /// Re-evaluate reachability against the device. Called by the coordinator before/after polls.
    @MainActor
    func evaluate(using client: ARIAClient) async {
        let ssid = Self.copyCurrentSSID()
        currentSSID = ssid
        guard ssid?.hasPrefix(Self.ssidPrefix) ?? false else {
            state = .notOnARIANetwork
            return
        }
        let alive = await client.ping()
        if alive {
            state = .connected
            lastSuccessfulPoll = Date()
        } else {
            state = .deviceUnreachable
        }
    }

    /// Current joined SSID via CaptiveNetwork. Requires the Access-WiFi-Information
    /// entitlement + location permission on-device; returns nil if unavailable.
    private static func copyCurrentSSID() -> String? {
        guard let interfaces = CNCopySupportedInterfaces() as? [String] else { return nil }
        for name in interfaces {
            guard
                let info = CNCopyCurrentNetworkInfo(name as CFString) as? [String: Any],
                let ssid = info[kCNNetworkInfoKeySSID as String] as? String
            else { continue }
            return ssid
        }
        return nil
    }
}
