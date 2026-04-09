import SwiftUI
import TillyCore

// MARK: - Message View (ChatGPT-style)

struct MessageView: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Avatar
            avatar

            // Content column
            VStack(alignment: .leading, spacing: 6) {
                // Role label
                Text(roleLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(roleColor)

                // Tool calls (inline, collapsed by default) — shown BEFORE text
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    ForEach(toolCalls) { toolCall in
                        InlineToolCallView(toolCall: toolCall)
                    }
                }

                // Main content
                if message.role == .tool {
                    InlineToolResultView(text: message.textContent)
                } else if !message.textContent.isEmpty {
                    MessageContentView(content: message.content)
                }

                // Metadata (subtle, bottom)
                if let metadata = message.metadata {
                    MetadataBar(metadata: metadata)
                }
            }
            .frame(maxWidth: 680, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(backgroundColor)
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatar: some View {
        Group {
            switch message.role {
            case .user:
                Circle()
                    .fill(.blue.gradient)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    )
            case .assistant:
                Circle()
                    .fill(.purple.gradient)
                    .overlay(
                        Image(systemName: "sparkle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    )
            case .system:
                Circle()
                    .fill(.gray.gradient)
                    .overlay(
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                    )
            case .tool:
                Circle()
                    .fill(.orange.gradient)
                    .overlay(
                        Image(systemName: "wrench.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: 30, height: 30)
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "Tilly"
        case .system: return "System"
        case .tool: return "Tool Result"
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user: return .primary
        case .assistant: return .purple
        case .system: return .secondary
        case .tool: return .orange
        }
    }

    private var backgroundColor: Color {
        message.role == .assistant ? Color(.controlBackgroundColor).opacity(0.3) : .clear
    }
}

// MARK: - Inline Tool Call (collapsed by default)

struct InlineToolCallView: View {
    let toolCall: ToolCall
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    // Accent bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.orange.opacity(0.6))
                        .frame(width: 3)

                    Image(systemName: iconForTool(toolCall.function.name))
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Text(displayNameForTool(toolCall.function.name))
                        .font(.caption.weight(.medium))
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
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)

            // Expanded details
            if isExpanded {
                Text(prettyArguments)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.textBackgroundColor).opacity(0.5))
            }
        }
        .background(Color.orange.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.12), lineWidth: 1)
        )
    }

    private var argumentsSummary: String {
        guard let data = toolCall.function.arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if let cmd = json["command"] as? String { return "$ \(cmd.prefix(50))" }
        if let target = json["target"] as? String { return target }
        if let path = json["path"] as? String { return path }
        if let url = json["url"] as? String { return url.prefix(50).description }
        if let name = json["name"] as? String { return name }
        if let goal = json["goal"] as? String { return goal.prefix(50).description }
        return ""
    }

    private var prettyArguments: String {
        guard let data = toolCall.function.arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let str = String(data: pretty, encoding: .utf8) else { return toolCall.function.arguments }
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
        case "memory_store", "memory_search", "memory_list", "memory_delete": return "brain"
        case "skill_create", "skill_run", "skill_list", "skill_delete": return "sparkles"
        case "scratchpad_write", "scratchpad_read": return "note.text"
        case "plan_task": return "checklist"
        case "ask_user": return "questionmark.circle"
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
        case "memory_store": return "Save Memory"
        case "memory_search": return "Search Memory"
        case "skill_run": return "Run Skill"
        case "skill_create": return "Create Skill"
        case "scratchpad_write": return "Write Notes"
        case "scratchpad_read": return "Read Notes"
        case "plan_task": return "Plan Task"
        case "ask_user": return "Ask User"
        default: return name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - Inline Tool Result (collapsed by default)

struct InlineToolResultView: View {
    let text: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.green.opacity(0.6))
                        .frame(width: 3)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)

                    Text("Output")
                        .font(.caption.weight(.medium))

                    Text("(\(text.count) chars)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(nil)
                }
                .frame(maxHeight: 250)
                .padding(10)
                .background(Color(.textBackgroundColor).opacity(0.5))
            }
        }
        .background(Color.green.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Metadata Bar

struct MetadataBar: View {
    let metadata: MessageMetadata

    var body: some View {
        HStack(spacing: 10) {
            if let model = metadata.model {
                Label(model, systemImage: "cpu")
            }
            if let tokens = metadata.totalTokens {
                Label("\(tokens) tok", systemImage: "number")
            }
            if let latency = metadata.latencyMs {
                Label(latency < 1000 ? "\(latency)ms" : String(format: "%.1fs", Double(latency) / 1000.0), systemImage: "clock")
            }
        }
        .font(.caption2)
        .foregroundStyle(.quaternary)
        .padding(.top, 2)
    }
}
