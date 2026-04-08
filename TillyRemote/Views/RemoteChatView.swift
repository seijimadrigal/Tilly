import SwiftUI
import TillyCore

struct RemoteChatView: View {
    @Environment(RemoteClient.self) private var client
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let session = client.currentSession {
                            ForEach(session.messages) { message in
                                RemoteMessageRow(message: message)
                                    .id(message.id)
                            }
                        }

                        // Streaming indicator
                        if client.isStreaming && !client.streamingText.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "sparkle")
                                    .font(.caption)
                                    .foregroundStyle(.purple)
                                    .padding(.top, 2)
                                Text(client.streamingText)
                                    .font(.body)
                                    .textSelection(.enabled)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .id("streaming")
                        }

                        if client.isStreaming {
                            ProgressView()
                                .padding()
                                .id("progress")
                        }
                    }
                }
                .onChange(of: client.streamingText) {
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
                .onChange(of: client.currentSession?.messages.count) {
                    if let last = client.currentSession?.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .lineLimit(1...5)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onSubmit {
                        sendMessage()
                    }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: client.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(client.isStreaming ? .red : .blue)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !client.isStreaming)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .navigationTitle(client.currentSession?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isInputFocused = true }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        client.sendMessage(text)
    }
}

// MARK: - Message Row

struct RemoteMessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Icon
            Group {
                switch message.role {
                case .user:
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.blue)
                case .assistant:
                    Image(systemName: "sparkle")
                        .foregroundStyle(.purple)
                case .tool:
                    Image(systemName: "wrench.fill")
                        .foregroundStyle(.orange)
                case .system:
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.gray)
                }
            }
            .font(.caption)
            .padding(.top, 2)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(message.role == .user ? "You" : message.role == .assistant ? "Tilly" : message.role.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(message.textContent)
                    .font(.body)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(message.role == .assistant ? Color(.secondarySystemBackground).opacity(0.5) : .clear)
    }
}
