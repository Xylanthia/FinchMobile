import Foundation
import CoreBluetooth

enum BLEConnectionState: String, Codable, Hashable {
    case disconnected
    case connecting
    case discovering
    case connected
    case failed
}

struct GATTCharacteristicInfo: Codable, Hashable, Identifiable {
    var id: String { uuid }
    var uuid: String
    var properties: [String]
    var valueHex: String?
    var valueUTF8: String?
}

struct GATTServiceInfo: Codable, Hashable, Identifiable {
    var id: String { uuid }
    var uuid: String
    var characteristics: [GATTCharacteristicInfo]
}

struct BLEDevice: Identifiable, Codable, Hashable {
    var id: UUID { identifier }
    var identifier: UUID
    var name: String?
    var localName: String?
    var rssi: Int
    var lastSeen: Date
    var advertisementHex: String
    var manufacturerCompanyId: UInt16?
    var manufacturerDataHex: String?
    var manufacturerName: String?
    var serviceUUIDs: [String]
    var txPower: Int?
    var connectable: Bool
    var overflowServiceUUIDs: [String]
    var solicitedServiceUUIDs: [String]
    var connectionState: BLEConnectionState
    var gattError: String?
    var gattServices: [GATTServiceInfo]

    init(
        identifier: UUID,
        name: String? = nil,
        localName: String? = nil,
        rssi: Int,
        lastSeen: Date = Date(),
        advertisementHex: String,
        manufacturerCompanyId: UInt16? = nil,
        manufacturerDataHex: String? = nil,
        manufacturerName: String? = nil,
        serviceUUIDs: [String] = [],
        txPower: Int? = nil,
        connectable: Bool = false,
        overflowServiceUUIDs: [String] = [],
        solicitedServiceUUIDs: [String] = [],
        connectionState: BLEConnectionState = .disconnected,
        gattError: String? = nil,
        gattServices: [GATTServiceInfo] = []
    ) {
        self.identifier = identifier
        self.name = name
        self.localName = localName
        self.rssi = rssi
        self.lastSeen = lastSeen
        self.advertisementHex = advertisementHex
        self.manufacturerCompanyId = manufacturerCompanyId
        self.manufacturerDataHex = manufacturerDataHex
        self.manufacturerName = manufacturerName
        self.serviceUUIDs = serviceUUIDs
        self.txPower = txPower
        self.connectable = connectable
        self.overflowServiceUUIDs = overflowServiceUUIDs
        self.solicitedServiceUUIDs = solicitedServiceUUIDs
        self.connectionState = connectionState
        self.gattError = gattError
        self.gattServices = gattServices
    }

    /// Broadcast name if present; otherwise empty (prefer `friendly.title`).
    var broadcastName: String? {
        if let localName, !localName.isEmpty { return localName }
        if let name, !name.isEmpty { return name }
        return nil
    }

    var displayName: String {
        broadcastName ?? friendly.title
    }

    var shortUUID: String {
        let s = identifier.uuidString
        return String(s.prefix(8))
    }

    var signalBars: Int {
        if rssi >= -50 { return 4 }
        if rssi >= -65 { return 3 }
        if rssi >= -80 { return 2 }
        if rssi >= -90 { return 1 }
        return 0
    }

    var friendly: BLEFriendlyIdentity {
        BLEFriendlyIdentity.classify(self)
    }

    var signalLabel: String {
        switch signalBars {
        case 4: return "Very strong"
        case 3: return "Strong"
        case 2: return "OK"
        case 1: return "Weak"
        default: return "Very weak"
        }
    }

    /// Estimated meters from RSSI (log-distance path loss). Rough — walls/pockets skew it.
    var estimatedDistanceMeters: Double {
        let measuredPower = Double(txPower ?? -59) // typical BLE RSSI at ~1 m if TxPower unknown
        let pathLossExponent = 2.2 // indoor-ish
        let rssiValue = Double(max(min(rssi, 0), -100))
        let exponent = (measuredPower - rssiValue) / (10.0 * pathLossExponent)
        let meters = pow(10.0, exponent)
        return min(max(meters, 0.1), 80.0)
    }

