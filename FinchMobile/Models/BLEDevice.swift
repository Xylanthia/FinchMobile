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
    /// GAP Device Name (0x2A00), Model Number (0x2A24), or similar after GATT connect.
    var gattDeviceName: String?
    var rssi: Int
    var lastSeen: Date
    var advertisementHex: String
    var manufacturerCompanyId: UInt16?
    var manufacturerDataHex: String?
    var manufacturerName: String?
    var serviceUUIDs: [String]
    /// Service-data UUID → payload hex (Eddystone, Tile, Continuity helpers).
    var serviceData: [String: String]
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
        gattDeviceName: String? = nil,
        rssi: Int,
        lastSeen: Date = Date(),
        advertisementHex: String,
        manufacturerCompanyId: UInt16? = nil,
        manufacturerDataHex: String? = nil,
        manufacturerName: String? = nil,
        serviceUUIDs: [String] = [],
        serviceData: [String: String] = [:],
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
        self.gattDeviceName = gattDeviceName
        self.rssi = rssi
        self.lastSeen = lastSeen
        self.advertisementHex = advertisementHex
        self.manufacturerCompanyId = manufacturerCompanyId
        self.manufacturerDataHex = manufacturerDataHex
        self.manufacturerName = manufacturerName
        self.serviceUUIDs = serviceUUIDs
        self.serviceData = serviceData
        self.txPower = txPower
        self.connectable = connectable
        self.overflowServiceUUIDs = overflowServiceUUIDs
        self.solicitedServiceUUIDs = solicitedServiceUUIDs
        self.connectionState = connectionState
        self.gattError = gattError
        self.gattServices = gattServices
    }

    /// Best human name from ads / GATT (still may be nil for privacy ads).
    var broadcastName: String? {
        if let gattDeviceName, !gattDeviceName.isEmpty { return gattDeviceName }
        if let localName, !localName.isEmpty { return localName }
        if let name, !name.isEmpty { return name }
        return nil
    }

    var displayName: String {
        broadcastName ?? friendly.title
    }

    var shortUUID: String {
        String(identifier.uuidString.prefix(8))
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

    var estimatedDistanceMeters: Double {
        let measuredPower = Double(txPower ?? -59)
        let pathLossExponent = 2.2
        let rssiValue = Double(max(min(rssi, 0), -100))
        let exponent = (measuredPower - rssiValue) / (10.0 * pathLossExponent)
        let meters = pow(10.0, exponent)
        return min(max(meters, 0.1), 80.0)
    }

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
        return m < 10 ? String(format: "~%.1f m", m) : String(format: "~%.0f m", m)
    }

    var copyText: String {
        let identity = friendly
        var lines = [
            identity.title,
            "Type: \(identity.deviceType)",
            "Category: \(identity.category)",
            identity.summary,
            "Distance: \(distanceLabel)",
            "Signal: \(signalLabel) (\(rssi) dBm)",
            "Status: \(connectionLabel)",
            "Connection: \(connectabilityLabel)",
            "Broadcast name: \(broadcastName ?? "—")",
            "Brand hint: \(manufacturerName ?? "—")",
            "Company ID: \(manufacturerCompanyId.map { String(format: "0x%04X", $0) } ?? "—")",
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
        if !serviceData.isEmpty {
            for (uuid, hex) in serviceData.sorted(by: { $0.key < $1.key }) {
                lines.append("Service data \(uuid): \(hex)")
            }
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

        var serviceDataMap: [String: String] = [:]
        if let sd = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            for (uuid, data) in sd {
                serviceDataMap[uuid.uuidString] = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            }
        }

        return BLEDevice(
            identifier: peripheral.identifier,
            name: peripheral.name,
            localName: localName,
            rssi: rssi.intValue,
            lastSeen: Date(),
            advertisementHex: encodeAdvertisement(advertisementData),
            manufacturerCompanyId: mfgCompany,
            manufacturerDataHex: mfgHex,
            manufacturerName: mfgName,
            serviceUUIDs: services,
            serviceData: serviceDataMap,
            txPower: tx,
            connectable: connectable,
            overflowServiceUUIDs: overflow,
            solicitedServiceUUIDs: solicited
        )
    }

    enum CodingKeys: String, CodingKey {
        case identifier, name, localName, gattDeviceName, rssi, lastSeen, advertisementHex
        case manufacturerCompanyId, manufacturerDataHex, manufacturerName
        case serviceUUIDs, serviceData, txPower, connectable, overflowServiceUUIDs, solicitedServiceUUIDs
        case connectionState, gattError, gattServices
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try c.decode(UUID.self, forKey: .identifier)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        localName = try c.decodeIfPresent(String.self, forKey: .localName)
        gattDeviceName = try c.decodeIfPresent(String.self, forKey: .gattDeviceName)
        rssi = try c.decodeIfPresent(Int.self, forKey: .rssi) ?? -100
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen) ?? Date()
        advertisementHex = try c.decodeIfPresent(String.self, forKey: .advertisementHex) ?? ""
        manufacturerCompanyId = try c.decodeIfPresent(UInt16.self, forKey: .manufacturerCompanyId)
        manufacturerDataHex = try c.decodeIfPresent(String.self, forKey: .manufacturerDataHex)
        manufacturerName = try c.decodeIfPresent(String.self, forKey: .manufacturerName)
        serviceUUIDs = try c.decodeIfPresent([String].self, forKey: .serviceUUIDs) ?? []
        serviceData = try c.decodeIfPresent([String: String].self, forKey: .serviceData) ?? [:]
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
            } else if let dict = v as? [CBUUID: Data] {
                let inner = dict.map { "\($0.key.uuidString):\($0.value.map { String(format: "%02X", $0) }.joined())" }
                    .sorted().joined(separator: ",")
                parts.append("\(k)={\(inner)}")
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
        if let n = newer.gattDeviceName, !n.isEmpty { gattDeviceName = n }
        if newer.manufacturerCompanyId != nil {
            manufacturerCompanyId = newer.manufacturerCompanyId
            manufacturerDataHex = newer.manufacturerDataHex
            manufacturerName = newer.manufacturerName
        }
        if !newer.serviceUUIDs.isEmpty { serviceUUIDs = newer.serviceUUIDs }
        if !newer.serviceData.isEmpty {
            for (k, v) in newer.serviceData { serviceData[k] = v }
        }
        advertisementHex = newer.advertisementHex
        if let tx = newer.txPower { txPower = tx }
        connectable = newer.connectable
        if newer.connectionState != .disconnected || !newer.gattServices.isEmpty {
            connectionState = newer.connectionState
            gattServices = newer.gattServices
            gattError = newer.gattError
        }
    }

    /// Prefer GAP Device Name / Model Number from a finished GATT map.
    mutating func applyGATTIdentity(from services: [GATTServiceInfo], peripheralName: String?) {
        if let peripheralName, !peripheralName.isEmpty {
            name = peripheralName
        }
        let wanted = Set(["2A00", "2A24", "2A29", "2A25", "2A26"])
        var found: [String: String] = [:]
        for svc in services {
            for ch in svc.characteristics {
                let short = BLEFriendlyIdentity.normalizeUUID(ch.uuid)
                guard wanted.contains(short), let utf = ch.valueUTF8?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !utf.isEmpty else { continue }
                found[short] = utf
            }
        }
        if let deviceName = found["2A00"] {
            gattDeviceName = deviceName
        } else if let model = found["2A24"] {
            let mfg = found["2A29"]
            gattDeviceName = mfg.map { "\($0) \(model)" } ?? model
        } else if let mfg = found["2A29"] {
            gattDeviceName = mfg
        }
        if manufacturerName == nil, let mfg = found["2A29"] {
            manufacturerName = mfg
        }
    }
}

