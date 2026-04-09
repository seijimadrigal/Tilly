import SwiftUI
import GoogleSignInSwift

struct SignInViewIOS: View {
    @Environment(AuthServiceIOS.self) private var authService

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkle")
                .font(.system(size: 72))
                .foregroundStyle(.purple)

            Text("Tilly Remote")
                .font(.largeTitle.bold())

            Text("Control your Mac AI agent from anywhere")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            if let error = authService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Button {
                Task {
                    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                          let rootVC = scene.windows.first?.rootViewController else { return }
                    await authService.signInWithGoogle(presenting: rootVC)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.title3)
                    Text("Sign in with Google")
                        .font(.body.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 40)

            Spacer()

            Text("Sign in with the same Google account on your Mac and iPhone")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom)
        }
    }
}