    /// Friendly distance for operators, e.g. "~2 m (about 6 ft)".
    var distanceLabel: String {
        let m = estimatedDistanceMeters
        let ft = m * 3.28084
        let band: String
        switch m {
        case ..<0.8: band = "arm's reach"
        case ..<2.0: band = "same room, very close"
        case ..<5.0: band = "same room"
        case ..<12.0: band = "down the hall / next room"
        case ..<25.0: band = "far side of space"
        default: band = "edge of Bluetooth range"
        }
        if m < 10 {
            return String(format: "~%.1f m / ~%.0f ft (%@)", m, ft, band)
        }
        return String(format: "~%.0f m / ~%.0f ft (%@)", m, ft, band)
    }

    var distanceShortLabel: String {
        let m = estimatedDistanceMeters
        if m < 10 {
            return String(format: "~%.1f m", m)
        }
        return String(format: "~%.0f m", m)
    }

    /// Plain-text dump for clipboard / notes.
    var copyText: String {
        let identity = friendly
        var lines = [
            identity.title,
            "Category: \(identity.category)",
            identity.summary,
            "Distance: \(distanceLabel)",
            "Signal: \(signalLabel) (\(rssi) dBm)",
            "Status: \(connectionLabel)",
            "Connection: \(connectabilityLabel)",
            "Broadcast name: \(broadcastName ?? "—")",
            "Brand hint: \(manufacturerName ?? "—")",
            "ID: \(identifier.uuidString)"
        ]
        if !identity.serviceLabels.isEmpty {
            lines.append("Advertises: \(identity.serviceLabels.joined(separator: ", "))")
        }
        if !cves.isEmpty {
            lines.append("CVEs:")
            for cve in cves {
                lines.append("  \(cve.cve) [\(cve.confidence)] \(cve.title)")
                lines.append("    \(cve.why)")
                lines.append("    \(cve.nvdURL)")
            }
        }
        for svc in gattServices {
            lines.append("Inside: \(BLEServiceNames.label(forUUID: svc.uuid))")
            for ch in svc.characteristics {
                let val = ch.valueUTF8 ?? ch.valueHex ?? ""
                lines.append("  - \(BLEServiceNames.label(forUUID: ch.uuid)): \(val)")
            }
        }
        if let mfg = manufacturerDataHex, !mfg.isEmpty {
            lines.append("Manufacturer data: \(mfg)")
        }
        if !advertisementHex.isEmpty {
            lines.append("Advertisement: \(advertisementHex)")
        }
        return lines.joined(separator: "\n")
    }

    var copyCVEsText: String {
        if cves.isEmpty { return "No CVEs mapped for \(friendly.title)" }
        return cves.map { "\($0.cve) — \($0.title)\n\($0.why)\n\($0.nvdURL)" }
            .joined(separator: "\n\n")
    }

    var connectionLabel: String {
        switch connectionState {
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting…"
        case .discovering: return "Reading device…"
        case .connected: return "Connected"
        case .failed: return "Couldn't connect"
        }
    }

    var connectabilityLabel: String {
        connectable ? "Can connect for more detail" : "Broadcast only — usually can't connect"
    }

    /// Real CVEs mapped from this BLE Radar finding (identity / brand / services).
    var cves: [CVERef] {
        BLECVEEnricher.cves(for: self)
    }

