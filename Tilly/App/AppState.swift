import Foundation
import SwiftUI
import TillyCore
import TillyProviders
import TillyStorage
import TillyTools

@MainActor
@Observable
final class AppState {
    // MARK: - Provider Management
    var providerConfigs: [ProviderConfiguration] = ProviderConfiguration.defaults
    var selectedProviderID: ProviderID = .zaiCoding
    var selectedModelID: String = "glm-4-flash"
    var availableModels: [ModelInfo] = []
    var isLoadingModels: Bool = false

    // MARK: - Session Management
    var sessions: [Session] = []
    var currentSession: Session?
    var isStreaming: Bool = false
    private var streamTask: Task<Void, Never>?

    // MARK: - Tools
    let toolRegistry: ToolRegistry
    var toolsEnabled: Bool = true
    private let maxToolRounds = 10  // Safety limit on consecutive tool call rounds

    // MARK: - Services
    let keychainService = KeychainService()
    let memoryService = MemoryService()
    let skillService = SkillService()
    private var providers: [ProviderID: any LLMProvider] = [:]

    init() {
        toolRegistry = ToolRegistry.withBuiltinTools(
            memoryService: memoryService,
            skillService: skillService
        )
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
            systemPrompt: SystemPrompt(
                name: "Agent",
                content: buildDynamicSystemPrompt()
            ),
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

    // MARK: - Chat with Agent Loop

    func sendMessage(_ text: String) async {
        guard var session = currentSession, let provider = currentProvider else { return }

        // Add user message
        let userMessage = Message(role: .user, content: [.text(text)])
        session.appendMessage(userMessage)
        updateCurrentSession(session)

        isStreaming = true

        do {
            try await runAgentLoop(session: &session, provider: provider)
        } catch {
            if !(error is CancellationError) {
                let errorMessage = Message(
                    role: .assistant,
                    content: [.text("Error: \(error.localizedDescription)")]
                )
                session.appendMessage(errorMessage)
                updateCurrentSession(session)
            }
        }

        isStreaming = false

        // Auto-generate title from first exchange
        if session.messages.count <= 4 && session.title == "New Chat" {
            let title = String(text.prefix(50))
            session.title = title.count < text.count ? title + "..." : title
            updateCurrentSession(session)
        }
    }

    /// The core agent loop: stream -> detect tool calls -> execute -> repeat
    private func runAgentLoop(session: inout Session, provider: any LLMProvider) async throws {
        for round in 0..<maxToolRounds {
            let chatMessages = buildChatMessages(from: session)
            let tools = toolsEnabled ? toolRegistry.definitions : nil

            let request = ChatCompletionRequest(
                model: selectedModelID,
                messages: chatMessages,
                stream: true,
                tools: tools?.isEmpty == true ? nil : tools
            )

            let result = try await streamResponse(
                request: request,
                provider: provider,
                session: &session
            )

            // If the model returned tool calls, execute them and loop
            if !result.toolCalls.isEmpty {
                // Execute all tool calls
                for toolCall in result.toolCalls {
                    let toolResult = await executeToolCall(toolCall)

                    // Add tool result message to session
                    let toolMessage = Message(
                        role: .tool,
                        content: [.text(toolResult.content)],
                        toolCallID: toolCall.id
                    )
                    session.appendMessage(toolMessage)
                    updateCurrentSession(session)
                }

                // Continue the loop so the model can see tool results
                continue
            }

            // No tool calls - the model is done
            break
        }
    }

    /// Stream a single completion and return accumulated tool calls (if any).
    private func streamResponse(
        request: ChatCompletionRequest,
        provider: any LLMProvider,
        session: inout Session
    ) async throws -> StreamResult {
        var accumulatedText = ""
        var accumulatedToolCalls: [String: AccumulatingToolCall] = [:]
        var usage: StreamDelta.Usage?
        var finishReason: String?
        let startTime = Date()

        // Create assistant message placeholder
        var assistantMessage = Message(role: .assistant, content: [.text("")])
        session.appendMessage(assistantMessage)
        updateCurrentSession(session)
        let assistantIndex = session.messages.count - 1

        for try await delta in provider.stream(request) {
            if !isStreaming { throw CancellationError() }

            guard let choice = delta.choices?.first else {
                if let u = delta.usage { usage = u }
                continue
            }

            // Accumulate text content
            if let content = choice.delta.content {
                accumulatedText += content
                assistantMessage.content = [.text(accumulatedText)]
                session.messages[assistantIndex] = assistantMessage
                updateCurrentSession(session)
            }

            // Accumulate reasoning content (DeepSeek)
            if let reasoning = choice.delta.reasoningContent {
                // Show reasoning in a separate block or prefix
                accumulatedText += reasoning
                assistantMessage.content = [.text(accumulatedText)]
                session.messages[assistantIndex] = assistantMessage
                updateCurrentSession(session)
            }

            // Accumulate tool call deltas
            if let toolCallDeltas = choice.delta.toolCalls {
                for tcd in toolCallDeltas {
                    let key = "\(tcd.index)"
                    if accumulatedToolCalls[key] == nil {
                        accumulatedToolCalls[key] = AccumulatingToolCall(
                            id: tcd.id ?? "call_\(tcd.index)",
                            name: tcd.function?.name ?? "",
                            arguments: ""
                        )
                    }
                    if let name = tcd.function?.name, !name.isEmpty {
                        accumulatedToolCalls[key]?.name = name
                    }
                    if let id = tcd.id, !id.isEmpty {
                        accumulatedToolCalls[key]?.id = id
                    }
                    if let args = tcd.function?.arguments {
                        accumulatedToolCalls[key]?.arguments += args
                    }
                }
            }

            if let reason = choice.finishReason {
                finishReason = reason
            }
        }

        // Build final tool calls
        let toolCalls = accumulatedToolCalls.sorted(by: { $0.key < $1.key }).map { (_, acc) in
            ToolCall(
                id: acc.id,
                function: ToolCall.FunctionCall(name: acc.name, arguments: acc.arguments)
            )
        }

        // Finalize assistant message
        let latency = Int(Date().timeIntervalSince(startTime) * 1000)
        assistantMessage.metadata = MessageMetadata(
            model: selectedModelID,
            provider: selectedProviderID.rawValue,
            promptTokens: usage?.promptTokens,
            completionTokens: usage?.completionTokens,
            totalTokens: usage?.totalTokens,
            finishReason: finishReason,
            latencyMs: latency
        )
        assistantMessage.toolCalls = toolCalls.isEmpty ? nil : toolCalls
        session.messages[assistantIndex] = assistantMessage
        updateCurrentSession(session)

        return StreamResult(
            text: accumulatedText,
            toolCalls: toolCalls,
            finishReason: finishReason
        )
    }

    /// Execute a single tool call and return the result.
    private func executeToolCall(_ toolCall: ToolCall) async -> ToolResult {
        do {
            return try await toolRegistry.execute(toolCall: toolCall)
        } catch {
            return ToolResult(
                content: "Tool execution error: \(error.localizedDescription)",
                isError: true
            )
        }
    }

    func stopStreaming() {
        isStreaming = false
        streamTask?.cancel()
    }

    // MARK: - Message Building

    private func buildChatMessages(from session: Session) -> [ChatCompletionRequest.ChatMessage] {
        var messages: [ChatCompletionRequest.ChatMessage] = []

        // System prompt (rebuilt dynamically to include latest memory/skill context)
        let dynamicPrompt = buildDynamicSystemPrompt()
        messages.append(ChatCompletionRequest.ChatMessage(
            role: "system",
            content: dynamicPrompt
        ))

        for msg in session.messages {
            switch msg.role {
            case .user:
                messages.append(ChatCompletionRequest.ChatMessage(
                    role: "user",
                    content: msg.textContent
                ))
            case .assistant:
                messages.append(ChatCompletionRequest.ChatMessage(
                    role: "assistant",
                    content: msg.textContent.isEmpty ? nil : msg.textContent,
                    toolCalls: msg.toolCalls
                ))
            case .tool:
                messages.append(ChatCompletionRequest.ChatMessage(
                    role: "tool",
                    content: msg.textContent,
                    toolCallID: msg.toolCallID
                ))
            case .system:
                break
            }
        }

        return messages
    }

    // MARK: - Types

    private struct AccumulatingToolCall {
        var id: String
        var name: String
        var arguments: String
    }

    private struct StreamResult {
        let text: String
        let toolCalls: [ToolCall]
        let finishReason: String?
    }

    // MARK: - Dynamic System Prompt

    func buildDynamicSystemPrompt() -> String {
        let memoryIndex = memoryService.loadIndex()
        let skillIndex = skillService.loadIndex()

        return """
        You are Tilly, a powerful AI agent running as a native macOS application. You have direct access to the user's computer through tools, persistent memory across sessions, and a reusable skill library.

        ## Core Tools

        ### execute_command
        Run any shell command on macOS via /bin/zsh. Use for terminal commands, installing packages, compiling code, git operations, system administration.

        ### open_application
        Open macOS applications, files, or URLs. Use for launching apps (Finder, Safari, Xcode, etc.), opening files, or URLs.

        ### read_file
        Read file contents. Supports line ranges for large files.

        ### write_file
        Write or append to files. Creates parent directories automatically.

        ### list_directory
        List directory contents, optionally recursive.

        ### web_fetch
        Fetch and read web page content.

        ## Memory System

        You have persistent memory that survives across sessions. Use it proactively:

        - **memory_store**: Save important information (user preferences, project context, what works/doesn't)
        - **memory_search**: Search memories by keyword or type
        - **memory_list**: See all stored memories
        - **memory_delete**: Remove outdated memories

        Memory types: `user` (about the person), `feedback` (how they want you to work), `project` (current work context), `reference` (where to find things).

        **Save memories when you learn something worth remembering.** Don't wait to be asked.

        ### Known Memories
        \(memoryIndex)

        ## Skill Library

        Skills are saved workflows you can create and reuse:

        - **skill_create**: Save a new reusable workflow
        - **skill_run**: Execute a saved skill
        - **skill_list**: See available skills
        - **skill_delete**: Remove a skill

        **Create skills when you discover a useful multi-step workflow** the user might want to repeat.

        ### Available Skills
        \(skillIndex)

        ## Guidelines

        1. **Be proactive with tools.** Actually do things, don't just explain how.
        2. **Use memory.** When you learn user preferences, project patterns, or useful context - save it. When starting a task, check your memories.
        3. **Create skills.** When you complete a multi-step workflow the user might want again, offer to save it as a skill.
        4. **Read before modifying.** Always read files before editing them.
        5. **Handle errors gracefully.** If something fails, try an alternative.
        6. **Chain operations.** Break complex tasks into tool call steps.
        7. **Respect the system.** No destructive commands without explicit confirmation.
        """
    }
}
