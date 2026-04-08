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
                set: { _ in }
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)

                Text(client.askUserQuestion)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                ForEach(Array(client.askUserOptions.enumerated()), id: \.offset) { index, option in
                    Button {
                        client.respondToAskUser(choice: option)
                    } label: {
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(colorFor(index)))

                            Text(option)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .navigationTitle("Question")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        .presentationDetents([.medium])
    }

    private func colorFor(_ index: Int) -> Color {
        [Color.blue, .orange, .green][index % 3]
    }
}