    static func from(
        peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) -> BLEDevice {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let tx = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? Int
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false

        var mfgCompany: UInt16?
        var mfgHex: String?
        var mfgName: String?
        if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, data.count >= 2 {
            let company = UInt16(data[0]) | (UInt16(data[1]) << 8)
            mfgCompany = company
            mfgHex = data.dropFirst(2).map { String(format: "%02X", $0) }.joined(separator: " ")
            mfgName = BLEManufacturerLookup.name(for: company)
        }

        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
        let overflow = (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
        let solicited = (advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)

        let advBlob = Self.encodeAdvertisement(advertisementData)

        return BLEDevice(
            identifier: peripheral.identifier,
            name: peripheral.name,
            localName: localName,
            rssi: rssi.intValue,
            lastSeen: Date(),
            advertisementHex: advBlob,
            manufacturerCompanyId: mfgCompany,
            manufacturerDataHex: mfgHex,
            manufacturerName: mfgName,
            serviceUUIDs: services,
            txPower: tx,
            connectable: connectable,
            overflowServiceUUIDs: overflow,
            solicitedServiceUUIDs: solicited,
            connectionState: .disconnected,
            gattError: nil,
            gattServices: []
        )
    }

    enum CodingKeys: String, CodingKey {
        case identifier, name, localName, rssi, lastSeen, advertisementHex
        case manufacturerCompanyId, manufacturerDataHex, manufacturerName
        case serviceUUIDs, txPower, connectable, overflowServiceUUIDs, solicitedServiceUUIDs
        case connectionState, gattError, gattServices
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try c.decode(UUID.self, forKey: .identifier)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        localName = try c.decodeIfPresent(String.self, forKey: .localName)
        rssi = try c.decodeIfPresent(Int.self, forKey: .rssi) ?? -100
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen) ?? Date()
        advertisementHex = try c.decodeIfPresent(String.self, forKey: .advertisementHex) ?? ""
        manufacturerCompanyId = try c.decodeIfPresent(UInt16.self, forKey: .manufacturerCompanyId)
        manufacturerDataHex = try c.decodeIfPresent(String.self, forKey: .manufacturerDataHex)
        manufacturerName = try c.decodeIfPresent(String.self, forKey: .manufacturerName)
        serviceUUIDs = try c.decodeIfPresent([String].self, forKey: .serviceUUIDs) ?? []
        txPower = try c.decodeIfPresent(Int.self, forKey: .txPower)
        connectable = try c.decodeIfPresent(Bool.self, forKey: .connectable) ?? false
        overflowServiceUUIDs = try c.decodeIfPresent([String].self, forKey: .overflowServiceUUIDs) ?? []
        solicitedServiceUUIDs = try c.decodeIfPresent([String].self, forKey: .solicitedServiceUUIDs) ?? []
        connectionState = try c.decodeIfPresent(BLEConnectionState.self, forKey: .connectionState) ?? .disconnected
        gattError = try c.decodeIfPresent(String.self, forKey: .gattError)
        gattServices = try c.decodeIfPresent([GATTServiceInfo].self, forKey: .gattServices) ?? []
    }

    private static func encodeAdvertisement(_ data: [String: Any]) -> String {
        var parts: [String] = []
        for (k, v) in data.sorted(by: { $0.key < $1.key }) {
            if let d = v as? Data {
                parts.append("\(k)=\(d.map { String(format: "%02X", $0) }.joined())")
            } else if let arr = v as? [CBUUID] {
                parts.append("\(k)=[\(arr.map(\.uuidString).joined(separator: ","))]")
            } else {
                parts.append("\(k)=\(String(describing: v))")
            }
        }
        return parts.joined(separator: " | ")
    }

    mutating func merge(with newer: BLEDevice) {
        rssi = newer.rssi
        lastSeen = newer.lastSeen
        if let n = newer.name, !n.isEmpty { name = n }
        if let n = newer.localName, !n.isEmpty { localName = n }
        if newer.manufacturerCompanyId != nil {
            manufacturerCompanyId = newer.manufacturerCompanyId
            manufacturerDataHex = newer.manufacturerDataHex
            manufacturerName = newer.manufacturerName
        }
        if !newer.serviceUUIDs.isEmpty { serviceUUIDs = newer.serviceUUIDs }
        advertisementHex = newer.advertisementHex
        if let tx = newer.txPower { txPower = tx }
        connectable = newer.connectable
        // Preserve GATT session state unless newer explicitly carries it
        if newer.connectionState != .disconnected || !newer.gattServices.isEmpty {
            connectionState = newer.connectionState
            gattServices = newer.gattServices
            gattError = newer.gattError
        }
    }
}

