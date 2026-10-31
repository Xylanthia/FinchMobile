import Foundation
import CoreBluetooth

struct BLEInferredExport: Codable, Hashable {
    var manufacturerName: String?
    var manufacturerNameRule: String?
    var categories: [String]?
    var ruleIds: [String]?
    var estimatedDistanceMeters: Double?
}

enum BLEConnectionState: String, Codable, Hashable {
    case disconnected
    case connecting
    case discovering
    case connected
    case failed
}

struct GATTDescriptorInfo: Codable, Hashable, Identifiable {
    var id: String { uuid }
    var uuid: String
    var valueHex: String?
    var valueUTF8: String?
    var valueSummary: String {
        BLEValueExplainer.explainCharacteristic(uuid: uuid, utf8: valueUTF8, hex: valueHex)
    }
}

struct GATTCharacteristicInfo: Codable, Hashable, Identifiable {
    var id: String { uuid }
    var uuid: String
    var properties: [String]
    var valueHex: String?
    var valueUTF8: String?
    var descriptors: [GATTDescriptorInfo]

    init(
        uuid: String,
        properties: [String],
        valueHex: String? = nil,
        valueUTF8: String? = nil,
        descriptors: [GATTDescriptorInfo] = []
    ) {
        self.uuid = uuid
        self.properties = properties
        self.valueHex = valueHex
        self.valueUTF8 = valueUTF8
        self.descriptors = descriptors
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try c.decode(String.self, forKey: .uuid)
        properties = try c.decodeIfPresent([String].self, forKey: .properties) ?? []
        valueHex = try c.decodeIfPresent(String.self, forKey: .valueHex)
        valueUTF8 = try c.decodeIfPresent(String.self, forKey: .valueUTF8)
        descriptors = try c.decodeIfPresent([GATTDescriptorInfo].self, forKey: .descriptors) ?? []
    }

    var valueSummary: String {
        BLEValueExplainer.explainCharacteristic(uuid: uuid, utf8: valueUTF8, hex: valueHex)
    }

    private enum CodingKeys: String, CodingKey {
        case uuid, properties, valueHex, valueUTF8, descriptors
    }
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
    var nameStatus: ObservationStatus
    var localName: String?
    var localNameStatus: ObservationStatus
    /// GAP Device Name (0x2A00), Model Number (0x2A24), or similar after GATT connect.
    var gattDeviceName: String?
    var gattDeviceNameStatus: ObservationStatus
    /// RSSI in dBm. `nil` when CoreBluetooth reports 127 (unavailable) or the value fails sanitizer bounds.
    var rssi: Int?
    var lastSeen: Date
    var advertisementHex: String
    var manufacturerCompanyId: UInt16?
    /// Payload only (company ID bytes stripped) — space-separated hex.
    var manufacturerDataHex: String?
    /// Full manufacturer AD including little-endian company ID — space-separated hex.
    var manufacturerDataRawHex: String?
    var manufacturerName: String?
    var serviceUUIDs: [String]
    /// Service-data UUID → payload hex (Eddystone, Tile, Continuity helpers).
    var serviceData: [String: String]
    var txPower: Int?
    /// Raw Tx Power Level AD value as hex byte (signed).
    var txPowerHex: String?
    /// GAP Flags AD type when CoreBluetooth exposes it (`kCBAdvDataFlags`); else nil.
    var advertisementFlags: UInt8?
    var advertisementFlagsHex: String?
    var advertisementFlagsSummary: String?
    var connectable: Bool
    var overflowServiceUUIDs: [String]
    var solicitedServiceUUIDs: [String]
    var connectionState: BLEConnectionState
    var gattError: String?
    var gattServices: [GATTServiceInfo]
    /// Auto-classified categories (refreshed on merge / scan).
    var categories: [BLEDeviceCategory]
    /// User re-classification; when set, filters/exports use this alone.
    var manualCategoryOverride: BLEDeviceCategory?
    /// First advertisement this session (survey).
    var firstSeen: Date?
    /// How many ads merged this session — driving quality metric.
    var hitCount: Int?
    /// Strongest RSSI (closest pass).
    var rssiPeak: Int?
    /// Weakest RSSI kept.
    var rssiMin: Int?
    var collectorLocation: ObservationLocation?
    var latitude: Double?
    var longitude: Double?
    var gpsAccuracyMeters: Double?

    init(
        identifier: UUID,
        name: String? = nil,
        nameStatus: ObservationStatus = .notAvailable,
        localName: String? = nil,
        localNameStatus: ObservationStatus = .notAvailable,
        gattDeviceName: String? = nil,
        gattDeviceNameStatus: ObservationStatus = .notChecked,
        rssi: Int? = nil,
        lastSeen: Date = Date(),
        advertisementHex: String,
        manufacturerCompanyId: UInt16? = nil,
        manufacturerDataHex: String? = nil,
        manufacturerDataRawHex: String? = nil,
        manufacturerName: String? = nil,
        serviceUUIDs: [String] = [],
        serviceData: [String: String] = [:],
        txPower: Int? = nil,
        txPowerHex: String? = nil,
        advertisementFlags: UInt8? = nil,
        advertisementFlagsHex: String? = nil,
        advertisementFlagsSummary: String? = nil,
        connectable: Bool = false,
        overflowServiceUUIDs: [String] = [],
        solicitedServiceUUIDs: [String] = [],
        connectionState: BLEConnectionState = .disconnected,
        gattError: String? = nil,
        gattServices: [GATTServiceInfo] = [],
        categories: [BLEDeviceCategory] = [],
        manualCategoryOverride: BLEDeviceCategory? = nil,
        firstSeen: Date? = nil,
        hitCount: Int? = 1,
        rssiPeak: Int? = nil,
        rssiMin: Int? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        gpsAccuracyMeters: Double? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.nameStatus = nameStatus
        self.localName = localName
        self.localNameStatus = localNameStatus
        self.gattDeviceName = gattDeviceName
        self.gattDeviceNameStatus = gattDeviceNameStatus
        self.rssi = rssi
        self.lastSeen = lastSeen
        self.collectorLocation = ObservationLocation.capture(at: lastSeen)
        self.advertisementHex = advertisementHex
        self.manufacturerCompanyId = manufacturerCompanyId
        self.manufacturerDataHex = manufacturerDataHex
        self.manufacturerDataRawHex = manufacturerDataRawHex
        self.manufacturerName = manufacturerName
        self.serviceUUIDs = serviceUUIDs
        self.serviceData = serviceData
        self.txPower = txPower
        self.txPowerHex = txPowerHex
        self.advertisementFlags = advertisementFlags
        self.advertisementFlagsHex = advertisementFlagsHex
        self.advertisementFlagsSummary = advertisementFlagsSummary
        self.connectable = connectable
        self.overflowServiceUUIDs = overflowServiceUUIDs
        self.solicitedServiceUUIDs = solicitedServiceUUIDs
        self.connectionState = connectionState
        self.gattError = gattError
        self.gattServices = gattServices
        self.categories = categories
        self.manualCategoryOverride = manualCategoryOverride
        self.firstSeen = firstSeen ?? lastSeen
        self.hitCount = hitCount ?? 1
        self.rssiPeak = rssiPeak
        self.rssiMin = rssiMin
        self.latitude = latitude
        self.longitude = longitude
        self.gpsAccuracyMeters = gpsAccuracyMeters
        applyEvidenceSanitizer()
        if self.categories.isEmpty {
            self.categories = BLECategoryClassifier.classify(self)
        }
    }

