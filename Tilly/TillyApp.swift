import SwiftUI
import TillyCore
import TillyProviders
import TillyStorage
import TillyTools
import FirebaseCore
import GoogleSignIn

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            GIDSignIn.sharedInstance.handle(url)
        }
    }
}

@main
struct TillyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.authService.isSignedIn {
                    ContentView()
                        .environment(appState)
                } else {
                    SignInView()
                        .environment(appState)
                }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
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
