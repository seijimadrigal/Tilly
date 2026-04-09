import SwiftUI
import TillyCore

enum SidebarTab: String, CaseIterable {
    case sessions = "Sessions"
    case memories = "Memories"
    case skills = "Skills"

    var icon: String {
        switch self {
        case .sessions: return "bubble.left.and.bubble.right"
        case .memories: return "brain"
        case .skills: return "sparkles"
        }
    }
}

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: SidebarTab = .sessions

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // Provider & Model Picker
            VStack(spacing: 8) {
                Picker("Provider", selection: $state.selectedProviderID) {
                    ForEach(ProviderID.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                if appState.isLoadingModels {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if !appState.availableModels.isEmpty {
                    Picker("Model", selection: $state.selectedModelID) {
                        ForEach(appState.availableModels) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                } else {
                    TextField("Model ID", text: $state.selectedModelID)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Tab content
            switch selectedTab {
            case .sessions:
                sessionsList
            case .memories:
                MemoryBrowserView()
            case .skills:
                SkillBrowserView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    appState.createNewSession()
                    selectedTab = .sessions
                } label: {
                    Label("New Chat", systemImage: "plus")
                }
            }
        }
        .onChange(of: appState.selectedProviderID) {
            if let config = appState.providerConfigs.first(where: { $0.providerID == appState.selectedProviderID }),
               let defaultModel = config.defaultModel {
                appState.selectedModelID = defaultModel
            }
            appState.saveProviderSelection()
            Task {
                await appState.loadModels()
            }
        }
        .onChange(of: appState.selectedModelID) {
            appState.saveProviderSelection()
        }
        .task {
            await appState.loadModels()
        }
    }

    private var sessionsList: some View {
        List(selection: Binding(
            get: { appState.currentSession?.id },
            set: { id in
                if let id, let session = appState.sessions.first(where: { $0.id == id }) {
                    appState.selectSession(session)
                }
            }
        )) {
            ForEach(appState.sessions) { session in
                SessionRowView(session: session)
                    .tag(session.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            appState.deleteSession(session)
                        }
                    }
            }
        }
        .listStyle(.sidebar)
    }
}

struct SessionRowView: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title)
                .font(.body)
                .lineLimit(1)

            Text(session.updatedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
