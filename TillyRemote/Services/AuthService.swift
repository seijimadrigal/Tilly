import Foundation
import SwiftUI
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

@MainActor
@Observable
final class AuthServiceIOS {
    var isSignedIn: Bool = false
    var userID: String?
    var userEmail: String?
    var userName: String?
    var userPhotoURL: URL?
    var errorMessage: String?

    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.updateUser(user)
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func restoreSession() {
        if let user = Auth.auth().currentUser {
            updateUser(user)
        }
    }

    func signInWithGoogle(presenting viewController: UIViewController) async {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Firebase not configured"
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
            let user = result.user
            guard let idToken = user.idToken?.tokenString else {
                errorMessage = "Failed to get Google ID token"
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )

            let authResult = try await Auth.auth().signIn(with: credential)
            updateUser(authResult.user)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            isSignedIn = false
            userID = nil
            userEmail = nil
            userName = nil
            userPhotoURL = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateUser(_ user: User?) {
        if let user {
            isSignedIn = true
            userID = user.uid
            userEmail = user.email
            userName = user.displayName
            userPhotoURL = user.photoURL
        } else {
            isSignedIn = false
            userID = nil
        }
    }
}
