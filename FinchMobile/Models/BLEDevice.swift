import Foundation
import CoreBluetooth

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
            solicitedServiceUUIDs: solicited
        )
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
