import SwiftUI
import TillyCore

enum SidebarSection: String, CaseIterable {
    case sessions = "Sessions"
    case memories = "Memories"
    case skills = "Skills"
    case credentials = "Credentials"

    var icon: String {
        switch self {
        case .sessions: return "bubble.left.and.bubble.right"
        case .memories: return "brain"
        case .skills: return "sparkles"
        case .credentials: return "key.fill"
        }
    }

    var color: Color {
        switch self {
        case .sessions: return .blue
        case .memories: return .purple
        case .skills: return .orange
        case .credentials: return .green
        }
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var activeSection: SidebarSection = .sessions
    @State private var showModelPopover = false
    @State private var memories: [MemoryEntry] = []
    @State private var skills: [SkillEntry] = []
    @State private var credentials: [KeychainCredential] = []

    private var providerStatusColor: Color {
        switch appState.providerStatuses[appState.selectedProviderID] {
        case .connected: return .green
        case .failed: return .red
        case .testing: return .yellow
        case .untested, .none:
            let id = appState.selectedProviderID
            if !id.requiresAPIKey || appState.keychainService.hasAPIKey(for: id) {
                return .yellow
            }
            return .gray
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkle")
                    .font(.title3)
                    .foregroundStyle(.purple)
                Text("Tilly")
                    .font(.headline)

                Spacer()

                Button { showModelPopover.toggle() } label: {
                    HStack(spacing: 4) {
                        // Status dot
                        Circle()
                            .fill(providerStatusColor)
                            .frame(width: 6, height: 6)
                        Image(systemName: appState.selectedProviderID.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(appState.selectedModelID)
                            .font(.caption2)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(.controlBackgroundColor).opacity(0.6)))
                    .overlay(Capsule().stroke(Color.gray.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("\(appState.selectedProviderID.displayName) — \(appState.selectedModelID)")
                .popover(isPresented: $showModelPopover) {
                    ModelPopoverView().environment(appState)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // New Chat button
            Button {
                appState.createNewSession()
                activeSection = .sessions
                appState.showChat()
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("New Chat")
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            // Section selector rows
            VStack(spacing: 2) {
                ForEach(SidebarSection.allCases, id: \.self) { section in
                    SectionRow(
                        section: section,
                        count: countFor(section),
                        isActive: activeSection == section
                    ) {
                        activeSection = section
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            // Content for selected section
            switch activeSection {
            case .sessions:
                sessionsList
            case .memories:
                memoryList
            case .skills:
                skillList
            case .credentials:
                credentialList
            }
        }
        .onAppear { refreshData() }
    }

    // MARK: - Counts

    private func countFor(_ section: SidebarSection) -> Int {
        switch section {
        case .sessions: return appState.sessions.count
        case .memories: return memories.count
        case .skills: return skills.count
        case .credentials: return credentials.count
        }
    }

    private func refreshData() {
        memories = (try? appState.memoryService.list()) ?? []
        skills = (try? appState.skillService.list()) ?? []
        #if os(macOS)
        credentials = appState.listCredentials()
        #endif
    }

    // MARK: - Sessions List

    private var sessionsList: some View {
        List(selection: Binding(
            get: { appState.currentSession?.id },
            set: { id in
                if let id, let session = appState.sessions.first(where: { $0.id == id }) {
                    appState.selectSession(session)
                    appState.showChat()
                }
            }
        )) {
            ForEach(appState.sessions) { session in
                SessionRowView(session: session, isActive: appState.currentSession?.id == session.id)
                    .tag(session.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation { appState.deleteSession(session) }
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) { appState.deleteSession(session) }
                    }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Memory List

    private var memoryList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(memories) { memory in
                    CompactRow(
                        icon: iconForMemoryType(memory.type),
                        iconColor: colorForMemoryType(memory.type),
                        title: memory.name,
                        isSelected: appState.detailTarget == .memoryDetail(memory)
                    ) {
                        appState.detailTarget = .memoryDetail(memory)
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            try? appState.memoryService.delete(name: memory.id)
                            refreshData()
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Skill List

    private var skillList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(skills) { skill in
                    CompactRow(
                        icon: "bolt.fill",
                        iconColor: .yellow,
                        title: skill.name,
                        isSelected: appState.detailTarget == .skillDetail(skill)
                    ) {
                        appState.detailTarget = .skillDetail(skill)
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            try? appState.skillService.delete(name: skill.id)
                            refreshData()
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Credential List

    private var credentialList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(credentials) { cred in
                    CompactRow(
                        icon: "key.fill",
                        iconColor: .green,
                        title: cred.server.isEmpty ? cred.label : cred.server,
                        subtitle: cred.account,
                        isSelected: appState.detailTarget == .credentialDetail(cred)
                    ) {
                        appState.detailTarget = .credentialDetail(cred)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    private func iconForMemoryType(_ type: MemoryType) -> String {
        switch type {
        case .user: return "person.fill"
        case .feedback: return "bubble.left.fill"
        case .project: return "folder.fill"
        case .reference: return "link"
        }
    }

    private func colorForMemoryType(_ type: MemoryType) -> Color {
        switch type {
        case .user: return .blue
        case .feedback: return .green
        case .project: return .orange
        case .reference: return .purple
        }
    }
}

// MARK: - Section Row

struct SectionRow: View {
    let section: SidebarSection
    let count: Int
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.body)
                    .foregroundStyle(isActive ? section.color : .secondary)
                    .frame(width: 22)
                Text(section.rawValue)
                    .font(.headline)
                    .foregroundStyle(isActive ? .primary : .secondary)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.gray.opacity(0.15)))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? section.color.opacity(0.1) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Row (for memories, skills, credentials)

struct CompactRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(iconColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    let session: Session
    var isActive: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.body)
                    .fontWeight(isActive ? .medium : .regular)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(session.messages.count) msgs")
                    Text("·")
                    Text(session.updatedAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
