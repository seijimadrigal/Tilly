import SwiftUI
import TillyCore

struct ChatView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let session = appState.currentSession {
                            // Group messages into "turns" — each turn is an assistant response
                            // with its tool calls and results bundled together
                            let turns = groupIntoTurns(session.messages)
                            ForEach(turns) { turn in
                                TurnView(turn: turn)
                                    .id(turn.id)
                            }
                        }

                        if appState.isStreaming {
                            StreamingIndicatorView()
                                .id("streaming-indicator")
                        }
                    }
                    .padding(.vertical, 16)
                }
                .onChange(of: appState.currentSession?.messages.count) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if appState.isStreaming {
                            proxy.scrollTo("streaming-indicator", anchor: .bottom)
                        } else if let session = appState.currentSession {
                            let turns = groupIntoTurns(session.messages)
                            if let last = turns.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: appState.currentSession?.messages.last?.textContent) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if appState.isStreaming {
                            proxy.scrollTo("streaming-indicator", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()
            InputBarView()
        }
        .navigationTitle(appState.currentSession?.title ?? "Chat")
        .navigationSubtitle("\(appState.selectedProviderID.displayName) · \(appState.selectedModelID)")
    }

    // MARK: - Group messages into turns

    /// A "turn" groups related messages together:
    /// - User turn: single user message
    /// - Assistant turn: assistant message + all tool calls/results until next user message or final text
    private func groupIntoTurns(_ messages: [Message]) -> [MessageTurn] {
        var turns: [MessageTurn] = []
        var i = 0

        while i < messages.count {
            let msg = messages[i]

            if msg.role == .user {
                turns.append(MessageTurn(id: msg.id, type: .user, userMessage: msg))
                i += 1
            } else if msg.role == .assistant {
                // Collect this assistant message + all following tool results + assistant continuations
                var assistantMessages: [Message] = [msg]
                var toolMessages: [Message] = []
                var j = i + 1

                while j < messages.count {
                    let next = messages[j]
                    if next.role == .tool {
                        toolMessages.append(next)
                        j += 1
                    } else if next.role == .assistant {
                        // Another assistant message (continuation after tool results)
                        assistantMessages.append(next)
                        j += 1
                    } else {
                        break  // Hit a user message — end of this turn
                    }
                }

                turns.append(MessageTurn(
                    id: msg.id,
                    type: .assistant,
                    assistantMessages: assistantMessages,
                    toolMessages: toolMessages
                ))
                i = j
            } else if msg.role == .tool {
                // Orphan tool message (shouldn't happen, but handle gracefully)
                turns.append(MessageTurn(id: msg.id, type: .toolOrphan, toolMessages: [msg]))
                i += 1
            } else {
                i += 1
            }
        }

        return turns
    }
}

// MARK: - Message Turn Model

struct MessageTurn: Identifiable {
    let id: UUID
    let type: TurnType
    var userMessage: Message?
    var assistantMessages: [Message] = []
    var toolMessages: [Message] = []

    enum TurnType {
        case user
        case assistant
        case toolOrphan
    }

    /// The final text content from the assistant (last non-empty text)
    var finalAssistantText: String {
        for msg in assistantMessages.reversed() {
            let text = msg.textContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        return ""
    }

    /// All tool calls across all assistant messages in this turn
    var allToolCalls: [ToolCall] {
        assistantMessages.flatMap { $0.toolCalls ?? [] }
    }

    /// The last assistant message's metadata
    var metadata: MessageMetadata? {
        assistantMessages.last?.metadata
    }

    /// Total tool operations (calls + results)
    var toolOperationCount: Int {
        allToolCalls.count + toolMessages.count
    }
}

// MARK: - Turn View

struct TurnView: View {
    let turn: MessageTurn

    var body: some View {
        switch turn.type {
        case .user:
            if let msg = turn.userMessage {
                UserMessageView(message: msg)
            }
        case .assistant:
            AssistantTurnView(turn: turn)
        case .toolOrphan:
            // Shouldn't normally appear
            EmptyView()
        }
    }
}

// MARK: - User Message

struct UserMessageView: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(.blue.gradient)
                .overlay(Image(systemName: "person.fill").font(.system(size: 14, weight: .medium)).foregroundStyle(.white))
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text("You")
                    .font(.subheadline.weight(.semibold))
                MessageContentView(content: message.content)
            }
            .frame(maxWidth: 680, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

// MARK: - Assistant Turn (with nested tool calls)

struct AssistantTurnView: View {
    let turn: MessageTurn
    @State private var showToolDetails = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Avatar
            Circle()
                .fill(.purple.gradient)
                .overlay(Image(systemName: "sparkle").font(.system(size: 14, weight: .medium)).foregroundStyle(.white))
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 8) {
                Text("Tilly")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)

                // Tool operations — single collapsible block
                if turn.toolOperationCount > 0 {
                    ToolOperationsBlock(
                        toolCalls: turn.allToolCalls,
                        toolResults: turn.toolMessages,
                        isExpanded: $showToolDetails
                    )
                }

                // Final text response (the part the user actually cares about)
                if !turn.finalAssistantText.isEmpty {
                    MessageContentView(content: [.text(turn.finalAssistantText)])
                }

                // Metadata
                if let metadata = turn.metadata {
                    MetadataBar(metadata: metadata)
                }
            }
            .frame(maxWidth: 680, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.controlBackgroundColor).opacity(0.3))
    }
}

