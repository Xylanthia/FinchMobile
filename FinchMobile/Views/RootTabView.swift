import SwiftUI

struct RootTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            EngageView()
                .tabItem { Label("Engage", systemImage: "dot.radiowaves.left.and.right") }

            BLERadarView()
                .tabItem { Label("BLE Radar", systemImage: "antenna.radiowaves.left.and.right") }

            VaultView()
                .tabItem { Label("Vault", systemImage: "lock.square.stack") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .background(FinchTheme.background.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                app.vaultManager.wipeKeyOnBackground()
            }
        }
        .onAppear {
            app.bleScanner.continuousMode = app.settings.continuousBLEDefault
        }
    }
}