// MARK: - Manufacturer company IDs (Bluetooth SIG assigned numbers, common subset)

enum BLEManufacturerLookup {
    static func name(for companyId: UInt16) -> String? {
        known[companyId]
    }

    /// Large practical subset — enough to label everyday phones, wearables, IoT, cars, trackers.
    private static let known: [UInt16: String] = [
        0x0001: "Ericsson",
        0x0002: "Intel",
        0x0006: "Microsoft",
        0x000A: "CSR / Qualcomm",
        0x000D: "Texas Instruments",
        0x000F: "Broadcom",
        0x0013: "Atmel",
        0x001D: "Qualcomm",
        0x0025: "NEC",
        0x0030: "STMicroelectronics",
        0x004C: "Apple",
        0x0059: "Nordic Semiconductor",
        0x005A: "Wahoo Fitness",
        0x005D: "Garmin",
        0x006D: "Polar Electro",
        0x0075: "Samsung",
        0x0078: "Nike",
        0x0087: "Garmin",
        0x008A: "Bose",
        0x00A0: "Philips",
        0x00A7: "Flic / Shortcut Labs",
        0x00AF: "Nike",
        0x00C4: "LG Electronics",
        0x00D2: "Sony",
        0x00D7: "Google",
        0x00E0: "Google",
        0x00E2: "Nike",
        0x0118: "NXP",
        0x012D: "Sony Mobile",
        0x0131: "Cypress / Infineon",
        0x0136: "Xiaomi",
        0x0157: "Huami / Amazfit",
        0x015A: "Fitbit",
        0x015F: "Xiaomi",
        0x0171: "Amazon",
        0x0175: "Tesla",
        0x01D7: "Withings",
        0x0211: "iRobot",
        0x02A9: "Huawei",
        0x02E5: "Espressif",
        0x02F2: "Google",
        0x038F: "Xiaomi",
        0x03C2: "Govee",
        0x03DA: "Tile",
        0x0499: "Ruuvi",
        0x049F: "3M",
        0x0502: "Gimbal",
        0x0528: "Radius Networks",
        0x05A7: "Sonos",
        0x06D5: "Samsung",
        0x0822: "OnePlus",
        0x08A9: "Nothing",
        0x094F: "Pur3 / Beats-class",
        0x0A7C: "TPMS (generic)",
        0x0BDB: "Google Nest",
        0x0D2D: "Flipper Devices",
        0x0DC9: "Samsung SDS",
        0x0E65: "Meta / Oculus",
        0x0F1D: "August / Yale",
        0x1011: "Chipolo",
        0x1075: "Google",
        0x1212: "Qingping",
    ]
}