    mutating func applyEvidenceSanitizer() {
        let gattChecked = gattDeviceNameStatus != .notChecked
            || !gattServices.isEmpty
            || (gattDeviceName?.isEmpty == false)
        let patch = BLEEvidenceSanitizer.sanitizeDeviceFields(
            rssi: rssi,
            rssiPeak: rssiPeak,
            rssiMin: rssiMin,
            txPower: txPower,
            latitude: latitude,
            longitude: longitude,
            gpsAccuracyMeters: gpsAccuracyMeters,
            name: name,
            localName: localName,
            gattDeviceName: gattDeviceName,
            gattWasChecked: gattChecked,
            lastSeen: lastSeen,
            firstSeen: firstSeen
        )
        rssi = patch.rssi
        rssiPeak = patch.rssiPeak
        rssiMin = patch.rssiMin
        txPower = patch.txPower
        latitude = patch.latitude
        longitude = patch.longitude
        gpsAccuracyMeters = patch.gpsAccuracyMeters
        name = patch.name
        nameStatus = patch.nameStatus
        localName = patch.localName
        localNameStatus = patch.localNameStatus
        if gattChecked {
            gattDeviceName = patch.gattDeviceName
            gattDeviceNameStatus = patch.gattDeviceNameStatus
        } else {
            gattDeviceName = nil
            gattDeviceNameStatus = .notChecked
        }
        if let last = patch.lastSeen { lastSeen = last }
        firstSeen = patch.firstSeen ?? firstSeen
    }

    var resolvedCategories: [BLEDeviceCategory] {
        if let manualCategoryOverride { return [manualCategoryOverride] }
        if categories.isEmpty { return BLECategoryClassifier.classify(self) }
        return categories
    }

    var primaryCategory: BLEDeviceCategory {
        resolvedCategories.first ?? .unknown
    }

    mutating func refreshCategories() {
        if manualCategoryOverride == nil {
            categories = BLECategoryClassifier.classify(self)
        }
    }

    mutating func setManualCategory(_ category: BLEDeviceCategory?) {
        manualCategoryOverride = category
        if let category {
            categories = [category]
        } else {
            categories = BLECategoryClassifier.classify(self)
        }
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
        guard let rssi else { return 0 }
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
        guard rssi != nil else { return "not_available" }
        switch signalBars {
        case 4: return "Very strong"
        case 3: return "Strong"
        case 2: return "OK"
        case 1: return "Weak"
        default: return "Very weak"
        }
    }

    var estimatedDistanceMeters: Double? {
        guard let rssi, let tx = txPower else { return nil }
        let measuredPower = Double(tx)
        let pathLossExponent = 2.2
        let rssiValue = Double(rssi)
        let exponent = (measuredPower - rssiValue) / (10.0 * pathLossExponent)
        let meters = pow(10.0, exponent)
        return min(max(meters, 0.1), 80.0)
    }

    var distanceLabel: String {
        guard let m = estimatedDistanceMeters else { return "range unknown (no TX power advertised)" }
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
        guard let m = estimatedDistanceMeters else { return "range unknown" }
        return m < 10 ? String(format: "~%.1f m", m) : String(format: "~%.0f m", m)
    }

    var copyText: String {
        let identity = friendly
        var lines = [
            identity.title,
            "Type: \(identity.deviceType)",
            "Friendly category: \(identity.category)",
            "Taxonomy: \(resolvedCategories.map(\.label).joined(separator: ", "))",
            identity.summary,
            "Distance: \(distanceLabel)",
            "Signal: \(signalLabel) (\(rssi.map { "\($0) dBm" } ?? "not_available"))",
            "Status: \(connectionLabel)",
            "Connection: \(connectabilityLabel)",
            "Broadcast name: \(broadcastName ?? "—")",
            "Brand hint: \(manufacturerName ?? "—")",
            "Company: \(manufacturerCompanyId.map { BLEValueExplainer.explainCompanyId($0) } ?? "—")",
            "ID: \(identifier.uuidString)",
            "Hits this session: \(hitCount ?? 1)",
            "RSSI peak/min: \(rssiPeak.map(String.init) ?? "not_available") / \(rssiMin.map(String.init) ?? "not_available") dBm",
            "ID confidence: \(identity.confidence)"
        ]
        if !identity.evidence.isEmpty {
            lines.append("Evidence: \(identity.evidence.joined(separator: " | "))")
        }
        if let lat = latitude, let lon = longitude {
            let accText = gpsAccuracyMeters.map { String(format: "±%.0fm", $0) } ?? "accuracy not_available"
            lines.append(String(format: "GPS: %.6f, %.6f (%@)", lat, lon, accText))
        }
        if let override = manualCategoryOverride {
            lines.append("Manual category override: \(override.label)")
        }
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
        if manufacturerCompanyId != nil || !(manufacturerDataHex ?? "").isEmpty || !(manufacturerDataRawHex ?? "").isEmpty {
            lines.append(
                "Manufacturer: \(BLEValueExplainer.explainManufacturer(companyId: manufacturerCompanyId, brand: manufacturerName, payloadHex: manufacturerDataHex))"
            )
            if let raw = manufacturerDataRawHex, !raw.isEmpty {
                lines.append("Manufacturer hex (raw): \(raw)")
            }
            if let payload = manufacturerDataHex, !payload.isEmpty {
                lines.append("Manufacturer hex (payload): \(payload)")
            }
        }
        if let tx = txPower {
            lines.append("Tx Power: \(tx) dBm")
            if let hx = txPowerHex { lines.append("Tx Power hex: \(hx)") }
        }
        if let flagsSummary = advertisementFlagsSummary {
            lines.append("Flags: \(flagsSummary)")
        }
        if let flagsHex = advertisementFlagsHex {
            lines.append("Flags hex: \(flagsHex)")
        }
        if !serviceData.isEmpty {
            for (uuid, hex) in serviceData.sorted(by: { $0.key < $1.key }) {
                lines.append(BLEValueExplainer.explainServiceData(uuid: uuid, hex: hex))
                lines.append("  Service data hex (\(uuid)): \(hex)")
            }
        }
        for svc in gattServices {
            lines.append("GATT service: \(BLEServiceNames.label(forUUID: svc.uuid)) [\(svc.uuid)]")
            for ch in svc.characteristics {
                let explained = ch.valueSummary
                lines.append("  - \(BLEServiceNames.label(forUUID: ch.uuid)): \(explained)")
                if let hex = ch.valueHex, !hex.isEmpty {
                    lines.append("    value hex: \(hex)")
                }
                for desc in ch.descriptors {
                    lines.append("    descriptor \(BLEServiceNames.label(forUUID: desc.uuid)): \(desc.valueSummary)")
                    if let hex = desc.valueHex, !hex.isEmpty {
                        lines.append("      descriptor hex: \(hex)")
                    }
                }
            }
        }
        if !advertisementHex.isEmpty {
            lines.append(BLEValueExplainer.explainAdvertisementBlob(advertisementHex))
            lines.append("Advertisement dump: \(advertisementHex)")
        }
        return lines.joined(separator: "\n")
    }

