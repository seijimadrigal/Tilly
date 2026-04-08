import SwiftUI
import TillyCore

@main
struct TillyRemoteApp: App {
    @State private var client = RemoteClient()

    var body: some Scene {
        WindowGroup {
            RemoteContentView()
                .environment(client)
        }
    }
}