enum BLEManufacturerLookup {
    static func name(for companyId: UInt16) -> String? {
        known[companyId]
    }

    private static let known: [UInt16: String] = [
        0x0006: "Microsoft",
        0x004C: "Apple",
        0x00E0: "Google",
        0x0075: "Samsung",
        0x000F: "Broadcom",
        0x000A: "CSR",
        0x000D: "Texas Instruments",
        0x0059: "Nordic Semiconductor",
        0x008A: "Bose",
        0x0157: "Huami / Amazfit",
        0x02E5: "Espressif (Wi‑Fi chip)",
        0x0499: "Ruuvi",
        0x005D: "Garmin",
        0x0131: "Cypress",
        0x03DA: "Tile",
        0x06D5: "Samsung",
        0x0001: "Ericsson",
        0x00D2: "Sony",
        0x012D: "Sony Ericsson",
        0x0171: "Amazon",
        0x02A9: "Huawei",
        0x038F: "Xiaomi",
        0x0528: "Proximity Beacon",
        0x0A7C: "Tire pressure sensor (TPMS)",
        0x0136: "Xiaomi",
        0x015A: "Fitbit",
        0x0822: "OnePlus",
        0x00C4: "LG Electronics",
        0x00E2: "Nike",
        0x0078: "Nike",
        0x00AF: "Nike",
        0x049F: "3M",
        0x00A0: "Philips",
        0x0087: "Garmin",
        0x02F2: "Google",
        0x0118: "NXP",
        0x0002: "Intel",
        0x001D: "Qualcomm",
        0x005A: "Wahoo Fitness",
        0x01D7: "Withings",
        0x00D7: "Google",
        0x0211: "iRobot",
        0x0175: "Tesla",
        0x00A7: "Flic"
    ]
}

/// Plain-language identity for non-technical users.
struct BLEFriendlyIdentity: Hashable {
    /// Short headline shown in the list (e.g. "Tire pressure sensor").
    var title: String
    /// One-line explanation of what this likely is.
    var summary: String
    /// Category chip (phone, tracker, TPMS…).
    var category: String
    /// SF Symbol name.
    var icon: String
    /// How sure we are: high / medium / low.
    var confidence: String
    /// Friendly names for advertised services (empty if none known).
    var serviceLabels: [String]

