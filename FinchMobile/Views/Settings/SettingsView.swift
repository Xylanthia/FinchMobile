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

                Section("About") {
                    Text("Finch Mobile · Glass Fabric")
                        .font(FinchTheme.mono)
                    Text("On-device BLE + IoT red team only. No backend. Authorized use only.")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(.secondary)
                    Text("Schema: finch.sentinel.glass.v1")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(FinchTheme.cyan)
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
