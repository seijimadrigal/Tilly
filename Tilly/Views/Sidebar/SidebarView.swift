import SwiftUI
import TillyCore

struct SidebarView: View {
    @Environment(AppState.self) private var appState

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

            // Session List
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
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    appState.createNewSession()
                } label: {
                    Label("New Chat", systemImage: "plus")
                }
            }
        }
        .onChange(of: appState.selectedProviderID) {
            // Update default model for the selected provider
            if let config = appState.providerConfigs.first(where: { $0.providerID == appState.selectedProviderID }),
               let defaultModel = config.defaultModel {
                appState.selectedModelID = defaultModel
            }
            Task {
                await appState.loadModels()
            }
        }
        .task {
            await appState.loadModels()
        }
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
