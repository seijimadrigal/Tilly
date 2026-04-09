import SwiftUI
import TillyCore
import FirebaseCore
import GoogleSignIn

@main
struct TillyRemoteApp: App {
    @State private var authService = AuthServiceIOS()
    @State private var relay = FirebaseRelayIOS()

    init() {
        FirebaseApp.configure()
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