    static func classify(_ device: BLEDevice) -> BLEFriendlyIdentity {
        let nameBlob = [device.localName, device.name]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let serviceKeys = device.serviceUUIDs.map { normalizeUUID($0) }
        let serviceLabels = serviceKeys.compactMap { BLEServiceNames.label(for: $0) }
        let mfgPayload = parseManufacturerPayload(device.manufacturerDataHex)

        // --- Name heuristics (highest priority when explicit) ---
        if matches(nameBlob, ["tpms", "tire", "tyre", "fobo", "pressure sensor", "tirepress"]) {
            return make(
                title: "Tire pressure sensor",
                summary: "Wireless sensor that reports tire pressure (and often temperature).",
                category: "Car / TPMS",
                icon: "tirepressure",
                confidence: "high",
                serviceLabels: serviceLabels
            )
        }
        if matches(nameBlob, ["airpods", "beats", "galaxy buds", "earbuds", "earbud", "headphone", "headset", "wf-", "wh-"]) {
            return make(
                title: device.broadcastName ?? "Wireless headphones",
                summary: "Audio earbuds or headphones broadcasting nearby.",
                category: "Headphones",
                icon: "earbuds",
                confidence: "high",
                serviceLabels: serviceLabels
            )
        }
        if matches(nameBlob, ["watch", "band", "fitbit", "garmin", "amazfit", "mi band", "whoop"]) {
            return make(
                title: device.broadcastName ?? "Wearable / watch",
                summary: "Fitness band or smartwatch advertising over Bluetooth.",
                category: "Wearable",
                icon: "applewatch",
                confidence: "high",
                serviceLabels: serviceLabels
            )
        }
        if matches(nameBlob, ["tile", "airtag", "smarttag", "chipolo", "tracker", "find my"]) {
            return make(
                title: device.broadcastName ?? "Item tracker",
                summary: "Bluetooth tracker used to find keys, bags, or other items.",
                category: "Tracker",
                icon: "location.magnifyingglass",
                confidence: "high",
                serviceLabels: serviceLabels
            )
        }
        if matches(nameBlob, ["iphone", "ipad", "macbook", "imac"]) {
            return make(
                title: device.broadcastName ?? "Apple device",
                summary: "An Apple phone, tablet, or computer nearby.",
                category: "Phone / computer",
                icon: "iphone",
                confidence: "high",
                serviceLabels: serviceLabels
            )
        }
        if matches(nameBlob, ["printer", "hp ", "epson", "brother", "canon"]) {
            return make(
                title: device.broadcastName ?? "Printer",
                summary: "A printer or print accessory advertising over Bluetooth.",
                category: "Printer",
                icon: "printer",
                confidence: "high",
                serviceLabels: serviceLabels
            )
        }
        if matches(nameBlob, ["tv", "roku", "fire tv", "chromecast", "samsung tv", "lg tv"]) {
            return make(
                title: device.broadcastName ?? "TV / streamer",
                summary: "Television or streaming stick Bluetooth advertisement.",
                category: "TV",
                icon: "tv",
                confidence: "high",
                serviceLabels: serviceLabels
            )
        }
        if matches(nameBlob, ["ruuvi", "sensor", "temp", "thermo", "humidity"]) {
            return make(
                title: device.broadcastName ?? "Environment sensor",
                summary: "Likely a temperature / humidity / environment sensor.",
                category: "Sensor",
                icon: "thermometer.medium",
                confidence: "medium",
                serviceLabels: serviceLabels
            )
        }

        // --- Manufacturer company ID ---
        if let company = device.manufacturerCompanyId {
            if company == 0x0A7C {
                return make(
                    title: "Tire pressure sensor",
                    summary: "TPMS sensor for car tires. Shows up when the sensor is awake and broadcasting.",
                    category: "Car / TPMS",
                    icon: "tirepressure",
                    confidence: "high",
                    serviceLabels: serviceLabels
                )
            }
            if company == 0x03DA || company == 0x0528 {
                return make(
                    title: "Item tracker / beacon",
                    summary: "A tracker or proximity beacon used to locate something nearby.",
                    category: "Tracker",
                    icon: "location.magnifyingglass",
                    confidence: "high",
                    serviceLabels: serviceLabels
                )
            }
            if company == 0x0499 {
                return make(
                    title: "Ruuvi environment sensor",
                    summary: "Battery-powered sensor for temperature, humidity, and air pressure.",
                    category: "Sensor",
                    icon: "thermometer.medium",
                    confidence: "high",
                    serviceLabels: serviceLabels
                )
            }
            if company == 0x004C {
                return appleIdentity(payload: mfgPayload, broadcastName: device.broadcastName, serviceLabels: serviceLabels)
            }
            if company == 0x0006 {
                return make(
                    title: device.broadcastName ?? "Microsoft / Windows device",
                    summary: "Usually a Windows PC, Surface, Xbox controller, or Microsoft accessory.",
                    category: "Computer / accessory",
                    icon: "desktopcomputer",
                    confidence: "medium",
                    serviceLabels: serviceLabels
                )
            }
            if company == 0x0075 || company == 0x06D5 {
                return make(
                    title: device.broadcastName ?? "Samsung device",
                    summary: "Phone, watch, earbuds, or other Samsung Bluetooth device.",
                    category: "Phone / wearable",
                    icon: "iphone",
                    confidence: "medium",
                    serviceLabels: serviceLabels
                )
            }
            if company == 0x00E0 || company == 0x02F2 || company == 0x00D7 {
                return make(
                    title: device.broadcastName ?? "Google device",
                    summary: "Pixel phone, Chromebook, Nest, or other Google Bluetooth advertisement.",
                    category: "Phone / smart home",
                    icon: "iphone",
                    confidence: "medium",
                    serviceLabels: serviceLabels
                )
            }
            if company == 0x008A {
                return make(
                    title: device.broadcastName ?? "Bose speaker / headphones",
                    summary: "Bose audio product advertising nearby.",
                    category: "Headphones",
                    icon: "hifispeaker",
                    confidence: "high",
                    serviceLabels: serviceLabels
                )
            }
            if company == 0x0171 {
                return make(
                    title: device.broadcastName ?? "Amazon device",
                    summary: "Echo, Fire, or other Amazon Bluetooth advertisement.",
                    category: "Smart home",
                    icon: "homepod",
                    confidence: "medium",
                    serviceLabels: serviceLabels
                )
            }
            if company == 0x0157 || company == 0x005D || company == 0x015A || company == 0x0087 {
                return make(
                    title: device.broadcastName ?? "Fitness wearable",
                    summary: "Watch or fitness band from Garmin, Fitbit, Amazfit, or similar.",
                    category: "Wearable",
                    icon: "applewatch",
                    confidence: "medium",
                    serviceLabels: serviceLabels
                )
            }
            if company == 0x02E5 {
                return make(
                    title: device.broadcastName ?? "DIY / IoT gadget",
                    summary: "Often an ESP32-based smart home or maker device.",
                    category: "IoT gadget",
                    icon: "cpu",
                    confidence: "medium",
                    serviceLabels: serviceLabels
                )
            }
            if company == 0x0175 {
                return make(
                    title: device.broadcastName ?? "Tesla / vehicle Bluetooth",
                    summary: "Vehicle key or car Bluetooth presence advertisement.",
                    category: "Car",
                    icon: "car.fill",
                    confidence: "medium",
                    serviceLabels: serviceLabels
                )
            }
        }

        // --- Service UUID heuristics ---
        if serviceKeys.contains("180D") {
            return make(
                title: device.broadcastName ?? "Heart-rate / fitness device",
                summary: "Advertises a heart-rate service — typically a strap, watch, or bike computer.",
                category: "Fitness",
                icon: "heart.fill",
                confidence: "high",
                serviceLabels: serviceLabels
            )
        }
        if serviceKeys.contains("1812") {
            return make(
                title: device.broadcastName ?? "Keyboard, mouse, or remote",
                summary: "Human Interface Device — input accessory.",
                category: "Accessory",
                icon: "keyboard",
                confidence: "high",
                serviceLabels: serviceLabels
            )
        }
        if serviceKeys.contains("110B") || serviceKeys.contains("1108") || serviceKeys.contains("111E") {
            return make(
                title: device.broadcastName ?? "Audio device",
                summary: "Bluetooth audio sink / headset advertisement.",
                category: "Headphones",
                icon: "earbuds",
                confidence: "medium",
                serviceLabels: serviceLabels
            )
        }
        if serviceKeys.contains("FD6F") {
            return make(
                title: "Phone exposure / proximity beacon",
                summary: "Often a phone broadcasting a privacy / proximity service UUID.",
                category: "Phone",
                icon: "iphone",
                confidence: "medium",
                serviceLabels: serviceLabels
            )
        }
        if serviceKeys.contains("FE2C") {
            return make(
                title: "Tile tracker",
                summary: "Tile item finder advertising nearby.",
                category: "Tracker",
                icon: "location.magnifyingglass",
                confidence: "high",
                serviceLabels: serviceLabels
            )
        }

        // --- Fallbacks ---
        if let brand = device.manufacturerName {
            let title = device.broadcastName ?? "\(brand) device"
            return make(
                title: title,
                summary: "Bluetooth device from \(brand). Name unknown — only a short broadcast was seen.",
                category: "Nearby Bluetooth",
                icon: "wave.3.right",
                confidence: "low",
                serviceLabels: serviceLabels
            )
        }
        if let broadcast = device.broadcastName {
            return make(
                title: broadcast,
                summary: "Named Bluetooth device nearby. Tap for more detail.",
                category: "Nearby Bluetooth",
                icon: "wave.3.right",
                confidence: "low",
                serviceLabels: serviceLabels
            )
        }
        return make(
            title: "Unknown Bluetooth device",
            summary: "Something nearby is broadcasting Bluetooth, but it didn't share a name or known brand.",
            category: "Unknown",
            icon: "questionmark.circle",
            confidence: "low",
            serviceLabels: serviceLabels
        )
    }

