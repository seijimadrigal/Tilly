import SwiftUI
import TillyCore

struct RemoteContentView: View {
    @Environment(RemoteClient.self) private var client

    var body: some View {
        NavigationStack {
            Group {
                switch client.state {
                case .disconnected, .browsing:
                    RemoteConnectionView()
                case .connecting:
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Connecting...")
                            .foregroundStyle(.secondary)
                    }
                case .connected:
                    if client.currentSession != nil {
                        RemoteChatView()
                    } else {
                        RemoteSessionListView()
                    }
                }
            }
            .navigationTitle("Tilly Remote")
            .toolbar {
                if client.state == .connected {
                    ToolbarItem(placement: .topBarLeading) {
                        if client.currentSession != nil {
                            Button {
                                client.currentSession = nil
                                client.send(RemoteMessage(type: .listSessions))
                            } label: {
                                Label("Sessions", systemImage: "chevron.left")
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("New Chat") {
                                client.createNewSession()
                            }
                            Button("Disconnect", role: .destructive) {
                                client.disconnect()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { client.showAskUser },
                set: { newValue in
                    if !newValue { client.showAskUser = false }
                }
            )) {
                RemoteAskUserView()
                    .environment(client)
            }
        }
    }
}

// MARK: - Ask User Relay View

struct RemoteAskUserView: View {
    @Environment(RemoteClient.self) private var client
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text(client.askUserQuestion)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    ForEach(Array(client.askUserOptions.enumerated()), id: \.offset) { index, option in
                        Button(action: {
                            let choice = option
                            dismiss()
                            // Small delay to ensure sheet dismisses before sending
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                client.respondToAskUser(choice: choice)
                            }
                        }) {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(colorFor(index)))

                                Text(option)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Tilly needs input")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func colorFor(_ index: Int) -> Color {
        [Color.blue, .orange, .green][index % 3]
    }
}
