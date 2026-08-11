import SwiftUI

struct RootTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            EngageView()
                .tabItem { Label("Engage", systemImage: "dot.radiowaves.left.and.right") }

            BLERadarView()
                .tabItem { Label("Nearby", systemImage: "antenna.radiowaves.left.and.right") }

            TracksView()
                .tabItem { Label("Tracks", systemImage: "point.3.connected.trianglepath.dotted") }

            DronePanelView()
                .tabItem { Label("Drone", systemImage: "airplane") }

            CommandHubView()
                .tabItem { Label("Command", systemImage: "square.grid.2x2") }
        }
        .background(FinchTheme.background.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                app.vaultManager.wipeKeyOnBackground()
            }
            if phase == .active {
                app.refreshFusion()
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