    /// Full structured export for clipboard / ShareLink.
    func exportJSON(pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    var exportJSONString: String {
        (try? String(data: exportJSON(), encoding: .utf8)) ?? "{}"
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
        var mfgRawHex: String?
        var mfgName: String?
        if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, data.count >= 2 {
            let company = UInt16(data[0]) | (UInt16(data[1]) << 8)
            mfgCompany = company
            mfgRawHex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
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

        let txHex: String? = tx.map { String(format: "%02X", UInt8(bitPattern: Int8(clamping: $0))) }
        let (flags, flagsHex, flagsSummary) = parseAdvertisementFlags(
            advertisementData: advertisementData,
            connectable: connectable
        )

        let rawRSSI = rssi.intValue
        let sanitizedRSSI = BLEEvidenceSanitizer.sanitizeRSSI(rawRSSI)
        let (advName, advNameStatus) = BLEEvidenceSanitizer.sanitizeName(peripheral.name, sourceNilMeans: .notAvailable)
        let (locName, locNameStatus) = BLEEvidenceSanitizer.sanitizeName(localName, sourceNilMeans: .notAvailable)
        let txSan = BLEEvidenceSanitizer.sanitizeTxPower(tx)
        let (lat, lon, acc) = BLEEvidenceSanitizer.sanitizeCoordinate(
            lat: ObservationLocation.capture().latitude,
            lon: ObservationLocation.capture().longitude,
            accuracy: ObservationLocation.capture().horizontalAccuracyMeters
        )

        var device = BLEDevice(
            identifier: peripheral.identifier,
            name: advName,
            nameStatus: advNameStatus,
            localName: locName,
            localNameStatus: locNameStatus,
            gattDeviceName: nil,
            gattDeviceNameStatus: .notChecked,
            rssi: sanitizedRSSI,
            lastSeen: Date(),
            advertisementHex: encodeAdvertisement(advertisementData),
            manufacturerCompanyId: mfgCompany,
            manufacturerDataHex: mfgHex,
            manufacturerDataRawHex: mfgRawHex,
            manufacturerName: mfgName,
            serviceUUIDs: services,
            serviceData: serviceDataMap,
            txPower: txSan,
            txPowerHex: txSan == nil ? nil : txHex,
            advertisementFlags: flags,
            advertisementFlagsHex: flagsHex,
            advertisementFlagsSummary: flagsSummary,
            connectable: connectable,
            overflowServiceUUIDs: overflow,
            solicitedServiceUUIDs: solicited,
            firstSeen: Date(),
            hitCount: 1,
            rssiPeak: sanitizedRSSI,
            rssiMin: sanitizedRSSI,
            latitude: lat,
            longitude: lon,
            gpsAccuracyMeters: acc
        )
        device.refreshCategories()
        return device
    }

    /// Best-effort GAP Flags. CoreBluetooth sometimes exposes undocumented `kCBAdvDataFlags`.
    private static func parseAdvertisementFlags(
        advertisementData: [String: Any],
        connectable: Bool
    ) -> (UInt8?, String?, String?) {
        let flagKeys = ["kCBAdvDataFlags", "CBAdvertisementDataFlagsKey"]
        var raw: UInt8?
        for key in flagKeys {
            if let n = advertisementData[key] as? NSNumber {
                raw = n.uint8Value
                break
            }
            if let i = advertisementData[key] as? Int {
                raw = UInt8(clamping: i)
                break
            }
        }
        if let raw {
            return (raw, String(format: "%02X", raw), explainFlagsByte(raw, connectable: connectable))
        }
        // iOS often strips the Flags AD type — still surface connectable / overflow context.
        let summary = "GAP Flags AD not exposed by CoreBluetooth · connectable=\(connectable ? "yes" : "no")"
        return (nil, nil, summary)
    }

    private static func explainFlagsByte(_ flags: UInt8, connectable: Bool) -> String {
        var parts: [String] = []
        if flags & 0x01 != 0 { parts.append("LE Limited Discoverable") }
        if flags & 0x02 != 0 { parts.append("LE General Discoverable") }
        if flags & 0x04 != 0 { parts.append("BR/EDR Not Supported") }
        if flags & 0x08 != 0 { parts.append("Simultaneous LE + BR/EDR Controller") }
        if flags & 0x10 != 0 { parts.append("Simultaneous LE + BR/EDR Host") }
        if parts.isEmpty { parts.append("no standard bits set") }
        parts.append("connectable=\(connectable ? "yes" : "no")")
        return parts.joined(separator: " · ")
    }

    enum CodingKeys: String, CodingKey {
        case identifier, name, nameStatus, localName, localNameStatus
        case gattDeviceName, gattDeviceNameStatus, rssi, lastSeen, advertisementHex
        case manufacturerCompanyId, manufacturerDataHex, manufacturerDataRawHex, manufacturerName
        case serviceUUIDs, serviceData, txPower, txPowerHex
        case advertisementFlags, advertisementFlagsHex, advertisementFlagsSummary
        case connectable, overflowServiceUUIDs, solicitedServiceUUIDs
        case connectionState, gattError, gattServices
        case categories, manualCategoryOverride
        case firstSeen, hitCount, rssiPeak, rssiMin
        case latitude, longitude, gpsAccuracyMeters, collectorLocation
        case inferred
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try c.decode(UUID.self, forKey: .identifier)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        nameStatus = try c.decodeIfPresent(ObservationStatus.self, forKey: .nameStatus) ?? (name == nil ? .notAvailable : .present)
        localName = try c.decodeIfPresent(String.self, forKey: .localName)
        localNameStatus = try c.decodeIfPresent(ObservationStatus.self, forKey: .localNameStatus) ?? (localName == nil ? .notAvailable : .present)
        gattDeviceName = try c.decodeIfPresent(String.self, forKey: .gattDeviceName)
        gattDeviceNameStatus = try c.decodeIfPresent(ObservationStatus.self, forKey: .gattDeviceNameStatus)
            ?? (gattDeviceName == nil ? .notChecked : .present)
        rssi = try c.decodeIfPresent(Int.self, forKey: .rssi)
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen) ?? Date()
        advertisementHex = try c.decodeIfPresent(String.self, forKey: .advertisementHex) ?? ""
        manufacturerCompanyId = try c.decodeIfPresent(UInt16.self, forKey: .manufacturerCompanyId)
        manufacturerDataHex = try c.decodeIfPresent(String.self, forKey: .manufacturerDataHex)
        manufacturerDataRawHex = try c.decodeIfPresent(String.self, forKey: .manufacturerDataRawHex)
        manufacturerName = try c.decodeIfPresent(String.self, forKey: .manufacturerName)
        serviceUUIDs = try c.decodeIfPresent([String].self, forKey: .serviceUUIDs) ?? []
        serviceData = try c.decodeIfPresent([String: String].self, forKey: .serviceData) ?? [:]
        txPower = try c.decodeIfPresent(Int.self, forKey: .txPower)
        txPowerHex = try c.decodeIfPresent(String.self, forKey: .txPowerHex)
        advertisementFlags = try c.decodeIfPresent(UInt8.self, forKey: .advertisementFlags)
        advertisementFlagsHex = try c.decodeIfPresent(String.self, forKey: .advertisementFlagsHex)
        advertisementFlagsSummary = try c.decodeIfPresent(String.self, forKey: .advertisementFlagsSummary)
        connectable = try c.decodeIfPresent(Bool.self, forKey: .connectable) ?? false
        overflowServiceUUIDs = try c.decodeIfPresent([String].self, forKey: .overflowServiceUUIDs) ?? []
        solicitedServiceUUIDs = try c.decodeIfPresent([String].self, forKey: .solicitedServiceUUIDs) ?? []
        connectionState = try c.decodeIfPresent(BLEConnectionState.self, forKey: .connectionState) ?? .disconnected
        gattError = try c.decodeIfPresent(String.self, forKey: .gattError)
        gattServices = try c.decodeIfPresent([GATTServiceInfo].self, forKey: .gattServices) ?? []
        categories = try c.decodeIfPresent([BLEDeviceCategory].self, forKey: .categories) ?? []
        manualCategoryOverride = try c.decodeIfPresent(BLEDeviceCategory.self, forKey: .manualCategoryOverride)
        firstSeen = try c.decodeIfPresent(Date.self, forKey: .firstSeen)
        hitCount = try c.decodeIfPresent(Int.self, forKey: .hitCount)
        rssiPeak = try c.decodeIfPresent(Int.self, forKey: .rssiPeak)
        rssiMin = try c.decodeIfPresent(Int.self, forKey: .rssiMin)
        collectorLocation = try c.decodeIfPresent(ObservationLocation.self, forKey: .collectorLocation)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        gpsAccuracyMeters = try c.decodeIfPresent(Double.self, forKey: .gpsAccuracyMeters)
        applyEvidenceSanitizer()
        if categories.isEmpty {
            categories = BLECategoryClassifier.classify(self)
        }
    }

    func encode(to encoder: Encoder) throws {
        var device = self
        device.applyEvidenceSanitizer()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(device.identifier, forKey: .identifier)
        try c.encodeIfPresent(device.name, forKey: .name)
        try c.encode(device.nameStatus, forKey: .nameStatus)
        try c.encodeIfPresent(device.localName, forKey: .localName)
        try c.encode(device.localNameStatus, forKey: .localNameStatus)
        try c.encodeIfPresent(device.gattDeviceName, forKey: .gattDeviceName)
        try c.encode(device.gattDeviceNameStatus, forKey: .gattDeviceNameStatus)
        try encodeNullOrValue(device.rssi, forKey: .rssi, into: &c)
        try c.encode(device.lastSeen, forKey: .lastSeen)
        try c.encodeIfPresent(device.collectorLocation, forKey: .collectorLocation)
        try c.encode(device.advertisementHex, forKey: .advertisementHex)
        try c.encodeIfPresent(device.manufacturerCompanyId, forKey: .manufacturerCompanyId)
        try c.encodeIfPresent(device.manufacturerDataHex, forKey: .manufacturerDataHex)
        try c.encodeIfPresent(device.manufacturerDataRawHex, forKey: .manufacturerDataRawHex)
        try c.encode(device.serviceUUIDs, forKey: .serviceUUIDs)
        try c.encode(device.serviceData, forKey: .serviceData)
        try encodeNullOrValue(device.txPower, forKey: .txPower, into: &c)
        try c.encodeIfPresent(device.txPowerHex, forKey: .txPowerHex)
        try c.encodeIfPresent(device.advertisementFlags, forKey: .advertisementFlags)
        try c.encodeIfPresent(device.advertisementFlagsHex, forKey: .advertisementFlagsHex)
        try c.encodeIfPresent(device.advertisementFlagsSummary, forKey: .advertisementFlagsSummary)
        try c.encode(device.connectable, forKey: .connectable)
        try c.encode(device.overflowServiceUUIDs, forKey: .overflowServiceUUIDs)
        try c.encode(device.solicitedServiceUUIDs, forKey: .solicitedServiceUUIDs)
        try c.encode(device.connectionState, forKey: .connectionState)
        try c.encodeIfPresent(device.gattError, forKey: .gattError)
        try c.encode(device.gattServices, forKey: .gattServices)
        try c.encodeIfPresent(device.manualCategoryOverride, forKey: .manualCategoryOverride)
        try c.encodeIfPresent(device.firstSeen, forKey: .firstSeen)
        try c.encodeIfPresent(device.hitCount, forKey: .hitCount)
        try encodeNullOrValue(device.rssiPeak, forKey: .rssiPeak, into: &c)
        try encodeNullOrValue(device.rssiMin, forKey: .rssiMin, into: &c)
        try encodeNullOrValue(device.latitude, forKey: .latitude, into: &c)
        try encodeNullOrValue(device.longitude, forKey: .longitude, into: &c)
        try encodeNullOrValue(device.gpsAccuracyMeters, forKey: .gpsAccuracyMeters, into: &c)

        let ruleIds = BLECategoryClassifier.matchedRuleIds(for: device)
        let cats = device.resolvedCategories.filter { $0 != .unknown }
        let inferred = BLEInferredExport(
            manufacturerName: device.manufacturerCompanyId != nil ? device.manufacturerName : nil,
            manufacturerNameRule: (device.manufacturerName != nil && device.manufacturerCompanyId != nil) ? "known_company_id" : nil,
            categories: cats.isEmpty ? nil : cats.map(\.rawValue),
            ruleIds: ruleIds.isEmpty ? nil : ruleIds,
            estimatedDistanceMeters: device.estimatedDistanceMeters
        )
        try c.encode(inferred, forKey: .inferred)
    }

    private func encodeNullOrValue<T: Encodable>(
        _ value: T?,
        forKey key: CodingKeys,
        into c: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value {
            try c.encode(value, forKey: key)
        } else {
            try c.encodeNil(forKey: key)
        }
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
        let preservedOverride = manualCategoryOverride
        let preservedGattStatus = gattDeviceNameStatus
        if firstSeen == nil { firstSeen = newer.firstSeen ?? lastSeen }
        hitCount = (hitCount ?? 1) + 1
        let extrema = BLEEvidenceSanitizer.mergeRSSIExtrema(
            current: rssi,
            incoming: newer.rssi,
            peak: rssiPeak,
            floor: rssiMin
        )
        rssi = extrema.rssi
        rssiPeak = extrema.peak
        rssiMin = extrema.min
        lastSeen = newer.lastSeen
        collectorLocation = newer.collectorLocation
        latitude = newer.collectorLocation?.latitude
        longitude = newer.collectorLocation?.longitude
        gpsAccuracyMeters = newer.collectorLocation?.horizontalAccuracyMeters
        if let n = newer.name, !n.isEmpty {
            name = n
            nameStatus = .present
        }
        if let n = newer.localName, !n.isEmpty {
            localName = n
            localNameStatus = .present
        }
        if let n = newer.gattDeviceName, !n.isEmpty {
            gattDeviceName = n
            gattDeviceNameStatus = .present
        }
        if newer.manufacturerCompanyId != nil {
            manufacturerCompanyId = newer.manufacturerCompanyId
            manufacturerDataHex = newer.manufacturerDataHex
            manufacturerDataRawHex = newer.manufacturerDataRawHex
            manufacturerName = newer.manufacturerName
        }
        if !newer.serviceUUIDs.isEmpty { serviceUUIDs = newer.serviceUUIDs }
        if !newer.serviceData.isEmpty {
            for (k, v) in newer.serviceData { serviceData[k] = v }
        }
        advertisementHex = newer.advertisementHex
        if let tx = newer.txPower {
            txPower = tx
            txPowerHex = newer.txPowerHex
        }
        if newer.advertisementFlags != nil || newer.advertisementFlagsSummary != nil {
            advertisementFlags = newer.advertisementFlags
            advertisementFlagsHex = newer.advertisementFlagsHex
            advertisementFlagsSummary = newer.advertisementFlagsSummary
        }
        connectable = newer.connectable
        if newer.connectionState != .disconnected || !newer.gattServices.isEmpty {
            connectionState = newer.connectionState
            gattServices = newer.gattServices
            gattError = newer.gattError
        }
        manualCategoryOverride = preservedOverride
        if preservedGattStatus == .notChecked, newer.gattDeviceNameStatus == .notChecked {
            gattDeviceNameStatus = .notChecked
        }
        applyEvidenceSanitizer()
        refreshCategories()
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
            gattDeviceNameStatus = .present
        } else if let model = found["2A24"] {
            let mfg = found["2A29"]
            gattDeviceName = mfg.map { "\($0) \(model)" } ?? model
            gattDeviceNameStatus = .present
        } else if let mfg = found["2A29"] {
            gattDeviceName = mfg
            gattDeviceNameStatus = .present
        } else {
            gattDeviceNameStatus = .notAvailable
        }
        if manufacturerName == nil, let mfg = found["2A29"] {
            manufacturerName = mfg
        }
        applyEvidenceSanitizer()
        refreshCategories()
    }
}

