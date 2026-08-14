import Foundation
import UIKit

enum SentinelExporter {
    /// SENTINEL export schema (JSON)
    /// {
    ///   "schema": "finch.sentinel.glass.v1",
    ///   "generatedAt": ISO8601,
    ///   "query": String,
    ///   "cidr": String,
    ///   "localIP": String?,
    ///   "hosts": [ IoTHost ],
    ///   "warnings": [String],
    ///   "mdnsServiceCount": Int
    /// }
    static func json(from report: GlassFabricReport, ble: [BLEDevice] = []) throws -> Data {
        let envelope: [String: Any] = [
            "schema": "finch.sentinel.glass.v1",
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "query": report.query,
            "cidr": report.cidr,
            "localIP": report.localIP as Any,
            "netmask": report.netmask as Any,
            "warnings": report.warnings,
            "mdnsServiceCount": report.mdnsServiceCount,
            "ssdpDeviceCount": report.ssdpDeviceCount,
            "hosts": try encodeJSONObject(report.hosts),
            "ble": try encodeJSONObject(ble.map { d -> BLEDevice in
                var copy = d
                copy.applyEvidenceSanitizer()
                return copy
            })
        ]
        return try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
    }

    static func csv(from report: GlassFabricReport) -> String {
        var lines: [String] = ["ip,mac,vendor,hostname,open_ports,fingerprint,services,cves,vuln_summaries"]
        for h in report.hosts {
            let ports = h.openPorts.map(String.init).joined(separator: ";")
            let fp = h.fingerprint.map { "\($0.vendor) \($0.model) (inferred)" } ?? ""
            let svc = h.services.map(\.type).joined(separator: ";")
            let cves = Array(Set(h.offenseHits.flatMap { $0.cves.map(\.cve) })).sorted().joined(separator: ";")
            let summaries = h.offenseHits.map(\.summary).joined(separator: " | ")
            lines.append([
                h.ip,
                h.mac ?? "",
                csvEscape(h.vendor ?? ""),
                csvEscape(h.hostname ?? ""),
                ports,
                csvEscape(fp),
                csvEscape(svc),
                csvEscape(cves),
                csvEscape(summaries)
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    static func share(data: Data, filename: String, from viewController: UIViewController? = nil) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        DispatchQueue.main.async {
            let presenter = viewController ?? topViewController()
            presenter?.present(av, animated: true)
        }
    }

    static func shareText(_ text: String, filename: String) {
        share(data: Data(text.utf8), filename: filename)
    }

    private static func encodeJSONObject<T: Encodable>(_ value: T) throws -> Any {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }

    private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        if let nav = base as? UINavigationController { return topViewController(base: nav.visibleViewController) }
        if let tab = base as? UITabBarController { return topViewController(base: tab.selectedViewController) }
        if let presented = base?.presentedViewController { return topViewController(base: presented) }
        return base
    }
}
