import Foundation
import Observation

@Observable
final class GlassFabricPipeline {
    var report: GlassFabricReport?
    var isRunning: Bool = false
    var phase: String = "idle"
    var progressText: String = ""
    var selectedHostIP: String?

    private let sweep = SubnetSweepService()
    private let mdns = MDNSBrowserService()
    private let ssdp = SSDPDiscoveryService()
    private let deep = DeepIoTScanner()
    private let offense = OffenseProbeService()
    private let mqtt = MQTTClient()
    private var runTask: Task<Void, Never>?

    func reset() {
        runTask?.cancel()
        mdns.stop()
        ssdp.stop()
        mqtt.cancel()
        report = nil
        isRunning = false
        phase = "idle"
        progressText = ""
        selectedHostIP = nil
    }

    func engage(query: String) {
        runTask?.cancel()
        runTask = Task { await run(query: query) }
    }

    func run(query: String) async {
        await MainActor.run {
            isRunning = true
            phase = "init"
            progressText = "Resolving local fabric… FinchMobile/1.1"
        }

        let iface = NetworkInterfaceHelper.primaryIPv4()
        var warnings: [String] = []
        let cidr: String

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == "scan my network" || lower == "scan network" || trimmed.isEmpty {
            if let iface {
                cidr = iface.cidr
            } else {
                await MainActor.run {
                    isRunning = false
                    phase = "error"
                    progressText = "No local IPv4 interface (en0) found."
                    report = GlassFabricReport(
                        query: query,
                        cidr: "",
                        localIP: nil,
                        netmask: nil,
                        startedAt: Date(),
                        finishedAt: Date(),
                        hosts: [],
                        warnings: ["Unable to determine local subnet. Enter a CIDR manually."],
                        mdnsServiceCount: 0,
                        ssdpDeviceCount: 0,
                        phase: "error"
                    )
                }
                return
            }
        } else if InputRouter.isCIDR(trimmed) {
            cidr = trimmed
        } else if InputRouter.isPrivateIP(trimmed) {
            if let ip = NetworkInterfaceHelper.ipv4ToUInt32(trimmed) {
                let net = ip & NetworkInterfaceHelper.prefixMask(24)
                cidr = "\(NetworkInterfaceHelper.uInt32ToIPv4(net))/24"
            } else {
                cidr = "\(trimmed)/32"
            }
        } else {
            cidr = iface?.cidr ?? "192.168.1.0/24"
            warnings.append("Input not CIDR/private IP — using \(cidr).")
        }

        await MainActor.run {
            report = GlassFabricReport(
                query: query,
                cidr: cidr,
                localIP: iface?.ip,
                netmask: iface?.netmask,
                startedAt: Date(),
                finishedAt: nil,
                hosts: [],
                warnings: warnings,
                mdnsServiceCount: 0,
                ssdpDeviceCount: 0,
                phase: "sweep"
            )
            phase = "sweep"
            progressText = "Subnet sweep \(cidr)"
        }

        sweep.onHostFound = { [weak self] host in
            Task { @MainActor in
                self?.mergeHost(host)
            }
        }
        sweep.onProgress = { [weak self] text in
            Task { @MainActor in
                self?.progressText = text
            }
        }

        mdns.onUpdate = { [weak self] services in
            Task { @MainActor in
                self?.mergeMDNS(services)
            }
        }
        ssdp.onUpdate = { [weak self] devices in
            Task { @MainActor in
                self?.mergeSSDP(devices)
            }
        }
        mdns.start()
        ssdp.start(duration: 4.0)

        let sweepResult = await sweep.sweep(cidr: cidr)
        await MainActor.run {
            var w = self.report?.warnings ?? []
            w.append(contentsOf: sweepResult.warnings)
            for h in sweepResult.hosts { self.mergeHost(h) }
            self.phase = "discovery"
            self.progressText = "mDNS + SSDP discovery…"
            self.report?.warnings = w
            self.report?.cidr = sweepResult.effectiveCIDR
            self.report?.phase = self.phase
        }

        try? await Task.sleep(nanoseconds: 3_500_000_000)
        let services = mdns.snapshot()
        let ssdpDevices = ssdp.snapshot()
        await MainActor.run {
            self.mergeMDNS(services)
            self.mergeSSDP(ssdpDevices)
            self.phase = "ready"
            self.progressText = "Fabric mapped — Deep Scan / IoT Vulns available"
            self.report?.finishedAt = Date()
            self.report?.phase = self.phase
            self.isRunning = false
        }
    }

