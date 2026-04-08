import SwiftUI
import TillyCore

struct MessageView: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            avatar
                .frame(width: 28, height: 28)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Role label
                Text(roleLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                // Message content
                if !message.textContent.isEmpty {
                    if message.role == .tool {
                        ToolResultContentView(text: message.textContent)
                    } else {
                        MessageContentView(content: message.content)
                    }
                }

                // Tool calls made by this assistant message
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    ForEach(toolCalls) { toolCall in
                        ToolCallView(toolCall: toolCall)
                    }
                }

                // Metadata
                if let metadata = message.metadata {
                    MetadataView(metadata: metadata)
                }
            }

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(backgroundColor)
    }

    @ViewBuilder
    private var avatar: some View {
        switch message.role {
        case .user:
            Image(systemName: "person.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)
        case .assistant:
            Image(systemName: "sparkle")
                .font(.title3)
                .foregroundStyle(.purple)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.purple.opacity(0.15)))
        case .system:
            Image(systemName: "gearshape.fill")
                .font(.title3)
                .foregroundStyle(.gray)
        case .tool:
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.orange))
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "Assistant"
        case .system: return "System"
        case .tool:
            if let toolCallID = message.toolCallID {
                return "Tool Result [\(toolCallID.prefix(8))...]"
            }
            return "Tool Result"
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: return Color.clear
        case .assistant: return Color(.controlBackgroundColor).opacity(0.5)
        case .system: return Color.yellow.opacity(0.05)
        case .tool: return Color.orange.opacity(0.05)
        }
    }
}

// MARK: - Tool Call View

struct ToolCallView: View {
    let toolCall: ToolCall
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: iconForTool(toolCall.function.name))
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Text(displayNameForTool(toolCall.function.name))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text(argumentsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            // Expanded arguments
            if isExpanded {
                Text(prettyArguments)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }

    private var argumentsSummary: String {
        // Parse arguments JSON and show a brief summary
        guard let data = toolCall.function.arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }

        if let command = json["command"] as? String {
            return "$ \(command.prefix(60))"
        }
        if let target = json["target"] as? String {
            return target
        }
        if let path = json["path"] as? String {
            return path
        }
        if let url = json["url"] as? String {
            return url.prefix(60).description
        }
        return ""
    }

    private var prettyArguments: String {
        guard let data = toolCall.function.arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let str = String(data: pretty, encoding: .utf8) else {
            return toolCall.function.arguments
        }
        return str
    }

    private func iconForTool(_ name: String) -> String {
        switch name {
        case "execute_command": return "terminal"
        case "open_application": return "macwindow"
        case "read_file": return "doc.text"
        case "write_file": return "square.and.pencil"
        case "list_directory": return "folder"
        case "web_fetch": return "globe"
        default: return "wrench"
        }
    }

    private func displayNameForTool(_ name: String) -> String {
        switch name {
        case "execute_command": return "Shell"
        case "open_application": return "Open App"
        case "read_file": return "Read File"
        case "write_file": return "Write File"
        case "list_directory": return "List Dir"
        case "web_fetch": return "Web Fetch"
        default: return name
        }
    }
}

// MARK: - Tool Result Content View

struct ToolResultContentView: View {
    let text: String
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text("Output (\(text.count) chars)")
                        .font(.caption)
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(nil)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(Color(.textBackgroundColor).opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

// MARK: - Metadata View

struct MetadataView: View {
    let metadata: MessageMetadata

    var body: some View {
        HStack(spacing: 8) {
            if let model = metadata.model {
                Label(model, systemImage: "cpu")
            }

            if let tokens = metadata.totalTokens {
                Label("\(tokens) tokens", systemImage: "number")
            }

            if let latency = metadata.latencyMs {
                Label(formatLatency(latency), systemImage: "clock")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.top, 4)
    }

    private func formatLatency(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else {
            return String(format: "%.1fs", Double(ms) / 1000.0)
        }
    }
}
