import Foundation
import CoreBluetooth
import Observation

@Observable
final class BLEScannerService: NSObject {
    var devices: [UUID: BLEDevice] = [:]
    var isScanning: Bool = false
    var continuousMode: Bool = true
    var bluetoothState: CBManagerState = .unknown
    var statusText: String = "Bluetooth idle"
    var errorMessage: String?
    var connectedPeripheralID: UUID?

    private var central: CBCentralManager!
    private let bleQueue = DispatchQueue(label: "com.aetherverse.finch.ble", qos: .userInitiated)
    private var restartTask: Task<Void, Never>?
    private let scanWindowSeconds: UInt64 = 30
    private let pauseNanoseconds: UInt64 = 1_000_000_000

    private var knownPeripherals: [UUID: CBPeripheral] = [:]
    private var activePeripheral: CBPeripheral?
    private var pendingCharReads = 0
    private var gattBuild: [CBUUID: GATTServiceInfo] = [:]

    var sortedDevices: [BLEDevice] {
        devices.values.sorted { $0.lastSeen > $1.lastSeen }
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: bleQueue, options: [
            CBCentralManagerOptionShowPowerAlertKey: true
        ])
    }

    func start() {
        errorMessage = nil
        bleQueue.async { [weak self] in
            guard let self else { return }
            guard self.activePeripheral == nil else {
                DispatchQueue.main.async {
                    self.statusText = "Looking inside a device — scan paused"
                }
                return
            }
            guard self.central.state == .poweredOn else {
                DispatchQueue.main.async {
                    self.statusText = "Waiting for Bluetooth…"
                    self.errorMessage = self.central.state == .unauthorized
                        ? "Bluetooth permission denied. Enable it in Settings."
                        : "Bluetooth isn’t ready yet (\(self.friendlyState(self.central.state)))."
                }
                return
            }
            self.beginScanCycle()
        }
    }

    func stop() {
        restartTask?.cancel()
        restartTask = nil
        bleQueue.async { [weak self] in
            self?.central.stopScan()
            DispatchQueue.main.async {
                self?.isScanning = false
                self?.statusText = "Scan stopped"
            }
        }
    }

    func clearDevices() {
        disconnect()
        devices.removeAll()
        bleQueue.async { [weak self] in
            self?.knownPeripherals.removeAll()
        }
    }

    func toggleContinuous(_ on: Bool) {
        continuousMode = on
        if on && !isScanning && connectedPeripheralID == nil {
            start()
        }
    }

    func connect(to id: UUID) {
        bleQueue.async { [weak self] in
            guard let self else { return }
            guard self.central.state == .poweredOn else {
                DispatchQueue.main.async {
                    self.errorMessage = "Bluetooth not ready"
                }
                return
            }
            guard let peripheral = self.knownPeripherals[id]
                ?? self.central.retrievePeripherals(withIdentifiers: [id]).first else {
                DispatchQueue.main.async {
                    self.updateDevice(id) {
                        $0.connectionState = .failed
                        $0.gattError = "Device dropped off the list — keep scanning, then try again"
                    }
                }
                return
            }
            self.knownPeripherals[id] = peripheral
            if let current = self.activePeripheral, current.identifier != id {
                self.central.cancelPeripheralConnection(current)
            }
            self.restartTask?.cancel()
            self.central.stopScan()
            DispatchQueue.main.async {
                self.isScanning = false
                self.statusText = "Opening device…"
                self.connectedPeripheralID = id
                self.updateDevice(id) {
                    $0.connectionState = .connecting
                    $0.gattError = nil
                    $0.gattServices = []
                }
            }
            self.gattBuild.removeAll()
            self.pendingCharReads = 0
            self.activePeripheral = peripheral
            peripheral.delegate = self
            self.central.connect(peripheral, options: nil)
        }
    }

    func disconnect() {
        bleQueue.async { [weak self] in
            guard let self else { return }
            if let p = self.activePeripheral {
                self.central.cancelPeripheralConnection(p)
            }
            let id = self.activePeripheral?.identifier
            self.activePeripheral = nil
            DispatchQueue.main.async {
                self.connectedPeripheralID = nil
                if let id {
                    self.updateDevice(id) {
                        $0.connectionState = .disconnected
                    }
                }
                self.statusText = "Disconnected — scanning again soon"
            }
        }
    }

    func readCharacteristic(serviceUUID: String, characteristicUUID: String) {
        bleQueue.async { [weak self] in
            guard let self, let peripheral = self.activePeripheral else { return }
            guard let service = peripheral.services?.first(where: { $0.uuid.uuidString == serviceUUID }),
                  let characteristic = service.characteristics?.first(where: { $0.uuid.uuidString == characteristicUUID })
            else { return }
            guard characteristic.properties.contains(.read) else { return }
            peripheral.readValue(for: characteristic)
        }
    }

    private func beginScanCycle() {
        guard activePeripheral == nil else { return }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        DispatchQueue.main.async {
            self.isScanning = true
            self.statusText = self.continuousMode
                ? "Listening for nearby Bluetooth…"
                : "Scanning for \(self.scanWindowSeconds) seconds…"
        }

        restartTask?.cancel()
        guard continuousMode else { return }

        restartTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.scanWindowSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self.bleQueue.async {
                guard self.activePeripheral == nil else { return }
                self.central.stopScan()
            }
            DispatchQueue.main.async {
                if self.connectedPeripheralID == nil {
                    self.statusText = "Refreshing…"
                }
            }
            try? await Task.sleep(nanoseconds: self.pauseNanoseconds)
            guard !Task.isCancelled else { return }
            self.bleQueue.async {
                guard self.central.state == .poweredOn, self.activePeripheral == nil else { return }
                self.beginScanCycle()
            }
        }
    }

    private func updateDevice(_ id: UUID, _ mutate: (inout BLEDevice) -> Void) {
        guard var device = devices[id] else { return }
        mutate(&device)
        devices[id] = device
    }

    private func friendlyState(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "starting up"
        case .resetting: return "resetting"
        case .unsupported: return "not supported on this phone"
        case .unauthorized: return "permission needed"
        case .poweredOff: return "turned off"
        case .poweredOn: return "on"
        @unknown default: return "unavailable"
        }
    }

    private func propertyNames(_ props: CBCharacteristicProperties) -> [String] {
        var names: [String] = []
        if props.contains(.read) { names.append("read") }
        if props.contains(.write) { names.append("write") }
        if props.contains(.writeWithoutResponse) { names.append("writeNR") }
        if props.contains(.notify) { names.append("notify") }
        if props.contains(.indicate) { names.append("indicate") }
        if props.contains(.broadcast) { names.append("broadcast") }
        return names
    }

    private func publishGATT(for peripheral: CBPeripheral) {
        let services = (peripheral.services ?? []).map { service -> GATTServiceInfo in
            let chars = (service.characteristics ?? []).map { ch -> GATTCharacteristicInfo in
                let data = ch.value
                let hex = data.map { $0.map { String(format: "%02X", $0) }.joined(separator: " ") }
                let utf = data.flatMap { String(data: $0, encoding: .utf8) }
                return GATTCharacteristicInfo(
                    uuid: ch.uuid.uuidString,
                    properties: propertyNames(ch.properties),
                    valueHex: hex,
                    valueUTF8: utf
                )
            }
            return GATTServiceInfo(uuid: service.uuid.uuidString, characteristics: chars)
        }
        let id = peripheral.identifier
        DispatchQueue.main.async {
            self.updateDevice(id) {
                $0.gattServices = services
                $0.connectionState = .connected
                $0.name = peripheral.name ?? $0.name
            }
            let n = services.count
            self.statusText = n == 1
                ? "Opened — 1 feature found"
                : "Opened — \(n) features found"
        }
    }
}