    @MainActor
    private func mergeHost(_ host: IoTHost) {
        guard var report else {
            self.report = GlassFabricReport(
                query: host.ip,
                cidr: "",
                localIP: nil,
                netmask: nil,
                startedAt: Date(),
                finishedAt: nil,
                hosts: [host],
                warnings: [],
                mdnsServiceCount: 0,
                ssdpDeviceCount: 0,
                phase: phase
            )
            return
        }
        if let idx = report.hosts.firstIndex(where: { $0.ip == host.ip }) {
            report.hosts[idx].merge(host)
        } else {
            report.hosts.append(host)
            report.hosts.sort { $0.ip < $1.ip }
        }
        report.phase = phase
        self.report = report
    }

    @MainActor
    private func mergeMDNS(_ services: [MDNSServiceRecord]) {
        guard var report else { return }
        report.mdnsServiceCount = services.count
        for svc in services {
            let ip = extractIPv4(from: svc.host) ?? svc.host
            var host = report.hosts.first(where: { $0.ip == ip }) ?? IoTHost(ip: ip, hostname: svc.name)
            if host.services.contains(where: { $0.id == svc.id }) == false {
                host.services.append(svc)
            }
            if host.hostname == nil { host.hostname = svc.name }
            if !host.openPorts.contains(svc.port) {
                host.openPorts.append(svc.port)
                host.openPorts.sort()
            }
            if let idx = report.hosts.firstIndex(where: { $0.ip == host.ip }) {
                report.hosts[idx].merge(host)
            } else {
                report.hosts.append(host)
            }
        }
        report.hosts.sort { $0.ip < $1.ip }
        self.report = report
    }

    @MainActor
    private func mergeSSDP(_ devices: [SSDPDevice]) {
        guard report != nil else { return }
        for device in devices {
            var host = report?.hosts.first(where: { $0.ip == device.ip }) ?? IoTHost(ip: device.ip)
            if host.hostname == nil || host.hostname?.isEmpty == true {
                host.hostname = device.friendlyHint ?? device.server
            }
            var txt: [String: String] = [:]
            if let loc = device.location { txt["LOCATION"] = loc }
            if let server = device.server { txt["SERVER"] = server }
            if let usn = device.usn { txt["USN"] = usn }
            if let st = device.st { txt["ST"] = st }
            let svc = MDNSServiceRecord(
                name: device.friendlyHint ?? "ssdp",
                type: "_ssdp._udp",
                host: device.ip,
                port: 1900,
                txt: txt
            )
            if !host.services.contains(where: { $0.id == svc.id }) {
                host.services.append(svc)
            }
            if !host.openUDPPorts.contains(1900) {
                host.openUDPPorts.append(1900)
                host.openUDPPorts.sort()
            }
            let hit = OffenseHit(
                source: "ssdp",
                severity: "INFO",
                port: 1900,
                proto: "udp",
                summary: "SSDP \(device.st ?? "device") · \(device.ip)",
                detail: [device.location, device.server, device.usn].compactMap { $0 }.joined(separator: " · ")
            )
            if !host.offenseHits.contains(where: { $0.id == hit.id }) {
                host.offenseHits.append(hit)
            }
            mergeHost(host)
        }
        self.report?.ssdpDeviceCount = devices.count
    }

    private func extractIPv4(from host: String) -> String? {
        if InputRouter.isIPv4(host) { return host }
        let cleaned = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if InputRouter.isIPv4(cleaned) { return cleaned }
        return nil
    }

    func deepScan(ip: String) {
        Task { await performDeepScan(ip: ip) }
    }

    func deepScanAll() {
        Task {
            let ips = await MainActor.run { report?.hosts.map(\.ip) ?? [] }
            for ip in ips {
                await performDeepScan(ip: ip)
            }
        }
    }

    func iotVulns(ip: String) {
        Task { await performIoTVulns(ip: ip, autoMQTT: true) }
    }

    func iotVulnsAll() {
        Task {
            let ips = await MainActor.run { report?.hosts.map(\.ip) ?? [] }
            for ip in ips {
                await performIoTVulns(ip: ip, autoMQTT: true)
            }
        }
    }

