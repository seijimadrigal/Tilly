import SwiftUI

struct CredentialDetailView: View {
    @Environment(AppState.self) private var appState
    let credential: KeychainCredential

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "key.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text(credential.label)
                            .font(.title2.bold())
                        Text("Stored in macOS Keychain")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Details
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Server", value: credential.server)
                    LabeledContent("Account", value: credential.account)
                }

                Divider()

                // Actions
                HStack(spacing: 12) {
                    Button {
                        // Copy password to clipboard (via the keychain tool approval flow)
                        Task {
                            await appState.sendMessage("Use keychain autofill for \(credential.server)")
                        }
                        appState.showChat()
                    } label: {
                        Label("Copy Password", systemImage: "doc.on.clipboard")
                    }

                    if !credential.server.isEmpty {
                        Button {
                            let url = credential.server.hasPrefix("http") ? credential.server : "https://\(credential.server)"
                            #if os(macOS)
                            NSWorkspace.shared.open(URL(string: url)!)
                            #endif
                        } label: {
                            Label("Open in Browser", systemImage: "safari")
                        }
                    }
                }

                Text("Password access requires your approval via the ask_user dialog.")
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
        .navigationTitle(credential.label)
    }
}
