import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Query private var vaultItems: [VaultItem]
    @State private var passphrase = ""
    @State private var confirmClear = false
    @State private var status = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("BLE") {
                    Toggle("Continuous scan by default", isOn: Bindable(app.settings).continuousBLEDefault)
                        .tint(FinchTheme.cyan)
                }

                Section("Finch backend (same results as web app)") {
                    TextField("Backend URL", text: Bindable(app.settings).finchBackendURL)
                        .font(FinchTheme.mono)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Text("On your PC: python -m backend serve --host 0.0.0.0 --port 8765")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(.secondary)
                    Text("Phone and PC on same Wi‑Fi. Enter http://YOUR_PC_IP:8765 (no trailing slash). Engage then uses the same Python rails as the web app.")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    Text("Finch Mobile 3.1")
                        .font(FinchTheme.mono)
                    Text("With a Finch backend URL set, OSINT searches use the same desktop Python engine as the web app. Without it: on-device public rails only (identity, address, plate, cyber, web3). Also: BLE scan, GATT read, LAN Glass, MQTT listen.")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(.secondary)
                    Text("Schema: finch.osint.v1 + finch.ble.survey.v2 + finch.sentinel.glass.v1")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(.secondary)
                }

                Section("Vault") {
                    if app.vaultManager.hasPassphrase() {
                        Text("Passphrase on file (Keychain)")
                            .font(FinchTheme.monoSmall)
                    }
                    SecureField("Set / rotate passphrase", text: $passphrase)
                        .font(FinchTheme.mono)
                    Button("Save Passphrase") {
                        guard !passphrase.isEmpty else { return }
                        app.vaultManager.setPassphrase(passphrase)
                        passphrase = ""
                        status = "Passphrase saved"
                    }
                    Button("Clear Vault", role: .destructive) {
                        confirmClear = true
                    }
                }

                Section("MQTT defaults") {
                    TextField("Username", text: Bindable(app.settings).mqttUsername)
                        .font(FinchTheme.mono)
                    SecureField("Password", text: Bindable(app.settings).mqttPassword)
                        .font(FinchTheme.mono)
                }

                Section("OSINT API keys (optional)") {
                    SecureField("Have I Been Pwned", text: Bindable(app.settings).hibpApiKey)
                        .font(FinchTheme.mono)
                    SecureField("Etherscan", text: Bindable(app.settings).etherscanApiKey)
                        .font(FinchTheme.mono)
                    SecureField("Shodan", text: Bindable(app.settings).shodanApiKey)
                        .font(FinchTheme.mono)
                    Text("Public rails run without keys. These only unlock HIBP, Etherscan txs, and Shodan host.")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(.secondary)
                }

                Section("Fingerprints") {
                    Text("Bundled rules: \(FingerprintEngine.shared.rules.count)")
                        .font(FinchTheme.monoSmall)
                    TextField("Update URL (optional)", text: Bindable(app.settings).fingerprintUpdateURL)
                        .font(FinchTheme.monoSmall)
                        .textInputAutocapitalization(.never)
                    Button("Reload bundled fingerprints") {
                        FingerprintEngine.shared.loadBundled()
                        status = "Loaded \(FingerprintEngine.shared.rules.count) rules"
                    }
                }

                if !status.isEmpty {
                    Section {
                        Text(status)
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(FinchTheme.cyan)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(FinchTheme.background)
            .navigationTitle("SETTINGS")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete all vault items?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear Vault", role: .destructive) {
                    try? app.vaultManager.clearAll(context: modelContext, items: vaultItems)
                    status = "Vault cleared"
                }
            }
        }
    }
}
