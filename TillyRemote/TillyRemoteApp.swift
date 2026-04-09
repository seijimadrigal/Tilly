import SwiftUI
import TillyCore
import FirebaseCore
import GoogleSignIn

/// Configure Firebase at static init time — before ANY Swift code touches Auth.
private let _firebaseConfigured: Bool = {
    FirebaseApp.configure()
    return true
}()

class RemoteAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}

@main
struct TillyRemoteApp: App {
    @UIApplicationDelegateAdaptor(RemoteAppDelegate.self) var appDelegate
    @State private var authService: AuthServiceIOS
    @State private var relay: FirebaseRelayIOS

    init() {
        _ = _firebaseConfigured
        _authService = State(initialValue: AuthServiceIOS())
        _relay = State(initialValue: FirebaseRelayIOS())
    }

    var body: some Scene {
        WindowGroup {
            Group {
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
            }
            .onAppear {
                authService.restoreSession()
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
