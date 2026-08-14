import Foundation

/// Operator-facing taxonomy for BLE list filtering (orthogonal to BLEFriendlyIdentity).
enum BLEDeviceCategory: String, Codable, Hashable, CaseIterable, Identifiable {
    case cameraSecurity
    case tracker
    case audio
    case wearable
    case medical
    case smartHome
    case tvMedia
    case drone
    case phone
    case computer
    case beacon
    case gaming
    case automotive
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cameraSecurity: return "Camera / Security"
        case .tracker: return "Tracker"
        case .audio: return "Audio / Headphones"
        case .wearable: return "Wearable / Fitness"
        case .medical: return "Medical / Health"
        case .smartHome: return "Smart Home / IoT"
        case .tvMedia: return "TV / Media"
        case .drone: return "Drone / UAV"
        case .phone: return "Phone / Tablet"
        case .computer: return "Computer / Laptop"
        case .beacon: return "Beacon / Wayfinding"
        case .gaming: return "Game controller"
        case .automotive: return "Car / Automotive"
        case .unknown: return "Unknown / Unclassified"
        }
    }

    var shortLabel: String {
        switch self {
        case .cameraSecurity: return "Cameras"
        case .tracker: return "Trackers"
        case .audio: return "Audio"
        case .wearable: return "Wearables"
        case .medical: return "Medical"
        case .smartHome: return "Smart Home"
        case .tvMedia: return "TV / Media"
        case .drone: return "Drones"
        case .phone: return "Phones"
        case .computer: return "Computers"
        case .beacon: return "Beacons"
        case .gaming: return "Gaming"
        case .automotive: return "Cars"
        case .unknown: return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .cameraSecurity: return "camera.fill"
        case .tracker: return "location.magnifyingglass"
        case .audio: return "earbuds"
        case .wearable: return "applewatch"
        case .medical: return "cross.case.fill"
        case .smartHome: return "house.fill"
        case .tvMedia: return "tv"
        case .drone: return "airplane"
        case .phone: return "iphone"
        case .computer: return "laptopcomputer"
        case .beacon: return "dot.radiowaves.left.and.right"
        case .gaming: return "gamecontroller"
        case .automotive: return "car.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Quick-filter pills (All is separate).
    static var quickFilterCases: [BLEDeviceCategory] {
        [.phone, .computer, .tracker, .audio, .wearable, .tvMedia, .beacon, .gaming, .automotive, .smartHome, .unknown]
    }
}

struct BLECategoryRuleConfig: Codable {
    var version: Int
    var categories: [BLECategoryRule]
}

struct BLECategoryRule: Codable {
    var id: String
    var label: String
    var companyIds: [String]
    var nameContains: [String]
    var serviceUUIDs: [String]

    var parsedCompanyIds: Set<UInt16> {
        Set(companyIds.compactMap { Self.parseCompanyId($0) })
    }

    var normalizedServices: Set<String> {
        Set(serviceUUIDs.map { BLEFriendlyIdentity.normalizeUUID($0) })
    }

    var nameNeedles: [String] {
        nameContains.map { $0.lowercased() }
    }

    var category: BLEDeviceCategory? {
        BLEDeviceCategory(rawValue: id)
    }

    static func parseCompanyId(_ raw: String) -> UInt16? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "0X", with: "")
        return UInt16(cleaned, radix: 16)
    }
}

enum BLECategoryClassifier {
    private static let rules: [BLECategoryRule] = loadRules()

    static var bundledRuleCount: Int { rules.count }

