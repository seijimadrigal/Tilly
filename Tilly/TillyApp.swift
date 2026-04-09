import SwiftUI
import TillyCore
import TillyProviders
import TillyStorage
import TillyTools
import FirebaseCore
import GoogleSignIn

/// Configure Firebase at static init time — before ANY Swift code touches Auth.
private let _firebaseConfigured: Bool = {
    FirebaseApp.configure()
    return true
}()

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
    @State private var appState: AppState

    init() {
        // Force Firebase to configure before AppState is created
        _ = _firebaseConfigured
        _appState = State(initialValue: AppState())
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
            .onChange(of: appState.authService.isSignedIn) {
                appState.onAuthStateChanged()
            }
            .onAppear {
                // Start relay if already signed in from previous session
                if appState.authService.isSignedIn {
                    appState.onAuthStateChanged()
                }
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
