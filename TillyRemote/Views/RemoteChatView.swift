import SwiftUI
import TillyCore

struct RemoteChatView: View {
    @Environment(RemoteClient.self) private var client
    @State private var inputText = ""
    @State private var showImagePicker = false
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

                        // Streaming text
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
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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

            // Input bar
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
                    if client.isStreaming {
                        // Stop not implemented on remote yet
                    } else {
                        sendMessage()
                    }
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

// MARK: - Message Row (with rich content)

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
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundStyle(.orange)
                case .system:
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.gray)
                }
            }
            .font(.caption)
            .padding(.top, 2)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(roleName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Render all content blocks
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
                        RemoteFileReferenceView(file: file)
                    }
                }

                // Tool calls
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    ForEach(toolCalls) { toolCall in
                        RemoteToolCallView(toolCall: toolCall)
                    }
                }

                // Metadata
                if let meta = message.metadata, let model = meta.model {
                    Text(model)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(message.role == .assistant ? Color(.secondarySystemBackground).opacity(0.5) : .clear)
    }

    private var roleName: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "Tilly"
        case .tool: return "Tool Result"
        case .system: return "System"
        }
    }
}

// MARK: - File Reference View (iOS)

struct RemoteFileReferenceView: View {
    let file: FileAttachment

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForMimeType(file.mimeType))
                .foregroundStyle(.blue)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.fileName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func iconForMimeType(_ mime: String) -> String {
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("video/") { return "film" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime.contains("pdf") { return "doc.richtext" }
        return "doc"
    }
}

// MARK: - Tool Call View (iOS)

struct RemoteToolCallView: View {
    let toolCall: ToolCall
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: toolIcon)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(toolDisplayName)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(argsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.borderless)

            if isExpanded {
                Text(prettyArgs)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.2), lineWidth: 1))
    }

    private var toolIcon: String {
        switch toolCall.function.name {
        case "execute_command": return "terminal"
        case "open_application": return "macwindow"
        case "read_file": return "doc.text"
        case "write_file": return "square.and.pencil"
        case "list_directory": return "folder"
        case "web_fetch": return "globe"
        case "memory_store": return "brain"
        case "skill_run": return "sparkles"
        case "ask_user": return "questionmark.circle"
        default: return "wrench"
        }
    }

    private var toolDisplayName: String {
        switch toolCall.function.name {
        case "execute_command": return "Shell"
        case "open_application": return "Open App"
        case "read_file": return "Read File"
        case "write_file": return "Write File"
        case "list_directory": return "List Dir"
        case "web_fetch": return "Web Fetch"
        default: return toolCall.function.name
        }
    }

    private var argsSummary: String {
        guard let data = toolCall.function.arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if let cmd = json["command"] as? String { return "$ \(cmd.prefix(40))" }
        if let target = json["target"] as? String { return target }
        if let path = json["path"] as? String { return path }
        return ""
    }

    private var prettyArgs: String {
        guard let data = toolCall.function.arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let str = String(data: pretty, encoding: .utf8) else { return toolCall.function.arguments }
        return str
    }
}
