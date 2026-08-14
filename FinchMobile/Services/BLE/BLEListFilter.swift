import Foundation

enum BLESortMode: String, CaseIterable, Identifiable {
    case rssi
    case distance
    case name
    case category
    case lastSeen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rssi: return "RSSI (strongest)"
        case .distance: return "Distance (closest)"
        case .name: return "Name (A–Z)"
        case .category: return "Category"
        case .lastSeen: return "Last seen"
        }
    }
}

enum BLEConnectableFilter: String, CaseIterable, Identifiable {
    case either
    case yes
    case no

    var id: String { rawValue }

    var label: String {
        switch self {
        case .either: return "Either"
        case .yes: return "Yes"
        case .no: return "No"
        }
    }
}

enum BLELastSeenWindow: String, CaseIterable, Identifiable {
    case any
    case s60
    case m5
    case m15

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: return "Any time"
        case .s60: return "Last 60s"
        case .m5: return "Last 5 min"
        case .m15: return "Last 15 min"
        }
    }

    var maxAgeSeconds: TimeInterval? {
        switch self {
        case .any: return nil
        case .s60: return 60
        case .m5: return 5 * 60
        case .m15: return 15 * 60
        }
    }
}

struct BLEListFilterState: Equatable {
    var quickCategory: BLEDeviceCategory? = nil // nil = All
    var includeCategories: Set<BLEDeviceCategory> = []
    var excludeCategories: Set<BLEDeviceCategory> = []
    var rssiMin: Double = -100
    var rssiMax: Double = -20
    var distanceMin: Double = 0
    var distanceMax: Double = 100
    var companyIdText: String = ""
    var nameContains: String = ""
    var connectable: BLEConnectableFilter = .either
    var serviceUUID: String = ""
    var lastSeen: BLELastSeenWindow = .any
    var searchText: String = ""
    var sortMode: BLESortMode = .rssi

    var hasAdvancedActive: Bool {
        !includeCategories.isEmpty
            || !excludeCategories.isEmpty
            || rssiMin > -100 || rssiMax < -20
            || distanceMin > 0 || distanceMax < 100
            || !companyIdText.trimmingCharacters(in: .whitespaces).isEmpty
            || !nameContains.trimmingCharacters(in: .whitespaces).isEmpty
            || connectable != .either
            || !serviceUUID.trimmingCharacters(in: .whitespaces).isEmpty
            || lastSeen != .any
    }

    var activeFilterCount: Int {
        var n = 0
        if quickCategory != nil { n += 1 }
        if hasAdvancedActive { n += 1 }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty { n += 1 }
        return n
    }

    mutating func resetAdvanced() {
        includeCategories = []
        excludeCategories = []
        rssiMin = -100
        rssiMax = -20
        distanceMin = 0
        distanceMax = 100
        companyIdText = ""
        nameContains = ""
        connectable = .either
        serviceUUID = ""
        lastSeen = .any
    }

    mutating func resetAll() {
        quickCategory = nil
        searchText = ""
        sortMode = .rssi
        resetAdvanced()
    }
}

enum BLEListFilterEngine {
    static func filtered(_ devices: [BLEDevice], state: BLEListFilterState, now: Date = Date()) -> [BLEDevice] {
        var list = devices.filter { matches($0, state: state, now: now) }
        sort(&list, mode: state.sortMode)
        return list
    }

