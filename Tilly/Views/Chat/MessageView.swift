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
                MessageContentView(content: message.content)

                // Metadata
                if let metadata = message.metadata {
                    MetadataView(metadata: metadata)
                }
            }

            Spacer(minLength: 40)
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
            Image(systemName: "wrench.fill")
                .font(.title3)
                .foregroundStyle(.orange)
        }
    }

    private var roleLabel: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "Assistant"
        case .system: return "System"
        case .tool: return "Tool"
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
