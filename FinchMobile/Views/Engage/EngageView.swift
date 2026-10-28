import SwiftUI
import UIKit

struct EngageView: View {
    @Environment(AppModel.self) private var app
    @FocusState private var engageFocused: Bool
    @State private var lastScan: (query: String, kind: PipelineKind)?
    @State private var mqttDuration: Double = 20
    @State private var showMQTTSheet = false
    @State private var mqttTargetIP: String = ""
    @State private var mqttPort: String = "1883"
    @State private var persistTitle: String = ""
    @State private var persistPassphrase: String = ""
    @State private var showPersist = false
    @Environment(\.modelContext) private var modelContext

    var detected: PipelineKind {
        InputRouter.resolve(query: app.engageQuery.isEmpty ? "scan my network" : app.engageQuery, override: app.selectedPipeline)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FinchTheme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    ARIAHeader()
                    engageBar
                    pipelinePicker
                    if !app.statusMessage.isEmpty || app.glassPipeline.isRunning || app.osintEngine.isRunning {
                        Text(statusLine)
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(FinchTheme.cyan)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                    if shouldShowOsint {
                        if let report = app.osintEngine.report {
                            OsintLatticeView(report: report, onAction: followOsintAction)
                                .refreshable { await repeatScan() }
                        } else if app.osintEngine.isRunning {
                            ProgressView(app.osintEngine.progressText)
                                .tint(FinchTheme.cyan)
                                .padding()
                        }
                    } else {
                    LatticeView(
                        report: app.glassPipeline.report,
                        showNetworkHeader: false,
                        onDeepScan: {
                            app.glassPipeline.deepScan(ip: $0)
                            app.statusMessage = "Deep Scan → \($0)"
                        },
                        onDeepScanAll: {
                            app.glassPipeline.deepScanAll()
                            app.statusMessage = "Deep Scan All…"
                        },
                        onIoTVulns: {
                            app.glassPipeline.iotVulns(ip: $0)
                            app.statusMessage = "IoT Vulns → \($0)"
                        },
                        onIoTVulnsAll: {
                            app.glassPipeline.iotVulnsAll()
                            app.statusMessage = "IoT Vulns All…"
                        },
                        onMQTT: { ip in
                            mqttTargetIP = ip
                            showMQTTSheet = true
                        },
                        onExport: exportSentinel
                    )
                    .refreshable { await repeatScan() }
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Persist") { preparePersist() }
                        .disabled(app.reportContainer.isEmpty && app.glassPipeline.report == nil && app.osintEngine.report == nil)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        app.clearEphemeral()
                        app.engageQuery = ""
                        app.osintEngine.reset()
                    }
                }
            }
            .onChange(of: app.glassPipeline.isRunning) { _, running in
                if !running {
                    syncReport()
                    app.refreshFusion()
                }
            }
            .onChange(of: app.glassPipeline.progressText) { _, text in
                if !text.isEmpty { app.statusMessage = text }
            }
            .onChange(of: app.osintEngine.isRunning) { _, running in
                if !running, let r = app.osintEngine.report {
                    app.reportContainer.osint = r
                    app.reportContainer.title = "OSINT \(r.pipeline.label)"
                    app.statusMessage = app.osintEngine.progressText
                }
            }
            .onChange(of: app.osintEngine.progressText) { _, text in
                if !text.isEmpty { app.statusMessage = text }
            }
        }
    }

    private var engageBar: some View {
        HStack(spacing: 8) {
            TextField("SCAN MY NETWORK", text: Bindable(app).engageQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(FinchTheme.mono)
                .foregroundStyle(FinchTheme.textPrimary)
                .padding(12)
                .focused($engageFocused)
                .glowBorder(active: engageFocused)
                .onSubmit { engage() }

            Button(action: engage) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(FinchTheme.background)
                    .padding(12)
                    .background(FinchTheme.cyan)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(app.glassPipeline.isRunning || app.osintEngine.isRunning)
        }
        .padding(.horizontal)
    }

    private var pipelinePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PipelineKind.allCases.filter { $0 != .ble }) { kind in
                        Button {
                            app.selectedPipeline = kind
                        } label: {
                            Text(kind.label)
                                .font(FinchTheme.monoSmall)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(app.selectedPipeline == kind ? FinchTheme.cyan : FinchTheme.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(app.selectedPipeline == kind ? FinchTheme.cyan : FinchTheme.cyan.opacity(0.25), lineWidth: 1)
                                )
                                .foregroundStyle(app.selectedPipeline == kind ? Color.black : FinchTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            Text("detected: \(detected.label)")
                .font(FinchTheme.monoSmall)
                .foregroundStyle(FinchTheme.textSecondary)
                .padding(.horizontal)
            if !app.caseSeeds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(app.caseSeeds) { seed in
                            Button {
                                app.engageQuery = seed.value
                                app.selectedPipeline = seed.kind
                                engage()
                            } label: {
                                Text("\(seed.kind.label) · \(seed.value)")
                                    .font(FinchTheme.monoSmall)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().stroke(FinchTheme.cyan.opacity(0.45), lineWidth: 1))
                                    .foregroundStyle(FinchTheme.textPrimary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.bottom, 4)
    }

    private var actionRow: some View {
        HStack {
            Button("Scan My Network") {
                app.engageQuery = "scan my network"
                app.selectedPipeline = .glassFabric
                engage()
            }
            .buttonStyle(FinchOutlineButtonStyle())

            Button("Nearby Bluetooth") {
                app.engageQuery = "scan ble"
                app.selectedPipeline = .ble
                engage()
            }
            .buttonStyle(FinchOutlineButtonStyle())
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var shouldShowOsint: Bool {
        app.lastKind.isOsint || app.osintEngine.isRunning || app.osintEngine.report != nil && app.lastKind.isOsint
    }

    private var statusLine: String {
        if app.osintEngine.isRunning, !app.osintEngine.progressText.isEmpty { return app.osintEngine.progressText }
        if app.glassPipeline.isRunning, !app.glassPipeline.progressText.isEmpty { return app.glassPipeline.progressText }
        return app.statusMessage
    }

    private func followOsintAction(_ action: OsintAction) {
        app.engageQuery = action.seed
        app.selectedPipeline = action.pipeline
        engage()
    }

    private func rememberSeed(_ kind: PipelineKind, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !app.caseSeeds.contains(where: { $0.value == trimmed && $0.kind == kind }) {
            app.caseSeeds.insert(CaseSeed(kind: kind, value: trimmed), at: 0)
            if app.caseSeeds.count > 12 { app.caseSeeds = Array(app.caseSeeds.prefix(12)) }
        }
    }

    private func repeatScan() async {
        guard !app.glassPipeline.isRunning && !app.osintEngine.isRunning else { return }
        if let lastScan {
            app.engageQuery = lastScan.query
            app.selectedPipeline = lastScan.kind
        }
        await runScan()
        await app.glassPipeline.waitForCompletion()
        await Task.yield()
        while app.glassPipeline.isRunning || app.osintEngine.isRunning {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func engage() {
        Task { await runScan() }
    }

    private func runScan() async {
        guard await app.aria.connection.awaitPreflight() else {
            app.statusMessage = "Allow Local Network access in Settings, then retry."
            return
        }
        performEngage()
    }

    private func performEngage() {
        if app.engageQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            app.engageQuery = "scan my network"
        }
        let kind = InputRouter.resolve(query: app.engageQuery, override: app.selectedPipeline)
        lastScan = (app.engageQuery, app.selectedPipeline)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        app.lastKind = kind
        rememberSeed(kind, app.engageQuery)
        switch kind {
        case .ble:
            app.statusMessage = "Opening Nearby Bluetooth…"
            app.bleScanner.continuousMode = true
            app.bleScanner.start()
            app.reportContainer.bleSnapshot = app.bleScanner.sortedDevices
            app.reportContainer.title = "Nearby Bluetooth"
        case .glassFabric, .auto:
            app.statusMessage = "Dispatch → Glass Fabric"
            app.glassPipeline.engage(query: app.engageQuery.isEmpty ? "scan my network" : app.engageQuery)
            syncReport()
        case .identity, .property, .plate, .cyber, .web3:
            app.statusMessage = "Dispatch → \(kind.label)"
            app.osintEngine.run(
                query: app.engageQuery,
                kind: kind,
                settings: app.settings,
                caseSeeds: app.caseSeeds
            )
        }
    }

    private func syncReport() {
        if let r = app.glassPipeline.report {
            app.reportContainer.glassReport = r
            app.reportContainer.title = "Glass \(r.cidr)"
        }
        if let o = app.osintEngine.report {
            app.reportContainer.osint = o
        }
    }

    private func exportSentinel() {
        syncReport()
        guard let report = app.glassPipeline.report else { return }
        do {
            let data = try SentinelExporter.json(from: report, ble: app.bleScanner.sortedDevices)
            SentinelExporter.share(data: data, filename: "sentinel-\(Int(Date().timeIntervalSince1970)).json")
        } catch {
            app.statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func preparePersist() {
        syncReport()
        if let r = app.glassPipeline.report {
            app.reportContainer.glassReport = r
        }
        if let o = app.osintEngine.report {
            app.reportContainer.osint = o
        }
        app.reportContainer.bleSnapshot = app.bleScanner.sortedDevices
        persistTitle = app.reportContainer.title.isEmpty ? "Finch report" : app.reportContainer.title
        showPersist = true
    }

    private var mqttSheet: some View {
        NavigationStack {
            Form {
                Section("Broker") {
                    TextField("Host IP", text: $mqttTargetIP)
                        .font(FinchTheme.mono)
                    TextField("Port", text: $mqttPort)
                        .font(FinchTheme.mono)
                        .keyboardType(.numberPad)
                }
                Section("Duration (max 60s)") {
                    Slider(value: $mqttDuration, in: 5...60, step: 5)
                    Text("\(Int(mqttDuration)) seconds")
                        .font(FinchTheme.mono)
                }
                Section("Auth (optional)") {
                    TextField("Username", text: Bindable(app.settings).mqttUsername)
                    SecureField("Password", text: Bindable(app.settings).mqttPassword)
                }
                Section {
                    Text("Subscribe only (#). Publish disabled.")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(FinchTheme.background)
            .navigationTitle("Listen MQTT")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showMQTTSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listen") {
                        let port = UInt16(mqttPort) ?? 1883
                        let user = app.settings.mqttUsername.isEmpty ? nil : app.settings.mqttUsername
                        let pass = app.settings.mqttPassword.isEmpty ? nil : app.settings.mqttPassword
                        app.glassPipeline.listenMQTT(
                            ip: mqttTargetIP,
                            port: port,
                            duration: mqttDuration,
                            username: user,
                            password: pass
                        )
                        showMQTTSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var persistSheet: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $persistTitle)
                if !app.vaultManager.hasPassphrase() {
                    SecureField("Vault passphrase", text: $persistPassphrase)
                    Text("Required once — stored in Keychain, used for AES-256-GCM.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Vault passphrase on file. Biometrics required to decrypt later.")
                        .font(.caption)
                }
            }
            .navigationTitle("Persist to Vault")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showPersist = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Encrypt") {
                        Task { await persistNow() }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @MainActor
    private func persistNow() async {
        if !app.vaultManager.hasPassphrase() {
            guard !persistPassphrase.isEmpty else {
                app.statusMessage = "Passphrase required"
                return
            }
            app.vaultManager.setPassphrase(persistPassphrase)
        } else {
            let ok = await app.vaultManager.authenticateBiometric(reason: "Authenticate to encrypt vault item")
            if !ok, !app.vaultManager.unlockWithStoredPassphrase() {
                app.statusMessage = "Auth failed"
                return
            }
        }
        do {
            syncReport()
            let data = try app.reportContainer.encodeJSON()
            try app.vaultManager.persist(reportJSON: data, title: persistTitle, context: modelContext)
            showPersist = false
            app.statusMessage = "Persisted to vault"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            app.statusMessage = error.localizedDescription
        }
    }
}

struct FinchOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FinchTheme.monoSmall)
            .foregroundStyle(FinchTheme.cyan)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(FinchTheme.cyan.opacity(configuration.isPressed ? 0.4 : 0.8), lineWidth: 1)
            )
    }
}

/// Uses the same Glass Fabric coordinator as Scan; all actions retain 3.2 behavior.
struct FinchNetworkView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var local: LocalInterfaceInfo?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ARIAHeader()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(local?.cidr ?? "No local network")
                                .font(.system(.title2, design: .monospaced).bold())
                                .foregroundStyle(FinchTheme.cyan)
                            Spacer()
                            Text("\(currentReport?.hosts.count ?? 0) hosts").font(FinchTheme.monoSmall)
                        }
                        Text("local \(local?.ip ?? "—") · mask \(local?.netmask ?? "—")")
                        Text("mDNS \(currentReport?.mdnsServiceCount ?? 0) · SSDP \(currentReport?.ssdpDeviceCount ?? 0)")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                Button("Deep Scan All") { app.glassPipeline.deepScanAll() }
                                    .buttonStyle(.borderedProminent).tint(FinchTheme.cyan)
                                    .disabled(currentReport == nil || app.glassPipeline.isRunning)
                                Button("IoT Vulns") { app.glassPipeline.iotVulnsAll() }
                                    .buttonStyle(FinchOutlineButtonStyle())
                                    .disabled(currentReport == nil || app.glassPipeline.isRunning)
                                Button("SENTINEL", action: export).buttonStyle(.plain)
                                    .foregroundStyle(FinchTheme.cyan).disabled(currentReport == nil)
                                Button("SWEEP") { Task { await refresh() } }
                                    .buttonStyle(.borderedProminent).tint(FinchTheme.secondaryAccent)
                                    .disabled(local == nil || app.glassPipeline.isRunning)
                            }
                        }
                        if app.glassPipeline.isRunning {
                            ProgressView(app.glassPipeline.progressText).tint(FinchTheme.cyan)
                        }
                        ForEach(currentReport?.warnings ?? [], id: \.self) { warning in
                            Text(warning).foregroundStyle(FinchTheme.textSecondary)
                        }
                        if let report = currentReport {
                            ForEach(report.hosts) { host in
                                HostRow(host: host).padding().frame(maxWidth: .infinity, alignment: .leading)
                                    .background(FinchCardBackground())
                            }
                        }
                    }.font(FinchTheme.monoSmall).padding()
                }
                .refreshable { await refresh() }
            }
            .background(FinchTheme.background.ignoresSafeArea())
            .navigationTitle("Network").navigationBarTitleDisplayMode(.inline)
            .task { await refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await refresh() } }
            }
        }
    }

    private var currentReport: GlassFabricReport? {
        guard let report = app.glassPipeline.report, report.localIP == local?.ip else { return nil }
        return report
    }

    private func refresh() async {
        local = NetworkInterfaceHelper.primaryIPv4(preferring: ["en0", "en1"])
        guard let local, local.interfaceName == "en0" || local.interfaceName == "en1",
              !app.glassPipeline.isRunning else { return }
        guard await app.aria.connection.awaitPreflight() else { return }
        app.glassPipeline.engage(query: local.cidr)
        await app.glassPipeline.waitForCompletion()
    }

    private func export() {
        guard let report = currentReport else { return }
        do {
            let data = try SentinelExporter.json(from: report, ble: app.bleScanner.sortedDevices)
            SentinelExporter.share(data: data, filename: "sentinel-\(Int(Date().timeIntervalSince1970)).json")
        } catch { app.statusMessage = "Export failed: \(error.localizedDescription)" }
    }
}
