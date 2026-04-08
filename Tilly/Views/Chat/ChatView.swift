import SwiftUI
import TillyCore

struct ChatView: View {
    @Environment(AppState.self) private var appState
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if let session = appState.currentSession {
                            ForEach(Array(session.messages.enumerated()), id: \.element.id) { index, message in
                                MessageView(message: message)
                                    .id(message.id)
                            }
                        }

                        if appState.isStreaming {
                            StreamingIndicatorView()
                                .id("streaming-indicator")
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onAppear { scrollProxy = proxy }
                .onChange(of: appState.currentSession?.messages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: appState.currentSession?.messages.last?.textContent) {
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()

            // Input
            InputBarView()
        }
        .navigationTitle(appState.currentSession?.title ?? "Chat")
        .navigationSubtitle(
            "\(appState.selectedProviderID.displayName) / \(appState.selectedModelID)"
        )
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if appState.isStreaming {
                proxy.scrollTo("streaming-indicator", anchor: .bottom)
            } else if let lastMessage = appState.currentSession?.messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

struct StreamingIndicatorView: View {
    @State private var dotCount = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.accentColor.opacity(i < dotCount ? 1.0 : 0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Spacer()
        }
        .padding(.horizontal, 16)
        .onReceive(timer) { _ in
            dotCount = (dotCount % 3) + 1
        }
    }
}
