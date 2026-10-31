import SwiftUI
import SwiftData

struct ARIASessionExportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VaultItem.createdAt, order: .reverse) private var vaultItems: [VaultItem]

    @State private var shareURL: URL?
    @State private var status: String?
    @State private var exporting = false
    @State private var confirmClear = false

    var body: some View {
        let session = app.aria.session
        let history = app.aria.history
        List {
            Section("Stored history (exported)") {
                ARIAHistoryBanner()
                ForEach(ARIALogSource.allCases) { source in
                    row("\(source.label) · total seen / live now",
                        "\(history.totalText(source)) / \(source == .rfid ? "—" : history.liveCount(source).formatted())")
                }
                if let error = app.aria.historyError ?? history.storeError {
                    Text(error).font(.caption2).foregroundStyle(FinchTheme.warn)
                }
            }
            .listRowBackground(FinchTheme.surface)

            Section("Live snapshot") {
                // Skipped-record count surfaced in UI, not just logs (§4).
                row("malformed records skipped", "\(session.malformedSkipped)")
                row("stream", app.aria.streamConnected ? "/api/stream connected" : "polling only (stream down)")
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

            Section("Collector GPS") {
                Text("Each observation includes the iPhone fix at first receipt of that record version, with accuracy and UTC timestamps. This is the collector position, not the target position or firmware capture time. Missing or stale GPS is marked unavailable.")
                    .font(.caption).foregroundStyle(FinchTheme.textSecondary)
            }
            Section("Export") {
                Button(exporting ? "Writing export…" : "Share full history JSON") { exportHistory(toVault: false) }
                    .disabled(exporting || !history.loaded)
                Button("Save full history to Vault") { exportHistory(toVault: true) }
                    .disabled(exporting || !history.loaded || !app.vaultManager.isUnlocked)
                Button("Share live snapshot only") { exportShare(app.aria.exportData) }
                    .disabled(app.aria.exportData.isEmpty)
                Text("Full history = every device and capture stored on this phone, in range or not, streamed to disk with no size cap. Its summary block reports exported counts (= array lengths) separately from live-at-export counts.")
                    .font(.caption2).foregroundStyle(FinchTheme.textSecondary)
                if !app.vaultManager.isUnlocked {
                    Text("Unlock the Vault in Settings to persist sessions (AES-256-GCM, opt-in).")
                        .font(.caption2).foregroundStyle(FinchTheme.textSecondary)
                }
                if let status { Text(status).font(.caption2).foregroundStyle(FinchTheme.cyan) }
                Button("Clear stored history on this phone", role: .destructive) { confirmClear = true }
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
        .confirmationDialog("Delete every stored ARIA record on this phone? The handheld's own log is not touched and will be backfilled again on the next connect.",
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) {
                Task {
                    await app.aria.history.clearLocal()
                    app.aria.requestBackfill()
                }
            }
        }
    }

    private func exportHistory(toVault: Bool) {
        exporting = true
        Task {
            defer { exporting = false }
            do {
                let (url, counts) = try await app.aria.exportHistory()
                let summary = ARIALogSource.allCases.map { "\($0.label) \(counts[$0] ?? 0)" }.joined(separator: " · ")
                if toVault {
                    saveToVault(try Data(contentsOf: url, options: .alwaysMapped))   // sets its own status
                } else {
                    shareURL = url
                    status = "exported \(summary)"
                }
            } catch {
                status = "export failed: \(error.localizedDescription)"
            }
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
