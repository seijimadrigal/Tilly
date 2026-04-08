import SwiftUI

struct AppCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") {
                appState.createNewSession()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Chat") {
            Button("Stop Generation") {
                appState.stopStreaming()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!appState.isStreaming)
        }
    }
}