extension BLEScannerService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.bluetoothState = central.state
            switch central.state {
            case .poweredOn:
                self.statusText = "Bluetooth is on"
            case .poweredOff:
                self.statusText = "Turn Bluetooth on in Control Center"
            case .unauthorized:
                self.statusText = "Allow Bluetooth in Settings"
            default:
                self.statusText = "Bluetooth: \(self.friendlyState(central.state))"
            }
        }
        if central.state == .poweredOn, continuousMode, activePeripheral == nil {
            beginScanCycle()
        } else if central.state != .poweredOn {
            DispatchQueue.main.async {
                self.isScanning = false
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        knownPeripherals[peripheral.identifier] = peripheral
        let device = BLEDevice.from(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
        DispatchQueue.main.async {
            if var existing = self.devices[device.identifier] {
                let state = existing.connectionState
                let gatt = existing.gattServices
                let err = existing.gattError
                existing.merge(with: device)
                if state != .disconnected {
                    existing.connectionState = state
                    existing.gattServices = gatt
                    existing.gattError = err
                }
                self.devices[device.identifier] = existing
            } else {
                self.devices[device.identifier] = device
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        DispatchQueue.main.async {
            self.updateDevice(peripheral.identifier) {
                $0.connectionState = .discovering
                $0.gattError = nil
            }
            self.statusText = "Reading what’s inside…"
        }
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async {
            self.connectedPeripheralID = nil
            self.updateDevice(peripheral.identifier) {
                $0.connectionState = .failed
                $0.gattError = error?.localizedDescription ?? "Couldn't open this device"
            }
            self.statusText = "Couldn't open device"
        }
        activePeripheral = nil
        if continuousMode { beginScanCycle() }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async {
            if self.connectedPeripheralID == peripheral.identifier {
                self.connectedPeripheralID = nil
            }
            self.updateDevice(peripheral.identifier) {
                $0.connectionState = .disconnected
                if let error { $0.gattError = error.localizedDescription }
            }
            self.statusText = "Disconnected — scanning again"
        }
        if activePeripheral?.identifier == peripheral.identifier {
            activePeripheral = nil
        }
        if continuousMode { beginScanCycle() }
    }
}

extension BLEScannerService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            DispatchQueue.main.async {
                self.updateDevice(peripheral.identifier) {
                    $0.connectionState = .failed
                    $0.gattError = error.localizedDescription
                }
            }
            return
        }
        guard let services = peripheral.services, !services.isEmpty else {
            DispatchQueue.main.async {
                self.updateDevice(peripheral.identifier) {
                    $0.connectionState = .connected
                    $0.gattServices = []
                    $0.gattError = "Opened, but nothing useful was listed inside"
                }
                self.statusText = "Opened — nothing listed inside"
            }
            return
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            DispatchQueue.main.async {
                self.updateDevice(peripheral.identifier) {
                    $0.gattError = error.localizedDescription
                }
            }
        }
        for ch in service.characteristics ?? [] where ch.properties.contains(.read) {
            pendingCharReads += 1
            peripheral.readValue(for: ch)
        }
        // If nothing to read, still publish map when all services have characteristics discovered
        let allReady = (peripheral.services ?? []).allSatisfy { $0.characteristics != nil }
        if allReady && pendingCharReads == 0 {
            publishGATT(for: peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if pendingCharReads > 0 { pendingCharReads -= 1 }
        if let error {
            DispatchQueue.main.async {
                self.updateDevice(peripheral.identifier) {
                    $0.gattError = error.localizedDescription
                }
            }
        }
        let allReady = (peripheral.services ?? []).allSatisfy { $0.characteristics != nil }
        if allReady && pendingCharReads == 0 {
            publishGATT(for: peripheral)
        } else {
            publishGATT(for: peripheral)
        }
    }
}