    static func classify(_ device: BLEDevice) -> [BLEDeviceCategory] {
        if let override = device.manualCategoryOverride {
            return [override]
        }
        var hits = Set<BLEDeviceCategory>()
        let nameBlob = [device.gattDeviceName, device.localName, device.name]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let serviceKeys = Set(
            (device.serviceUUIDs + device.overflowServiceUUIDs + Array(device.serviceData.keys))
                .map { BLEFriendlyIdentity.normalizeUUID($0) }
        )
        let company = device.manufacturerCompanyId

        for rule in rules {
            guard let cat = rule.category else { continue }
            var matched = false
            if let company, rule.parsedCompanyIds.contains(company) {
                // Apple/Samsung company IDs alone are too broad — require name/service cue when listed with others
                if (company == 0x004C || company == 0x0075), rule.nameNeedles.isEmpty == false || !rule.normalizedServices.isEmpty {
                    if matchesName(nameBlob, rule.nameNeedles) || !serviceKeys.isDisjoint(with: rule.normalizedServices) {
                        matched = true
                    } else if cat == .tracker, company == 0x004C {
                        // Apple Continuity Find My / AirTag types
                        let payload = BLEValueExplainer.parseHex(device.manufacturerDataHex ?? "")
                        if let t = payload.first, t == 0x12 || t == 0x16 { matched = true }
                    }
                } else if company == 0x0000, cat == .smartHome {
                    if matchesName(nameBlob, rule.nameNeedles) { matched = true }
                } else {
                    matched = true
                }
            }
            if !matched, matchesName(nameBlob, rule.nameNeedles) {
                matched = true
            }
            if !matched, !serviceKeys.isDisjoint(with: rule.normalizedServices) {
                // Medical: 180A alone is too common — require a health name cue or a more specific UUID
                if cat == .medical {
                    let specific = Set(["181E", "1810", "1808", "1809", "181D"])
                    if !serviceKeys.isDisjoint(with: specific) || matchesName(nameBlob, rule.nameNeedles) {
                        matched = true
                    }
                } else if cat == .wearable {
                    // Battery (180F) alone is ubiquitous
                    let specific = Set(["180D", "1822", "1826"])
                    if !serviceKeys.isDisjoint(with: specific) || matchesName(nameBlob, rule.nameNeedles) {
                        matched = true
                    }
                } else if cat == .phone {
                    // HFP/A2DP alone is common on headphones — require phone-ish name
                    if matchesName(nameBlob, ["iphone", "galaxy", "pixel", "phone", "ipad", "oneplus"]) {
                        matched = true
                    }
                } else {
                    matched = true
                }
            }
            // Extra drone company ID not only in JSON name path
            if !matched, cat == .drone, company == 0x0960 {
                matched = true
            }
            // Flock / ALPR cameras
            if !matched, cat == .cameraSecurity, FlockCameraDetector.matchBLE(device) != nil {
                matched = true
            }
            if !matched, cat == .phone, PhoneDetector.matchBLE(device) != nil {
                matched = true
            }
            if !matched, cat == .beacon, BeaconDetector.matchBLE(device) != nil {
                matched = true
            }
            if !matched, cat == .computer, ComputerDetector.matchBLE(device) != nil {
                matched = true
            }
            if !matched, cat == .gaming, GamingDetector.matchBLE(device) != nil {
                matched = true
            }
            if !matched, cat == .automotive, AutomotiveDetector.matchBLE(device) != nil {
                matched = true
            }
            if matched { hits.insert(cat) }
        }

        // Prefer not marking "Ring" wearable when it's clearly a doorbell/camera
        if hits.contains(.cameraSecurity), hits.contains(.wearable),
           matchesName(nameBlob, ["doorbell", "cam", "arlo", "eufy", "security", "dbc"]) {
            hits.remove(.wearable)
        }

        if hits.isEmpty { return [] }
        return BLEDeviceCategory.allCases.filter { hits.contains($0) && $0 != .unknown }
    }

