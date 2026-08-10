import SwiftUI
import UIKit

struct LatticeView: View {
    var report: GlassFabricReport?
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
                    header(report)
                    List {
                        ForEach(report.hosts) { host in
                            NavigationLink {
                                HostDetailView(
                                    host: host,
                                    onDeepScan: { onDeepScan(host.ip) },
                                    onIoTVulns: { onIoTVulns(host.ip) },
                                    onMQTT: { onMQTT(host.ip) }
                                )
                            } label: {
                                HostRow(host: host)
                            }
                            .listRowBackground(FinchTheme.surface)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            } else {
                emptyState
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
                Button("Deep Scan All", action: onDeepScanAll)
                    .buttonStyle(FinchOutlineButtonStyle())
                Button("IoT Vulns", action: onIoTVulnsAll)
                    .buttonStyle(FinchOutlineButtonStyle())
                Button("SENTINEL", action: onExport)
                    .buttonStyle(FinchOutlineButtonStyle())
                Spacer()
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
            Text("GLASS FABRIC · 1.1")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(host.ip)
                    .font(FinchTheme.mono)
                    .foregroundStyle(FinchTheme.textPrimary)
                Spacer()
                if !host.offenseHits.isEmpty {
                    Text("VULN \(host.offenseHits.count)")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.warn)
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
    let host: IoTHost
    var onDeepScan: () -> Void
    var onIoTVulns: () -> Void
    var onMQTT: () -> Void

    var body: some View {
        List {
            Section("Identity") {
                latticeRow("IP", host.ip)
                latticeRow("MAC", host.mac ?? "—")
                latticeRow("Vendor", host.vendor ?? "—")
                latticeRow("Hostname", host.hostname ?? "—")
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
                Text("TCP: " + host.openPorts.map(String.init).joined(separator: ", "))
                    .font(FinchTheme.mono)
                if !host.openUDPPorts.isEmpty {
                    Text("UDP: " + host.openUDPPorts.map(String.init).joined(separator: ", "))
                        .font(FinchTheme.mono)
                }
            }
            Section("Services") {
                if host.services.isEmpty {
                    Text("None discovered").foregroundStyle(.secondary)
                } else {
                    ForEach(host.services) { svc in
                        VStack(alignment: .leading) {
                            Text("\(svc.name) · \(svc.type)")
                                .font(FinchTheme.monoSmall)
                            Text("\(svc.host):\(svc.port)")
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(FinchTheme.cyan)
                        }
                    }
                }
            }
            if !host.offenseHits.isEmpty {
                Section("Offense (\(host.offenseHits.count))") {
                    ForEach(host.offenseHits) { hit in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(hit.severity)
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(hit.severity == "HIGH" ? FinchTheme.danger : FinchTheme.warn)
                                Text(hit.source)
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(FinchTheme.cyan)
                                Spacer()
                                Text("\(hit.proto)/\(hit.port)")
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(FinchTheme.textSecondary)
                            }
                            Text(hit.summary)
                                .font(FinchTheme.mono)
                            Text(hit.detail)
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(FinchTheme.textSecondary)
                                .textSelection(.enabled)
                                .lineLimit(6)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            Section("Banners") {
                if host.banners.isEmpty {
                    Text("Run Deep Scan or IoT Vulns").foregroundStyle(.secondary)
                } else {
                    ForEach(host.banners) { banner in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(":\(banner.port) \(banner.protocolGuess)")
                                .font(FinchTheme.mono)
                                .foregroundStyle(FinchTheme.cyan)
                            Text(banner.rawASCII.isEmpty ? "(no banner)" : banner.rawASCII)
                                .font(FinchTheme.monoSmall)
                                .foregroundStyle(FinchTheme.textSecondary)
                                .textSelection(.enabled)
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
                                .lineLimit(4)
                        }
                    }
                }
            }
            Section {
                Button("Deep Scan", action: onDeepScan)
                Button("IoT Vulns", action: onIoTVulns)
                    .foregroundStyle(FinchTheme.cyan)
                if host.hasMQTT {
                    Button("Listen MQTT", action: onMQTT)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FinchTheme.background)
        .navigationTitle(host.displayLabel)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func latticeRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(FinchTheme.monoSmall)
                .foregroundStyle(FinchTheme.textSecondary)
            Spacer()
            Text(value)
                .font(FinchTheme.mono)
                .foregroundStyle(FinchTheme.textPrimary)
                .textSelection(.enabled)
                .onTapGesture {
                    UIPasteboard.general.string = value
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
        }
    }
}