// MARK: - Friendly identity / device type

struct BLEFriendlyIdentity: Hashable {
    /// Short headline in the list.
    var title: String
    /// Operator-facing device type (Phone, Headphones, Tracker…).
    var deviceType: String
    var summary: String
    var category: String
    var icon: String
    var confidence: String
    var serviceLabels: [String]

    static func classify(_ device: BLEDevice) -> BLEFriendlyIdentity {
        let nameBlob = [device.gattDeviceName, device.localName, device.name]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let serviceKeys = Set(
            (device.serviceUUIDs + device.overflowServiceUUIDs + Array(device.serviceData.keys))
                .map { normalizeUUID($0) }
        )
        let serviceLabels = serviceKeys.compactMap { BLEServiceNames.label(for: $0) }.sorted()
        let mfgPayload = parseManufacturerPayload(device.manufacturerDataHex)

        // --- Flock Safety / Raven / Penguin / Pigvision (flock-back signatures) ---
        if let flock = FlockCameraDetector.matchBLE(device) {
            return make(
                device.broadcastName ?? "\(flock.vendor) \(flock.model)",
                "ALPR / security camera",
                flock.reason,
                "Flock-class camera",
                "camera.metering.spot",
                flock.confidence,
                serviceLabels
            )
        }

        // --- Explicit name heuristics ---
        if matches(nameBlob, ["flipper", "flipper zero"]) {
            return make("Flipper Zero", "RF toolkit", "Portable multi-tool advertising over BLE.", "RF / pentest", "wave.3.left.and.right", "high", serviceLabels)
        }
        if matches(nameBlob, ["tpms", "tire", "tyre", "fobo", "tirepress", "pressure sensor"]) {
            return make("Tire pressure sensor", "TPMS", "Wireless tire pressure / temperature sensor.", "Car / TPMS", "gauge.with.dots.needle.33percent", "high", serviceLabels)
        }
        if matches(nameBlob, ["airpods", "beats", "galaxy buds", "earbuds", "earbud", "headphone", "headset", "wf-", "wh-", "freebuds", "pixel buds", "nothing ear"]) {
            return make(device.broadcastName ?? "Wireless headphones", "Headphones", "Audio earbuds or headphones broadcasting nearby.", "Headphones", "earbuds", "high", serviceLabels)
        }
        if matches(nameBlob, ["watch", "band", "fitbit", "garmin", "amazfit", "mi band", "whoop", "galaxy watch", "pixel watch"]) {
            return make(device.broadcastName ?? "Wearable / watch", "Wearable", "Fitness band or smartwatch.", "Wearable", "applewatch", "high", serviceLabels)
        }
        if matches(nameBlob, ["tile", "airtag", "smarttag", "chipolo", "tracker", "find my", "eufy", "pebblebee"]) {
            return make(device.broadcastName ?? "Item tracker", "Tracker", "Bluetooth item finder / tracker.", "Tracker", "location.magnifyingglass", "high", serviceLabels)
        }
        if matches(nameBlob, ["iphone", "ipad", "macbook", "imac", "pixel ", "galaxy s", "galaxy z", "oneplus"]) {
            return make(device.broadcastName ?? "Phone / tablet", "Phone", "Phone or tablet advertising nearby.", "Phone / computer", "iphone", "high", serviceLabels)
        }
        if matches(nameBlob, ["printer", "hp ", "epson", "brother", "canon"]) {
            return make(device.broadcastName ?? "Printer", "Printer", "Printer or print accessory.", "Printer", "printer", "high", serviceLabels)
        }
        if matches(nameBlob, ["tv", "roku", "fire tv", "chromecast", "samsung tv", "lg tv", "apple tv", "shield"]) {
            return make(device.broadcastName ?? "TV / streamer", "TV / media", "Television or streaming stick.", "TV", "tv", "high", serviceLabels)
        }
        if matches(nameBlob, ["camera", "gopro", "insta360", "dji ", "ring ", "arlo", "wyze", "nest cam"]) {
            return make(device.broadcastName ?? "Camera", "Camera", "Camera or doorbell advertising over BLE.", "Camera", "camera.fill", "high", serviceLabels)
        }
        if matches(nameBlob, ["lock", "yale", "august", "schlage", "kwikset", "level lock"]) {
            return make(device.broadcastName ?? "Smart lock", "Smart lock", "Door lock / access device.", "Smart home", "lock.fill", "high", serviceLabels)
        }
        if matches(nameBlob, ["ruuvi", "temp", "thermo", "humidity", "qingping", "govee", "sensor"]) {
            return make(device.broadcastName ?? "Environment sensor", "Sensor", "Temperature / humidity / environment sensor.", "Sensor", "thermometer.medium", "medium", serviceLabels)
        }
        if matches(nameBlob, ["keyboard", "mouse", "trackpad", "magic keyboard", "mx master", "remote"]) {
            return make(device.broadcastName ?? "Input accessory", "HID / input", "Keyboard, mouse, trackpad, or remote.", "Accessory", "keyboard", "high", serviceLabels)
        }
        if matches(nameBlob, ["speaker", "homepod", "echo", "sonos", "jbl ", "ue boom"]) {
            return make(device.broadcastName ?? "Speaker", "Speaker", "Smart or portable speaker.", "Speaker", "hifispeaker", "high", serviceLabels)
        }
        if matches(nameBlob, ["tesla", "carplay", "android auto"]) {
            return make(device.broadcastName ?? "Vehicle Bluetooth", "Vehicle", "Car key / vehicle presence advertisement.", "Car", "car.fill", "high", serviceLabels)
        }

        // --- Service data fingerprints ---
        if serviceKeys.contains("FEAA") {
            return make(device.broadcastName ?? "Eddystone beacon", "Beacon", "Google Eddystone beacon (location / wayfinding).", "Beacon", "dot.radiowaves.left.and.right", "high", serviceLabels)
        }
        if serviceKeys.contains("FE2C") {
            return make("Tile tracker", "Tracker", "Tile item finder advertising nearby.", "Tracker", "location.magnifyingglass", "high", serviceLabels)
        }
        if serviceKeys.contains("FD6F") {
            return make("Phone exposure / proximity beacon", "Phone", "Phone broadcasting a privacy / proximity UUID (often COVID-era or similar).", "Phone", "iphone", "medium", serviceLabels)
        }
        if serviceKeys.contains("FD69") {
            return make(device.broadcastName ?? "Amazon device", "Smart home", "Amazon BLE advertisement (Echo / Fire / accessory).", "Smart home", "homepod", "medium", serviceLabels)
        }

        // --- Manufacturer company + payload ---
        if let company = device.manufacturerCompanyId {
            if company == 0x0A7C {
                return make("Tire pressure sensor", "TPMS", "TPMS sensor awake and broadcasting.", "Car / TPMS", "gauge.with.dots.needle.33percent", "high", serviceLabels)
            }
            if company == 0x004C {
                return appleIdentity(payload: mfgPayload, broadcastName: device.broadcastName, serviceLabels: serviceLabels)
            }
            if company == 0x00E0 || company == 0x02F2 || company == 0x00D7 || company == 0x1075 {
                return googleIdentity(payload: mfgPayload, broadcastName: device.broadcastName, serviceLabels: serviceLabels)
            }
            if company == 0x0006 {
                return microsoftIdentity(payload: mfgPayload, broadcastName: device.broadcastName, serviceLabels: serviceLabels)
            }
            if company == 0x0075 || company == 0x06D5 || company == 0x0DC9 {
                return samsungIdentity(payload: mfgPayload, broadcastName: device.broadcastName, serviceLabels: serviceLabels)
            }
            if company == 0x03DA || company == 0x1011 || company == 0x0528 {
                return make(device.broadcastName ?? "Item tracker / beacon", "Tracker", "Tracker or proximity beacon.", "Tracker", "location.magnifyingglass", "high", serviceLabels)
            }
            if company == 0x0499 {
                return make("Ruuvi environment sensor", "Sensor", "Ruuvi temperature / humidity / pressure sensor.", "Sensor", "thermometer.medium", "high", serviceLabels)
            }
            if company == 0x008A {
                return make(device.broadcastName ?? "Bose audio", "Headphones", "Bose speaker or headphones.", "Headphones", "hifispeaker", "high", serviceLabels)
            }
            if company == 0x0171 || company == 0x0BDB {
                return make(device.broadcastName ?? "Amazon / Nest device", "Smart home", "Amazon or Google Nest smart-home advertisement.", "Smart home", "homepod", "medium", serviceLabels)
            }
            if company == 0x0157 || company == 0x005D || company == 0x015A || company == 0x0087 || company == 0x006D || company == 0x01D7 {
                return make(device.broadcastName ?? "Fitness wearable", "Wearable", "Watch or fitness band.", "Wearable", "applewatch", "medium", serviceLabels)
            }
            if company == 0x02E5 || company == 0x0059 || company == 0x000D || company == 0x0131 {
                return make(device.broadcastName ?? "IoT / MCU gadget", "IoT / MCU", "Nordic / TI / Espressif / Cypress-class IoT board or product.", "IoT gadget", "cpu", "medium", serviceLabels)
            }
            if company == 0x0175 {
                return make(device.broadcastName ?? "Tesla / vehicle Bluetooth", "Vehicle", "Vehicle key or car presence advertisement.", "Car", "car.fill", "high", serviceLabels)
            }
            if company == 0x0D2D {
                return make(device.broadcastName ?? "Flipper Zero", "RF toolkit", "Flipper Devices BLE advertisement.", "RF / pentest", "wave.3.left.and.right", "high", serviceLabels)
            }
            if company == 0x02A9 || company == 0x0136 || company == 0x015F || company == 0x038F || company == 0x0822 || company == 0x08A9 {
                let brand = device.manufacturerName ?? "Phone OEM"
                return make(device.broadcastName ?? "\(brand) device", "Phone / wearable", "\(brand) phone, earbuds, or wearable advertisement.", "Phone / wearable", "iphone", "medium", serviceLabels)
            }
            if company == 0x0211 {
                return make(device.broadcastName ?? "iRobot / vacuum", "Robot", "Robot vacuum or related accessory.", "Smart home", "fan", "medium", serviceLabels)
            }
            if company == 0x05A7 {
                return make(device.broadcastName ?? "Sonos speaker", "Speaker", "Sonos audio product.", "Speaker", "hifispeaker", "high", serviceLabels)
            }
            if company == 0x0E65 {
                return make(device.broadcastName ?? "Meta / Quest device", "Headset", "Meta / Oculus headset or accessory.", "Headset", "visionpro", "medium", serviceLabels)
            }
            if company == 0x0F1D {
                return make(device.broadcastName ?? "Smart lock", "Smart lock", "August / Yale-class lock advertisement.", "Smart home", "lock.fill", "high", serviceLabels)
            }
            if company == 0x03C2 || company == 0x1212 {
                return make(device.broadcastName ?? "Environment sensor", "Sensor", "Govee / Qingping-class sensor.", "Sensor", "thermometer.medium", "medium", serviceLabels)
            }

            if let brand = device.manufacturerName {
                let guessed = guessTypeFromBrand(brand, services: serviceKeys)
                return make(
                    device.broadcastName ?? "\(brand) \(guessed.type.lowercased())",
                    guessed.type,
                    "Bluetooth from \(brand). No friendly name in the ad — type inferred from brand/services.",
                    guessed.category,
                    guessed.icon,
                    "low",
                    serviceLabels
                )
            }
            return make(
                device.broadcastName ?? String(format: "BLE device (company 0x%04X)", company),
                "Nearby Bluetooth",
                String(format: "Company ID 0x%04X is present but not in Finch’s brand table. Tap Open to read GAP Device Name if connectable.", company),
                "Nearby Bluetooth",
                "wave.3.right",
                "low",
                serviceLabels
            )
        }

        // --- Service UUID type heuristics ---
        if serviceKeys.contains("180D") || serviceKeys.contains("1822") || serviceKeys.contains("1826") {
            return make(device.broadcastName ?? "Fitness / heart-rate device", "Fitness", "Heart-rate, oximeter, or fitness-machine service.", "Fitness", "heart.fill", "high", serviceLabels)
        }
        if serviceKeys.contains("1812") {
            return make(device.broadcastName ?? "Keyboard, mouse, or remote", "HID / input", "Human Interface Device — input accessory.", "Accessory", "keyboard", "high", serviceLabels)
        }
        if serviceKeys.contains("110B") || serviceKeys.contains("1108") || serviceKeys.contains("111E") {
            return make(device.broadcastName ?? "Audio device", "Headphones", "Bluetooth audio / headset advertisement.", "Headphones", "earbuds", "medium", serviceLabels)
        }
        if serviceKeys.contains("181A") || serviceKeys.contains("1809") {
            return make(device.broadcastName ?? "Environment / thermometer", "Sensor", "Environment sensing or health thermometer service.", "Sensor", "thermometer.medium", "high", serviceLabels)
        }
        if serviceKeys.contains("1810") || serviceKeys.contains("1808") {
            return make(device.broadcastName ?? "Medical / health device", "Health", "Blood pressure or glucose service advertisement.", "Health", "cross.case.fill", "high", serviceLabels)
        }
        if serviceKeys.contains("181D") {
            return make(device.broadcastName ?? "Weight scale", "Health", "Weight scale service.", "Health", "scalemass", "high", serviceLabels)
        }
        if serviceKeys.contains("1802") || serviceKeys.contains("1803") {
            return make(device.broadcastName ?? "Proximity / alert tag", "Tracker", "Immediate alert / link-loss style tag.", "Tracker", "bell.fill", "medium", serviceLabels)
        }

        // --- Named but unclassified ---
        if let broadcast = device.broadcastName {
            return make(broadcast, "Named Bluetooth", "Named device nearby — type not matched; open it to read Device Info.", "Nearby Bluetooth", "wave.3.right", "low", serviceLabels)
        }

        // --- Last resort: never pretend we know nothing if connectable ---
        if device.connectable {
            return make(
                "Unnamed connectable device",
                "Unknown (open to ID)",
                "No name/brand in the advertisement (common for privacy BLE). Tap Open — Finch will read Device Name / Model if exposed.",
                "Unknown",
                "questionmark.circle",
                "low",
                serviceLabels
            )
        }
        return make(
            "Privacy / nameless BLE ad",
            "Unknown (privacy ad)",
            "Broadcast-only with no name or known company ID. Many phones/trackers hide identity on purpose.",
            "Unknown",
            "questionmark.circle",
            "low",
            serviceLabels
        )
    }

