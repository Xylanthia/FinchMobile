import SwiftUI

struct ARIASessionExportView: View {
    @Environment(AppModel.self) private var app

    @State private var shareURL: URL?
    @State private var status: String?
    @State private var exporting = false

    var body: some View {
        let session = app.aria.session
        let history = app.aria.history
        List {
            Section("Current boot session") {
                ARIAHistoryBanner()
                ForEach(ARIALogSource.allCases) { source in
                    row(source.label, history.totalText(source))
                }
                if let error = app.aria.historyError ?? history.storeError {
                    Text(error).font(.caption2).foregroundStyle(FinchTheme.warn)
                }
            }
            .listRowBackground(FinchTheme.surface)

            Section("Capture status") {
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

            Section("Export") {
                Button(exporting ? "Collecting boot session…" : "Share current session JSON") { exportSession() }
                    .disabled(exporting || !app.aria.connection.state.isConnected)
                Text("Includes available captures from handheld boot through export, including captures before the app connected. Previous boots are excluded. Nothing is saved on this phone unless you export.")
                    .font(.caption2).foregroundStyle(FinchTheme.textSecondary)
                if let status { Text(status).font(.caption2).foregroundStyle(FinchTheme.cyan) }

            }
            .listRowBackground(FinchTheme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(FinchTheme.background)
        .navigationTitle("Session / Export")
        .sheet(item: Binding(get: { shareURL.map { ShareItem(url: $0) } }, set: { shareURL = $0?.url })) { item in
            ShareSheet(items: [item.url])
        }
    }

    private func exportSession() {
        exporting = true
        Task {
            defer { exporting = false }
            do {
                let (url, counts) = try await app.aria.exportSession()
                let summary = ARIALogSource.allCases.map { "\($0.label) \(counts[$0] ?? 0)" }.joined(separator: " · ")
                shareURL = url
                status = "exported \(summary)"
            } catch {
                status = "export failed: \(error.localizedDescription)"
            }
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
