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

    func clearEphemeral() {
        reportContainer.clear()
        glassPipeline.reset()
        statusMessage = ""
    }
}

@Observable
final class ReportContainer {
    var glassReport: GlassFabricReport?
    var bleSnapshot: [BLEDevice] = []
    var title: String = ""
    var createdAt: Date = Date()

    var isEmpty: Bool {
        glassReport == nil && bleSnapshot.isEmpty
    }

    func clear() {
        glassReport = nil
        bleSnapshot = []
        title = ""
        createdAt = Date()
    }

    func encodeJSON() throws -> Data {
        let envelope = PersistEnvelope(
            title: title.isEmpty ? "Glass Fabric \(ISO8601DateFormatter().string(from: createdAt))" : title,
            createdAt: createdAt,
            glass: glassReport,
            ble: bleSnapshot
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
}
