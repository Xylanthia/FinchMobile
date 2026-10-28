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

    private var monitor: NWPathMonitor?
    private var browser: NWBrowser?
    private(set) var localNetworkReady = false
    private let queue = DispatchQueue(label: "aria.connection.monitor")
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.currentSSID = Self.copyCurrentSSID()
                // SSID is optional on iOS. A missing entitlement must not erase a
                // successful HTTP probe, and an offline AP need not have Internet.
                if path.status != .satisfied {
                    self.state = .notOnARIANetwork
                }
            }
        }
        monitor.start(queue: queue)
        preflight()
    }

    /// Bonjour browsing triggers local-network privacy before any ARIA HTTP call.
    /// No matching service is required; ARIA still uses its fixed HTTP endpoint.
    func preflight() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: "local."), using: .tcp)
        self.browser = browser
        browser.stateUpdateHandler = { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                switch status {
                case .ready: self.localNetworkReady = true
                case .waiting, .failed:
                    self.localNetworkReady = false
                    self.state = .notOnARIANetwork
                default: break
                }
            }
        }
        browser.start(queue: queue)
    }

    @MainActor
    func awaitPreflight() async -> Bool {
        start()
        // Bounded wait: denial never leaves pull-to-refresh spinning indefinitely.
        for _ in 0..<100 {
            if localNetworkReady { return true }
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    func retryPreflight() {
        guard !localNetworkReady else { return }
        browser?.cancel()
        browser = nil
        preflight()
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        browser?.cancel()
        browser = nil
        localNetworkReady = false
        started = false
    }

    /// Re-evaluate reachability against the device. Called by the coordinator before/after polls.
    @MainActor
    func evaluate(using client: ARIAClient) async {
        let ssid = Self.copyCurrentSSID()
        currentSSID = ssid
        guard await awaitPreflight() else { return }
        if let ssid, !ssid.hasPrefix(Self.ssidPrefix) {
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
