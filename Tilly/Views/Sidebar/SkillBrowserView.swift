import SwiftUI
import TillyCore
import TillyStorage

struct SkillBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var skills: [SkillEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Skills", systemImage: "sparkles")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(skills.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.gray.opacity(0.2)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            if skills.isEmpty {
                Text("No skills yet. Ask the agent to create a skill for a workflow you want to reuse.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                List(skills) { skill in
                    SkillRowView(skill: skill)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                deleteSkill(skill)
                            }
                        }
                }
                .listStyle(.plain)
            }
        }
        .onAppear { refreshSkills() }
    }

    private func refreshSkills() {
        skills = (try? appState.skillService.list()) ?? []
    }

    private func deleteSkill(_ skill: SkillEntry) {
        try? appState.skillService.delete(name: skill.id)
        refreshSkills()
    }
}

struct SkillRowView: View {
    let skill: SkillEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text(skill.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            Text(skill.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !skill.trigger.isEmpty {
                Text("Triggers: \(skill.trigger)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
