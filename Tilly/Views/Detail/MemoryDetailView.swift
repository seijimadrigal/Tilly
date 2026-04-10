import SwiftUI
import TillyCore

struct MemoryDetailView: View {
    @Environment(AppState.self) private var appState
    let memory: MemoryEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: iconForType(memory.type))
                        .font(.title2)
                        .foregroundStyle(colorForType(memory.type))
                    VStack(alignment: .leading) {
                        Text(memory.name)
                            .font(.title2.bold())
                        Text(memory.type.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(colorForType(memory.type).opacity(0.15)))
                    }
                }

                Divider()

                // Content
                Text(memory.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .lineSpacing(4)

                Divider()

                // Metadata
                HStack(spacing: 16) {
                    Label("Created \(memory.created, style: .relative) ago", systemImage: "calendar")
                    Label("Updated \(memory.updated, style: .relative) ago", systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // Actions
                HStack {
                    Button(role: .destructive) {
                        try? appState.memoryService.delete(name: memory.id)
                        appState.showChat()
                    } label: {
                        Label("Delete Memory", systemImage: "trash")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 700, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { appState.showChat() } label: {
                    Label("Back to Chat", systemImage: "chevron.left")
                }
            }
        }
        .navigationTitle(memory.name)
    }

    private func iconForType(_ type: MemoryType) -> String {
        switch type {
        case .user: return "person.fill"
        case .feedback: return "bubble.left.fill"
        case .project: return "folder.fill"
        case .reference: return "link"
        }
    }

    private func colorForType(_ type: MemoryType) -> Color {
        switch type {
        case .user: return .blue
        case .feedback: return .green
        case .project: return .orange
        case .reference: return .purple
        }
    }
}
