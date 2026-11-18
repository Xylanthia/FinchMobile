import Foundation
import UIKit

/// Renders a variable-length field report. Pages are created only for sections that have
/// source data, except for the cover, executive summary, RF overview, and appendix.
enum ARIAFieldReportPDFRenderer {
    static func makePDF(from document: ARIAFieldReportDocument) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            let canvas = ReportCanvas(context: context, document: document, bounds: pageRect)
            canvas.cover()
            canvas.executiveSummary()
            if let osint = document.osint { canvas.osint(osint) }
            canvas.radioEnvironment()
            if !document.subGHz.isEmpty { canvas.subGHz() }
            canvas.appendix()
            canvas.finishPage()
        }
    }
}

private final class ReportCanvas {
    private struct CompactRFRow {
        let id: String
        let mac: String?
        let vendor: String?
        let rssi: Int?
        let classification: String?
    }

    private struct SubGHzSummaryRow {
        let frequency: String
        let modulation: String
        let count: Int
        let replayEligibleCount: Int
    }

    private let context: UIGraphicsPDFRendererContext
    private let document: ARIAFieldReportDocument
    private let bounds: CGRect
    private let margin: CGFloat = 42
    private let footerY: CGFloat = 748
    private var y: CGFloat = 0
    private var pageNumber = 0
    private var pageOpen = false
    private var sectionTitle = ""

