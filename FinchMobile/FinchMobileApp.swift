import SwiftUI
import SwiftData

@main
struct FinchMobileApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(appModel)
                .preferredColorScheme(.dark)
                .tint(FinchTheme.cyan)
        }
        .modelContainer(for: VaultItem.self)
    }
}