    private static func appleIdentity(payload: [UInt8], broadcastName: String?, serviceLabels: [String]) -> BLEFriendlyIdentity {
        let type = payload.first
        switch type {
        case 0x07:
            return make(
                title: broadcastName ?? "AirPods / Beats",
                summary: "Apple proximity pairing — usually AirPods or Beats nearby.",
                category: "Headphones",
                icon: "earbuds",
                confidence: "high",
                serviceLabels: serviceLabels
            )
        case 0x12, 0x16:
            return make(
                title: broadcastName ?? "AirTag / Find My item",
                summary: "Apple Find My network advertisement — AirTag or Find My–enabled device.",
                category: "Tracker",
                icon: "location.magnifyingglass",
                confidence: "high",
                serviceLabels: serviceLabels
            )
        case 0x10, 0x0F:
            return make(
                title: broadcastName ?? "iPhone / iPad nearby",
                summary: "Apple Nearby Info — typically an unlocked iPhone or iPad in the area.",
                category: "Phone / tablet",
                icon: "iphone",
                confidence: "medium",
                serviceLabels: serviceLabels
            )
        case 0x05:
            return make(
                title: broadcastName ?? "Apple AirDrop",
                summary: "Someone nearby has AirDrop / sharing active.",
                category: "Phone / computer",
                icon: "square.and.arrow.up",
                confidence: "medium",
                serviceLabels: serviceLabels
            )
        case 0x0C:
            return make(
                title: broadcastName ?? "Apple Handoff",
                summary: "Apple Continuity / Handoff signal from a Mac, iPhone, or iPad.",
                category: "Phone / computer",
                icon: "laptopcomputer.and.iphone",
                confidence: "medium",
                serviceLabels: serviceLabels
            )
        case 0x02:
            return make(
                title: broadcastName ?? "iBeacon",
                summary: "Location beacon often used in stores or venues.",
                category: "Beacon",
                icon: "dot.radiowaves.left.and.right",
                confidence: "medium",
                serviceLabels: serviceLabels
            )
        default:
            return make(
                title: broadcastName ?? "Apple device",
                summary: "Apple Bluetooth advertisement (phone, watch, Mac, AirPods, or AirTag).",
                category: "Apple",
                icon: "apple.logo",
                confidence: "medium",
                serviceLabels: serviceLabels
            )
        }
    }

