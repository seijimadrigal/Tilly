import SwiftUI
import TillyCore
import TillyProviders

struct ModelAutoRec {
    let providerID: ProviderID
    let modelID: String
    let label: String
}

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
                VStack(alignment: .leading, spacing: 14) {

                    // ── Main Agent ──
                    ModelSectionView(
                        title: "Main Agent",
                        icon: "sparkle",
                        color: .purple,
                        description: "Primary model for conversations and tool use",
                        autoRecommendation: autoRecommendation(for: .premium),
                        isAuto: Binding(
                            get: { appState.mainAgentAuto },
                            set: { appState.mainAgentAuto = $0 }
                        ),
                        providerBinding: $state.selectedProviderID,
                        modelBinding: $state.selectedModelID,
                        models: appState.availableModels,
                        isLoading: appState.isLoadingModels,
                        statusColor: statusColor(for: appState.selectedProviderID),
                        onProviderChange: {
                            autoSelectDefault(for: appState.selectedProviderID, into: &state.selectedModelID)
                            appState.saveProviderSelection()
                            Task { await appState.loadModels() }
                        },
                        onModelChange: { appState.saveProviderSelection() },
                        onAutoToggle: { isAuto in
                            if isAuto, let rec = autoRecommendation(for: .premium) {
                                state.selectedProviderID = rec.providerID
                                state.selectedModelID = rec.modelID
                                appState.saveProviderSelection()
                                Task { await appState.loadModels() }
                            }
                        }
                    )

                    Divider().padding(.horizontal, 4)

                    // ── Orchestrator ──
                    ModelSectionView(
                        title: "Orchestrator",
                        icon: "brain",
                        color: .blue,
                        description: "Triage, planning, reflection — fast/cheap model",
                        autoRecommendation: autoRecommendation(for: .flash),
                        isAuto: Binding(
                            get: { appState.orchestratorAuto },
                            set: { appState.orchestratorAuto = $0 }
                        ),
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
                        statusColor: statusColor(for: appState.orchestratorProviderID),
                        onProviderChange: {
                            autoSelectDefault(for: appState.orchestratorProviderID, into: Binding(
                                get: { appState.orchestratorModelID },
                                set: { appState.orchestratorModelID = $0 }
                            ))
                            appState.setupOrchestration()
                            Task { isLoadingOrch = true; orchModels = await appState.loadModels(for: appState.orchestratorProviderID); isLoadingOrch = false }
                        },
                        onModelChange: { appState.setupOrchestration() },
                        onAutoToggle: { isAuto in
                            if isAuto, let rec = autoRecommendation(for: .flash) {
                                appState.orchestratorProviderID = rec.providerID
                                appState.orchestratorModelID = rec.modelID
                                appState.setupOrchestration()
                                Task { isLoadingOrch = true; orchModels = await appState.loadModels(for: rec.providerID); isLoadingOrch = false }
                            }
                        }
                    )

                    Divider().padding(.horizontal, 4)

                    // ── Sub-Agent ──
                    ModelSectionView(
                        title: "Sub-Agent",
                        icon: "person.2.fill",
                        color: .orange,
                        description: "Delegated parallel tasks — balanced model",
                        autoRecommendation: autoRecommendation(for: .standard),
                        isAuto: Binding(
                            get: { appState.subAgentAuto },
                            set: { appState.subAgentAuto = $0 }
                        ),
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
                        statusColor: statusColor(for: appState.subAgentProviderID),
                        onProviderChange: {
                            autoSelectDefault(for: appState.subAgentProviderID, into: Binding(
                                get: { appState.subAgentModelID },
                                set: { appState.subAgentModelID = $0 }
                            ))
                            Task { isLoadingSub = true; subModels = await appState.loadModels(for: appState.subAgentProviderID); isLoadingSub = false }
                        },
                        onModelChange: {},
                        onAutoToggle: { isAuto in
                            if isAuto, let rec = autoRecommendation(for: .standard) {
                                appState.subAgentProviderID = rec.providerID
                                appState.subAgentModelID = rec.modelID
                                Task { isLoadingSub = true; subModels = await appState.loadModels(for: rec.providerID); isLoadingSub = false }
                            }
                        }
                    )

                    Divider().padding(.horizontal, 4)

                    // ── Global Auto Mode ──
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                            Text("Routing")
                                .font(.subheadline.weight(.semibold))
                        }

                        Toggle("Auto-route by complexity", isOn: Binding(
                            get: { appState.autoRouting },
                            set: { appState.autoRouting = $0 }
                        ))
                        .font(.subheadline)

                        Toggle("Enable triage", isOn: Binding(
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
        .frame(width: 340, height: 580)
        .task {
            await appState.loadModels()
            async let o: () = loadOrchModels()
            async let s: () = loadSubModels()
            _ = await (o, s)
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

    private func autoRecommendation(for tier: ModelRouter.ModelTier) -> ModelAutoRec? {
        let route = ModelRouter().route(complexity: tier == .flash ? 0.1 : tier == .standard ? 0.5 : 0.9)
        return ModelAutoRec(providerID: route.providerID, modelID: route.modelID, label: "\(route.providerID.displayName) / \(route.modelID)")
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

// MARK: - Model Section View (reusable for each role)

private struct ModelSectionView: View {
    let title: String
    let icon: String
    let color: Color
    let description: String
    let autoRecommendation: ModelAutoRec?
    @Binding var isAuto: Bool
    @Binding var providerBinding: ProviderID
    @Binding var modelBinding: String
    let models: [ModelInfo]
    let isLoading: Bool
    let statusColor: Color
    let onProviderChange: () -> Void
    let onModelChange: () -> Void
    let onAutoToggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row with auto toggle
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                // Auto pill toggle
                Button {
                    isAuto.toggle()
                    onAutoToggle(isAuto)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isAuto ? "wand.and.stars" : "hand.raised.fill")
                            .font(.system(size: 9))
                        Text(isAuto ? "Auto" : "Manual")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(isAuto ? .green : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(isAuto ? Color.green.opacity(0.12) : Color.gray.opacity(0.1))
                    )
                    .overlay(
                        Capsule().stroke(isAuto ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.tertiary)

            if isAuto {
                // Auto mode — show recommendation
                if let rec = autoRecommendation {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text(rec.label)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.15), lineWidth: 1))
                }
            } else {
                // Manual mode — provider + model pickers
                Picker("", selection: $providerBinding) {
                    ForEach(ProviderID.allCases) { p in
                        HStack(spacing: 4) {
                            Image(systemName: p.icon)
                            Text(p.displayName)
                        }
                        .tag(p)
                    }
                }
                .labelsHidden()
                .onChange(of: providerBinding) { _, _ in onProviderChange() }

                if isLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !models.isEmpty {
                    Picker("", selection: $modelBinding) {
                        ForEach(models) { m in
                            Text(m.name).tag(m.id)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: modelBinding) { _, _ in onModelChange() }
                } else {
                    TextField("Model ID", text: $modelBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .onChange(of: modelBinding) { _, _ in onModelChange() }
                }
            }
        }
    }
}

