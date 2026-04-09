import SwiftUI
import TillyCore

struct ChatView: View {
    @Environment(AppState.self) private var appState
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Center content with max width like ChatGPT
                        LazyVStack(spacing: 0) {
                            if let session = appState.currentSession {
                                ForEach(session.messages) { message in
                                    MessageView(message: message)
                                        .id(message.id)
                                }
                            }

                            if appState.isStreaming {
                                StreamingIndicatorView()
                                    .id("streaming-indicator")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .onAppear { scrollProxy = proxy }
                .onChange(of: appState.currentSession?.messages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: appState.currentSession?.messages.last?.textContent) {
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()

            // Input
            InputBarView()
        }
        .navigationTitle(appState.currentSession?.title ?? "Chat")
        .navigationSubtitle(
            "\(appState.selectedProviderID.displayName) · \(appState.selectedModelID)"
        )
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if appState.isStreaming {
                proxy.scrollTo("streaming-indicator", anchor: .bottom)
            } else if let lastMessage = appState.currentSession?.messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Streaming Indicator

struct StreamingIndicatorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Avatar matching assistant style
            Circle()
                .fill(.purple.gradient)
                .overlay(
                    Image(systemName: "sparkle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                )
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 6) {
                Text("Tilly")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.purple)

                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)

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
        case "memory_store", "memory_search", "memory_list", "memory_delete": return "brain"
        case "skill_create", "skill_run", "skill_list", "skill_delete": return "sparkles"
        case "scratchpad_write", "scratchpad_read": return "note.text"
        case "plan_task": return "checklist"
        case "ask_user": return "questionmark.circle"
        default: return "wrench"
        }
    }
}