    private static func appleIdentity(payload: [UInt8], broadcastName: String?, serviceLabels: [String]) -> BLEFriendlyIdentity {
        let type = payload.first
        switch type {
        case 0x01:
            return make(broadcastName ?? "Apple AirPrint", "Printer", "Apple AirPrint Continuity advertisement.", "Printer", "printer", "medium", serviceLabels)
        case 0x02:
            return make(broadcastName ?? "iBeacon", "Beacon", "Location beacon (stores / venues / apps).", "Beacon", "dot.radiowaves.left.and.right", "high", serviceLabels)
        case 0x05:
            return make(broadcastName ?? "Apple AirDrop", "Phone / computer", "AirDrop / sharing Continuity signal.", "Phone / computer", "square.and.arrow.up", "high", serviceLabels)
        case 0x06:
            return make(broadcastName ?? "HomeKit accessory", "Smart home", "Apple HomeKit Continuity advertisement.", "Smart home", "homekit", "medium", serviceLabels)
        case 0x07:
            return make(broadcastName ?? "AirPods / Beats", "Headphones", "Apple proximity pairing — usually AirPods or Beats.", "Headphones", "earbuds", "high", serviceLabels)
        case 0x08:
            return make(broadcastName ?? "Apple Hey Siri", "Phone / computer", "Hey Siri Continuity advertisement.", "Phone / computer", "waveform", "medium", serviceLabels)
        case 0x09:
            return make(broadcastName ?? "Apple AirPlay", "TV / media", "AirPlay target / source Continuity.", "TV", "airplayvideo", "medium", serviceLabels)
        case 0x0B:
            return make(broadcastName ?? "Apple Magic Move", "Phone / computer", "Apple Magic Move Continuity.", "Phone / computer", "iphone", "low", serviceLabels)
        case 0x0C:
            return make(broadcastName ?? "Apple Handoff", "Phone / computer", "Handoff / Continuity from Mac, iPhone, or iPad.", "Phone / computer", "laptopcomputer.and.iphone", "high", serviceLabels)
        case 0x0D, 0x0E:
            return make(broadcastName ?? "Apple Instant Hotspot", "Phone / computer", "Tethering / Instant Hotspot Continuity.", "Phone / computer", "personalhotspot", "medium", serviceLabels)
        case 0x0F:
            return make(broadcastName ?? "Apple Nearby Action", "Phone / computer", "Nearby Action Continuity (often iPhone/iPad).", "Phone / computer", "iphone", "medium", serviceLabels)
        case 0x10:
            return make(broadcastName ?? "iPhone / iPad nearby", "Phone", "Apple Nearby Info — typically an unlocked iPhone or iPad.", "Phone / tablet", "iphone", "high", serviceLabels)
        case 0x12, 0x16:
            return make(broadcastName ?? "AirTag / Find My item", "Tracker", "Find My network advertisement — AirTag or Find My–enabled accessory.", "Tracker", "location.magnifyingglass", "high", serviceLabels)
        default:
            return make(
                broadcastName ?? "Apple device",
                "Apple",
                payload.isEmpty
                    ? "Apple company ID with empty Continuity payload."
                    : String(format: "Apple Continuity type 0x%02X — phone, watch, Mac, AirPods, or AirTag.", type ?? 0),
                "Apple",
                "apple.logo",
                "medium",
                serviceLabels
            )
        }
    }

