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

    var displayName: String {
        if let localName, !localName.isEmpty { return localName }
        if let name, !name.isEmpty { return name }
        return "Unknown"
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
        0x0157: "Anhui Huami",
        0x02E5: "Espressif",
        0x0499: "Ruuvi",
        0x005D: "Garmin",
        0x0131: "Cypress",
        0x03DA: "Tile",
        0x06D5: "Samsung Electronics",
        0x0001: "Ericsson",
        0x00D2: "Sony",
        0x012D: "Sony Ericsson",
        0x0171: "Amazon",
        0x02A9: "Huawei",
        0x038F: "Xiaomi",
        0x0528: "Proximity Beacon",
        0x0A7C: "TPMS / tire pressure (generic)"
    ]
}