    private static func make(
        title: String,
        summary: String,
        category: String,
        icon: String,
        confidence: String,
        serviceLabels: [String]
    ) -> BLEFriendlyIdentity {
        // tirepressure SF Symbol may not exist on older iOS — map safely
        let safeIcon = (icon == "tirepressure") ? "gauge.with.dots.needle.33percent" : icon
        return BLEFriendlyIdentity(
            title: title,
            summary: summary,
            category: category,
            icon: safeIcon,
            confidence: confidence,
            serviceLabels: serviceLabels
        )
    }

    private static func matches(_ blob: String, _ needles: [String]) -> Bool {
        guard !blob.isEmpty else { return false }
        return needles.contains { blob.contains($0) }
    }

    private static func normalizeUUID(_ uuid: String) -> String {
        let compact = uuid.replacingOccurrences(of: "-", with: "").uppercased()
        if compact.count == 4 { return compact }
        // 128-bit Bluetooth Base UUID: 0000XXXX-0000-1000-8000-00805F9B34FB
        if compact.count == 32, compact.hasPrefix("0000"), compact.hasSuffix("00001000800000805F9B34FB") {
            let start = compact.index(compact.startIndex, offsetBy: 4)
            let end = compact.index(compact.startIndex, offsetBy: 8)
            return String(compact[start..<end])
        }
        return compact
    }

