import SwiftUI
import GoogleSignInSwift

struct SignInView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo
            Image(systemName: "sparkle")
                .font(.system(size: 64))
                .foregroundStyle(.purple)

            Text("Tilly")
                .font(.largeTitle.bold())

            Text("Your AI agent harness for macOS")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            // Error
            if let error = appState.authService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            // Google Sign-In button
            Button {
                Task {
                    await appState.authService.signInWithGoogle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.title3)
                    Text("Sign in with Google")
                        .font(.body.weight(.medium))
                }
                .frame(maxWidth: 280)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Sign in to sync your sessions across devices")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom)
        }
        .frame(minWidth: 400, minHeight: 500)
    }
}