// MARK: - Tool Operations Block (single collapsible container)

struct ToolOperationsBlock: View {
    let toolCalls: [ToolCall]
    let toolResults: [Message]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — always visible
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Text(summaryText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            // Expanded: show each tool call + its result
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(toolCalls.enumerated()), id: \.element.id) { index, tc in
                        NestedToolCallRow(
                            toolCall: tc,
                            result: toolResults.first(where: { $0.toolCallID == tc.id })
                        )
                    }
                    // Show orphan results not matched to a call
                    let matchedIDs = Set(toolCalls.map(\.id))
                    ForEach(toolResults.filter({ !matchedIDs.contains($0.toolCallID ?? "") })) { result in
                        NestedToolResultRow(text: result.textContent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(Color(.controlBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.12), lineWidth: 1)
        )
    }

    private var summaryText: String {
        let callNames = toolCalls.map { displayName($0.function.name) }
        let unique = Array(Set(callNames)).sorted()
        let count = toolCalls.count
        if unique.count <= 3 {
            return "\(count) tool \(count == 1 ? "call" : "calls"): \(unique.joined(separator: ", "))"
        }
        return "\(count) tool calls"
    }

    private func displayName(_ name: String) -> String {
        switch name {
        case "execute_command": return "Shell"
        case "open_application": return "Open App"
        case "read_file": return "Read"
        case "write_file": return "Write"
        case "list_directory": return "List Dir"
        case "web_fetch": return "Web"
        case "memory_store": return "Memory"
        case "memory_search": return "Search"
        case "skill_run": return "Skill"
        case "plan_task": return "Plan"
        case "scratchpad_write": return "Notes"
        case "ask_user": return "Ask"
        default: return name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - Nested Tool Call Row

struct NestedToolCallRow: View {
    let toolCall: ToolCall
    let result: Message?
    @State private var showArgs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Tool call header
            Button {
                withAnimation(.easeInOut(duration: 0.1)) { showArgs.toggle() }
            } label: {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.orange.opacity(0.5))
                        .frame(width: 2.5, height: 16)

                    Image(systemName: iconForTool(toolCall.function.name))
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)

                    Text(toolCall.function.name.replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 11, weight: .medium))

                    Text(argsSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if result != nil {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9))
                            .foregroundStyle(.green)
                    }

                    Image(systemName: showArgs ? "chevron.up" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if showArgs {
                // Arguments
                Text(prettyArgs)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.textBackgroundColor).opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                // Result
                if let result {
                    let text = result.textContent
                    Text(String(text.prefix(500)) + (text.count > 500 ? "..." : ""))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.8))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    private var argsSummary: String {
        guard let data = toolCall.function.arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if let cmd = json["command"] as? String { return "$ \(cmd.prefix(40))" }
        if let target = json["target"] as? String { return target }
        if let path = json["path"] as? String { return path }
        if let url = json["url"] as? String { return url.prefix(40).description }
        if let name = json["name"] as? String { return name }
        if let goal = json["goal"] as? String { return goal.prefix(40).description }
        return ""
    }

    private var prettyArgs: String {
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
}

// MARK: - Nested Tool Result Row (orphan)

struct NestedToolResultRow: View {
    let text: String

    var body: some View {
        Text(String(text.prefix(200)))
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.textBackgroundColor).opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Streaming Indicator

struct StreamingIndicatorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(.purple.gradient)
                .overlay(Image(systemName: "sparkle").font(.system(size: 14, weight: .medium)).foregroundStyle(.white))
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 6) {
                Text("Tilly")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)

                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)

                    if let toolName = appState.currentToolName {
                        Image(systemName: iconForTool(toolName))
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text(appState.currentToolSummary ?? toolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Thinking...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if appState.agentRound > 1 {
                        Text("Round \(appState.agentRound)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.gray.opacity(0.12)))
                    }
                }
            }
            .frame(maxWidth: 680, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
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
}
