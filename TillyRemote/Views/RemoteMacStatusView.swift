import SwiftUI
import TillyCore

struct RemoteMacStatusView: View {
    @Environment(FirebaseRelayIOS.self) private var relay

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if relay.macOnline {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text("Your Mac is online")
                    .font(.headline)

                Text("Tilly is running and ready")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if relay.sessions.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Loading sessions...")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 20)
                }
            } else {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 48))
                    .foregroundStyle(.gray)

                Text("Your Mac is offline")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Make sure Tilly is running on your Mac and you're signed in with the same Google account.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .padding()
    }
}
