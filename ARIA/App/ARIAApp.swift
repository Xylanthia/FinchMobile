import SwiftUI

@main
struct ARIAApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
        }
    }
}

/// App-wide state: the ARIA handheld coordinator only (no Finch modules).
@MainActor
@Observable
final class AppModel {
    @ObservationIgnored let aria = ARIACoordinator()
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            ARIADashboardView()
                .tabItem { Label("Overview", systemImage: "dot.radiowaves.left.and.right") }
            NavigationStack { ARIAFramesView() }
                .tabItem { Label("Frames", systemImage: "list.bullet.rectangle") }
            NavigationStack { ARIAControlsView() }
                .tabItem { Label("Controls", systemImage: "slider.horizontal.3") }
            NavigationStack { ARIASessionExportView() }
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }
        .tint(FinchTheme.cyan)
        .background(FinchTheme.background.ignoresSafeArea())
        .task { app.aria.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.aria.connection.retryPreflight()
                Task { await app.aria.refresh() }
            }
        }
    }
}

/// The handheld's own modes and actions, as it reports them.
struct ARIAControlsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            if app.aria.modes.isEmpty {
                Text(app.aria.connection.state.isConnected
                     ? "The handheld has not reported its control registry in the live snapshot yet."
                     : "Join ARIA-Setup Wi-Fi to load the handheld's controls.")
                    .font(FinchTheme.monoSmall).foregroundStyle(FinchTheme.textSecondary)
                    .listRowBackground(FinchTheme.surface)
            }
            ForEach(app.aria.modes) { mode in
                NavigationLink(mode.name) { ARIAModeActionsView(mode: mode) }
                    .listRowBackground(FinchTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FinchTheme.background)
        .navigationTitle("Controls")
    }
}
