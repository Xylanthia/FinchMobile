import SwiftUI

/// Overflow hub so primary tabs stay ≤5.
struct CommandHubView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            List {
                Section("Situational") {
                    NavigationLink("Live Map") { LiveProximityMapView() }
                    NavigationLink("AR Overlay") { AROverlayView() }
                    NavigationLink("Consent / Arm") { ConsentView() }
                    NavigationLink("Forensic chain") { ForensicReplayView() }
                }
                Section("Platform") {
                    NavigationLink("Vault") { VaultView() }
                    NavigationLink("Settings") { SettingsView() }
                }
                Section("Mesh") {
                    Toggle("Advertise + browse mesh", isOn: Binding(
                        get: { app.mesh.isAdvertising },
                        set: { on in
                            if on { app.mesh.start() } else { app.mesh.stop() }
                        }
                    ))
                    .tint(FinchTheme.cyan)
                    Button("Broadcast tracks") {
                        app.refreshFusion()
                        app.mesh.broadcastTracks(app.fusion.sortedTracks)
                    }
                    Text(app.mesh.lastMessage.isEmpty ? "Peers: \(app.mesh.peers.count)" : app.mesh.lastMessage)
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(.secondary)
                    if !app.mesh.peers.isEmpty {
                        Text(app.mesh.peers.joined(separator: ", "))
                            .font(FinchTheme.monoSmall)
                    }
                }
                Section("Research Mode") {
                    Toggle("Research Mode (synthetic sensors)", isOn: Binding(
                        get: { app.settings.researchMode },
                        set: { on in
                            app.settings.researchMode = on
                            app.sensors.applyResearchMode(on)
                        }
                    ))
                    .tint(FinchTheme.cyan)
                    Button("Inject Flipper") {
                        _ = app.fusion.injectSynthetic(name: "LAB-FLIPPER", deviceClass: .flipper, threatBoost: 2)
                        app.drone.refresh(from: app.fusion.sortedTracks)
                    }
                    Button("Inject Drone") {
                        _ = app.fusion.injectSynthetic(name: "LAB-DRONE", deviceClass: .drone, threatBoost: 2)
                        app.drone.refresh(from: app.fusion.sortedTracks)
                    }
                    Text(app.sensors.lastClassification)
                        .font(FinchTheme.monoSmall)
                        .foregroundStyle(.secondary)
                }
                Section("Playbooks") {
                    Text(app.playbooks.statusText)
                        .font(FinchTheme.monoSmall)
                    ForEach(app.playbooks.lastFires, id: \.self) { fire in
                        Text(fire).font(FinchTheme.monoSmall)
                    }
                    Button("Re-evaluate") {
                        app.refreshFusion()
                        app.playbooks.evaluate(tracks: app.fusion.sortedTracks)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(FinchTheme.background)
            .navigationTitle("COMMAND")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