// MARK: - Manufacturer company IDs (Bluetooth SIG assigned numbers, common subset)

/// Full Bluetooth SIG Assigned Numbers tables — the same source as the ARIA handheld's
/// ble_companies.inc — so the phone names every advertiser the handheld can:
/// 3,893 company identifiers and 688 member service UUIDs (FCxx–FExx).
enum BLESIGTables {
    static let companies: [UInt16: String] = {
        var out: [UInt16: String] = [:]
        for (key, value) in strings("ble_companies") {
            if let id = UInt16(key, radix: 16) { out[id] = value }
        }
        return out
    }()

    static let memberServices: [String: String] = strings("ble_member_uuids")

    private static func strings(_ resource: String) -> [String: String] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    /// Company that registered a 16-bit member service UUID (e.g. FEED → Tile, Inc.).
    static func memberCompany(_ shortUUID: String) -> String? {
        memberServices[shortUUID.uppercased()]
    }

    /// "Samsung Electronics Co., Ltd." → "Samsung Electronics" for display.
    static func shortName(_ registered: String) -> String {
        var name = registered
        for suffix in [", Inc.", " Inc.", ", Inc", " Inc", " LLC", ", LLC", " Co., Ltd.", " Co.,Ltd.", " Co., Ltd", " Co.,Ltd",
                       " Ltd.", " Ltd", " GmbH", " AG", " AB", " A/S", " ASA", " B.V.", " BV", " S.A.", " SA", " SAS",
                       " S.r.l.", " Corporation", " Corp.", " Corp", " Limited", " Oy", " Pty", " plc", " PLC", " KG", " Co."] {
            if name.hasSuffix(suffix) { name = String(name.dropLast(suffix.count)) }
        }
        return name.trimmingCharacters(in: CharacterSet(charactersIn: " ,."))
    }
}