    private static func googleIdentity(payload: [UInt8], broadcastName: String?, serviceLabels: [String]) -> BLEFriendlyIdentity {
        // Fast Pair often uses company 0x00E0 with a model ID in the first bytes.
        if !payload.isEmpty {
            return make(broadcastName ?? "Google Fast Pair device", "Headphones / accessory", "Google Fast Pair / Pixel-class advertisement — often earbuds, headphones, or a Pixel phone.", "Phone / accessory", "iphone", "medium", serviceLabels)
        }
        return make(broadcastName ?? "Google device", "Phone / smart home", "Pixel, Chromebook, Nest, or other Google BLE advertisement.", "Phone / smart home", "iphone", "medium", serviceLabels)
    }

    private static func microsoftIdentity(payload: [UInt8], broadcastName: String?, serviceLabels: [String]) -> BLEFriendlyIdentity {
        if payload.first == 0x01 {
            return make(broadcastName ?? "Windows PC (Swift Pair)", "Computer", "Microsoft Swift Pair / CDS — usually a Windows PC advertising for quick pairing.", "Computer", "desktopcomputer", "high", serviceLabels)
        }
        return make(broadcastName ?? "Microsoft / Windows device", "Computer / accessory", "Windows PC, Surface, Xbox controller, or Microsoft accessory.", "Computer / accessory", "desktopcomputer", "medium", serviceLabels)
    }

