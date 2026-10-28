import SwiftUI
import UIKit

struct LatticeView: View {
    var report: GlassFabricReport?
    var showNetworkHeader: Bool = true
    var onDeepScan: (String) -> Void
    var onDeepScanAll: () -> Void
    var onIoTVulns: (String) -> Void
    var onIoTVulnsAll: () -> Void
    var onMQTT: (String) -> Void
    var onExport: () -> Void

    var body: some View {
        Group {
            if let report {
                VStack(spacing: 0) {
                    if showNetworkHeader { header(report) }
                    List {
                        ForEach(report.hosts) { host in
                            NavigationLink {
                                HostDetailView(hostIP: host.ip, onMQTT: { onMQTT(host.ip) })
                            } label: {
                                HostRow(host: host)
                            }
                            .listRowBackground(FinchTheme.surface)
                            .contextMenu {
                                Button {
                                    onDeepScan(host.ip)
                                } label: {
                                    Label("Deep Scan", systemImage: "dot.radiowaves.left.and.right")
                                }
                                Button {
                                    onIoTVulns(host.ip)
                                } label: {
                                    Label("IoT Vulns", systemImage: "ladybug")
                                }
                                Button {
                                    FinchCopy.set(host.copyText)
                                } label: {
                                    Label("Copy this host", systemImage: "doc.on.doc")
                                }
                                Button {
                                    FinchCopy.set(host.ip)
                                } label: {
                                    Label("Copy IP", systemImage: "network")
                                }
                                let cves = Array(Set(host.offenseHits.flatMap { $0.cves.map(\.cve) })).sorted()
                                if !cves.isEmpty {
                                    Button {
                                        FinchCopy.set(cves.joined(separator: "\n"))
                                    } label: {
                                        Label("Copy CVEs", systemImage: "ladybug")
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            } else {
                ScrollView { emptyState }
            }
        }
    }

    private func header(_ report: GlassFabricReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(report.cidr)
                    .font(FinchTheme.monoTitle)
                    .foregroundStyle(FinchTheme.cyan)
                Spacer()
                Text("\(report.hosts.count) hosts")
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.textSecondary)
            }
            if let local = report.localIP {
                Text("local \(local) · mask \(report.netmask ?? "?") · mDNS \(report.mdnsServiceCount) · SSDP \(report.ssdpDeviceCount)")
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.textSecondary)
            }
            if !report.warnings.isEmpty {
                ForEach(report.warnings, id: \.self) { w in
                    Text("⚠ \(w)")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.warn)
                }
            }
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button("Deep Scan All", action: onDeepScanAll)
                            .buttonStyle(FinchOutlineButtonStyle())
                        Button("IoT Vulns", action: onIoTVulnsAll)
                            .buttonStyle(FinchOutlineButtonStyle())
                        Button("SENTINEL", action: onExport)
                            .buttonStyle(FinchOutlineButtonStyle())
                        Button {
                            let all = report.hosts.map(\.copyText).joined(separator: "\n\n————\n\n")
                            FinchCopy.set(all.isEmpty ? "No hosts" : all)
                        } label: {
                            Image(systemName: "doc.on.doc.fill")
                        }
                        .buttonStyle(FinchOutlineButtonStyle())
                        .accessibilityLabel("Copy all hosts")
                    }
                }
                Text(report.phase.uppercased())
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.cyan)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(FinchTheme.surface.opacity(0.9))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 40))
                .foregroundStyle(FinchTheme.cyan.opacity(0.6))
            Text("GLASS FABRIC · 2.0")
                .font(FinchTheme.monoTitle)
                .foregroundStyle(FinchTheme.cyan)
            Text("Enter a CIDR (192.168.1.0/24) or tap Scan My Network.\nIoT Vulns = deep ports + offense + auto MQTT.\nResults stay ephemeral until Persist.")
                .font(FinchTheme.monoSmall)
                .foregroundStyle(FinchTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .padding(.top, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HostRow: View {
    let host: IoTHost

    private var flockHit: FlockCameraDetector.Hit? {
        FlockCameraDetector.matchHost(host)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(host.ip)
                    .font(FinchTheme.mono)
                    .foregroundStyle(FinchTheme.textPrimary)
                Spacer()
                if let flock = flockHit {
                    Text(flock.badge)
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.warn)
                }
                if !host.offenseHits.isEmpty {
                    let cveN = host.offenseHits.reduce(0) { $0 + $1.cves.count }
                    Text(cveN > 0 ? "CVE \(cveN)" : "VULN \(host.offenseHits.count)")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.danger)
                }
                if !host.mqttMessages.isEmpty {
                    Text("MQTT \(host.mqttMessages.count)")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.cyan)
                }
                if let fp = host.fingerprint {
                    Text(fp.vendor)
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.cyan)
                }
            }
            HStack(spacing: 8) {
                if let mac = host.mac {
                    Text(mac)
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.textSecondary)
                }
                if let vendor = host.vendor {
                    Text(vendor)
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.textSecondary)
                }
            }
            if let hostname = host.hostname {
                Text(hostname)
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.cyan.opacity(0.8))
            }
            Text("tcp \(host.openPorts.map(String.init).joined(separator: ","))")
                .font(FinchTheme.monoSmall)
                .foregroundStyle(FinchTheme.textSecondary)
                .lineLimit(1)
            if !host.openUDPPorts.isEmpty {
                Text("udp \(host.openUDPPorts.map(String.init).joined(separator: ","))")
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

struct HostDetailView: View {
    @Environment(AppModel.self) private var app
    let hostIP: String
    var onMQTT: () -> Void

    private var host: IoTHost? {
        app.glassPipeline.report?.hosts.first(where: { $0.ip == hostIP })
    }

    private var scanningThisHost: Bool {
        app.glassPipeline.isRunning &&
        (app.glassPipeline.selectedHostIP == hostIP || app.glassPipeline.phase == "deep" || app.glassPipeline.phase == "vulns")
    }

    var body: some View {
        Group {
            if let host {
                hostList(host)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .font(.largeTitle)
                        .foregroundStyle(FinchTheme.cyan.opacity(0.6))
                    Text("Host gone")
                        .font(FinchTheme.monoTitle)
                        .foregroundStyle(FinchTheme.textPrimary)
                    Text("\(hostIP) is no longer in the Glass report. Re-scan the network.")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(FinchTheme.background)
        .navigationTitle(host?.displayLabel ?? hostIP)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    kickDeepScan()
                } label: {
                    Label("Deep Scan", systemImage: "dot.radiowaves.left.and.right")
                }
                .disabled(app.glassPipeline.isRunning && app.glassPipeline.selectedHostIP != hostIP && app.glassPipeline.phase == "sweep")

                Button {
                    kickIoTVulns()
                } label: {
                    Label("IoT Vulns", systemImage: "ladybug")
                }

                if host?.hasMQTT == true {
                    Button(action: onMQTT) {
                        Label("MQTT", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if !app.glassPipeline.progressText.isEmpty,
               app.glassPipeline.isRunning || app.glassPipeline.selectedHostIP == hostIP {
                Text(app.glassPipeline.progressText)
                    .font(FinchTheme.monoSmall)
                    .foregroundStyle(FinchTheme.cyan)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(FinchTheme.surface.opacity(0.95))
            }
        }
    }

    @ViewBuilder
    private func hostList(_ host: IoTHost) -> some View {
        List {
            Section("Identity") {
                latticeRow("IP", host.ip)
                latticeRow("MAC", host.mac ?? "—")
                latticeRow("Vendor", host.vendor ?? "—")
                latticeRow("Hostname", host.hostname ?? "—")
                if let flock = FlockCameraDetector.matchHost(host) {
                    latticeRow("ALPR / Flock-class", "\(flock.vendor) · \(flock.model)")
                    Text(flock.reason)
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.warn)
                }
            }
            if let fp = host.fingerprint {
                Section("Fingerprint") {
                    latticeRow("Type", fp.deviceType)
                    latticeRow("Vendor", fp.vendor)
                    latticeRow("Model", fp.model)
                    latticeRow("Confidence", String(format: "%.0f%%", fp.confidence * 100))
                    latticeRow("Tags", fp.tags.joined(separator: ", "))
                }
            }
            Section("Open Ports") {
                Text("TCP: " + (host.openPorts.isEmpty ? "—" : host.openPorts.map(String.init).joined(separator: ", ")))
                    .font(FinchTheme.mono)
                    .finchCopyable(host.openPorts.map(String.init).joined(separator: ", "))
                if !host.openUDPPorts.isEmpty {
                    Text("UDP: " + host.openUDPPorts.map(String.init).joined(separator: ", "))
                        .font(FinchTheme.mono)
                        .finchCopyable(host.openUDPPorts.map(String.init).joined(separator: ", "))
                }
            }
            Section("Services") {
                if host.services.isEmpty {
                    Text("None discovered").foregroundStyle(.secondary)
                } else {
                    ForEach(host.services) { svc in
                        let line = "\(svc.name) · \(svc.type) · \(svc.host):\(svc.port)"
                        VStack(alignment: .leading) {
                            Text("\(svc.name) · \(svc.type)")
                                .font(FinchTheme.monoSmall)
                            Text("\(svc.host):\(svc.port)")
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(FinchTheme.cyan)
                        }
                        .finchCopyable(line)
                    }
                }
            }
            if !host.offenseHits.isEmpty {
                Section("Vulns / CVEs (\(host.offenseHits.count))") {
                    ForEach(host.offenseHits) { hit in
                        let hitBlock: String = {
                            var lines = ["[\(hit.severity)] \(hit.summary) · \(hit.proto)/\(hit.port)", hit.detail]
                            for cve in hit.cves {
                                lines.append("\(cve.cve) — \(cve.title)")
                                lines.append(cve.why)
                                lines.append(cve.nvdURL)
                            }
                            return lines.joined(separator: "\n")
                        }()
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(hit.severity)
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(
                                        hit.severity == "CRITICAL" || hit.severity == "HIGH"
                                        ? FinchTheme.danger
                                        : FinchTheme.warn
                                    )
                                Text(plainSource(hit.source))
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(FinchTheme.cyan)
                                Spacer()
                                Text("\(hit.proto.uppercased()) \(hit.port)")
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(FinchTheme.textSecondary)
                            }
                            Text(hit.summary)
                                .font(FinchTheme.mono)
                                .finchCopyable(hit.summary)
                            if !hit.cves.isEmpty {
                                ForEach(hit.cves) { cve in
                                    let block = "\(cve.cve) — \(cve.title)\n\(cve.why)\n\(cve.nvdURL)"
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(cve.cve)
                                                .font(FinchTheme.mono)
                                                .foregroundStyle(FinchTheme.danger)
                                            Text(cve.confidence)
                                                .font(FinchTheme.monoSmall)
                                                .foregroundStyle(FinchTheme.textSecondary)
                                        }
                                        Text(cve.title)
                                            .font(FinchTheme.monoSmall)
                                            .foregroundStyle(FinchTheme.textPrimary)
                                        Text(cve.why)
                                            .font(FinchTheme.monoSmall)
                                            .foregroundStyle(FinchTheme.textSecondary)
                                        Text(cve.nvdURL)
                                            .font(FinchTheme.monoSmall)
                                            .foregroundStyle(FinchTheme.cyan.opacity(0.85))
                                    }
                                    .padding(.vertical, 2)
                                    .finchCopyable(block, label: "Copy CVE")
                                }
                            }
                            Text(hit.detail)
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(FinchTheme.textSecondary)
                                .finchCopyable(hit.detail)
                                .lineLimit(6)
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            Button { FinchCopy.set(hitBlock) } label: {
                                Label("Copy this finding", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }
            Section("Banners") {
                if host.banners.isEmpty {
                    Text(scanningThisHost ? "Scanning…" : "Tap Deep Scan or IoT Vulns below")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(host.banners) { banner in
                        let text = banner.rawASCII.isEmpty ? "(no banner)" : banner.rawASCII
                        VStack(alignment: .leading, spacing: 4) {
                            Text(":\(banner.port) \(banner.protocolGuess)")
                                .font(FinchTheme.mono)
                                .foregroundStyle(FinchTheme.cyan)
                            Text(text)
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(FinchTheme.textSecondary)
                                .finchCopyable(text)
                        }
                    }
                }
            }
            if !host.mqttMessages.isEmpty {
                Section("MQTT (\(host.mqttMessages.count))") {
                    ForEach(host.mqttMessages) { msg in
                        VStack(alignment: .leading) {
                            Text(msg.topic)
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(FinchTheme.cyan)
                            Text(msg.payloadASCII)
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(FinchTheme.textSecondary)
                                .lineLimit(6)
                                .finchCopyable("\(msg.topic)\n\(msg.payloadASCII)")
                        }
                    }
                }
            }
            Section("Actions") {
                Button {
                    kickDeepScan()
                } label: {
                    HStack {
                        Text("Deep Scan")
                        if scanningThisHost && app.glassPipeline.phase == "deep" {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .foregroundStyle(FinchTheme.cyan)

                Button {
                    kickIoTVulns()
                } label: {
                    HStack {
                        Text("IoT Vulns")
                        if scanningThisHost && app.glassPipeline.phase == "vulns" {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .foregroundStyle(FinchTheme.cyan)

                if host.hasMQTT {
                    Button("Listen MQTT", action: onMQTT)
                }

                Button("Copy everything") {
                    FinchCopy.set(host.copyText)
                }
                .foregroundStyle(FinchTheme.cyan)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FinchTheme.background)
    }

    private func kickDeepScan() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        app.glassPipeline.deepScan(ip: hostIP)
        app.statusMessage = "Deep Scan → \(hostIP)"
    }

    private func kickIoTVulns() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        app.glassPipeline.iotVulns(ip: hostIP)
        app.statusMessage = "IoT Vulns → \(hostIP)"
    }

    private func plainSource(_ source: String) -> String {
        switch source {
        case "offense.redis": return "Redis"
        case "offense.memcached": return "Memcached"
        case "offense.mongodb": return "MongoDB"
        case "offense.mqtt": return "MQTT"
        case "offense.snmp": return "SNMP"
        case "offense.coap": return "CoAP"
        case "offense.telnet": return "Telnet"
        case "offense.ftp": return "FTP"
        case "offense.rtsp": return "Camera / RTSP"
        case "offense.onvif": return "ONVIF camera"
        case "offense.http": return "Web service"
        case "offense.ports": return "Open service"
        case "offense.udp": return "UDP service"
        case "cve.fingerprint": return "Device CVEs"
        case "cve.banner": return "Banner CVEs"
        default: return source.replacingOccurrences(of: "offense.", with: "")
        }
    }

    private func latticeRow(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key)
                .font(FinchTheme.monoSmall)
                .foregroundStyle(FinchTheme.textSecondary)
            Text(value)
                .font(FinchTheme.mono)
                .foregroundStyle(FinchTheme.textPrimary)
                .finchCopyable(value, label: "Copy \(key)")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button { FinchCopy.set(value) } label: {
                Label("Copy \(key)", systemImage: "doc.on.doc")
            }
            Button { FinchCopy.set("\(key): \(value)") } label: {
                Label("Copy labeled", systemImage: "text.append")
            }
        }
    }
}
