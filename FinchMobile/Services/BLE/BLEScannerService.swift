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

    private var central: CBCentralManager!
    private let bleQueue = DispatchQueue(label: "com.aetherverse.finch.ble", qos: .userInitiated)
    private var restartTask: Task<Void, Never>?
    private let scanWindowSeconds: UInt64 = 30
    private let pauseNanoseconds: UInt64 = 1_000_000_000

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
            guard self.central.state == .poweredOn else {
                DispatchQueue.main.async {
                    self.statusText = "Waiting for Bluetooth…"
                    self.errorMessage = self.central.state == .unauthorized
                        ? "Bluetooth permission denied. Enable in Settings."
                        : "Bluetooth not ready (\(self.describeState(self.central.state)))."
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
        devices.removeAll()
    }

    func toggleContinuous(_ on: Bool) {
        continuousMode = on
        if on && !isScanning {
            start()
        }
    }

    private func beginScanCycle() {
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        DispatchQueue.main.async {
            self.isScanning = true
            self.statusText = self.continuousMode
                ? "Continuous scan (AllowDuplicates)"
                : "Scanning \(self.scanWindowSeconds)s window"
        }

        restartTask?.cancel()
        guard continuousMode else { return }

        restartTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.scanWindowSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self.bleQueue.async {
                self.central.stopScan()
            }
            DispatchQueue.main.async {
                self.statusText = "Restarting scan…"
            }
            try? await Task.sleep(nanoseconds: self.pauseNanoseconds)
            guard !Task.isCancelled else { return }
            self.bleQueue.async {
                guard self.central.state == .poweredOn else { return }
                self.beginScanCycle()
            }
        }
    }

    private func describeState(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "powered off"
        case .poweredOn: return "powered on"
        @unknown default: return "other"
        }
    }
}

extension BLEScannerService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.bluetoothState = central.state
            self.statusText = "Bluetooth \(self.describeState(central.state))"
        }
        if central.state == .poweredOn, continuousMode {
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
        let device = BLEDevice.from(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)
        DispatchQueue.main.async {
            if var existing = self.devices[device.identifier] {
                existing.merge(with: device)
                self.devices[device.identifier] = existing
            } else {
                self.devices[device.identifier] = device
            }
        }
    }
}