enum BLEManufacturerLookup {
    /// Curated short names first, then the full Bluetooth SIG company table.
    static func name(for companyId: UInt16) -> String? {
        known[companyId] ?? BLESIGTables.companies[companyId].map(BLESIGTables.shortName)
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
        0x0960: "DJI",
        0x0DE8: "Vivint",
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
    /// Why this label was chosen. Empty means “name only / unknown”.
    var evidence: [String]

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
                flock.model,
                flock.reason,
                flock.confidence == "high" ? "Flock-class camera" : "Possible camera",
                "camera.metering.spot",
                flock.confidence,
                serviceLabels,
                evidence: [flock.reason]
            )
        }
        if let phone = PhoneDetector.matchBLE(device) {
            return make(
                phone.title,
                "Phone / tablet",
                phone.reason,
                "Phone / tablet",
                "iphone",
                phone.confidence,
                serviceLabels,
                evidence: [phone.reason]
            )
        }
        if ComputerDetector.matchBLE(device) {
            return make(
                device.broadcastName ?? "Windows / Mac computer",
                "Computer",
                "Laptop/desktop BLE (Swift Pair or computer name).",
                "Computer / Laptop",
                "laptopcomputer",
                "high",
                serviceLabels,
                evidence: ["computer name or Microsoft Swift Pair"]
            )
        }
        if GamingDetector.matchBLE(device) {
            return make(
                device.broadcastName ?? "Game controller",
                "Game controller",
                "Controller / console accessory name match.",
                "Game controller",
                "gamecontroller",
                "high",
                serviceLabels,
                evidence: ["broadcast name matches a known controller"]
            )
        }
        if let car = AutomotiveDetector.matchBLE(device) {
            return make(
                car.title,
                "Vehicle",
                car.reason,
                "Car / Automotive",
                "car.fill",
                car.confidence,
                serviceLabels,
                evidence: [car.reason]
            )
        }
        if BeaconDetector.matchBLE(device) {
            return make(
                device.broadcastName ?? "Beacon",
                "Beacon",
                "iBeacon, Eddystone, or Estimote-class advertisement.",
                "Beacon / Wayfinding",
                "dot.radiowaves.left.and.right",
                "high",
                serviceLabels,
                evidence: ["iBeacon/Eddystone/FEAA"]
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
            return make(device.broadcastName ?? "Eddystone beacon", "Beacon", "Google Eddystone service FEAA.", "Beacon / Wayfinding", "dot.radiowaves.left.and.right", "high", serviceLabels, evidence: ["service FEAA Eddystone"])
        }
        if serviceKeys.contains("FEED") || serviceKeys.contains("FEEC") {
            return make(device.broadcastName ?? "Tile tracker", "Tracker", "Tile item finder advertising nearby (service FEED/FEEC, registered to Tile, Inc.).", "Tracker", "location.magnifyingglass", "high", serviceLabels, evidence: ["Tile member service UUID"])
        }
        if serviceKeys.contains("FE2C") {
            return make(device.broadcastName ?? "Google Fast Pair device", "Headphones / accessory", "Google Fast Pair advertisement (service FE2C, registered to Google) — typically earbuds, headphones or a speaker offering one-tap Android pairing.", "Headphones", "earbuds", "medium", serviceLabels, evidence: ["service FE2C Google Fast Pair"])
        }
        if serviceKeys.contains("FD6F") {
            return make(device.broadcastName ?? "Phone (Exposure Notification)", "Phone / tablet", "FD6F Exposure Notification — almost always a phone.", "Phone / tablet", "iphone", "medium", serviceLabels, evidence: ["service FD6F"])
        }
        if serviceKeys.contains("FFF6") || serviceKeys.contains("FFF7") {
            return make(device.broadcastName ?? "Matter / Thread device", "Smart home", "Matter commissioning BLE UUID.", "Smart Home / IoT", "house.fill", "high", serviceLabels, evidence: ["Matter BLE UUID FFF6/FFF7"])
        }
        if serviceKeys.contains("1827") || serviceKeys.contains("1828") {
            return make(device.broadcastName ?? "Bluetooth Mesh node", "Smart home", "BLE Mesh provisioning/proxy service.", "Smart Home / IoT", "house.fill", "high", serviceLabels, evidence: ["Mesh service 1827/1828"])
        }
        if serviceKeys.contains("1816") || serviceKeys.contains("1818") || serviceKeys.contains("1814") {
            return make(device.broadcastName ?? "Bike / run sensor", "Fitness", "Cycling or running speed/cadence/power service.", "Wearable / Fitness", "bicycle", "high", serviceLabels, evidence: ["CSC/CPS/RSC GATT service"])
        }
        if matches(nameBlob, ["oral-b", "oralb", "oral b"]) {
            return make(device.broadcastName ?? "Oral-B toothbrush", "Personal care", "Oral-B BLE toothbrush.", "Smart Home / IoT", "mouthpiece", "high", serviceLabels, evidence: ["name Oral-B"])
        }
        if matches(nameBlob, ["dexcom", "libre", "freestyle"]) {
            return make(device.broadcastName ?? "CGM / glucose", "Medical / Health", "Continuous glucose monitor name.", "Medical / Health", "cross.case.fill", "high", serviceLabels, evidence: ["CGM brand name"])
        }
        if matches(nameBlob, ["logitech", "mx master", "mx keys"]) {
            return make(device.broadcastName ?? "Logitech accessory", "HID / input", "Logitech keyboard/mouse name.", "Accessory", "keyboard", "high", serviceLabels, evidence: ["Logitech name"])
        }
        if device.manufacturerCompanyId == 0x00A7 {
            return make(device.broadcastName ?? "Flic button", "Smart home", "Flic / Shortcut Labs company ID.", "Smart Home / IoT", "button.programmable", "high", serviceLabels, evidence: ["company 0x00A7 Flic"])
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
                return make(
                    device.broadcastName ?? "Unnamed Amazon/Nest-company BLE",
                    "Unknown (Amazon/Nest radio)",
                    "Amazon or Nest company ID only — Echo vs camera vs other not proven.",
                    "Unknown",
                    "questionmark.circle",
                    "low",
                    serviceLabels,
                    evidence: [String(format: "company ID 0x%04X", company)]
                )
            }
            if company == 0x0157 || company == 0x005D || company == 0x015A || company == 0x0087 || company == 0x006D || company == 0x01D7 {
                return make(device.broadcastName ?? "Fitness wearable", "Wearable", "Watch or fitness band.", "Wearable", "applewatch", "medium", serviceLabels)
            }
            if company == 0x02E5 || company == 0x0059 || company == 0x000D || company == 0x0131 {
                let chip = device.manufacturerName ?? String(format: "0x%04X", company)
                return make(
                    device.broadcastName ?? "Unnamed BLE (\(chip) radio)",
                    "Unknown (chip vendor)",
                    "\(chip) is a Bluetooth chip maker, not the product. Device type unknown without a name or GATT.",
                    "Unknown",
                    "cpu",
                    "low",
                    serviceLabels,
                    evidence: ["chip company ID \(chip) — not a product ID"]
                )
            }
            if company == 0x0175 {
                if matches(nameBlob, ["tesla"]) {
                    return make(device.broadcastName ?? "Tesla BLE", "Vehicle-related", "Name and Tesla company ID both present.", "Car", "car.fill", "high", serviceLabels, evidence: ["broadcast name tesla", "company 0x0175 Tesla"])
                }
                return make(
                    device.broadcastName ?? "Unnamed Tesla-company BLE",
                    "Unknown (Tesla radio)",
                    "Tesla company ID. Could be a car, key, or accessory — not proven.",
                    "Unknown",
                    "questionmark.circle",
                    "low",
                    serviceLabels,
                    evidence: ["company ID 0x0175 Tesla"]
                )
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

        // --- Bluetooth SIG member service UUID → the company that registered it ---
        if let member = serviceKeys.sorted().first(where: { BLESIGTables.memberCompany($0) != nil }),
           let owner = BLESIGTables.memberCompany(member) {
            let brand = BLESIGTables.shortName(owner)
            return make(
                device.broadcastName ?? "\(brand) device",
                "\(brand) device",
                "Advertises Bluetooth SIG member service \(member), which is registered to \(owner).",
                "Nearby Bluetooth",
                "wave.3.right",
                "medium",
                serviceLabels,
                evidence: ["member service UUID \(member) → \(owner)"]
            )
        }

        // --- Named but unclassified ---
        if let broadcast = device.broadcastName {
            return make(broadcast, "Named Bluetooth", "Named device nearby — type not matched; open it to read Device Info.", "Nearby Bluetooth", "wave.3.right", "low", serviceLabels)
        }

        // --- Last resort: never pretend we know nothing if connectable ---
        if device.connectable {
            let advertised = serviceLabels.first
            return make(
                advertised.map { "Connectable · \($0)" } ?? "Connectable BLE · no ID advertised",
                "Unknown (open to ID)",
                "The advertisement carries no name, no company ID and no registered service UUID"
                    + (advertised.map { " beyond \($0)" } ?? "")
                    + ". iOS also hides the Bluetooth address, so the OUI lookup the ARIA handheld uses is unavailable on the phone. Tap Open — Finch reads GAP Device Name and Device Information (manufacturer / model) if the device exposes them.",
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
        if let name = broadcastName, !name.isEmpty {
            return make(
                name,
                "Google-radio BLE (named)",
                "Google Bluetooth company ID. Name is from the ad; product not guessed beyond that.",
                "Nearby Bluetooth",
                "wave.3.right",
                "medium",
                serviceLabels,
                evidence: ["broadcast name", "Google company ID"]
            )
        }
        return make(
            "Unnamed Google BLE",
            "Unknown (Google radio)",
            "Google company ID (often Fast Pair). Earbuds, Pixel, or Chromebook are possible — none proven.",
            "Unknown",
            "questionmark.circle",
            "low",
            serviceLabels,
            evidence: ["Google company ID", "no local name"]
        )
    }

    private static func microsoftIdentity(payload: [UInt8], broadcastName: String?, serviceLabels: [String]) -> BLEFriendlyIdentity {
        if payload.first == 0x01 {
            return make(broadcastName ?? "Windows PC (Swift Pair)", "Computer", "Microsoft Swift Pair / CDS — usually a Windows PC advertising for quick pairing.", "Computer", "desktopcomputer", "high", serviceLabels)
        }
        return make(broadcastName ?? "Microsoft / Windows device", "Computer / accessory", "Windows PC, Surface, Xbox controller, or Microsoft accessory.", "Computer / accessory", "desktopcomputer", "medium", serviceLabels)
    }

    private static func samsungIdentity(payload: [UInt8], broadcastName: String?, serviceLabels: [String]) -> BLEFriendlyIdentity {
        if let name = broadcastName, name.lowercased().contains("[tv]") {
            return make(
                name,
                "TV / media",
                "Samsung TV BLE name prefix [TV]. Not a camera or tracker.",
                "TV",
                "tv",
                "high",
                serviceLabels,
                evidence: ["local name contains [TV]", "company ID 0x0075 Samsung"]
            )
        }
        if let name = broadcastName, !name.isEmpty {
            return make(
                name,
                "Samsung BLE (named)",
                "Samsung radio (0x0075). Product is the broadcast name only — not inferred.",
                "Nearby Bluetooth",
                "wave.3.right",
                "medium",
                serviceLabels,
                evidence: ["broadcast name", "company ID 0x0075 Samsung"]
            )
        }
        return make(
            "Unnamed Samsung BLE",
            "Unknown (Samsung radio)",
            "Samsung company ID only. Could be TV, phone, buds, tag, or appliance — product not proven.",
            "Unknown",
            "questionmark.circle",
            "low",
            serviceLabels,
            evidence: ["company ID 0x0075 Samsung", "no local name"]
        )
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
        _ serviceLabels: [String],
        evidence: [String] = []
    ) -> BLEFriendlyIdentity {
        let safeIcon: String
        switch icon {
        case "tirepressure": safeIcon = "gauge"
        case "visionpro": safeIcon = "eyeglasses"
        case "scalemass", "scalemass.fill": safeIcon = "heart.text.square"
        case "homekit": safeIcon = "house.fill"
        case "gauge.with.dots.needle.33percent": safeIcon = "gauge"
        case "mouthpiece": safeIcon = "mouth"
        case "button.programmable": safeIcon = "circle.grid.cross"
        case "bicycle": safeIcon = "figure.run"
        default: safeIcon = icon
        }
        return BLEFriendlyIdentity(
            title: title,
            deviceType: deviceType,
            summary: summary,
            category: category,
            icon: safeIcon,
            confidence: confidence,
            serviceLabels: serviceLabels,
            evidence: evidence.isEmpty ? [summary] : evidence
        )
    }

    static func matches(_ blob: String, _ needles: [String]) -> Bool {
        guard !blob.isEmpty else { return false }
        for needle in needles {
            let n = needle.lowercased()
            if n.isEmpty { continue }
            if n.contains(" ") {
                if blob.contains(n) { return true }
                continue
            }
            if n == "tv" {
                if blob.contains("[tv]") { return true }
            }
            if let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: n))\\b") {
                let range = NSRange(blob.startIndex..<blob.endIndex, in: blob)
                if regex.firstMatch(in: blob, range: range) != nil { return true }
            }
        }
        return false
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
    /// Bluetooth SIG GATT services + characteristics + descriptors (+ Raven / common vendor shorts).
    private static let table: [String: String] = {
        if let url = Bundle.main.url(forResource: "gatt_uuids", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            var map: [String: String] = [:]
            for (k, v) in decoded {
                map[k.uppercased()] = v
            }
            // Ensure Raven / flock-class always present even if JSON trimmed
            for (k, v) in fallbackExtras {
                map[k] = v
            }
            return map
        }
        return fallbackKnown
    }()

    static var recognizedCount: Int { table.count }

    static func label(for normalizedShortOrFull: String) -> String? {
        let key = shortKey(normalizedShortOrFull)
        if let name = table[key] { return name }
        // Bluetooth SIG member service UUIDs are registered to a company.
        return BLESIGTables.memberCompany(key).map { "\(BLESIGTables.shortName($0)) service" }
    }

    /// Always returns a human label; unknown customs show as "Custom UUID …".
    static func label(forUUID uuid: String) -> String {
        let compact = uuid.replacingOccurrences(of: "-", with: "").uppercased()
        let short = shortKey(compact)
        if let name = label(for: short) {
            return "\(name) (\(short))"
        }
        if compact.count == 32 {
            return "Custom UUID \(String(compact.prefix(8)))…"
        }
        if compact.count == 4 {
            return "Unknown \(compact)"
        }
        return "UUID \(String(uuid.prefix(8)))…"
    }

    /// Short 16-bit key from 16-bit or Bluetooth Base 128-bit UUID.
    static func shortKey(_ uuid: String) -> String {
        let compact = uuid.replacingOccurrences(of: "-", with: "").uppercased()
        if compact.count == 4 { return compact }
        // Bluetooth Base UUID: 0000XXXX-0000-1000-8000-00805F9B34FB
        if compact.count == 32, compact.hasPrefix("0000"), compact.hasSuffix("00001000800000805F9B34FB") {
            let start = compact.index(compact.startIndex, offsetBy: 4)
            let end = compact.index(compact.startIndex, offsetBy: 8)
            return String(compact[start..<end])
        }
        // Some stacks omit dashes but still put the short in bytes 2-3 of the 128-bit form
        if compact.count == 32, compact.hasPrefix("0000") {
            let start = compact.index(compact.startIndex, offsetBy: 4)
            let end = compact.index(compact.startIndex, offsetBy: 8)
            return String(compact[start..<end])
        }
        return compact
    }

    private static let fallbackExtras: [String: String] = [
        "3100": "Raven GPS / location",
        "3200": "Raven power / battery",
        "3300": "Raven network status",
        "3400": "Raven upload stats",
        "3500": "Raven error / fault",
        "FE2C": "Google Fast Pair",
        "FEED": "Tile tracker",
        "FEEC": "Tile tracker",
        "FD6F": "Exposure Notification / proximity",
        "FEAA": "Eddystone beacon",
        "FEF5": "Apple Continuity"
    ]

    /// Minimal offline fallback if the bundled JSON is missing.
    private static let fallbackKnown: [String: String] = [
        "1800": "Generic Access",
        "1801": "Generic Attribute",
        "180A": "Device Information",
        "180F": "Battery Service",
        "180D": "Heart Rate",
        "1812": "Human Interface Device",
        "1813": "Scan Parameters",
        "1814": "Running Speed and Cadence",
        "1816": "Cycling Speed and Cadence",
        "1818": "Cycling Power",
        "181A": "Environmental Sensing",
        "181C": "User Data",
        "181D": "Weight Scale",
        "181E": "Bond Management",
        "1819": "Location and Navigation",
        "1822": "Pulse Oximeter",
        "1826": "Fitness Machine",
        "1827": "Mesh Provisioning",
        "1828": "Mesh Proxy",
        "1108": "Headset",
        "110B": "Audio Sink",
        "111E": "Handsfree",
        "1200": "PnP Information",
        "FE2C": "Google Fast Pair",
        "FEED": "Tile tracker",
        "FEEC": "Tile tracker",
        "FD6F": "Exposure Notification / proximity",
        "FD69": "Amazon",
        "FEAA": "Eddystone beacon",
        "FEF5": "Apple Continuity",
        "3100": "Raven GPS / location",
        "3200": "Raven power / battery",
        "3300": "Raven network status",
        "3400": "Raven upload stats",
        "3500": "Raven error / fault",
        "1802": "Immediate Alert",
        "1803": "Link Loss",
        "1804": "Tx Power",
        "1805": "Current Time",
        "1811": "Alert Notification",
        "1810": "Blood Pressure",
        "1808": "Glucose",
        "1809": "Health Thermometer",
        "2A00": "Device Name",
        "2A01": "Appearance",
        "2A19": "Battery Level",
        "2A24": "Model Number String",
        "2A25": "Serial Number String",
        "2A26": "Firmware Revision String",
        "2A27": "Hardware Revision String",
        "2A28": "Software Revision String",
        "2A29": "Manufacturer Name String",
        "2A50": "PnP ID",
        "2900": "Characteristic Extended Properties",
        "2901": "Characteristic User Description",
        "2902": "Client Characteristic Configuration",
        "2903": "Server Characteristic Configuration",
        "2904": "Characteristic Presentation Format",
        "2905": "Characteristic Aggregate Format"
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

/// Turn BLE hex / opaque bytes into plain-language explanations. Never leave the operator with hex alone.
enum BLEValueExplainer {
    static func parseHex(_ hex: String) -> [UInt8] {
        let cleaned = hex.replacingOccurrences(of: " ", with: "")
        var bytes: [UInt8] = []
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            if let b = UInt8(cleaned[idx..<next], radix: 16) { bytes.append(b) }
            idx = next
        }
        if bytes.isEmpty {
            return hex.split(separator: " ").compactMap { UInt8($0, radix: 16) }
        }
        return bytes
    }

    static func explainCharacteristic(uuid: String, utf8: String?, hex: String?) -> String {
        let short = BLEServiceNames.shortKey(uuid)
        if let utf = utf8?.trimmingCharacters(in: .whitespacesAndNewlines), !utf.isEmpty {
            return plainString(short: short, text: utf)
        }
        guard let hex, !hex.isEmpty else {
            return "No value read yet — tap Read if available."
        }
        let bytes = parseHex(hex)
        if bytes.isEmpty {
            return "Empty value from device."
        }
        if let decoded = decodeKnown(short: short, bytes: bytes) {
            return decoded
        }
        if let asText = String(bytes: bytes, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !asText.isEmpty,
           asText.unicodeScalars.allSatisfy({ $0.isASCII && ($0.value >= 32 || $0 == "\n" || $0 == "\t") }) {
            return plainString(short: short, text: asText)
        }
        return genericBytes(short: short, bytes: bytes)
    }

    static func explainManufacturer(companyId: UInt16?, brand: String?, payloadHex: String?) -> String {
        let brandPart = brand ?? (companyId.map { BLEManufacturerLookup.name(for: $0) } ?? nil)
        let idPart = companyId.map { String(format: "company 0x%04X", $0) }
        let who = [brandPart, idPart].compactMap { $0 }.joined(separator: " · ")
        let bytes = parseHex(payloadHex ?? "")
        if bytes.isEmpty {
            return who.isEmpty
                ? "No manufacturer payload in the advertisement."
                : "\(who). No extra payload bytes."
        }
        if companyId == 0x004C {
            return appleContinuity(bytes: bytes, header: who.isEmpty ? "Apple" : who)
        }
        if companyId == 0x00E0 || companyId == 0x02F2 || companyId == 0x00D7 {
            return "\(who.isEmpty ? "Google" : who): Fast Pair / Nearby-style payload (\(bytes.count) bytes). Often earbuds, Pixel, or Chromebook."
        }
        if companyId == 0x0006 {
            let kind = bytes.first == 0x01 ? "Swift Pair / CDS (usually a Windows PC)" : "Microsoft accessory beacon"
            return "\(who.isEmpty ? "Microsoft" : who): \(kind) — \(bytes.count) bytes."
        }
        if companyId == 0x0A7C {
            return "\(who.isEmpty ? "TPMS" : who): tire-pressure sensor payload (\(bytes.count) bytes)."
        }
        return "\(who.isEmpty ? "Unknown brand" : who) manufacturer payload — \(bytes.count) bytes of device-specific status/ID (not a human name)."
    }

    static func explainCompanyId(_ id: UInt16) -> String {
        if let name = BLEManufacturerLookup.name(for: id) {
            return "\(name) (Bluetooth company ID \(String(format: "0x%04X", id)))"
        }
        return "Unlisted Bluetooth company ID \(String(format: "0x%04X", id)) — brand table miss; still useful for fingerprinting."
    }

    static func explainServiceData(uuid: String, hex: String) -> String {
        let short = BLEServiceNames.shortKey(uuid)
        let name = BLEServiceNames.label(for: short) ?? "Service \(short)"
        let bytes = parseHex(hex)
        if short == "FEAA" {
            return eddystone(bytes: bytes)
        }
        if short == "FD6F" {
            return "\(name): privacy / exposure-style proximity beacon (\(bytes.count) bytes). Usually a phone — identity is randomized."
        }
        if short == "FE2C" {
            return "\(name): Google Fast Pair advertisement (\(bytes.count) bytes) — model ID / account key filter for one-tap pairing."
        }
        if short == "FEED" || short == "FEEC" {
            return "\(name): Tile finder advertisement (\(bytes.count) bytes)."
        }
        return "\(name) service data — \(bytes.count) bytes of beacon/status payload."
    }

    static func explainAdvertisementBlob(_ blob: String) -> String {
        if blob.isEmpty { return "No advertisement fields captured." }
        var notes: [String] = []
        let lower = blob.lowercased()
        if lower.contains("localname") || lower.contains("kcbadvlocalname") {
            notes.append("includes a broadcast name")
        }
        if lower.contains("manufacturer") {
            notes.append("includes manufacturer / brand payload")
        }
        if lower.contains("serviceuuid") || lower.contains("service uuids") {
            notes.append("lists GATT services it offers")
        }
        if lower.contains("txpower") {
            notes.append("reports transmit power (helps distance estimate)")
        }
        if lower.contains("isconnectable") || lower.contains("connectable") {
            notes.append("says whether you can open it")
        }
        if lower.contains("servicedata") {
            notes.append("includes service-data beacon bytes")
        }
        if notes.isEmpty {
            return "Raw advertisement dump from CoreBluetooth — tap Open to read named GATT values inside."
        }
        return "Advertisement summary: " + notes.joined(separator: "; ") + "."
    }

    // MARK: - Private

    private static func plainString(short: String, text: String) -> String {
        switch short {
        case "2A00": return "Device name: \(text)"
        case "2A24": return "Model number: \(text)"
        case "2A25": return "Serial number: \(text)"
        case "2A26": return "Firmware: \(text)"
        case "2A27": return "Hardware: \(text)"
        case "2A28": return "Software: \(text)"
        case "2A29": return "Manufacturer: \(text)"
        case "2A50": return "PnP ID text: \(text)"
        default:
            let label = BLEServiceNames.label(for: short) ?? short
            return "\(label): \(text)"
        }
    }

    private static func decodeKnown(short: String, bytes: [UInt8]) -> String? {
        switch short {
        case "2A19": // Battery Level
            guard let pct = bytes.first else { return nil }
            return "Battery level: \(min(Int(pct), 100))%"
        case "2A01": // Appearance
            guard bytes.count >= 2 else { return nil }
            let value = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
            return "Appearance category code \(value) — what kind of device it claims to be."
        case "2A00", "2A24", "2A25", "2A26", "2A27", "2A28", "2A29":
            if let s = String(bytes: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return plainString(short: short, text: s)
            }
            return nil
        case "2A37": // Heart Rate Measurement
            guard let flags = bytes.first else { return nil }
            let hr: Int
            if flags & 0x01 != 0, bytes.count >= 3 {
                hr = Int(UInt16(bytes[1]) | (UInt16(bytes[2]) << 8))
            } else if bytes.count >= 2 {
                hr = Int(bytes[1])
            } else { return nil }
            return "Heart rate: \(hr) bpm"
        case "2A1C", "2A1E": // Temperature
            if bytes.count >= 5 {
                // IEEE-11073 FLOAT: 32-bit mantissa + 8-bit exponent — simplify
                return "Temperature sample (\(bytes.count) bytes) — health thermometer reading."
            }
            return "Temperature characteristic (\(bytes.count) bytes)."
        case "2A6E": // Temperature Celsius (sint16, 0.01°C)
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(bytes[0]) | (UInt16(bytes[1]) << 8))
            let c = Double(raw) / 100.0
            return String(format: "Temperature: %.2f °C", c)
        case "2A6F": // Humidity
            guard bytes.count >= 2 else { return nil }
            let raw = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
            return String(format: "Humidity: %.2f%%", Double(raw) / 100.0)
        case "2A6D": // Pressure
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
            return String(format: "Pressure: %.1f Pa", Double(raw) / 10.0)
        case "2A2B": // Current Time — skip full parse
            return "Current time from device clock (\(bytes.count) bytes)."
        case "2A04": // Peripheral Preferred Connection Parameters
            return "Preferred connection timing (\(bytes.count) bytes) — how often it wants to talk."
        case "2A29":
            return nil
        default:
            return nil
        }
    }

    private static func genericBytes(short: String, bytes: [UInt8]) -> String {
        let label = BLEServiceNames.label(for: short) ?? "Characteristic \(short)"
        let preview = bytes.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        let more = bytes.count > 8 ? "…" : ""
        if bytes.count == 1 {
            return "\(label): single byte value \(bytes[0]) (0–255 scale / flag)."
        }
        if bytes.count == 2 {
            let v = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
            return "\(label): 16-bit value \(v)."
        }
        return "\(label): \(bytes.count) bytes of binary data (\(preview)\(more)). Not plain text — device-specific encoding."
    }

    private static func appleContinuity(bytes: [UInt8], header: String) -> String {
        let type = bytes.first
        let kind: String
        switch type {
        case 0x01: kind = "AirPrint"
        case 0x02: kind = "iBeacon"
        case 0x05: kind = "AirDrop"
        case 0x06: kind = "HomeKit"
        case 0x07: kind = "AirPods / Beats proximity"
        case 0x08: kind = "Hey Siri"
        case 0x09: kind = "AirPlay"
        case 0x0C: kind = "Handoff"
        case 0x0D, 0x0E: kind = "Instant Hotspot"
        case 0x0F: kind = "Nearby Action"
        case 0x10: kind = "Nearby Info (iPhone/iPad-class)"
        case 0x12, 0x16: kind = "Find My / AirTag-class"
        default: kind = type.map { String(format: "Continuity type 0x%02X", $0) } ?? "Continuity"
        }
        if type == 0x02, bytes.count >= 23, bytes[1] == 0x15 {
            let u = bytes[2..<18].map { String(format: "%02X", $0) }.joined()
            let uuid = [u.prefix(8), u.dropFirst(8).prefix(4), u.dropFirst(12).prefix(4), u.dropFirst(16).prefix(4), u.dropFirst(20)].joined(separator: "-")
            let major = Int(bytes[18]) << 8 | Int(bytes[19])
            let minor = Int(bytes[20]) << 8 | Int(bytes[21])
            return "\(header): iBeacon · UUID \(uuid) · major \(major) · minor \(minor) · calibrated TX \(Int8(bitPattern: bytes[22])) dBm."
        }
        return "\(header): \(kind) — \(bytes.count) bytes. Apple devices hide the friendly name on purpose."
    }

    private static func eddystone(bytes: [UInt8]) -> String {
        guard let frame = bytes.first else {
            return "Eddystone beacon with empty payload."
        }
        func hex(_ range: Range<Int>) -> String { bytes[range].map { String(format: "%02X", $0) }.joined() }
        func be16(_ i: Int) -> Int { Int(bytes[i]) << 8 | Int(bytes[i + 1]) }
        func be32(_ i: Int) -> UInt32 { UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16 | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3]) }
        // Same field decoding as the ARIA handheld (recon_decode.cpp).
        switch frame {
        case 0x00 where bytes.count >= 18:
            return "Eddystone-UID beacon · namespace \(hex(2..<12)) · instance \(hex(12..<18)) · calibrated TX \(Int8(bitPattern: bytes[1])) dBm."
        case 0x00: return "Eddystone-UID beacon (unique ID frame, \(bytes.count) bytes — too short to decode)."
        case 0x10 where bytes.count >= 3:
            let schemes = ["http://www.", "https://www.", "http://", "https://"]
            let expansions = [".com/", ".org/", ".edu/", ".net/", ".info/", ".biz/", ".gov/", ".com", ".org", ".edu", ".net", ".info", ".biz", ".gov"]
            var url = Int(bytes[2]) < schemes.count ? schemes[Int(bytes[2])] : ""
            for b in bytes.dropFirst(3) {
                if Int(b) < expansions.count { url += expansions[Int(b)] } else if b >= 32 && b < 127 { url.append(Character(UnicodeScalar(b))) }
            }
            return "Eddystone-URL beacon · \(url) · calibrated TX \(Int8(bitPattern: bytes[1])) dBm."
        case 0x20 where bytes.count >= 14 && bytes[1] == 0:
            let rawTemp = be16(4)
            let temp = rawTemp == 0x8000 ? "unavailable" : String(format: "%.2f °C", Double(Int16(bitPattern: UInt16(rawTemp))) / 256)
            return String(format: "Eddystone-TLM beacon · battery %d mV · temperature %@ · %u advertisements · uptime %.1f s.",
                          be16(2), temp, be32(6), Double(be32(10)) / 10)
        case 0x20 where bytes.count >= 2:
            return "Eddystone-TLM beacon (encrypted telemetry, version \(bytes[1]))."
        case 0x30: return "Eddystone-EID beacon (ephemeral encrypted ID — needs the owner's resolver key)."
        default: return String(format: "Eddystone frame type 0x%02X (%d bytes).", frame, bytes.count)
        }
    }
}
