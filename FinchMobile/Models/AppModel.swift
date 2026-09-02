import Foundation
import Observation
import SwiftUI

@Observable
final class AppModel {
    var engageQuery: String = ""
    var selectedPipeline: PipelineKind = .auto
    var reportContainer = ReportContainer()
    var isEngaging: Bool = false
    var statusMessage: String = ""
    var showPersistSheet: Bool = false

    let bleScanner = BLEScannerService()
    let glassPipeline = GlassFabricPipeline()
    let vaultManager = VaultManager()
    let settings = SettingsStore()
    let osintEngine = OsintEngine()
    var caseSeeds: [CaseSeed] = []
    var lastKind: PipelineKind = .auto

    let fusion = TrackFusionEngine()
    let consent = ConsentGate()
    let forensic = ForensicLogger()
    let drone = DroneModuleService()
    let mesh = MeshCoordinator()
    let playbooks = PlaybookEngine()
    let sensors = SensorHub()

    init() {
        fusion.bind(forensic: forensic)
        drone.bind(consent: consent, forensic: forensic)
        mesh.bind(fusion: fusion, forensic: forensic)
        playbooks.bind(forensic: forensic)
        sensors.bind(fusion: fusion, forensic: forensic)
        playbooks.loadBundled()
        forensic.record(category: "system", summary: "Finch Mobile 3.2 (build 35) boot")
    }

    func refreshFusion() {
        fusion.ingestBLE(bleScanner.sortedDevices)
        if let hosts = glassPipeline.report?.hosts {
            fusion.ingestHosts(hosts)
        }
        drone.refresh(from: fusion.sortedTracks)
        playbooks.evaluate(tracks: fusion.sortedTracks)
    }

    func clearEphemeral() {
        reportContainer.clear()
        glassPipeline.reset()
        osintEngine.reset()
        caseSeeds = []
        lastKind = .auto
        statusMessage = ""
    }
}

@Observable
final class ReportContainer {
    var glassReport: GlassFabricReport?
    var bleSnapshot: [BLEDevice] = []
    var osint: OsintReport?
    var title: String = ""
    var createdAt: Date = Date()

    var isEmpty: Bool {
        glassReport == nil && bleSnapshot.isEmpty && osint == nil
    }

    func clear() {
        glassReport = nil
        bleSnapshot = []
        osint = nil
        title = ""
        createdAt = Date()
    }

    func encodeJSON() throws -> Data {
        let envelope = PersistEnvelope(
            title: title.isEmpty ? "Glass Fabric \(ISO8601DateFormatter().string(from: createdAt))" : title,
            createdAt: createdAt,
            glass: glassReport,
            ble: bleSnapshot,
            osint: osint
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }
}

struct PersistEnvelope: Codable {
    var title: String
    var createdAt: Date
    var glass: GlassFabricReport?
    var ble: [BLEDevice]?
    var osint: OsintReport?
}
