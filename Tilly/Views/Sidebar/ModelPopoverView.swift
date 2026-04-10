import SwiftUI
import TillyCore

struct ModelPopoverView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            Text("Model Configuration")
                .font(.headline)

            Picker("Provider", selection: $state.selectedProviderID) {
                ForEach(ProviderID.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }

            if appState.isLoadingModels {
                ProgressView().scaleEffect(0.7)
            } else if !appState.availableModels.isEmpty {
                Picker("Model", selection: $state.selectedModelID) {
                    ForEach(appState.availableModels) { model in
                        Text(model.name).tag(model.id)
                    }
                }
            } else {
                TextField("Model ID", text: $state.selectedModelID)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding()
        .frame(width: 280)
        .onChange(of: appState.selectedProviderID) {
            if let config = appState.providerConfigs.first(where: { $0.providerID == appState.selectedProviderID }),
               let defaultModel = config.defaultModel {
                appState.selectedModelID = defaultModel
            }
            appState.saveProviderSelection()
            Task { await appState.loadModels() }
        }
        .onChange(of: appState.selectedModelID) {
            appState.saveProviderSelection()
        }
        .task { await appState.loadModels() }
    }
}
