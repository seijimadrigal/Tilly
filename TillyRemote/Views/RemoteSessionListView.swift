import SwiftUI
import TillyCore

struct RemoteSessionListView: View {
    @Environment(RemoteClient.self) private var client

    var body: some View {
        List {
            if client.sessions.isEmpty {
                Text("No sessions yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(client.sessions) { session in
                    Button {
                        client.selectSession(id: session.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title)
                                .font(.body)
                                .lineLimit(1)
                            HStack {
                                Text("\(session.messageCount) messages")
                                Text("·")
                                Text(session.updatedAt, style: .relative)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .refreshable {
            client.send(RemoteMessage(type: .listSessions))
        }
    }
}