    /// Categories that came from an explicit rule (name substring, company ID, or service UUID).
    static func matchedRuleIds(for device: BLEDevice) -> [String] {
        let nameBlob = [device.gattDeviceName, device.localName, device.name]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let serviceKeys = Set(
            (device.serviceUUIDs + device.overflowServiceUUIDs + Array(device.serviceData.keys))
                .map { BLEFriendlyIdentity.normalizeUUID($0) }
        )
        let company = device.manufacturerCompanyId
        var ids: [String] = []
        for rule in rules {
            var matched = false
            if let company, rule.parsedCompanyIds.contains(company) { matched = true }
            if matchesName(nameBlob, rule.nameNeedles) { matched = true }
            if !serviceKeys.isDisjoint(with: rule.normalizedServices) { matched = true }
            if matched { ids.append(rule.id) }
        }
        return ids
    }

    static func primary(_ device: BLEDevice) -> BLEDeviceCategory {
        classify(device).first ?? .unknown
    }

    private static func matchesName(_ blob: String, _ needles: [String]) -> Bool {
        guard !blob.isEmpty, !needles.isEmpty else { return false }
        for needle in needles {
            let n = needle.lowercased()
            if n.contains("[") {
                if blob.contains(n) { return true }
                continue
            }
            if n.contains(" ") {
                if blob.contains(n) { return true }
                continue
            }
            if let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: n))\\b") {
                let range = NSRange(blob.startIndex..<blob.endIndex, in: blob)
                if regex.firstMatch(in: blob, range: range) != nil { return true }
            }
        }
        return false
    }

    private static func loadRules() -> [BLECategoryRule] {
        if let url = Bundle.main.url(forResource: "ble_category_rules", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(BLECategoryRuleConfig.self, from: data) {
            return decoded.categories
        }
        return fallbackRules
    }

    /// Built-in fallback if JSON missing from bundle.
    private static let fallbackRules: [BLECategoryRule] = [
        BLECategoryRule(id: "cameraSecurity", label: "Camera / Security", companyIds: ["0x0DE8"], nameContains: ["Ring", "Doorbell", "Arlo", "Wyze", "Blink"], serviceUUIDs: []),
        BLECategoryRule(id: "tracker", label: "Tracker", companyIds: ["0x03DA"], nameContains: ["Tile", "SmartTag", "Chipolo", "AirTag"], serviceUUIDs: ["FE2C"]),
        BLECategoryRule(id: "audio", label: "Audio / Headphones", companyIds: ["0x008A"], nameContains: ["JLab", "Bose", "Sony", "JBL", "AirPods", "Headphones", "Buds", "Speaker"], serviceUUIDs: ["110B", "1108", "111E"]),
        BLECategoryRule(id: "wearable", label: "Wearable / Fitness", companyIds: ["0x015A"], nameContains: ["Fitbit", "Watch", "Band", "HRM", "Oura"], serviceUUIDs: ["180D"]),
        BLECategoryRule(id: "medical", label: "Medical / Health", companyIds: [], nameContains: ["Temp", "BP", "Glucose", "Insulin", "Monitor", "Pulse", "O2"], serviceUUIDs: ["1810", "1808", "1809"]),
        BLECategoryRule(id: "smartHome", label: "Smart Home / IoT", companyIds: ["0x0171", "0x00A0"], nameContains: ["Hue", "Light", "Bulb", "Smart", "Thermo", "Plug", "Switch"], serviceUUIDs: ["FD69"]),
        BLECategoryRule(id: "tvMedia", label: "TV / Media", companyIds: [], nameContains: ["TV", "Chromecast", "Fire TV", "Roku", "Apple TV", "Display"], serviceUUIDs: ["183A", "1844"]),
        BLECategoryRule(id: "drone", label: "Drone / UAV", companyIds: ["0x0960"], nameContains: ["Drone", "UAV", "MAV", "XC-", "DJI"], serviceUUIDs: []),
        BLECategoryRule(id: "phone", label: "Phone / Tablet", companyIds: [], nameContains: ["iPhone", "Galaxy", "Pixel", "Phone"], serviceUUIDs: []),
        BLECategoryRule(id: "automotive", label: "Car / Automotive", companyIds: ["0x0175", "0x0A7C"], nameContains: ["Tesla", "BMW", "Mercedes", "Car", "Auto"], serviceUUIDs: [])
    ]
}
