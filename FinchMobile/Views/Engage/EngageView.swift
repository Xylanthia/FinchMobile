import SwiftUI
import UIKit

struct EngageView: View {
    @Environment(AppModel.self) private var app
    @FocusState private var engageFocused: Bool
    @State private var mqttDuration: Double = 20
    @State private var showMQTTSheet = false
    @State private var mqttTargetIP: String = ""
    @State private var mqttPort: String = "1883"
    @State private var persistTitle: String = ""
    @State private var persistPassphrase: String = ""
    @State private var showPersist = false
    @Environment(\.modelContext) private var modelContext

    var detected: PipelineKind {
        InputRouter.classify(app.engageQuery)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FinchTheme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    engageBar
                    pipelinePicker
                    actionRow
                    if !app.statusMessage.isEmpty || app.glassPipeline.isRunning {
                        Text(app.glassPipeline.progressText.isEmpty ? app.statusMessage : app.glassPipeline.progressText)
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(FinchTheme.cyan)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                    LatticeView(
                        report: app.glassPipeline.report,
                        onDeepScan: { app.glassPipeline.deepScan(ip: $0) },
                        onDeepScanAll: { app.glassPipeline.deepScanAll() },
                        onIoTVulns: { app.glassPipeline.iotVulns(ip: $0) },
                        onIoTVulnsAll: { app.glassPipeline.iotVulnsAll() },
                        onMQTT: { ip in
                            mqttTargetIP = ip
                            showMQTTSheet = true
                        },
                        onExport: exportSentinel
                    )
                }
                .padding(.top, 8)
            }
            .navigationTitle("FINCH · GLASS 2.0")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Persist") { preparePersist() }
                        .disabled(app.reportContainer.isEmpty && app.glassPipeline.report == nil)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        app.clearEphemeral()
                        app.engageQuery = ""
                    }
                }
            }
            .sheet(isPresented: $showMQTTSheet) { mqttSheet }
            .sheet(isPresented: $showPersist) { persistSheet }
        }
    }

    private var engageBar: some View {
        HStack(spacing: 8) {
            TextField("Wi‑Fi range · IP · nearby bluetooth", text: Bindable(app).engageQuery)
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
            .disabled(app.engageQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && app.selectedPipeline != .glassFabric)
        }
        .padding(.horizontal)
    }

    private var pipelinePicker: some View {
        Picker("Pipeline", selection: Bindable(app).selectedPipeline) {
            ForEach(PipelineKind.allCases) { kind in
                Text(kind.label).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .overlay(alignment: .bottom) {
            Text("detected: \(detected.label)")
                .font(FinchTheme.monoSmall)
                .foregroundStyle(FinchTheme.textSecondary)
                .offset(y: 18)
        }
        .padding(.bottom, 8)
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

    private func engage() {
        let kind = InputRouter.resolve(query: app.engageQuery, override: app.selectedPipeline)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
        }
    }

    private func syncReport() {
        if let r = app.glassPipeline.report {
            app.reportContainer.glassReport = r
            app.reportContainer.title = "Glass \(r.cidr)"
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
        app.reportContainer.bleSnapshot = app.bleScanner.sortedDevices
        persistTitle = app.reportContainer.title.isEmpty ? "Glass Fabric" : app.reportContainer.title
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
