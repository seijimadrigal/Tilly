import SwiftUI
import TillyCore
import TillyProviders
import TillyStorage
import TillyTools
import FirebaseCore
import GoogleSignIn

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FirebaseApp.configure()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            GIDSignIn.sharedInstance.handle(url)
        }
    }
}

@main
struct TillyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState: AppState?

    var body: some Scene {
        WindowGroup {
            Group {
                if let appState {
                    if appState.authService.isSignedIn {
                        ContentView()
                            .environment(appState)
                    } else {
                        SignInView()
                            .environment(appState)
                    }
                } else {
                    ProgressView("Loading...")
                        .onAppear {
                            // Firebase is configured by AppDelegate before this runs
                            appState = AppState()
                        }
                }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
        .commands {
            if let appState {
                AppCommands(appState: appState)
            }
        }

        #if os(macOS)
        Settings {
            if let appState {
                SettingsView()
                    .environment(appState)
            }
        }
        #endif
    }
}
