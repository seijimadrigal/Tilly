import Foundation
import SwiftUI
import TillyCore
import TillyProviders
import TillyStorage

@MainActor
@Observable
final class AppState {
    // MARK: - Provider Management
    var providerConfigs: [ProviderConfiguration] = ProviderConfiguration.defaults
    var selectedProviderID: ProviderID = .ollama
    var selectedModelID: String = "llama3.2"
    var availableModels: [ModelInfo] = []
    var isLoadingModels: Bool = false

    // MARK: - Session Management
    var sessions: [Session] = []
    var currentSession: Session?
    var isStreaming: Bool = false

    // MARK: - Services
    let keychainService = KeychainService()
    private var providers: [ProviderID: any LLMProvider] = [:]

    init() {
        initializeProviders()
        createNewSession()
    }

    // MARK: - Provider Access

    var currentProvider: (any LLMProvider)? {
        providers[selectedProviderID]
    }

    func initializeProviders() {
        providers.removeAll()
        for config in providerConfigs where config.isEnabled {
            providers[config.providerID] = ProviderFactory.createProvider(
                for: config,
                keychain: keychainService
            )
        }
    }

    func refreshProviders() {
        initializeProviders()
    }

    func loadModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }

        guard let provider = currentProvider else {
            availableModels = []
            return
        }

        do {
            availableModels = try await provider.listModels()
        } catch {
            availableModels = []
            print("Failed to load models: \(error.localizedDescription)")
        }
    }

    // MARK: - Session Management

    func createNewSession() {
        let session = Session(
            providerID: selectedProviderID.rawValue,
            modelID: selectedModelID
        )
        sessions.insert(session, at: 0)
        currentSession = session
    }

    func selectSession(_ session: Session) {
        currentSession = session
    }

    func deleteSession(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        if currentSession?.id == session.id {
            currentSession = sessions.first
        }
    }

    func updateCurrentSession(_ session: Session) {
        currentSession = session
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
    }

    // MARK: - Chat

    func sendMessage(_ text: String) async {
        guard var session = currentSession, let provider = currentProvider else { return }

        // Add user message
        let userMessage = Message(role: .user, content: [.text(text)])
        session.appendMessage(userMessage)
        updateCurrentSession(session)

        // Build request
        let chatMessages = buildChatMessages(from: session)
        let request = ChatCompletionRequest(
            model: selectedModelID,
            messages: chatMessages,
            stream: true
        )

        // Stream response
        isStreaming = true
        var assistantMessage = Message(role: .assistant, content: [.text("")])
        let startTime = Date()
        var accumulatedText = ""
        var usage: StreamDelta.Usage?

        do {
            for try await delta in provider.stream(request) {
                guard let choice = delta.choices?.first else {
                    if let u = delta.usage { usage = u }
                    continue
                }

                if let content = choice.delta.content {
                    accumulatedText += content
                    assistantMessage.content = [.text(accumulatedText)]
                    session.messages[session.messages.count - 1] = assistantMessage
                    // We do this indirection so we only have one assistant message being accumulated
                    if session.messages.last?.role == .assistant {
                        session.messages[session.messages.count - 1] = assistantMessage
                    } else {
                        session.appendMessage(assistantMessage)
                    }
                    updateCurrentSession(session)
                }

                if let reason = choice.finishReason {
                    let latency = Int(Date().timeIntervalSince(startTime) * 1000)
                    assistantMessage.metadata = MessageMetadata(
                        model: selectedModelID,
                        provider: selectedProviderID.rawValue,
                        promptTokens: usage?.promptTokens,
                        completionTokens: usage?.completionTokens,
                        totalTokens: usage?.totalTokens,
                        finishReason: reason,
                        latencyMs: latency
                    )
                }
            }

            // Finalize the assistant message
            if session.messages.last?.role == .assistant {
                session.messages[session.messages.count - 1] = assistantMessage
            } else {
                session.appendMessage(assistantMessage)
            }
            updateCurrentSession(session)

        } catch {
            let errorMessage = Message(
                role: .assistant,
                content: [.text("Error: \(error.localizedDescription)")]
            )
            session.appendMessage(errorMessage)
            updateCurrentSession(session)
        }

        isStreaming = false

        // Auto-generate title from first exchange
        if session.messages.count <= 3 && session.title == "New Chat" {
            let title = String(text.prefix(50))
            session.title = title.count < text.count ? title + "..." : title
            updateCurrentSession(session)
        }
    }

    func stopStreaming() {
        isStreaming = false
        // The stream task checks isStreaming and will exit
    }

    // MARK: - Helpers

    private func buildChatMessages(from session: Session) -> [ChatCompletionRequest.ChatMessage] {
        var messages: [ChatCompletionRequest.ChatMessage] = []

        if let systemPrompt = session.systemPrompt {
            messages.append(ChatCompletionRequest.ChatMessage(
                role: "system",
                content: systemPrompt.content
            ))
        }

        for msg in session.messages {
            switch msg.role {
            case .user, .assistant:
                messages.append(ChatCompletionRequest.ChatMessage(
                    role: msg.role.rawValue,
                    content: msg.textContent
                ))
            case .tool:
                messages.append(ChatCompletionRequest.ChatMessage(
                    role: "tool",
                    content: msg.textContent,
                    toolCallID: msg.toolCallID
                ))
            case .system:
                // System messages are handled above
                break
            }
        }

        return messages
    }
}
