import SwiftUI
import TillyCore
import UIKit

struct RemoteContentView: View {
    @Environment(AuthServiceIOS.self) private var authService
    @Environment(FirebaseRelayIOS.self) private var relay

    var body: some View {
        NavigationStack {
            Group {
                if !relay.sessions.isEmpty || relay.currentSession != nil {
                    if relay.currentSession != nil {
                        RemoteChatViewFirebase()
                    } else {
                        RemoteSessionListFirebase()
                    }
                } else {
                    RemoteMacStatusView()
                }
            }
            .navigationTitle("Tilly Remote")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if relay.currentSession != nil {
                        Button {
                            relay.currentSession = nil
                            relay.requestSessions()
                        } label: {
                            Label("Sessions", systemImage: "chevron.left")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New Chat") {
                            relay.createNewSession()
                        }
                        Button("Refresh") {
                            relay.requestSessions()
                        }

                        Divider()

                        Button("Sign Out", role: .destructive) {
                            relay.stop()
                            authService.signOut()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: Binding(
                get: { relay.showAskUser },
                set: { newValue in if !newValue { relay.showAskUser = false } }
            )) {
                RemoteAskUserFirebase()
                    .environment(relay)
            }
        }
    }
}

// MARK: - Session List (Firebase)

struct RemoteSessionListFirebase: View {
    @Environment(FirebaseRelayIOS.self) private var relay

    var body: some View {
        List {
            if relay.sessions.isEmpty {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("Loading sessions...").foregroundStyle(.secondary)
                }
            } else {
                ForEach(relay.sessions) { summary in
                    Button {
                        // Navigate immediately — create placeholder session
                        let placeholder = Session(
                            id: summary.id,
                            title: summary.title,
                            providerID: summary.providerID,
                            modelID: summary.modelID
                        )
                        relay.currentSession = relay.sessionCache[summary.id] ?? placeholder
                        // Request full data in background
                        relay.selectSession(id: summary.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(summary.title)
                                    .font(.body)
                                    .lineLimit(1)
                                HStack {
                                    Text("\(summary.messageCount) messages")
                                    Text("·")
                                    Text(summary.updatedAt, style: .relative)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .refreshable {
            relay.requestSessions()
        }
    }
}

// MARK: - Chat View (Firebase)

struct RemoteChatViewFirebase: View {
    @Environment(FirebaseRelayIOS.self) private var relay
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let session = relay.currentSession {
                            ForEach(session.messages) { message in
                                RemoteMessageRow(message: message)
                                    .id(message.id)
                            }
                        }

                        if relay.isStreaming && !relay.streamingText.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "sparkle")
                                    .font(.caption)
                                    .foregroundStyle(.purple)
                                    .padding(.top, 2)
                                Text(relay.streamingText)
                                    .font(.body)
                                    .textSelection(.enabled)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .id("streaming")
                        }

                        if relay.isStreaming {
                            HStack {
                                ProgressView().scaleEffect(0.8)
                                Text("Thinking...").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding()
                            .id("progress")
                        }
                    }
                }
                .onChange(of: relay.streamingText) {
                    withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                }
                .onChange(of: relay.currentSession?.messages.count) {
                    if let last = relay.currentSession?.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .lineLimit(1...5)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onSubmit { sendMessage() }

                Button { sendMessage() } label: {
                    Image(systemName: relay.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(relay.isStreaming ? .red : .blue)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !relay.isStreaming)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .navigationTitle(relay.currentSession?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isInputFocused = true }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        relay.sendMessage(text)
    }
}

// MARK: - Ask User (Firebase)

struct RemoteAskUserFirebase: View {
    @Environment(FirebaseRelayIOS.self) private var relay
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text(relay.askUserQuestion)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    ForEach(Array(relay.askUserOptions.enumerated()), id: \.offset) { index, option in
                        Button(action: {
                            let choice = option
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                relay.respondToAskUser(choice: choice)
                            }
                        }) {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill([Color.blue, .orange, .green][index % 3]))

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
}

// MARK: - Message Row

struct RemoteMessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                switch message.role {
                case .user:
                    Image(systemName: "person.circle.fill").foregroundStyle(.blue)
                case .assistant:
                    Image(systemName: "sparkle").foregroundStyle(.purple)
                case .tool:
                    Image(systemName: "wrench.and.screwdriver.fill").foregroundStyle(.orange)
                case .system:
                    Image(systemName: "gearshape.fill").foregroundStyle(.gray)
                }
            }
            .font(.caption)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == .user ? "You" : message.role == .assistant ? "Tilly" : message.role.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach(Array(message.content.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let text):
                        if !text.isEmpty {
                            Text(text)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    case .image(let data, _):
                        if let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 280, maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    case .fileReference(let file):
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill").foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(file.fileName).font(.caption).fontWeight(.medium)
                                Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    ForEach(toolCalls) { tc in
                        HStack(spacing: 6) {
                            Image(systemName: "terminal").font(.caption2).foregroundStyle(.orange)
                            Text(tc.function.name).font(.caption).fontWeight(.medium)
                        }
                        .padding(6)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(message.role == .assistant ? Color(.secondarySystemBackground).opacity(0.5) : .clear)
    }
}
