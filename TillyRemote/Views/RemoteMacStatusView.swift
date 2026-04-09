import SwiftUI
import TillyCore

struct RemoteMacStatusView: View {
    @Environment(FirebaseRelayIOS.self) private var relay

    var body: some View {
        VStack(spacing: 20) {
            if relay.macOnline {
                // Mac is online — show go to sessions
                VStack(spacing: 16) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)

                    Text("Your Mac is online")
                        .font(.headline)

                    Text("Tilly is running and ready")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        relay.requestSessions()
                    } label: {
                        Text("View Sessions")
                            .font(.body.weight(.medium))
                            .frame(maxWidth: 200)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            } else {
                // Mac is offline
                VStack(spacing: 16) {
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
            }
        }
        .padding()
        .onAppear {
            relay.requestSessions()
        }
    }
}