    private let background = UIColor(red: 0.075, green: 0.082, blue: 0.098, alpha: 1)
    private let panel = UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1)
    private let white = UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    private let muted = UIColor(red: 0.72, green: 0.74, blue: 0.77, alpha: 1)
    private let dim = UIColor(red: 0.55, green: 0.58, blue: 0.62, alpha: 1)
    private let red = UIColor(red: 0.96, green: 0.25, blue: 0.28, alpha: 1)
    private let amber = UIColor(red: 0.98, green: 0.69, blue: 0.25, alpha: 1)
    private let purple = UIColor(red: 0.66, green: 0.20, blue: 0.84, alpha: 1)

    init(context: UIGraphicsPDFRendererContext, document: ARIAFieldReportDocument, bounds: CGRect) {
        self.context = context
        self.document = document
        self.bounds = bounds
    }

    // MARK: Cover

    func cover() {
        openPage(title: "", cover: true)
        fill(CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height), color: background)
        fill(CGRect(x: 0, y: 0, width: 9, height: bounds.height), color: purple)
        strokeCircle(center: CGPoint(x: 510, y: 166), radius: 105, color: purple.withAlphaComponent(0.72), width: 2)
        strokeCircle(center: CGPoint(x: 510, y: 166), radius: 73, color: purple.withAlphaComponent(0.45), width: 1)
        strokeCircle(center: CGPoint(x: 510, y: 166), radius: 42, color: purple.withAlphaComponent(0.3), width: 1)

        draw("ARIA", at: CGPoint(x: margin, y: 56), font: .boldSystemFont(ofSize: 15), color: purple)
        draw("FIELD INTELLIGENCE", at: CGPoint(x: margin + 58, y: 59), font: .monospacedSystemFont(ofSize: 9, weight: .medium), color: muted)
        draw("ARIA FIELD\nINTELLIGENCE REPORT", at: CGPoint(x: margin, y: 217), width: 470,
             font: .boldSystemFont(ofSize: 31), color: white, lineSpacing: 5)
        fill(CGRect(x: margin, y: 317, width: 270, height: 1.5), color: purple)
        draw("UNCLASSIFIED // FOR AUTHORIZED USE ONLY",
             in: CGRect(x: margin, y: 340, width: bounds.width - margin * 2, height: 30),
             font: .boldSystemFont(ofSize: 10), color: white, background: UIColor(red: 0.29, green: 0.11, blue: 0.13, alpha: 1),
             border: red.withAlphaComponent(0.8), inset: 9)

        var fields: [(String, String)] = [("REPORT GENERATED", Self.dateTime(document.generatedAt))]
        if let timestamp = document.exportTimestamp { fields.append(("SOURCE EXPORT TIME", timestamp)) }
        if let operatorID = document.operatorID { fields.append(("OPERATOR ID", operatorID)) }
        if let gps = document.operatorGPS { fields.append(("OPERATOR GPS", gps.display)) }
        drawFieldList(fields, originY: 411, width: bounds.width - margin * 2, labelWidth: 130)

        let metrics = [
            ("WI-FI", String(document.wifi.count)),
            ("BLE", String(document.ble.count)),
            ("SUB-GHz", String(document.subGHz.count)),
        ]
        let cardY: CGFloat = 625
        let gap: CGFloat = 10
        let cardWidth = (bounds.width - margin * 2 - gap * 2) / 3
        for (index, metric) in metrics.enumerated() {
            let rect = CGRect(x: margin + CGFloat(index) * (cardWidth + gap), y: cardY, width: cardWidth, height: 64)
            fill(rect, color: panel)
            stroke(rect, color: purple.withAlphaComponent(0.65), width: 0.7)
            draw(metric.0, at: CGPoint(x: rect.minX + 12, y: rect.minY + 11), font: .monospacedSystemFont(ofSize: 8, weight: .medium), color: muted)
            draw(metric.1, at: CGPoint(x: rect.minX + 12, y: rect.minY + 28), font: .boldSystemFont(ofSize: 20), color: white)
        }
        draw("Signal indicators are investigative leads; they do not establish attribution, intent, or the presence of a surveillance device.",
             at: CGPoint(x: margin, y: 714), width: bounds.width - margin * 2,
             font: .systemFont(ofSize: 8), color: muted)
        finishPage()
    }

    // MARK: Executive summary

    func executiveSummary() {
        openPage(title: "EXECUTIVE SUMMARY & ANOMALIES")
        sectionHeading("Executive Summary", subtitle: "Counts reflect records present in the supplied JSON export.")
        let metrics = [
            ("WI-FI DEVICES", String(document.wifi.count)),
            ("BLE DEVICES", String(document.ble.count)),
            ("SUB-GHz SIGNALS", String(document.subGHz.count)),
        ]
        drawMetricCards(metrics)

        y += 19
        sectionHeading("TSCM Threat Matrix", subtitle: "Evidence is grouped and summarized from the supplied export; verify findings onsite.")
        let threats = deduplicatedThreatRows(document.anomalies)
        let hasHighThreat = threats.contains { $0.severity == .critical || $0.severity == .high }
        if !hasHighThreat {
            drawPanelText("No critical surveillance or close-proximity threats detected.", color: muted)
        }
        if threats.isEmpty {
            drawPanelText("No reportable anomalies were identified in the supplied observations.", color: muted)
        } else {
            drawThreatMatrix(threats)
        }
        finishPage()
    }

    // MARK: Conditional identity page

    func osint(_ section: ARIAFieldReportDocument.OSINTSection) {
        openPage(title: "IDENTITY & OSINT RESOLUTION")
        sectionHeading("Identity & OSINT Resolution", subtitle: "Included because address or OSINT data was attached to this report’s JSON.")
        var fields: [(String, String)] = []
        if let address = section.address { fields.append(("ADDRESS", address)) }
        if let query = section.query { fields.append(("SEARCH QUERY", query)) }
        if let owner = section.ownerName { fields.append(("RESIDENT / OWNER", owner)) }
        if let gps = section.propertyGPS { fields.append(("PROPERTY GPS", gps.display)) }
        if !fields.isEmpty { drawFieldList(fields, originY: y, width: bounds.width - margin * 2, labelWidth: 124); y += fieldListHeight(fields) }

        let alerts = section.findings.filter(\.isAlert)
        if !alerts.isEmpty {
            y += 8
            sectionHeading("OSINT Alerts", subtitle: nil)
            for alert in alerts { drawOSINTFinding(alert, alert: true) }
        }
        let remaining = section.findings.filter { !$0.isAlert }
        if !remaining.isEmpty {
            y += 8
            sectionHeading("Other Returned Findings", subtitle: nil)
            for finding in remaining { drawOSINTFinding(finding, alert: false) }
        }
        if fields.isEmpty && section.findings.isEmpty {
            drawPanelText("An OSINT query was included, but it returned no displayable identity fields or findings.", color: muted)
        }
        drawPanelText("Returned public-record or breach data is an investigative lead. Verify identity and source freshness independently.", color: muted)
        finishPage()
    }

    // MARK: RF environment

    func radioEnvironment() {
        openPage(title: "RF ENVIRONMENT · WI-FI & BLE")
        sectionHeading("RF Environment · Wi-Fi & BLE", subtitle: "Unique MAC addresses, strongest signal first. Proximity estimates are model-derived; RSSI is not a measured distance.")
        let rows = compactRFTableRows()
        if rows.isEmpty {
            drawPanelText("No Wi-Fi or BLE device records were present in the supplied JSON export.", color: muted)
        } else {
            drawSubheading("\(rows.count) UNIQUE RADIO IDENTITIES")
            drawCompactRFHeader()
            for row in rows {
                let widths: [CGFloat] = [142, 134, 88, bounds.width - margin * 2 - 364]
                let values = [row.mac ?? "Anonymous", row.vendor ?? "—", row.rssi.map { "\($0) dBm" } ?? "—", row.classification ?? "—"]
                let fonts: [UIFont] = [
                    .monospacedSystemFont(ofSize: 7.4, weight: .regular),
                    .systemFont(ofSize: 7.7),
                    .monospacedSystemFont(ofSize: 7.4, weight: .regular),
                    .systemFont(ofSize: 7.5),
                ]
                let contentHeight = values.indices.map { index in
                    measuredHeight(values[index], width: widths[index] - 10, font: fonts[index])
                }.max() ?? 12
                let rowHeight = max(23, contentHeight + 10)
                let pageBeforeRow = pageNumber
                ensureSpace(height: rowHeight, continuation: "RF ENVIRONMENT · WI-FI & BLE")
                if pageNumber != pageBeforeRow { drawCompactRFHeader() }
                var x = margin
                for index in values.indices {
                    let rect = CGRect(x: x, y: y, width: widths[index], height: rowHeight)
                    fill(rect, color: panel)
                    stroke(rect, color: dim.withAlphaComponent(0.4), width: 0.4)
                    draw(values[index], at: CGPoint(x: x + 5, y: y + 5), width: widths[index] - 10,
                         font: fonts[index], color: index == 2 && row.rssi.map({ $0 > -50 }) == true ? amber : white)
                    x += widths[index]
                }
                y += rowHeight
            }
        }
        finishPage()
    }

    // MARK: Conditional Sub-GHz page

    func subGHz() {
        openPage(title: "SUB-GHz & PHYSICAL VULNERABILITIES")
        sectionHeading("Sub-GHz & Physical Vulnerabilities", subtitle: "Captures are summarized by frequency and modulation; raw records remain in the appendix.")
        let replayable = document.replayEligibleSignals
        if !replayable.isEmpty {
            let frequencies = replayable.compactMap(\.frequencyMHz)
                .map { Self.number($0) + " MHz" }
            let unknownFrequencyCount = replayable.filter { $0.frequencyMHz == nil }.count
            let distinctFrequencies = Array(Set(frequencies)).sorted { lhs, rhs in
                let left = Double(lhs.replacingOccurrences(of: " MHz", with: "")) ?? .greatestFiniteMagnitude
                let right = Double(rhs.replacingOccurrences(of: " MHz", with: "")) ?? .greatestFiniteMagnitude
                return left == right ? lhs < rhs : left < right
            }
            var frequencyList = distinctFrequencies
            if unknownFrequencyCount > 0 { frequencyList.append("frequency not supplied") }
            let warning = "WARNING: \(replayable.count) Replay-Eligible Sub-GHz Signals Captured (Frequencies: \(frequencyList.joined(separator: ", "))). Review access-control implications."
            let height = measuredHeight(warning, width: bounds.width - margin * 2 - 20, font: .boldSystemFont(ofSize: 9)) + 20
            draw(warning, in: CGRect(x: margin, y: y, width: bounds.width - margin * 2, height: height),
                 font: .boldSystemFont(ofSize: 9), color: red, background: panel, border: red, inset: 10)
            y += height + 12
        }

        drawSubheading("CAPTURE SUMMARY BY FREQUENCY · MODULATION")
        let summaries = subGHzSummaryRows()
        drawSubGHzTableHeader()
        for summary in summaries {
            let frequencyWidth: CGFloat = 112
            let modulationWidth: CGFloat = 140
            let countWidth: CGFloat = 82
            let replayWidth = bounds.width - margin * 2 - frequencyWidth - modulationWidth - countWidth
            let values = [summary.frequency, summary.modulation, String(summary.count), String(summary.replayEligibleCount)]
            let widths = [frequencyWidth, modulationWidth, countWidth, replayWidth]
            let fonts = values.enumerated().map { index, _ in
                index < 2 ? UIFont.monospacedSystemFont(ofSize: 8, weight: .regular) : UIFont.systemFont(ofSize: 8)
            }
            let rowHeight = values.indices.map { index in
                measuredHeight(values[index], width: widths[index] - 12, font: fonts[index])
            }.max() ?? 14
            let height = max(26, rowHeight + 12)
            let pageBeforeRow = pageNumber
            ensureSpace(height: height, continuation: "SUB-GHz & PHYSICAL VULNERABILITIES")
            if pageNumber != pageBeforeRow { drawSubGHzTableHeader() }
            var x = margin
            for (index, value) in values.enumerated() {
                let cell = CGRect(x: x, y: y, width: widths[index], height: height)
                fill(cell, color: panel)
                stroke(cell, color: dim.withAlphaComponent(0.45), width: 0.45)
                draw(value, at: CGPoint(x: x + 6, y: y + 6), width: widths[index] - 12,
                     font: fonts[index], color: index == 3 && summary.replayEligibleCount > 0 ? red : white)
                x += widths[index]
            }
            y += height
        }
        finishPage()
    }

    private func drawThreatMatrix(_ anomalies: [ARIAFieldReportDocument.Anomaly]) {
        let widths: [CGFloat] = [78, 132, bounds.width - margin * 2 - 210]
        func drawHeader() {
            let labels = ["THREAT LEVEL", "DEVICE", "EVIDENCE"]
            var x = margin
            for index in labels.indices {
                let rect = CGRect(x: x, y: y, width: widths[index], height: 24)
                fill(rect, color: purple.withAlphaComponent(0.32))
                stroke(rect, color: purple.withAlphaComponent(0.75), width: 0.6)
                draw(labels[index], at: CGPoint(x: x + 6, y: y + 6), width: widths[index] - 12,
                     font: .monospacedSystemFont(ofSize: 7, weight: .bold), color: white)
                x += widths[index]
            }
            y += 24
        }

        drawHeader()
        let ordered = anomalies.sorted { rank($0.severity) < rank($1.severity) }
        for item in ordered {
            let values = [item.threatLevelLabel, item.device, item.detail]
            let heights = values.enumerated().map { index, value in
                measuredHeight(value, width: widths[index] - 12,
                               font: index == 0 ? .monospacedSystemFont(ofSize: 7.2, weight: .bold) : .systemFont(ofSize: 8))
            }
            let height = max(30, (heights.max() ?? 12) + 12)
            let pageBeforeRow = pageNumber
            ensureSpace(height: height, continuation: "EXECUTIVE SUMMARY · TSCM THREAT MATRIX")
            if pageNumber != pageBeforeRow { drawHeader() }
            let rowColor: UIColor = item.severity == .critical || item.severity == .high ? red : (item.severity == .review ? amber : purple)
            var x = margin
            for index in values.indices {
                let rect = CGRect(x: x, y: y, width: widths[index], height: height)
                fill(rect, color: panel)
                stroke(rect, color: rowColor.withAlphaComponent(index == 0 ? 0.85 : 0.35), width: index == 0 ? 0.8 : 0.4)
                draw(values[index], at: CGPoint(x: x + 6, y: y + 6), width: widths[index] - 12,
                     font: index == 0 ? .monospacedSystemFont(ofSize: 7.2, weight: .bold) : .systemFont(ofSize: 8),
                     color: index == 0 ? rowColor : white)
                x += widths[index]
            }
            y += height
        }
    }

    private func drawSubGHzTableHeader() {
        let widths: [CGFloat] = [112, 140, 82, bounds.width - margin * 2 - 334]
        let labels = ["FREQUENCY", "MODULATION", "CAPTURES", "REPLAY-ELIGIBLE"]
        var x = margin
        for index in labels.indices {
            let rect = CGRect(x: x, y: y, width: widths[index], height: 24)
            fill(rect, color: purple.withAlphaComponent(0.32))
            stroke(rect, color: purple.withAlphaComponent(0.75), width: 0.6)
            draw(labels[index], at: CGPoint(x: x + 6, y: y + 6), width: widths[index] - 12,
                 font: .monospacedSystemFont(ofSize: 6.5, weight: .bold), color: white)
            x += widths[index]
        }
        y += 24
    }

    private func subGHzSummaryRows() -> [SubGHzSummaryRow] {
        let grouped = Dictionary(grouping: document.subGHz) { signal in
            let frequency = signal.frequencyMHz.map { "\(Self.number($0)) MHz" } ?? "Frequency not supplied"
            let modulation = signal.modulation ?? "Not supplied"
            return "\(frequency)|\(modulation)"
        }
        return grouped.keys.sorted { lhs, rhs in
            let leftParts = lhs.split(separator: "|", maxSplits: 1).map(String.init)
            let rightParts = rhs.split(separator: "|", maxSplits: 1).map(String.init)
            let leftFrequency = Double((leftParts.first ?? "").replacingOccurrences(of: " MHz", with: "")) ?? .greatestFiniteMagnitude
            let rightFrequency = Double((rightParts.first ?? "").replacingOccurrences(of: " MHz", with: "")) ?? .greatestFiniteMagnitude
            if leftFrequency != rightFrequency { return leftFrequency < rightFrequency }
            return lhs < rhs
        }.compactMap { key in
            guard let signals = grouped[key] else { return nil }
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return SubGHzSummaryRow(
                frequency: parts.first ?? "Frequency not supplied",
                modulation: parts.count > 1 ? parts[1] : "Not supplied",
                count: signals.count,
                replayEligibleCount: signals.filter { $0.replayEligible == true }.count
            )
        }
    }

    private func rank(_ severity: ARIAFieldReportDocument.Anomaly.Severity) -> Int {
        switch severity {
        case .critical: return 0
        case .high: return 1
        case .review: return 2
        case .info: return 3
        }
    }

    // MARK: Appendix

    func appendix() {
        openPage(title: "APPENDIX · CHAIN OF CUSTODY")
        sectionHeading("Appendix · Chain of Custody", subtitle: "Condensed technical index from the exact JSON bytes used to generate this report.")
        var sourceFields = [
            ("SOURCE JSON SHA-256", document.exportSHA256),
            ("SOURCE JSON BYTES", String(document.originalJSON.count)),
            ("REPORT GENERATED", Self.dateTime(document.generatedAt)),
        ]
        if let sourceHash = document.sourceExportSHA256 {
            sourceFields.append(("ORIGINAL EXPORT SHA-256", sourceHash))
        }
        drawFieldList(sourceFields, originY: y, width: bounds.width - margin * 2, labelWidth: 132)
        y += fieldListHeight(sourceFields) + 13

        let rawRows = appendixRows()
        if rawRows.isEmpty {
            drawPanelText("No MAC addresses, timestamps, or raw pulse fields were present in the source JSON.", color: muted)
        } else {
            drawSubheading("SOURCE RECORD INDEX")
            for row in rawRows {
                let height = measuredHeight(row, width: bounds.width - margin * 2 - 20, font: UIFont.monospacedSystemFont(ofSize: 7.4, weight: .regular), charWrap: true) + 14
                ensureSpace(height: height, continuation: "APPENDIX · CHAIN OF CUSTODY")
                draw(row, in: CGRect(x: margin, y: y, width: bounds.width - margin * 2, height: height),
                     font: UIFont.monospacedSystemFont(ofSize: 7.4, weight: .regular), color: white,
                     background: panel, border: dim.withAlphaComponent(0.45), inset: 8, charWrap: true)
                y += height + 5
            }
        }
        y += 7
        drawPanelText("The SHA-256 value identifies the source JSON used for this PDF. This appendix is a condensed index; retain the original JSON export alongside the report for full chain-of-custody review.", color: muted)
        finishPage()
    }

    // MARK: Drawing helpers

    private func drawCompactRFHeader() {
        let widths: [CGFloat] = [142, 134, 88, bounds.width - margin * 2 - 364]
        let labels = ["MAC ADDRESS", "VENDOR", "SIGNAL (dBm)", "CLASSIFICATION"]
        var x = margin
        for index in labels.indices {
            let rect = CGRect(x: x, y: y, width: widths[index], height: 24)
            fill(rect, color: purple.withAlphaComponent(0.32))
            stroke(rect, color: purple.withAlphaComponent(0.75), width: 0.6)
            draw(labels[index], at: CGPoint(x: x + 5, y: y + 6), width: widths[index] - 10,
                 font: .monospacedSystemFont(ofSize: 6.6, weight: .bold), color: white)
            x += widths[index]
        }
        y += 24
    }

    private func compactRFTableRows() -> [CompactRFRow] {
        let observations = (document.wifi + document.ble).filter { !$0.isSystemAccessPoint }
        var grouped: [String: [ARIAFieldReportDocument.RadioObservation]] = [:]
        for row in observations {
            let key: String
            if let address = row.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
                key = "mac:\(address.uppercased())"
            } else {
                key = "anonymous:\(row.band):\(row.vendor?.lowercased() ?? ""):\(row.classification?.lowercased() ?? "")"
            }
            grouped[key, default: []].append(row)
        }

        return grouped.map { key, records in
            let ordered = records.sorted {
                let lhs = $0.rssi ?? Int.min
                let rhs = $1.rssi ?? Int.min
                return lhs == rhs ? $0.id < $1.id : lhs > rhs
            }
            let strongest = ordered.first
            return CompactRFRow(
                id: key,
                mac: strongest?.address,
                vendor: ordered.compactMap(\.vendor).first,
                rssi: strongest?.rssi,
                classification: ordered.compactMap(\.classification).first
            )
        }.sorted { lhs, rhs in
            let leftSignal = lhs.rssi ?? Int.min
            let rightSignal = rhs.rssi ?? Int.min
            return leftSignal == rightSignal ? lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending : leftSignal > rightSignal
        }
    }

    private func deduplicatedThreatRows(_ anomalies: [ARIAFieldReportDocument.Anomaly]) -> [ARIAFieldReportDocument.Anomaly] {
        let grouped = Dictionary(grouping: anomalies) { item in
            "\(rank(item.severity))|\(item.title)|\(item.detail)"
        }
        return grouped.values.compactMap { matches in
            guard let first = matches.first else { return nil }
            guard matches.count > 1 else { return first }
            return ARIAFieldReportDocument.Anomaly(
                id: "deduplicated-\(first.id)",
                title: "\(matches.count) × \(first.title)",
                device: "\(matches.count) devices",
                detail: first.detail,
                severity: first.severity
            )
        }.sorted { rank($0.severity) == rank($1.severity) ? $0.title < $1.title : rank($0.severity) < rank($1.severity) }
    }

    private func drawOSINTFinding(_ finding: ARIAFieldReportDocument.OSINTFinding, alert: Bool) {
        let label = [finding.source, finding.kind].compactMap { $0 }.joined(separator: " · ")
        let headline = finding.value ?? finding.note ?? label
        let detail = [finding.note, (finding.value == nil ? nil : label.isEmpty ? nil : label)].compactMap { $0 }.joined(separator: "\n")
        let height = measuredHeight(headline, width: bounds.width - margin * 2 - 26, font: .systemFont(ofSize: 9.5))
            + (detail.isEmpty ? 0 : measuredHeight(detail, width: bounds.width - margin * 2 - 26, font: .systemFont(ofSize: 8)) + 3) + 16
        ensureSpace(height: height, continuation: "IDENTITY & OSINT RESOLUTION")
        let color = alert ? red : purple
        let rect = CGRect(x: margin, y: y, width: bounds.width - margin * 2, height: height)
        fill(rect, color: panel)
        stroke(rect, color: color.withAlphaComponent(0.75), width: alert ? 1.1 : 0.6)
        draw(headline, at: CGPoint(x: rect.minX + 10, y: rect.minY + 7), width: rect.width - 20,
             font: .systemFont(ofSize: 9.5, weight: alert ? .bold : .regular), color: white)
        if !detail.isEmpty {
            let headlineHeight = measuredHeight(headline, width: rect.width - 20, font: .systemFont(ofSize: 9.5))
            draw(detail, at: CGPoint(x: rect.minX + 10, y: rect.minY + 8 + headlineHeight), width: rect.width - 20,
                 font: .systemFont(ofSize: 8), color: muted)
        }
        y += height + 6
    }

    private func appendixRows() -> [String] {
        var rows: [String] = []
        for radio in document.wifi + document.ble {
            var fields = [radio.band]
            if let address = radio.address { fields.append("address=\(address)") }
            if let timestamp = radio.timestamp { fields.append("timestamp=\(timestamp)") }
            if let rssi = radio.rssi { fields.append("rssi=\(rssi)") }
            if let vendor = radio.vendor { fields.append("vendor=\(vendor)") }
            rows.append(fields.joined(separator: " | "))
        }
        for signal in document.subGHz {
            var fields = ["SUB-GHz"]
            if let captureID = signal.captureID { fields.append("sequence=\(captureID)") }
            if let frequency = signal.frequencyMHz { fields.append("frequency_mhz=\(Self.number(frequency))") }
            if let timestamp = signal.timestamp { fields.append("timestamp=\(timestamp)") }
            if let rssi = signal.rssi { fields.append("rssi=\(rssi)") }
            if let raw = signal.rawPulseData { fields.append("raw_pulses=\(raw)") }
            rows.append(fields.joined(separator: " | "))
        }
        return rows.flatMap { row -> [String] in
            let limit = 1_200
            guard row.count > limit else { return [row] }
            var chunks: [String] = []
            var remaining = row[...]
            while !remaining.isEmpty {
                let end = remaining.index(remaining.startIndex, offsetBy: min(limit, remaining.count))
                chunks.append(String(remaining[..<end]))
                remaining = remaining[end...]
            }
            return chunks.enumerated().map { index, chunk in
                index == 0 ? chunk : "… continued … \(chunk)"
            }
        }
    }

    private func drawMetricCards(_ values: [(String, String)]) {
        let gap: CGFloat = 8
        let width = (bounds.width - margin * 2 - gap * CGFloat(values.count - 1)) / CGFloat(values.count)
        for (index, value) in values.enumerated() {
            let rect = CGRect(x: margin + CGFloat(index) * (width + gap), y: y, width: width, height: 57)
            fill(rect, color: panel)
            stroke(rect, color: purple.withAlphaComponent(0.65), width: 0.7)
            draw(value.0, at: CGPoint(x: rect.minX + 10, y: rect.minY + 8), font: .monospacedSystemFont(ofSize: 7, weight: .medium), color: muted)
            draw(value.1, at: CGPoint(x: rect.minX + 10, y: rect.minY + 25), font: .boldSystemFont(ofSize: 18), color: white)
        }
        y += 72
    }

    private func drawFieldList(_ fields: [(String, String)], originY: CGFloat, width: CGFloat, labelWidth: CGFloat) {
        var lineY = originY
        for field in fields {
            let valueWidth = width - labelWidth - 8
            let height = measuredHeight(field.1, width: valueWidth, font: .systemFont(ofSize: 9))
            draw(field.0, at: CGPoint(x: margin + 9, y: lineY + 1), width: labelWidth,
                 font: .monospacedSystemFont(ofSize: 7, weight: .medium), color: muted)
            draw(field.1, at: CGPoint(x: margin + 9 + labelWidth, y: lineY), width: valueWidth,
                 font: .systemFont(ofSize: 9), color: white)
            lineY += max(15, height + 4)
        }
    }

    private func fieldListHeight(_ fields: [(String, String)]) -> CGFloat {
        fields.reduce(0) { partial, field in
            partial + max(15, measuredHeight(field.1, width: bounds.width - margin * 2 - 150, font: .systemFont(ofSize: 9)) + 4)
        }
    }

    private func drawPanelText(_ text: String, color: UIColor) {
        let height = measuredHeight(text, width: bounds.width - margin * 2 - 20, font: .systemFont(ofSize: 9)) + 18
        ensureSpace(height: height, continuation: sectionTitle)
        draw(text, in: CGRect(x: margin, y: y, width: bounds.width - margin * 2, height: height),
             font: .systemFont(ofSize: 9), color: color, background: panel, border: dim.withAlphaComponent(0.45), inset: 9)
        y += height + 8
    }

    private func sectionHeading(_ title: String, subtitle: String?) {
        ensureSpace(height: subtitle == nil ? 36 : 54, continuation: sectionTitle)
        draw(title, at: CGPoint(x: margin, y: y), width: bounds.width - margin * 2,
             font: .boldSystemFont(ofSize: 16), color: white)
        y += 23
        if let subtitle {
            draw(subtitle, at: CGPoint(x: margin, y: y), width: bounds.width - margin * 2,
                 font: .systemFont(ofSize: 8.5), color: muted)
            y += measuredHeight(subtitle, width: bounds.width - margin * 2, font: .systemFont(ofSize: 8.5)) + 8
        } else { y += 4 }
    }

    private func drawSubheading(_ text: String) {
        ensureSpace(height: 27, continuation: sectionTitle)
        draw(text, at: CGPoint(x: margin, y: y), width: bounds.width - margin * 2,
             font: .boldSystemFont(ofSize: 8.5), color: purple)
        y += 18
    }

    private func openPage(title: String, cover: Bool = false) {
        if pageOpen { finishPage() }
        context.beginPage()
        pageOpen = true
        pageNumber += 1
        sectionTitle = title
        fill(bounds, color: background)
        if !cover {
            fill(CGRect(x: 0, y: 0, width: bounds.width, height: 5), color: purple)
            draw("ARIA FIELD INTELLIGENCE", at: CGPoint(x: margin, y: 21), font: .monospacedSystemFont(ofSize: 7.2, weight: .semibold), color: purple)
            draw(title, at: CGPoint(x: margin, y: 35), width: bounds.width - margin * 2,
                 font: .boldSystemFont(ofSize: 9.5), color: white)
            fill(CGRect(x: margin, y: 55, width: bounds.width - margin * 2, height: 0.6), color: dim.withAlphaComponent(0.55))
            y = 72
        } else { y = 0 }
    }

    func finishPage() {
        guard pageOpen else { return }
        fill(CGRect(x: margin, y: footerY, width: bounds.width - margin * 2, height: 0.6), color: dim.withAlphaComponent(0.55))
        let pageText = "ARIA FIELD REPORT  ·  PAGE \(pageNumber)"
        draw(pageText, at: CGPoint(x: margin, y: footerY + 8), font: .monospacedSystemFont(ofSize: 7, weight: .medium), color: muted)
        if let gps = document.operatorGPS {
            let gpsText = "OPERATOR GPS  \(gps.display)"
            let width = gpsText.size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 7, weight: .medium)]).width
            draw(gpsText, at: CGPoint(x: bounds.width - margin - width, y: footerY + 8),
                 font: .monospacedSystemFont(ofSize: 7, weight: .medium), color: muted)
        }
        pageOpen = false
    }

    private func ensureSpace(height: CGFloat, continuation: String) {
        guard pageOpen else { return }
        if y + height > footerY - 8 {
            openPage(title: continuation + " · CONTINUED")
        }
    }

    private func draw(_ text: String, at point: CGPoint, width: CGFloat = 0, font: UIFont, color: UIColor,
                      lineSpacing: CGFloat = 0) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color,
            .paragraphStyle: paragraphStyle(lineSpacing: lineSpacing)
        ]
        if width > 0 {
            let height = measuredHeight(text, width: width, font: font, lineSpacing: lineSpacing)
            (text as NSString).draw(in: CGRect(x: point.x, y: point.y, width: width, height: height + 2), withAttributes: attributes)
        } else {
            (text as NSString).draw(at: point, withAttributes: attributes)
        }
    }

    private func draw(_ text: String, in rect: CGRect, font: UIFont, color: UIColor,
                      background: UIColor? = nil, border: UIColor? = nil, inset: CGFloat = 0, charWrap: Bool = false) {
        if let background { fill(rect, color: background) }
        if let border { stroke(rect, color: border, width: 0.65) }
        let textRect = rect.insetBy(dx: inset, dy: inset * 0.72)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color,
            .paragraphStyle: paragraphStyle(charWrap: charWrap)
        ]
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private func measuredHeight(_ text: String, width: CGFloat, font: UIFont, lineSpacing: CGFloat = 0, charWrap: Bool = false) -> CGFloat {
        let style = paragraphStyle(lineSpacing: lineSpacing, charWrap: charWrap)
        let rect = (text as NSString).boundingRect(with: CGSize(width: max(1, width), height: 100_000),
                                                  options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                  attributes: [.font: font, .paragraphStyle: style], context: nil)
        return ceil(rect.height)
    }

    private func paragraphStyle(lineSpacing: CGFloat = 0, charWrap: Bool = false) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.lineBreakMode = charWrap ? .byCharWrapping : .byWordWrapping
        return style
    }

    private func fill(_ rect: CGRect, color: UIColor) {
        color.setFill(); UIRectFill(rect)
    }

    private func stroke(_ rect: CGRect, color: UIColor, width: CGFloat) {
        let path = UIBezierPath(rect: rect)
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    private func strokeCircle(center: CGPoint, radius: CGFloat, color: UIColor, width: CGFloat) {
        let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        path.lineWidth = width; color.setStroke(); path.stroke()
    }

    private static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return formatter.string(from: date)
    }

    private static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }
}
