import SwiftUI
import TillyCore
import TillyStorage

struct MemoryBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var memories: [MemoryEntry] = []
    @State private var expandedMemoryID: String?

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
                VStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No memories yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tilly saves memories automatically as you interact.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(memories) { memory in
                            MemoryCardView(
                                memory: memory,
                                isExpanded: expandedMemoryID == memory.id,
                                onTap: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        expandedMemoryID = expandedMemoryID == memory.id ? nil : memory.id
                                    }
                                },
                                onDelete: {
                                    deleteMemory(memory)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear { refreshMemories() }
    }

    private func refreshMemories() {
        memories = (try? appState.memoryService.list()) ?? []
    }

    private func deleteMemory(_ memory: MemoryEntry) {
        withAnimation {
            try? appState.memoryService.delete(name: memory.id)
            refreshMemories()
            if expandedMemoryID == memory.id {
                expandedMemoryID = nil
            }
        }
    }
}

// MARK: - Memory Card (expandable)

struct MemoryCardView: View {
    let memory: MemoryEntry
    let isExpanded: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible, clickable
            Button(action: onTap) {
                HStack(spacing: 6) {
                    Image(systemName: iconForType(memory.type))
                        .font(.caption2)
                        .foregroundStyle(colorForType(memory.type))
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(memory.name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        if !isExpanded {
                            Text(memory.content.prefix(60).replacingOccurrences(of: "\n", with: " "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Text(memory.type.rawValue)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(colorForType(memory.type).opacity(0.1)))

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(memory.content)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Text("Updated \(memory.updated, style: .relative) ago")
                            .font(.system(size: 9))
                            .foregroundStyle(.quaternary)

                        Spacer()

                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red.opacity(0.7))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .padding(.top, 2)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isExpanded ? Color(.controlBackgroundColor).opacity(0.5) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isExpanded ? Color.gray.opacity(0.15) : .clear, lineWidth: 1)
        )
        .contextMenu {
            Button("Delete", role: .destructive) { onDelete() }
        }
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
