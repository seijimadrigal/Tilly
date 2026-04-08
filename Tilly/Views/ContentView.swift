import SwiftUI
import TillyCore

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if appState.currentSession != nil {
                ChatView()
            } else {
                ContentUnavailableView(
                    "No Chat Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Create a new chat or select an existing one.")
                )
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 400)
        .frame(minWidth: 800, minHeight: 500)
    }
}
