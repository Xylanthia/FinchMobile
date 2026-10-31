import SwiftUI

struct RootTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            // Finch pipeline (THE MACHINE: OSINT + Glass Fabric + BLE), as in 3.2.
            EngageView()
                .tabItem { Label("Engage", systemImage: "bolt.fill") }

            ARIADashboardView()
                .tabItem { Label("ARIA", systemImage: "dot.radiowaves.left.and.right") }

            BLERadarView()
                .tabItem { Label("Nearby", systemImage: "antenna.radiowaves.left.and.right") }

            TracksView()
                .tabItem { Label("Tracks", systemImage: "point.3.connected.trianglepath.dotted") }

            CommandHubView()
                .tabItem { Label("More", systemImage: "ellipsis") }
        }
        .background(FinchTheme.background.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                app.vaultManager.wipeKeyOnBackground()
            }
            if phase == .active {
                app.refreshFusion()
                app.aria.connection.retryPreflight()
                Task { await app.aria.refresh() }
            }
        }
        .onAppear {
            app.bleScanner.continuousMode = app.settings.continuousBLEDefault
        }
        .onChange(of: app.bleScanner.devices.count) { _, _ in
            app.refreshFusion()
        }
    }
}
