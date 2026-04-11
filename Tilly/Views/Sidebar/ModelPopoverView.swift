import SwiftUI
import TillyCore

struct ModelPopoverView: View {
    @Environment(AppState.self) private var appState
    @State private var orchModels: [ModelInfo] = []
    @State private var subModels: [ModelInfo] = []
    @State private var isLoadingOrch = false
    @State private var isLoadingSub = false

    var body: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cpu.fill")
                    .font(.subheadline)
                    .foregroundStyle(.purple)
                Text("Model Configuration")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── Main Agent ──
                    modelSection(
                        title: "Main Agent",
                        icon: "sparkle",
                        color: .purple,
                        description: "Primary model for conversations and tool use",
                        providerBinding: $state.selectedProviderID,
                        modelBinding: $state.selectedModelID,
                        models: appState.availableModels,
                        isLoading: appState.isLoadingModels,
                        onProviderChange: {
                            autoSelectDefault(for: appState.selectedProviderID, into: &state.selectedModelID)
                            appState.saveProviderSelection()
                            Task { await appState.loadModels() }
                        },
                        onModelChange: { appState.saveProviderSelection() }
                    )

                    Divider().padding(.horizontal, 4)

                    // ── Orchestrator ──
                    modelSection(
                        title: "Orchestrator",
                        icon: "brain",
                        color: .blue,
                        description: "Triage classification, planning, reflection. Use a fast/cheap model.",
                        providerBinding: Binding(
                            get: { appState.orchestratorProviderID },
                            set: { appState.orchestratorProviderID = $0 }
                        ),
                        modelBinding: Binding(
                            get: { appState.orchestratorModelID },
                            set: { appState.orchestratorModelID = $0 }
                        ),
                        models: orchModels,
                        isLoading: isLoadingOrch,
                        onProviderChange: {
                            autoSelectDefault(for: appState.orchestratorProviderID, into: Binding(
                                get: { appState.orchestratorModelID },
                                set: { appState.orchestratorModelID = $0 }
                            ))
                            appState.setupOrchestration()
                            Task {
                                isLoadingOrch = true
                                orchModels = await appState.loadModels(for: appState.orchestratorProviderID)
                                isLoadingOrch = false
                            }
                        },
                        onModelChange: { appState.setupOrchestration() }
                    )

                    Divider().padding(.horizontal, 4)

                    // ── Sub-Agent ──
                    modelSection(
                        title: "Sub-Agent",
                        icon: "person.2.fill",
                        color: .orange,
                        description: "Delegated parallel tasks. Can match main or use a cheaper model.",
                        providerBinding: Binding(
                            get: { appState.subAgentProviderID },
                            set: { appState.subAgentProviderID = $0 }
                        ),
                        modelBinding: Binding(
                            get: { appState.subAgentModelID },
                            set: { appState.subAgentModelID = $0 }
                        ),
                        models: subModels,
                        isLoading: isLoadingSub,
                        onProviderChange: {
                            autoSelectDefault(for: appState.subAgentProviderID, into: Binding(
                                get: { appState.subAgentModelID },
                                set: { appState.subAgentModelID = $0 }
                            ))
                            Task {
                                isLoadingSub = true
                                subModels = await appState.loadModels(for: appState.subAgentProviderID)
                                isLoadingSub = false
                            }
                        },
                        onModelChange: {}
                    )

                    Divider().padding(.horizontal, 4)

                    // ── Auto Mode ──
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                            Text("Auto Mode")
                                .font(.subheadline.weight(.semibold))
                        }

                        Toggle("Auto-route by complexity", isOn: Binding(
                            get: { appState.autoRouting },
                            set: { appState.autoRouting = $0 }
                        ))
                        .font(.subheadline)

                        Text("Simple → flash model, complex → premium model")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Toggle("Enable triage classification", isOn: Binding(
                            get: { appState.triageEnabled },
                            set: { appState.triageEnabled = $0 }
                        ))
                        .font(.subheadline)

                        Toggle("Enable reflection", isOn: Binding(
                            get: { appState.reflectionEnabled },
                            set: { appState.reflectionEnabled = $0 }
                        ))
                        .font(.subheadline)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 340, height: 560)
        .task {
            await appState.loadModels()
            async let o: () = loadOrchModels()
            async let s: () = loadSubModels()
            _ = await (o, s)
        }
    }

    // MARK: - Model Section Builder

    @ViewBuilder
    private func modelSection(
        title: String,
        icon: String,
        color: Color,
        description: String,
        providerBinding: Binding<ProviderID>,
        modelBinding: Binding<String>,
        models: [ModelInfo],
        isLoading: Bool,
        onProviderChange: @escaping () -> Void,
        onModelChange: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                // Status dot
                Circle()
                    .fill(statusColor(for: providerBinding.wrappedValue))
                    .frame(width: 6, height: 6)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.tertiary)

            // Provider picker
            Picker("", selection: providerBinding) {
                ForEach(ProviderID.allCases) { p in
                    HStack(spacing: 4) {
                        Image(systemName: p.icon)
                        Text(p.displayName)
                    }
                    .tag(p)
                }
            }
            .labelsHidden()
            .onChange(of: providerBinding.wrappedValue) { _, _ in onProviderChange() }

            // Model picker or text field
            if isLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading models...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !models.isEmpty {
                Picker("", selection: modelBinding) {
                    ForEach(models) { m in
                        Text(m.name).tag(m.id)
                    }
                }
                .labelsHidden()
                .onChange(of: modelBinding.wrappedValue) { _, _ in onModelChange() }
            } else {
                TextField("Model ID", text: modelBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                    .onChange(of: modelBinding.wrappedValue) { _, _ in onModelChange() }
            }
        }
    }

    // MARK: - Helpers

    private func statusColor(for provider: ProviderID) -> Color {
        switch appState.providerStatuses[provider] {
        case .connected: return .green
        case .failed: return .red
        case .testing: return .yellow
        default:
            if !provider.requiresAPIKey || appState.keychainService.hasAPIKey(for: provider) {
                return .yellow
            }
            return .gray
        }
    }

    private func autoSelectDefault(for provider: ProviderID, into binding: inout String) {
        if let config = appState.providerConfigs.first(where: { $0.providerID == provider }),
           let defaultModel = config.defaultModel {
            binding = defaultModel
        }
    }

    private func autoSelectDefault(for provider: ProviderID, into binding: Binding<String>) {
        if let config = appState.providerConfigs.first(where: { $0.providerID == provider }),
           let defaultModel = config.defaultModel {
            binding.wrappedValue = defaultModel
        }
    }

    private func loadOrchModels() async {
        isLoadingOrch = true
        orchModels = await appState.loadModels(for: appState.orchestratorProviderID)
        isLoadingOrch = false
    }

    private func loadSubModels() async {
        isLoadingSub = true
        subModels = await appState.loadModels(for: appState.subAgentProviderID)
        isLoadingSub = false
    }
}