    private func performDeepScan(ip: String) async {
        await MainActor.run {
            isRunning = true
            phase = "deep"
            progressText = "Deep IoT scan \(ip)"
            selectedHostIP = ip
        }
        deep.onProgress = { [weak self] text in
            Task { @MainActor in self?.progressText = text }
        }
        let result = await deep.scanHost(ip)
        let fp = FingerprintEngine.shared.match(
            banners: result.banners,
            services: await MainActor.run { report?.hosts.first(where: { $0.ip == ip })?.services ?? [] }
        )
        await MainActor.run {
            var host = self.report?.hosts.first(where: { $0.ip == ip }) ?? IoTHost(ip: ip)
            host.openPorts = Array(Set(host.openPorts + result.openPorts)).sorted()
            host.banners = result.banners
            host.fingerprint = fp
            self.mergeHost(host)
            self.phase = "ready"
            self.progressText = "Deep scan complete — \(ip)"
            self.isRunning = false
            self.report?.phase = self.phase
        }
    }

    private func performIoTVulns(ip: String, autoMQTT: Bool) async {
        await MainActor.run {
            isRunning = true
            phase = "vulns"
            progressText = "IoT Vulns \(ip) — deep scan…"
            selectedHostIP = ip
        }
        deep.onProgress = { [weak self] text in
            Task { @MainActor in self?.progressText = text }
        }
        offense.onProgress = { [weak self] text in
            Task { @MainActor in self?.progressText = text }
        }

        let deepResult = await deep.scanHost(ip)
        let offenseResult = await offense.probeHost(
            ip: ip,
            openTCP: deepResult.openPorts,
            banners: deepResult.banners
        )
        let existingServices = await MainActor.run { report?.hosts.first(where: { $0.ip == ip })?.services ?? [] }
        let existingVendor = await MainActor.run { report?.hosts.first(where: { $0.ip == ip })?.vendor }
        let fp = FingerprintEngine.shared.match(
            banners: deepResult.banners,
            services: existingServices
        )
        let enrichedHits = CVEEnricher.enrich(
            hits: offenseResult.hits,
            banners: deepResult.banners,
            fingerprint: fp,
            vendor: existingVendor
        )

        await MainActor.run {
            var host = self.report?.hosts.first(where: { $0.ip == ip }) ?? IoTHost(ip: ip)
            host.openPorts = Array(Set(host.openPorts + deepResult.openPorts)).sorted()
            host.openUDPPorts = Array(Set(host.openUDPPorts + offenseResult.openUDP)).sorted()
            host.banners = deepResult.banners
            host.fingerprint = fp
            host.offenseHits.append(contentsOf: enrichedHits)
            self.mergeHost(host)
            let cveCount = enrichedHits.reduce(0) { $0 + $1.cves.count }
            self.progressText = "IoT Vulns \(ip) — \(enrichedHits.count) hits · \(cveCount) CVEs"
        }

        if autoMQTT {
            let mqttPorts = await MainActor.run {
                report?.hosts.first(where: { $0.ip == ip })?.mqttPorts ?? []
            }
            for port in mqttPorts {
                await listenMQTTAsync(ip: ip, port: UInt16(port), duration: 20, username: nil, password: nil)
            }
        }

        await MainActor.run {
            self.phase = "ready"
            self.progressText = "IoT Vulns complete — \(ip)"
            self.isRunning = false
            self.report?.phase = self.phase
        }
    }

    func listenMQTT(ip: String, port: UInt16 = 1883, duration: TimeInterval, username: String? = nil, password: String? = nil) {
        Task {
            await MainActor.run {
                isRunning = true
                phase = "mqtt"
            }
            await listenMQTTAsync(ip: ip, port: port, duration: duration, username: username, password: password)
            await MainActor.run {
                self.phase = "ready"
                self.isRunning = false
                self.report?.phase = self.phase
            }
        }
    }

    private func listenMQTTAsync(
        ip: String,
        port: UInt16,
        duration: TimeInterval,
        username: String?,
        password: String?
    ) async {
        let capped = min(max(duration, 1), 60)
        await MainActor.run {
            progressText = "MQTT listen \(ip):\(port) \(Int(capped))s"
        }
        let messages = await mqtt.listen(
            host: ip,
            port: port,
            topic: "#",
            username: username,
            password: password,
            durationSeconds: capped
        ) { [weak self] msg in
            Task { @MainActor in
                guard let self else { return }
                var host = self.report?.hosts.first(where: { $0.ip == ip }) ?? IoTHost(ip: ip)
                host.mqttMessages.append(msg)
                self.mergeHost(host)
                self.progressText = "MQTT \(host.mqttMessages.count) msgs @ \(ip):\(port)"
            }
        }
        await MainActor.run {
            var host = self.report?.hosts.first(where: { $0.ip == ip }) ?? IoTHost(ip: ip)
            if host.mqttMessages.count < messages.count {
                host.mqttMessages = messages
                self.mergeHost(host)
            }
            self.progressText = "MQTT listen finished \(ip):\(port) (\(messages.count))"
        }
    }
}
