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

    // Local state for auto toggles (synced to AppState on change)
    @State private var mainAuto: Bool = false
    @State private var orchAuto: Bool = false
    @State private var subAuto: Bool = false

    // Models fetched per-role
    @State private var orchModels: [ModelInfo] = []
    @State private var subModels: [ModelInfo] = []
    @State private var isLoadingOrch = false
    @State private var isLoadingSub = false

    // Auto-test status
    @State private var mainAutoStatus: String?
    @State private var orchAutoStatus: String?
    @State private var subAutoStatus: String?

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
                    modelSection(
                        title: "Main Agent",
                        icon: "sparkle",
                        color: .purple,
                        description: "Primary model for conversations and tool use",
                        tier: .premium,
                        isAuto: $mainAuto,
                        autoStatus: mainAutoStatus,
                        providerBinding: $state.selectedProviderID,
                        modelBinding: $state.selectedModelID,
                        models: appState.availableModels,
                        isLoading: appState.isLoadingModels,
                        onProviderChange: {
                            autoSelectDefault(for: appState.selectedProviderID, into: &state.selectedModelID)
                            appState.saveProviderSelection()
                            Task { await appState.loadModels() }
                        },
                        onModelChange: { appState.saveProviderSelection() },
                        onAutoToggle: { on in
                            appState.mainAgentAuto = on
                            if on { Task { await autoSelectWithTest(tier: .premium, setProvider: { state.selectedProviderID = $0 }, setModel: { state.selectedModelID = $0 }, setStatus: { mainAutoStatus = $0 }, postAction: { appState.saveProviderSelection(); Task { await appState.loadModels() } }) } }
                        }
                    )

                    Divider().padding(.horizontal, 4)

                    // ── Orchestrator ──
                    modelSection(
                        title: "Orchestrator",
                        icon: "brain",
                        color: .blue,
                        description: "Triage, planning, reflection — fast/cheap model",
                        tier: .flash,
                        isAuto: $orchAuto,
                        autoStatus: orchAutoStatus,
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
                            autoSelectDefault(for: appState.orchestratorProviderID, into: Binding(get: { appState.orchestratorModelID }, set: { appState.orchestratorModelID = $0 }))
                            appState.setupOrchestration()
                            Task { isLoadingOrch = true; orchModels = await appState.loadModels(for: appState.orchestratorProviderID); isLoadingOrch = false }
                        },
                        onModelChange: { appState.setupOrchestration() },
                        onAutoToggle: { on in
                            appState.orchestratorAuto = on
                            if on { Task { await autoSelectWithTest(tier: .flash, setProvider: { appState.orchestratorProviderID = $0 }, setModel: { appState.orchestratorModelID = $0 }, setStatus: { orchAutoStatus = $0 }, postAction: { appState.setupOrchestration(); Task { isLoadingOrch = true; orchModels = await appState.loadModels(for: appState.orchestratorProviderID); isLoadingOrch = false } }) } }
                        }
                    )

                    Divider().padding(.horizontal, 4)

                    // ── Sub-Agent ──
                    modelSection(
                        title: "Sub-Agent",
                        icon: "person.2.fill",
                        color: .orange,
                        description: "Delegated parallel tasks — balanced model",
                        tier: .standard,
                        isAuto: $subAuto,
                        autoStatus: subAutoStatus,
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
                            autoSelectDefault(for: appState.subAgentProviderID, into: Binding(get: { appState.subAgentModelID }, set: { appState.subAgentModelID = $0 }))
                            Task { isLoadingSub = true; subModels = await appState.loadModels(for: appState.subAgentProviderID); isLoadingSub = false }
                        },
                        onModelChange: {},
                        onAutoToggle: { on in
                            appState.subAgentAuto = on
                            if on { Task { await autoSelectWithTest(tier: .standard, setProvider: { appState.subAgentProviderID = $0 }, setModel: { appState.subAgentModelID = $0 }, setStatus: { subAutoStatus = $0 }, postAction: { Task { isLoadingSub = true; subModels = await appState.loadModels(for: appState.subAgentProviderID); isLoadingSub = false } }) } }
                        }
                    )

                    Divider().padding(.horizontal, 4)

                    // ── Routing Toggles ──
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                                .font(.subheadline)
                                .foregroundStyle(.green)
                            Text("Routing")
                                .font(.subheadline.weight(.semibold))
                        }

                        Toggle("Auto-route by complexity", isOn: Binding(get: { appState.autoRouting }, set: { appState.autoRouting = $0 }))
                            .font(.subheadline)
                        Toggle("Enable triage", isOn: Binding(get: { appState.triageEnabled }, set: { appState.triageEnabled = $0 }))
                            .font(.subheadline)
                        Toggle("Enable reflection", isOn: Binding(get: { appState.reflectionEnabled }, set: { appState.reflectionEnabled = $0 }))
                            .font(.subheadline)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 340, height: 580)
        .onAppear {
            mainAuto = appState.mainAgentAuto
            orchAuto = appState.orchestratorAuto
            subAuto = appState.subAgentAuto
        }
        .task {
            await appState.loadModels()
            isLoadingOrch = true; orchModels = await appState.loadModels(for: appState.orchestratorProviderID); isLoadingOrch = false
            isLoadingSub = true; subModels = await appState.loadModels(for: appState.subAgentProviderID); isLoadingSub = false
        }
    }

    // MARK: - Model Section

    @ViewBuilder
    private func modelSection(
        title: String,
        icon: String,
        color: Color,
        description: String,
        tier: ModelRouter.ModelTier,
        isAuto: Binding<Bool>,
        autoStatus: String?,
        providerBinding: Binding<ProviderID>,
        modelBinding: Binding<String>,
        models: [ModelInfo],
        isLoading: Bool,
        onProviderChange: @escaping () -> Void,
        onModelChange: @escaping () -> Void,
        onAutoToggle: @escaping (Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title + auto toggle
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    isAuto.wrappedValue.toggle()
                    onAutoToggle(isAuto.wrappedValue)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isAuto.wrappedValue ? "wand.and.stars" : "hand.raised.fill")
                            .font(.system(size: 9))
                        Text(isAuto.wrappedValue ? "Auto" : "Manual")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(isAuto.wrappedValue ? .green : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(isAuto.wrappedValue ? Color.green.opacity(0.15) : Color.gray.opacity(0.1)))
                    .overlay(Capsule().stroke(isAuto.wrappedValue ? Color.green.opacity(0.3) : Color.gray.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Circle()
                    .fill(statusColor(for: providerBinding.wrappedValue))
                    .frame(width: 6, height: 6)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.tertiary)

            if isAuto.wrappedValue {
                // Auto mode — show selected + status
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.caption)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(providerBinding.wrappedValue.displayName) / \(modelBinding.wrappedValue)")
                            .font(.subheadline)
                        if let status = autoStatus {
                            Text(status)
                                .font(.caption2)
                                .foregroundStyle(status.contains("Failed") ? .red : .green)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.15), lineWidth: 1))
            } else {
                // Manual — provider + model pickers
                Picker("", selection: providerBinding) {
                    ForEach(ProviderID.allCases) { p in
                        Label(p.displayName, systemImage: p.icon).tag(p)
                    }
                }
                .labelsHidden()
                .onChange(of: providerBinding.wrappedValue) { _, _ in onProviderChange() }

                if isLoading {
                    HStack { ProgressView().controlSize(.small); Text("Loading...").font(.caption).foregroundStyle(.secondary) }
                } else if !models.isEmpty {
                    // Ensure current selection is a valid tag — add it if missing
                    let currentID = modelBinding.wrappedValue
                    let hasCurrentInList = models.contains { $0.id == currentID }
                    Picker("", selection: modelBinding) {
                        if !hasCurrentInList && !currentID.isEmpty {
                            Text(currentID).tag(currentID)
                        }
                        ForEach(models) { m in Text(m.name).tag(m.id) }
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
    }

    // MARK: - Auto Selection with API Test

    /// Auto-select: test current provider first, pick best model from it for the role.
    /// Falls back to tier-matched profiles, then any working provider.
    private func autoSelectWithTest(
        tier: ModelRouter.ModelTier,
        setProvider: @escaping (ProviderID) -> Void,
        setModel: @escaping (String) -> Void,
        setStatus: @escaping (String?) -> Void,
        postAction: @escaping () -> Void
    ) async {
        let currentProvider = appState.selectedProviderID
        setStatus("Testing \(currentProvider.displayName)...")

        // Step 1: Test the currently selected provider first
        await appState.testProviderConnection(currentProvider)
        if case .connected = appState.providerStatuses[currentProvider] {
            // It works — pick the best model from this provider for the role
            let models = await appState.loadModels(for: currentProvider)
            let bestModel = pickBestModel(from: models, provider: currentProvider, tier: tier)
            setProvider(currentProvider)
            setModel(bestModel)
            setStatus("Connected — \(currentProvider.displayName) / \(bestModel)")
            postAction()
            return
        }

        // Step 2: Current provider failed — try tier-matched profiles
        setStatus("Trying alternatives...")
        let profiles = ModelRouter.ModelProfile.defaults.filter { $0.tier == tier }
        for profile in profiles where profile.providerID != currentProvider {
            await appState.testProviderConnection(profile.providerID)
            if case .connected = appState.providerStatuses[profile.providerID] {
                setProvider(profile.providerID)
                setModel(profile.modelID)
                setStatus("Connected — \(profile.providerID.displayName)")
                postAction()
                return
            }
        }

        // Step 3: Try any provider with a working API key
        for providerID in ProviderID.allCases where providerID != currentProvider {
            if appState.keychainService.hasAPIKey(for: providerID) || !providerID.requiresAPIKey {
                await appState.testProviderConnection(providerID)
                if case .connected = appState.providerStatuses[providerID] {
                    let models = await appState.loadModels(for: providerID)
                    let bestModel = pickBestModel(from: models, provider: providerID, tier: tier)
                    setProvider(providerID)
                    setModel(bestModel)
                    setStatus("Fallback — \(providerID.displayName)")
                    postAction()
                    return
                }
            }
        }

        setStatus("Failed — no working provider found")
    }

    /// Pick the best model from a provider's model list for a specific role.
    ///
    /// - Flash (Orchestrator): fastest/cheapest — triage classification, plan generation, reflection.
    ///   Prefers: flash, mini, fast, lite, small, nano, 4-flash, turbo
    /// - Standard (Sub-Agent): balanced cost/quality — parallel research, file tasks, delegated work.
    ///   Prefers: chat, standard, v1, deepseek-chat, 8k. Avoids: mini, flash, nano
    /// - Premium (Main Agent): best reasoning + tool use — complex conversations, orchestration.
    ///   Prefers: pro, plus, max, 5.1, sonnet, opus, gpt-4o, large. Avoids: mini, flash, lite
    private func pickBestModel(from models: [ModelInfo], provider: ProviderID, tier: ModelRouter.ModelTier) -> String {
        // 1. Exact profile match
        if let profile = ModelRouter.ModelProfile.defaults.first(where: { $0.providerID == provider && $0.tier == tier }),
           models.contains(where: { $0.id == profile.modelID }) {
            return profile.modelID
        }

        let ids = models.map { $0.id.lowercased() }

        // 2. Heuristic match by role
        switch tier {
        case .flash:
            let flashKeywords = ["flash", "mini", "fast", "lite", "small", "nano", "turbo"]
            for keyword in flashKeywords {
                if let m = models.first(where: { $0.id.lowercased().contains(keyword) }) { return m.id }
            }

        case .standard:
            let avoid = Set(["mini", "flash", "nano", "lite", "small"])
            // Prefer "chat" models that aren't tiny
            if let m = models.first(where: {
                let lower = $0.id.lowercased()
                return lower.contains("chat") && !avoid.contains(where: { lower.contains($0) })
            }) { return m.id }
            // Then any standard-looking model
            let stdKeywords = ["standard", "v1", "8k", "32k"]
            for keyword in stdKeywords {
                if let m = models.first(where: { $0.id.lowercased().contains(keyword) }) { return m.id }
            }

        case .premium:
            let avoid = Set(["mini", "flash", "nano", "lite", "small", "fast"])
            let premiumKeywords = ["pro", "plus", "max", "opus", "sonnet", "5.1", "gpt-4o", "large", "ultra", "thinking"]
            for keyword in premiumKeywords {
                if let m = models.first(where: {
                    let lower = $0.id.lowercased()
                    return lower.contains(keyword) && !avoid.contains(where: { lower.contains($0) })
                }) { return m.id }
            }
        }

        // 3. Provider default
        if let config = appState.providerConfigs.first(where: { $0.providerID == provider }), let dm = config.defaultModel {
            return dm
        }
        return models.first?.id ?? ""
    }

    // MARK: - Helpers

    private func statusColor(for provider: ProviderID) -> Color {
        switch appState.providerStatuses[provider] {
        case .connected: return .green
        case .failed: return .red
        case .testing: return .yellow
        default:
            if !provider.requiresAPIKey || appState.keychainService.hasAPIKey(for: provider) { return .yellow }
            return .gray
        }
    }

    private func autoSelectDefault(for provider: ProviderID, into binding: inout String) {
        if let config = appState.providerConfigs.first(where: { $0.providerID == provider }),
           let dm = config.defaultModel { binding = dm }
    }

    private func autoSelectDefault(for provider: ProviderID, into binding: Binding<String>) {
        if let config = appState.providerConfigs.first(where: { $0.providerID == provider }),
           let dm = config.defaultModel { binding.wrappedValue = dm }
    }
}