    private static func samsungIdentity(payload: [UInt8], broadcastName: String?, serviceLabels: [String]) -> BLEFriendlyIdentity {
        // SmartTag-ish packets are often longer manufacturer frames without a local name.
        if payload.count >= 8, broadcastName == nil {
            return make("Samsung SmartTag / Galaxy device", "Tracker / phone", "Samsung manufacturer frame — often SmartTag, Galaxy Buds, Watch, or phone.", "Phone / tracker", "location.magnifyingglass", "medium", serviceLabels)
        }
        return make(broadcastName ?? "Samsung device", "Phone / wearable", "Phone, watch, earbuds, TV, or SmartTag.", "Phone / wearable", "iphone", "medium", serviceLabels)
    }

    private static func guessTypeFromBrand(_ brand: String, services: Set<String>) -> (type: String, category: String, icon: String) {
        let b = brand.lowercased()
        if services.contains("1812") { return ("HID / input", "Accessory", "keyboard") }
        if services.contains("180D") { return ("Fitness", "Fitness", "heart.fill") }
        if b.contains("bose") || b.contains("sony") || b.contains("beats") { return ("Headphones", "Headphones", "earbuds") }
        if b.contains("garmin") || b.contains("fitbit") || b.contains("polar") { return ("Wearable", "Wearable", "applewatch") }
        if b.contains("philips") || b.contains("amazon") || b.contains("sonos") { return ("Smart home", "Smart home", "homepod") }
        if b.contains("tesla") { return ("Vehicle", "Car", "car.fill") }
        return ("Device", "Nearby Bluetooth", "wave.3.right")
    }

