import SwiftUI
import TillyCore
import FirebaseCore
import GoogleSignIn

class RemoteAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}

@main
struct TillyRemoteApp: App {
    @UIApplicationDelegateAdaptor(RemoteAppDelegate.self) var appDelegate
    @State private var authService: AuthServiceIOS?
    @State private var relay: FirebaseRelayIOS?

    var body: some Scene {
        WindowGroup {
            Group {
                if let authService, let relay {
                    if authService.isSignedIn {
                        RemoteContentView()
                            .environment(authService)
                            .environment(relay)
                            .onAppear {
                                if let uid = authService.userID {
                                    relay.start(userID: uid)
                                }
                            }
                    } else {
                        SignInViewIOS()
                            .environment(authService)
                    }
                } else {
                    ProgressView("Loading...")
                        .onAppear {
                            // Firebase is configured by AppDelegate before this runs
                            authService = AuthServiceIOS()
                            relay = FirebaseRelayIOS()
                            authService?.restoreSession()
                        }
                }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
