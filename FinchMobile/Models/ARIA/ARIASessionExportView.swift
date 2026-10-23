import SwiftUI
import SwiftData

struct ARIASessionExportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VaultItem.createdAt, order: .reverse) private var vaultItems: [VaultItem]

    @State private var shareURL: URL?
    @State private var status: String?

    var body: some View {
        let session = app.aria.session
        List {
            Section("This session") {
                // Skipped-record count surfaced in UI, not just logs (§4).
                row("malformed records skipped", "\(session.malformedSkipped)")
                row("Wi-Fi / BLE / Sub-GHz", "\(session.wifi.count) / \(session.ble.count) / \(session.subghz.count)")
                row("UAS / RFID", "\(session.uas.count) / \(session.rfid.count)")
                if session.malformedSkipped > 0 {
                    Text("Partial session: \(session.malformedSkipped) record(s) were corrupt and skipped. Fields were not repaired.")
                        .font(.caption2).foregroundStyle(FinchTheme.warn)
                }
            }
            .listRowBackground(FinchTheme.surface)

            Section("Diagnostics") {
                row("heap free", app.aria.summary?.heapFree.map(String.init) ?? "—")
                row("queue drops", app.aria.summary?.queueDrops.map(String.init) ?? "—")
            }
            .listRowBackground(FinchTheme.surface)

            Section("Export") {
                Button("Share current session JSON") { exportShare(session.raw) }
                    .disabled(session.raw.isEmpty)
                Button("Save to Vault") { saveToVault(session.raw) }
                    .disabled(session.raw.isEmpty || !app.vaultManager.isUnlocked)
                if !app.vaultManager.isUnlocked {
                    Text("Unlock the Vault in Settings to persist sessions (AES-256-GCM, opt-in).")
                        .font(.caption2).foregroundStyle(FinchTheme.textSecondary)
                }
                if let status { Text(status).font(.caption2).foregroundStyle(FinchTheme.cyan) }
            }
            .listRowBackground(FinchTheme.surface)

            if !vaultItems.isEmpty {
                Section("Saved sessions") {
                    ForEach(vaultItems) { item in
                        VStack(alignment: .leading) {
                            Text(item.title).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textPrimary)
                            Text(item.createdAt.formatted()).font(.caption2).foregroundStyle(FinchTheme.textSecondary)
                        }
                    }
                }
                .listRowBackground(FinchTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FinchTheme.background)
        .navigationTitle("Session / Export")
        .sheet(item: Binding(get: { shareURL.map { ShareItem(url: $0) } }, set: { shareURL = $0?.url })) { item in
            ShareSheet(items: [item.url])
        }
    }

    private func exportShare(_ data: Data) {
        let name = "aria-session-\(ISO8601DateFormatter().string(from: Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url); shareURL = url }
        catch { status = "share failed: \(error.localizedDescription)" }
    }

    private func saveToVault(_ data: Data) {
        do {
            try app.vaultManager.persist(
                reportJSON: data,
                title: "ARIA session \(Date().formatted(date: .abbreviated, time: .shortened))",
                context: modelContext
            )
            status = "saved to Vault"
        } catch {
            status = "vault save failed: \(error.localizedDescription)"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(FinchTheme.textSecondary)
            Spacer()
            Text(value).font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textPrimary)
        }
    }
}

private struct ShareItem: Identifiable { let url: URL; var id: String { url.absoluteString } }

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
