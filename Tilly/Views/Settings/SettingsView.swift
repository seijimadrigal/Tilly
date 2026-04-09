import SwiftUI
import TillyCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            ProviderSettingsView()
                .tabItem {
                    Label("Providers", systemImage: "server.rack")
                }

            AccountSettingsView()
                .tabItem {
                    Label("Account", systemImage: "person.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("fontSize") private var fontSize = 14.0

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }

                Slider(value: $fontSize, in: 10...24, step: 1) {
                    Text("Font Size: \(Int(fontSize))")
                }
            }

            Section("Chat") {
                Toggle("Stream responses", isOn: .constant(true))
                    .disabled(true)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ProviderSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedProvider: ProviderID? = .ollama

    var body: some View {
        HSplitView {
            // Provider list
            List(ProviderID.allCases, selection: $selectedProvider) { provider in
                HStack {
                    Circle()
                        .fill(providerStatusColor(provider))
                        .frame(width: 8, height: 8)
                    Text(provider.displayName)
                }
                .tag(provider)
            }
            .frame(minWidth: 150, maxWidth: 200)

            // Provider detail
            if let provider = selectedProvider {
                ProviderDetailView(providerID: provider)
            } else {
                Text("Select a provider")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }

    private func providerStatusColor(_ provider: ProviderID) -> Color {
        if !provider.requiresAPIKey {
            return .green
        }
        return appState.keychainService.hasAPIKey(for: provider) ? .green : .gray
    }
}

struct ProviderDetailView: View {
    @Environment(AppState.self) private var appState
    let providerID: ProviderID
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var saveStatus: String?

    var body: some View {
        Form {
            Section("Configuration") {
                if providerID.requiresAPIKey {
                    HStack {
                        if showKey {
                            TextField("API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("API Key", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack {
                        Button("Save Key") {
                            saveAPIKey()
                        }

                        if let status = saveStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(status.contains("Error") ? .red : .green)
                        }
                    }
                } else {
                    Text("No API key required for local models.")
                        .foregroundStyle(.secondary)
                }
            }

            if let config = appState.providerConfigs.first(where: { $0.providerID == providerID }) {
                Section("Details") {
                    LabeledContent("Endpoint", value: config.baseURL.absoluteString)
                    if let model = config.defaultModel {
                        LabeledContent("Default Model", value: model)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadExistingKey()
        }
        .onChange(of: providerID) {
            loadExistingKey()
        }
    }

    private func loadExistingKey() {
        apiKey = ""
        saveStatus = nil
        if let key = try? appState.keychainService.getAPIKey(for: providerID) {
            apiKey = key
        }
    }

    private func saveAPIKey() {
        do {
            if apiKey.isEmpty {
                try appState.keychainService.deleteAPIKey(for: providerID)
                saveStatus = "Key removed"
            } else {
                try appState.keychainService.setAPIKey(apiKey, for: providerID)
                saveStatus = "Saved"
            }
            appState.refreshProviders()
        } catch {
            saveStatus = "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Account Settings

struct AccountSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("Account") {
                if appState.authService.isSignedIn {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text(appState.authService.userName ?? "User")
                                .font(.headline)
                            Text(appState.authService.userEmail ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Sign Out", role: .destructive) {
                        appState.authService.signOut()
                        appState.firebaseRelay.stop()
                    }
                } else {
                    Text("Not signed in")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Cloud Sync") {
                HStack {
                    Circle()
                        .fill(appState.firebaseRelay.isConnected ? .green : .gray)
                        .frame(width: 10, height: 10)
                    Text(appState.firebaseRelay.isConnected ? "Connected to Firebase" : "Not connected")
                }

                Text("Your sessions and settings are synced to Firebase so you can access them from the Tilly Remote iOS app anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