    private static func parseManufacturerPayload(_ hex: String?) -> [UInt8] {
        guard let hex, !hex.isEmpty else { return [] }
        return hex.split(separator: " ").compactMap { UInt8($0, radix: 16) }
    }
}

enum BLEServiceNames {
    static func label(for normalizedShortOrFull: String) -> String? {
        let key = normalizedShortOrFull.uppercased()
        if let short = known[key] { return short }
        // Full 128-bit without dashes already handled by classifier normalize
        if key.count == 32, key.hasPrefix("0000") {
            let start = key.index(key.startIndex, offsetBy: 4)
            let end = key.index(key.startIndex, offsetBy: 8)
            return known[String(key[start..<end])]
        }
        return nil
    }

    static func label(forUUID uuid: String) -> String {
        let compact = uuid.replacingOccurrences(of: "-", with: "").uppercased()
        if let label = label(for: compact) { return label }
        // Prefer short form display for Bluetooth base UUIDs
        if compact.count == 32, compact.hasPrefix("0000"), compact.hasSuffix("00001000800000805F9B34FB") {
            let start = compact.index(compact.startIndex, offsetBy: 4)
            let end = compact.index(compact.startIndex, offsetBy: 8)
            let short = String(compact[start..<end])
            return known[short] ?? "Service \(short)"
        }
        return "Service \(String(uuid.prefix(8)))…"
    }

    private static let known: [String: String] = [
        "1800": "Device basics",
        "1801": "Generic access",
        "180A": "Device info",
        "180F": "Battery level",
        "180D": "Heart rate",
        "1812": "Keyboard / mouse / remote",
        "1813": "Scan parameters",
        "1814": "Running speed",
        "1816": "Cycling speed",
        "1818": "Cycling power",
        "181A": "Environment sensing",
        "181C": "User data",
        "181D": "Weight scale",
        "181E": "Bond management",
        "1822": "Pulse oximeter",
        "1826": "Fitness machine",
        "1108": "Headset audio",
        "110B": "Audio stream",
        "111E": "Hands-free audio",
        "1200": "Plug and play",
        "FE2C": "Tile tracker",
        "FD6F": "Phone proximity",
        "FD69": "Amazon",
        "FEAA": "Eddystone beacon",
        "FEF5": "Apple Continuity (service)",
        "1802": "Immediate alert",
        "1803": "Link loss",
        "1804": "Tx power",
        "1805": "Current time",
        "1811": "Alert notification",
        "1810": "Blood pressure",
        "1808": "Glucose",
        "1809": "Health thermometer"
    ]
}

enum BLEPropertyLabels {
    static func friendly(_ props: [String]) -> String {
        let mapped = props.map { p -> String in
            switch p {
            case "read": return "can read"
            case "write": return "can write"
            case "writeNR": return "can write (fast)"
            case "notify": return "sends updates"
            case "indicate": return "sends confirmed updates"
            case "broadcast": return "broadcasts"
            default: return p
            }
        }
        return mapped.isEmpty ? "no actions listed" : mapped.joined(separator: " · ")
    }
}
