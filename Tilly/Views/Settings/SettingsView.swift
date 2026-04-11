import SwiftUI
import TillyCore

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedSection: SettingsSection = .providers
    @State private var selectedProvider: ProviderID? = nil

    enum SettingsSection: String, CaseIterable {
        case providers = "Providers"
        case orchestration = "Orchestration"
        case appearance = "Appearance"
        case account = "Account"

        var icon: String {
            switch self {
            case .providers: return "server.rack"
            case .orchestration: return "cpu.fill"
            case .appearance: return "paintbrush.fill"
            case .account: return "person.circle.fill"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Settings header
                HStack {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Settings")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()

                // Section list
                VStack(spacing: 2) {
                    ForEach(SettingsSection.allCases, id: \.self) { section in
                        Button {
                            selectedSection = section
                            if section != .providers { selectedProvider = nil }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: section.icon)
                                    .font(.body)
                                    .foregroundStyle(selectedSection == section ? .blue : .secondary)
                                    .frame(width: 22)
                                Text(section.rawValue)
                                    .font(.headline)
                                    .foregroundStyle(selectedSection == section ? .primary : .secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedSection == section ? Color.blue.opacity(0.1) : .clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

                // Provider sub-list when Providers section is selected
                if selectedSection == .providers {
                    Divider()
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(ProviderID.allCases) { provider in
                                Button {
                                    selectedProvider = provider
                                } label: {
                                    HStack(spacing: 8) {
                                        statusDot(for: provider)
                                            .frame(width: 8, height: 8)
                                        Image(systemName: provider.icon)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 16)
                                        Text(provider.displayName)
                                            .font(.body)
                                            .foregroundStyle(selectedProvider == provider ? .primary : .secondary)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(selectedProvider == provider ? Color.accentColor.opacity(0.12) : .clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                }

                Spacer()
            }
        } detail: {
            switch selectedSection {
            case .providers:
                if let provider = selectedProvider {
                    ProviderDetailSettingsView(providerID: provider)
                } else {
                    ContentUnavailableView("Select a Provider", systemImage: "server.rack", description: Text("Choose a provider from the sidebar to configure it."))
                }
            case .orchestration:
                OrchestrationSettingsView()
            case .appearance:
                AppearanceSettingsView()
            case .account:
                AccountSettingsView()
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        .frame(minWidth: 720, minHeight: 500)
    }

    @ViewBuilder
    private func statusDot(for provider: ProviderID) -> some View {
        let status = appState.providerStatuses[provider]
        switch status {
        case .connected:
            Circle().fill(.green)
        case .failed:
            Circle().fill(.red)
        case .testing:
            Circle().fill(.yellow)
        case .untested, .none:
            if !provider.requiresAPIKey || appState.keychainService.hasAPIKey(for: provider) {
                Circle().fill(.yellow)  // Key exists but untested
            } else {
                Circle().fill(.gray)    // No key
            }
        }
    }
}

// MARK: - Provider Detail Settings

struct ProviderDetailSettingsView: View {
    @Environment(AppState.self) private var appState
    let providerID: ProviderID
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var saveStatus: String?
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var fetchedModels: [ModelInfo] = []
    @State private var isLoadingModels = false
    @State private var modelSearch = ""

    var filteredModels: [ModelInfo] {
        if modelSearch.isEmpty { return fetchedModels }
        return fetchedModels.filter { $0.name.localizedCaseInsensitiveContains(modelSearch) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: providerID.icon)
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 36, height: 36)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(providerID.displayName)
                            .font(.title2.bold())
                        if let config = appState.providerConfigs.first(where: { $0.providerID == providerID }) {
                            Text(config.baseURL.host ?? config.baseURL.absoluteString)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    connectionBadge
                }

                Divider()

                // API Key Section
                if providerID.requiresAPIKey {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Key")
                            .font(.headline)
                        HStack {
                            Group {
                                if showKey {
                                    TextField("Enter API key", text: $apiKey)
                                } else {
                                    SecureField("Enter API key", text: $apiKey)
                                }
                            }
                            .textFieldStyle(.roundedBorder)

                            Button { showKey.toggle() } label: {
                                Image(systemName: showKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }

                        HStack(spacing: 8) {
                            Button("Save") { saveAPIKey() }
                            Button("Delete", role: .destructive) { deleteAPIKey() }
                            Button {
                                Task { await testConnection() }
                            } label: {
                                HStack(spacing: 4) {
                                    if isTesting {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text("Test Connection")
                                }
                            }
                            .disabled(isTesting)

                            if let status = saveStatus {
                                Text(status)
                                    .font(.caption)
                                    .foregroundStyle(status.contains("Error") || status.contains("removed") ? .red : .green)
                            }
                        }

                        if let result = testResult {
                            HStack(spacing: 6) {
                                Image(systemName: result.contains("models") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.contains("models") ? .green : .red)
                                Text(result)
                                    .font(.caption)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.controlBackgroundColor).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Local provider — no API key required")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Available Models
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Available Models")
                            .font(.headline)
                        Spacer()
                        if isLoadingModels {
                            ProgressView().controlSize(.small)
                        }
                        Button {
                            Task { await loadModels() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh models")
                    }

                    if !fetchedModels.isEmpty {
                        TextField("Search models...", text: $modelSearch)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)

                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(filteredModels) { model in
                                    HStack {
                                        Text(model.name)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        Spacer()
                                        if model.id == appState.selectedModelID && providerID == appState.selectedProviderID {
                                            Image(systemName: "checkmark")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                        }
                                        Button("Use") {
                                            appState.selectedProviderID = providerID
                                            appState.selectedModelID = model.id
                                            appState.saveProviderSelection()
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color(.controlBackgroundColor).opacity(0.3))
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 250)

                        Text("\(filteredModels.count) models")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else if !isLoadingModels {
                        Text("No models loaded. Click refresh or test connection.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .onAppear { loadExistingKey(); Task { await loadModels() } }
        .onChange(of: providerID) { loadExistingKey(); Task { await loadModels() } }
    }

    @ViewBuilder
    private var connectionBadge: some View {
        let status = appState.providerStatuses[providerID]
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor(status))
                .frame(width: 8, height: 8)
            Text(badgeText(status))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(badgeColor(status).opacity(0.1)))
    }

    private func badgeColor(_ status: ConnectionStatus?) -> Color {
        switch status {
        case .connected: return .green
        case .failed: return .red
        case .testing: return .yellow
        default: return .gray
        }
    }

    private func badgeText(_ status: ConnectionStatus?) -> String {
        switch status {
        case .connected(let count): return "\(count) models"
        case .failed(let msg): return String(msg.prefix(30))
        case .testing: return "Testing..."
        default: return "Not tested"
        }
    }

    private func loadExistingKey() {
        apiKey = ""
        saveStatus = nil
        testResult = nil
        fetchedModels = []
        modelSearch = ""
        if let key = try? appState.keychainService.getAPIKey(for: providerID) {
            apiKey = key
        }
    }

    private func saveAPIKey() {
        do {
            try appState.keychainService.setAPIKey(apiKey, for: providerID)
            saveStatus = "Saved"
            appState.refreshProviders()
        } catch {
            saveStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func deleteAPIKey() {
        do {
            try appState.keychainService.deleteAPIKey(for: providerID)
            apiKey = ""
            saveStatus = "Key removed"
            appState.providerStatuses[providerID] = .untested
            appState.refreshProviders()
        } catch {
            saveStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        await appState.testProviderConnection(providerID)
        let status = appState.providerStatuses[providerID]
        switch status {
        case .connected(let count):
            testResult = "Connected — \(count) models available"
            await loadModels()
        case .failed(let msg):
            testResult = "Failed: \(msg)"
        default:
            testResult = "Unknown status"
        }
        isTesting = false
    }

    private func loadModels() async {
        isLoadingModels = true
        fetchedModels = await appState.loadModels(for: providerID)
        isLoadingModels = false
    }
}

// MARK: - Orchestration Settings

struct OrchestrationSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "cpu.fill")
                        .font(.title2)
                        .foregroundStyle(.purple)
                    Text("Orchestration")
                        .font(.title2.bold())
                }

                Divider()

                // Orchestrator Model
                VStack(alignment: .leading, spacing: 8) {
                    Text("Orchestrator Model")
                        .font(.headline)
                    Text("Used for triage classification, plan generation, and reflection. Use a fast/cheap model.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Picker("Provider", selection: Binding(
                            get: { appState.orchestratorProviderID },
                            set: { appState.orchestratorProviderID = $0; appState.setupOrchestration() }
                        )) {
                            ForEach(ProviderID.allCases) { p in Text(p.displayName).tag(p) }
                        }
                        .frame(maxWidth: 200)

                        TextField("Model ID", text: Binding(
                            get: { appState.orchestratorModelID },
                            set: { appState.orchestratorModelID = $0; appState.setupOrchestration() }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    }
                }

                Divider()

                // Sub-Agent Model
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sub-Agent Model")
                        .font(.headline)
                    Text("Used for delegated sub-tasks. Can be the same as the main model or a cheaper alternative.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Picker("Provider", selection: Binding(
                            get: { appState.subAgentProviderID },
                            set: { appState.subAgentProviderID = $0 }
                        )) {
                            ForEach(ProviderID.allCases) { p in Text(p.displayName).tag(p) }
                        }
                        .frame(maxWidth: 200)

                        TextField("Model ID", text: Binding(
                            get: { appState.subAgentModelID },
                            set: { appState.subAgentModelID = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    }
                }

                Divider()

                // Feature Toggles
                VStack(alignment: .leading, spacing: 12) {
                    Text("Features")
                        .font(.headline)

                    Toggle("Enable triage classification", isOn: Binding(
                        get: { appState.triageEnabled },
                        set: { appState.triageEnabled = $0 }
                    ))
                    Text("Classify incoming requests to route them optimally.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Toggle("Auto-route model by complexity", isOn: Binding(
                        get: { appState.autoRouting },
                        set: { appState.autoRouting = $0 }
                    ))
                    Text("Automatically select flash/standard/premium model based on task complexity.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Toggle("Enable reflection", isOn: Binding(
                        get: { appState.reflectionEnabled },
                        set: { appState.reflectionEnabled = $0 }
                    ))
                    Text("Self-critique output quality before returning to user.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(24)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("textSizeLevel") private var textSizeLevel = 3

    private let sizeLabels = ["XS", "S", "M", "Default", "L", "XL", "XXL"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "paintbrush.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text("Appearance")
                        .font(.title2.bold())
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme")
                        .font(.headline)
                    Picker("", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Text Size")
                        .font(.headline)
                    HStack {
                        Text("A").font(.caption)
                        Slider(value: Binding(
                            get: { Double(textSizeLevel) },
                            set: { textSizeLevel = Int($0) }
                        ), in: 0...6, step: 1)
                        .frame(maxWidth: 250)
                        Text("A").font(.title3)
                    }
                    Text(sizeLabels[textSizeLevel])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Cmd+/- to adjust, Cmd+0 to reset")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(24)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Account Settings

struct AccountSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text("Account")
                        .font(.title2.bold())
                }

                Divider()

                if appState.authService.isSignedIn {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text(appState.authService.userName ?? "User")
                                .font(.headline)
                            Text(appState.authService.userEmail ?? "")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Sign Out", role: .destructive) {
                        appState.authService.signOut()
                        appState.firebaseRelay.stop()
                    }
                } else {
                    Text("Sign in to sync sessions across devices")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await appState.authService.signInWithGoogle() }
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                            Text("Sign in with Google")
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Cloud Sync")
                        .font(.headline)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.firebaseRelay.isConnected ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text(appState.firebaseRelay.isConnected ? "Connected to Firebase" : "Not connected")
                            .font(.subheadline)
                    }
                    Text("Sessions and settings sync to Firebase for the Tilly Remote iOS app.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Memcloud")
                        .font(.headline)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.memoryService.isMemcloudEnabled ? .green : .gray)
                            .frame(width: 8, height: 8)
                        Text(appState.memoryService.isMemcloudEnabled ? "Cloud memory sync active" : "Not configured")
                            .font(.subheadline)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 600, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}
