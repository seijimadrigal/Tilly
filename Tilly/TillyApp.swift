import SwiftUI
import TillyCore
import TillyProviders
import TillyStorage

@main
struct TillyApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .commands {
            AppCommands(appState: appState)
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appState)
        }
        #endif
    }
}