    static func matches(_ device: BLEDevice, state: BLEListFilterState, now: Date = Date()) -> Bool {
        let cats = Set(device.resolvedCategories)

        if let quick = state.quickCategory {
            if quick == .unknown {
                guard cats == [.unknown] || cats.contains(.unknown) else { return false }
            } else {
                guard cats.contains(quick) else { return false }
            }
        }

        if !state.includeCategories.isEmpty {
            guard !cats.isDisjoint(with: state.includeCategories) else { return false }
        }
        if !state.excludeCategories.isEmpty {
            guard cats.isDisjoint(with: state.excludeCategories) else { return false }
        }

        let rssiLo = min(state.rssiMin, state.rssiMax)
        let rssiHi = max(state.rssiMin, state.rssiMax)
        if let rssi = device.rssi {
            let rssiD = Double(rssi)
            guard rssiD >= rssiLo && rssiD <= rssiHi else { return false }
        }

        let distLo = min(state.distanceMin, state.distanceMax)
        let distHi = max(state.distanceMin, state.distanceMax)
        if let dist = device.estimatedDistanceMeters {
            guard dist >= distLo && dist <= distHi else { return false }
        }

        let companyQuery = state.companyIdText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !companyQuery.isEmpty {
            guard let want = BLECategoryRule.parseCompanyId(companyQuery),
                  device.manufacturerCompanyId == want else { return false }
        }

        let nameQ = state.nameContains.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !nameQ.isEmpty {
            let blob = [device.broadcastName, device.name, device.localName, device.gattDeviceName]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            guard blob.contains(nameQ) else { return false }
        }

        switch state.connectable {
        case .either: break
        case .yes: guard device.connectable else { return false }
        case .no: guard !device.connectable else { return false }
        }

        let svcQ = state.serviceUUID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !svcQ.isEmpty {
            let want = BLEFriendlyIdentity.normalizeUUID(svcQ)
            let have = Set(
                (device.serviceUUIDs + device.overflowServiceUUIDs + Array(device.serviceData.keys))
                    .map { BLEFriendlyIdentity.normalizeUUID($0) }
            )
            guard have.contains(want) else { return false }
        }

        if let maxAge = state.lastSeen.maxAgeSeconds {
            guard now.timeIntervalSince(device.lastSeen) <= maxAge else { return false }
        }

        let search = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !search.isEmpty {
            var hay = [
                device.broadcastName,
                device.name,
                device.localName,
                device.gattDeviceName,
                device.identifier.uuidString,
                device.manufacturerName,
                device.manufacturerCompanyId.map { String(format: "0x%04x", $0) },
                device.manufacturerCompanyId.map { String(format: "%04x", $0) },
                device.manufacturerDataHex,
                device.advertisementHex
            ].compactMap { $0?.lowercased() }
            hay.append(contentsOf: device.serviceUUIDs.map { $0.lowercased() })
            hay.append(contentsOf: device.resolvedCategories.map { $0.label.lowercased() })
            guard hay.contains(where: { $0.contains(search) }) else { return false }
        }

        return true
    }

    static func sort(_ devices: inout [BLEDevice], mode: BLESortMode) {
        switch mode {
        case .rssi:
            devices.sort { ($0.rssi ?? Int.min) > ($1.rssi ?? Int.min) }
        case .distance:
            devices.sort { ($0.estimatedDistanceMeters ?? .greatestFiniteMagnitude) < ($1.estimatedDistanceMeters ?? .greatestFiniteMagnitude) }
        case .name:
            devices.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .category:
            devices.sort {
                let a = $0.primaryCategory.label
                let b = $1.primaryCategory.label
                if a != b { return a < b }
                return ($0.rssi ?? Int.min) > ($1.rssi ?? Int.min)
            }
        case .lastSeen:
            devices.sort { $0.lastSeen > $1.lastSeen }
        }
    }

    static func summary(from devices: [BLEDevice]) -> BLEScanSummary {
        var counts: [BLEDeviceCategory: Int] = [:]
        for cat in BLEDeviceCategory.allCases { counts[cat] = 0 }
        var connectable = 0
        var strongest: Int? = nil
        for d in devices {
            for c in d.resolvedCategories {
                counts[c, default: 0] += 1
            }
            if d.connectable { connectable += 1 }
            if let s = strongest {
                if let r = d.rssi { strongest = max(s, r) }
            } else {
                strongest = d.rssi
            }
        }
        return BLEScanSummary(
            total: devices.count,
            connectable: connectable,
            strongestRSSI: strongest,
            counts: counts
        )
    }
}

struct BLEScanSummary {
    var total: Int
    var connectable: Int
    var strongestRSSI: Int?
    var counts: [BLEDeviceCategory: Int]

    func count(for category: BLEDeviceCategory) -> Int {
        counts[category] ?? 0
    }
}
