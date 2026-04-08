import SwiftUI
import TillyCore
import TillyStorage

struct MemoryBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var memories: [MemoryEntry] = []
    @State private var selectedMemory: MemoryEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Memories", systemImage: "brain")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(memories.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.gray.opacity(0.2)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if memories.isEmpty {
                Text("No memories yet. The agent will store memories as you interact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                List(memories, selection: Binding(
                    get: { selectedMemory?.id },
                    set: { id in selectedMemory = memories.first { $0.id == id } }
                )) { memory in
                    MemoryRowView(memory: memory)
                        .tag(memory.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                deleteMemory(memory)
                            }
                        }
                }
                .listStyle(.plain)
            }
        }
        .onAppear { refreshMemories() }
    }

    private func refreshMemories() {
        memories = (try? appState.memoryService.list()) ?? []
    }

    private func deleteMemory(_ memory: MemoryEntry) {
        try? appState.memoryService.delete(name: memory.id)
        refreshMemories()
    }
}

struct MemoryRowView: View {
    let memory: MemoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: iconForType(memory.type))
                    .font(.caption2)
                    .foregroundStyle(colorForType(memory.type))
                Text(memory.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            Text(memory.content.prefix(80).replacingOccurrences(of: "\n", with: " "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
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