    private static func make(
        _ title: String,
        _ deviceType: String,
        _ summary: String,
        _ category: String,
        _ icon: String,
        _ confidence: String,
        _ serviceLabels: [String]
    ) -> BLEFriendlyIdentity {
        let safeIcon: String
        switch icon {
        case "tirepressure": safeIcon = "gauge"
        case "visionpro": safeIcon = "eyeglasses"
        case "scalemass", "scalemass.fill": safeIcon = "heart.text.square"
        case "homekit": safeIcon = "house.fill"
        case "gauge.with.dots.needle.33percent": safeIcon = "gauge"
        default: safeIcon = icon
        }
        return BLEFriendlyIdentity(
            title: title,
            deviceType: deviceType,
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

    static func normalizeUUID(_ uuid: String) -> String {
        let compact = uuid.replacingOccurrences(of: "-", with: "").uppercased()
        if compact.count == 4 { return compact }
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
        if compact.count == 32, compact.hasPrefix("0000"), compact.hasSuffix("00001000800000805F9B34FB") {
            let start = compact.index(compact.startIndex, offsetBy: 4)
            let end = compact.index(compact.startIndex, offsetBy: 8)
            let short = String(compact[start..<end])
            return known[short] ?? "Service \(short)"
        }
        if compact.count == 4 {
            return known[compact] ?? "Char \(compact)"
        }
        // Characteristic short form inside full UUID
        if compact.count == 32, compact.hasPrefix("0000") {
            let start = compact.index(compact.startIndex, offsetBy: 4)
            let end = compact.index(compact.startIndex, offsetBy: 8)
            let short = String(compact[start..<end])
            return known[short] ?? "UUID \(short)"
        }
        return "Service \(String(uuid.prefix(8)))…"
    }

    private static let known: [String: String] = [
        "1800": "Generic Access",
        "1801": "Generic Attribute",
        "180A": "Device Information",
        "180F": "Battery",
        "180D": "Heart rate",
        "1812": "HID (keyboard/mouse)",
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
        "FEF5": "Apple Continuity",
        "3100": "Raven GPS / location",
        "3200": "Raven power / battery",
        "3300": "Raven network status",
        "3400": "Raven upload stats",
        "3500": "Raven error / fault",
        "1802": "Immediate alert",
        "1803": "Link loss",
        "1804": "Tx power",
        "1805": "Current time",
        "1811": "Alert notification",
        "1810": "Blood pressure",
        "1808": "Glucose",
        "1809": "Health thermometer",
        "2A00": "Device name",
        "2A01": "Appearance",
        "2A19": "Battery level",
        "2A24": "Model number",
        "2A25": "Serial number",
        "2A26": "Firmware revision",
        "2A27": "Hardware revision",
        "2A28": "Software revision",
        "2A29": "Manufacturer name",
        "2A50": "PnP ID"
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
