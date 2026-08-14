import SwiftUI

struct CommandHubView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            List {
                Section("Working") {
                    NavigationLink("Live Map") { LiveProximityMapView() }
                    NavigationLink("Vault") { VaultView() }
                    NavigationLink("Settings") { SettingsView() }
                    NavigationLink("Forensic log") { ForensicReplayView() }
                }
                Section("Mesh (Multipeer on this LAN)") {
                    Toggle("Advertise + browse", isOn: Binding(
                        get: { app.mesh.isAdvertising },
                        set: { on in
                            if on { app.mesh.start() } else { app.mesh.stop() }
                        }
                    ))
                    .tint(FinchTheme.cyan)
                    Button("Broadcast track summaries") {
                        app.refreshFusion()
                        app.mesh.broadcastTracks(app.fusion.sortedTracks)
                    }
                    Text("Peers: \(app.mesh.peers.count)")
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(FinchTheme.background)
            .navigationTitle("COMMAND")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
