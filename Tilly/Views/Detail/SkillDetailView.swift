import SwiftUI
import TillyCore

struct SkillDetailView: View {
    @Environment(AppState.self) private var appState
    let skill: SkillEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading) {
                        Text(skill.name)
                            .font(.title2.bold())
                        Text(skill.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if !skill.trigger.isEmpty {
                    HStack {
                        Text("Triggers:")
                            .font(.subheadline.weight(.medium))
                        Text(skill.trigger)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Inputs / Outputs / Dependencies
                if !skill.inputs.isEmpty || !skill.outputs.isEmpty || !skill.dependencies.isEmpty {
                    Divider()
                    HStack(spacing: 24) {
                        if !skill.inputs.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Inputs").font(.subheadline.weight(.semibold))
                                ForEach(skill.inputs, id: \.self) { Text("• \($0)").font(.subheadline).foregroundStyle(.secondary) }
                            }
                        }
                        if !skill.outputs.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Outputs").font(.subheadline.weight(.semibold))
                                ForEach(skill.outputs, id: \.self) { Text("• \($0)").font(.subheadline).foregroundStyle(.secondary) }
                            }
                        }
                        if !skill.dependencies.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Dependencies").font(.subheadline.weight(.semibold))
                                ForEach(skill.dependencies, id: \.self) { Text("• \($0)").font(.subheadline).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }

                Divider()

                // Instructions
                Text("Instructions")
                    .font(.headline)
                Text(skill.instructions)
                    .font(.body)
                    .textSelection(.enabled)
                    .lineSpacing(4)

                // Tests
                if !skill.tests.isEmpty {
                    Divider()
                    Text("Test Prerequisites (\(skill.tests.count))")
                        .font(.headline)
                    ForEach(Array(skill.tests.enumerated()), id: \.offset) { _, test in
                        HStack(spacing: 6) {
                            Image(systemName: test.check == "credential" ? "key" : test.check == "api" ? "globe" : "terminal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(test.check): \(test.name ?? test.url ?? test.command ?? "")")
                                .font(.subheadline)
                        }
                    }
                }

                Divider()

                // Actions
                HStack(spacing: 12) {
                    Button {
                        appState.createNewSession()
                        appState.showChat()
                        Task { await appState.sendMessage("Run the skill: \(skill.name)") }
                    } label: { Label("Run Skill", systemImage: "play.fill") }

                    Button(role: .destructive) {
                        try? appState.skillService.delete(name: skill.id)
                        appState.showChat()
                    } label: { Label("Delete", systemImage: "trash") }
                }

                Text("Created \(skill.created, style: .relative) ago")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
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
        .navigationTitle(skill.name)
    }
}
