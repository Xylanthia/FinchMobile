import SwiftUI
import UIKit

struct ForensicReplayView: View {
    @Environment(AppModel.self) private var app
    @State private var sharePayload: SharePayload?

    var body: some View {
        NavigationStack {
            ZStack {
                FinchTheme.background.ignoresSafeArea()
                List {
                    Section("Chain tip") {
                        Text(app.forensic.tipHash)
                            .font(FinchTheme.monoSmall)
                            .foregroundStyle(FinchTheme.cyan)
                            .textSelection(.enabled)
                        Text("\(app.forensic.events.count) events · research=\(app.forensic.researchMode ? "ON" : "OFF")")
                            .font(FinchTheme.monoSmall)
                    }
                    Section("Timeline") {
                        ForEach(app.forensic.events) { e in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(e.category) · \(e.summary)")
                                    .font(FinchTheme.monoSmall)
                                Text(e.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(.secondary)
                                Text(String(e.hash.prefix(16)) + "…")
                                    .font(FinchTheme.monoSmall)
                                    .foregroundStyle(.secondary)
                            }
                            .listRowBackground(FinchTheme.background)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("FORENSIC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export") { export() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { app.forensic.clear() }
                }
            }
            .sheet(item: $sharePayload) { payload in
                ActivityView(items: [payload.url])
            }
        }
    }

    private func export() {
        do {
            let data = try app.forensic.exportChainJSON()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("finch-forensic-\(Int(Date().timeIntervalSince1970)).json")
            try data.write(to: url)
            sharePayload = SharePayload(url: url)
            app.forensic.record(category: "forensic", summary: "Exported chain JSON")
        } catch {
            app.forensic.record(category: "forensic", summary: "Export failed", detail: error.localizedDescription)
        }
    }
}

struct SharePayload: Identifiable {
    var id: String { url.absoluteString }
    var url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
