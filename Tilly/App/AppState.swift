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

    // MARK: - Ask User Dialog State
    var showAskUserDialog: Bool = false
    var askUserQuestion: String = ""
    var askUserOptions: [String] = []
    private var askUserContinuation: CheckedContinuation<String, Never>?

    // MARK: - Tools
    let toolRegistry: ToolRegistry
    var toolsEnabled: Bool = true
    private let maxToolRounds = 15

    // MARK: - Remote Control
    let remoteServer = RemoteServer()
    var onStreamDelta: ((String) -> Void)?

    // MARK: - Services
    let keychainService = KeychainService()
    let memoryService = MemoryService()
    let skillService = SkillService()
    let sessionService = SessionService()
    private var providers: [ProviderID: any LLMProvider] = [:]

    init() {
        toolRegistry = ToolRegistry.withBuiltinTools(
            memoryService: memoryService,
            skillService: skillService
        )
        setupAskUserHandler()
        setupRemoteServer()
        initializeProviders()
        loadSessions()
    }

    private func setupRemoteServer() {
        remoteServer.appState = self
        remoteServer.start()
        // Bridge streaming deltas to connected iOS clients
        onStreamDelta = { [weak self] delta in
            self?.remoteServer.broadcast(
                RemoteMessage(type: .streamDelta, text: delta)
            )
        }
    }

    // MARK: - Ask User Handler

    private func setupAskUserHandler() {
        toolRegistry.askUserTool?.handler = { [weak self] question, options in
            guard let self else { return "Proceed with best judgment" }
            return await self.showAskUserPopup(question: question, options: options)
        }
    }

    private func showAskUserPopup(question: String, options: [String]) async -> String {
        // Also broadcast to iOS clients
        remoteServer.broadcast(RemoteMessage(
            type: .askUser,
            text: question,
            options: options
        ))

        return await withCheckedContinuation { continuation in
            self.askUserQuestion = question
            self.askUserOptions = options
            self.askUserContinuation = continuation
            self.showAskUserDialog = true
        }
    }

    func respondToAskUser(choice: String) {
        showAskUserDialog = false
        askUserContinuation?.resume(returning: choice)
        askUserContinuation = nil
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

    // MARK: - Session Management (with persistence)

    func loadSessions() {
        let loaded = sessionService.loadAll()
        if loaded.isEmpty {
            createNewSession()
        } else {
            sessions = loaded
            currentSession = sessions.first
        }
    }

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
        sessionService.save(session)
    }

    func selectSession(_ session: Session) {
        currentSession = session
    }

    func deleteSession(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        sessionService.delete(session.id)
        if currentSession?.id == session.id {
            currentSession = sessions.first
            if currentSession == nil {
                createNewSession()
            }
        }
    }

    func updateCurrentSession(_ session: Session) {
        currentSession = session
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
        // Auto-persist to disk
        sessionService.save(session)
    }

    // MARK: - Chat with Agent Loop

    func sendMessage(_ text: String) async {
        await sendMessageWithAttachments(text, attachments: [])
    }

    func sendMessageWithAttachments(_ text: String, attachments: [AttachmentItem]) async {
        guard var session = currentSession, let provider = currentProvider else { return }

        // Build content blocks from text + attachments
        var contentBlocks: [ContentBlock] = []
        if !text.isEmpty {
            contentBlocks.append(.text(text))
        }
        for attachment in attachments {
            switch attachment.type {
            case .image:
                contentBlocks.append(.image(data: attachment.data, mimeType: attachment.mimeType))
            case .video, .audio, .file:
                contentBlocks.append(.fileReference(FileAttachment(
                    fileName: attachment.name,
                    filePath: attachment.filePath ?? "",
                    mimeType: attachment.mimeType,
                    sizeBytes: attachment.fileSize
                )))
            }
        }

        if contentBlocks.isEmpty { return }

        let userMessage = Message(role: .user, content: contentBlocks)
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

        // Notify remote clients that streaming is done
        remoteServer.broadcast(RemoteMessage(type: .streamEnd))
        if let session = currentSession {
            remoteServer.broadcast(RemoteMessage(type: .fullSession, session: session))
        }

        // Auto-generate title via LLM after first exchange
        if session.title == "New Chat" &&
           session.messages.contains(where: { $0.role == .assistant && !$0.textContent.isEmpty }) {
            let sid = session.id
            Task { @MainActor [weak self] in
                await self?.generateSessionTitle(sessionID: sid)
            }
        }
    }

    /// The core agent loop: stream -> detect tool calls -> execute -> repeat
    private func runAgentLoop(session: inout Session, provider: any LLMProvider) async throws {
        for _ in 0..<maxToolRounds {
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

            if !result.toolCalls.isEmpty {
                for toolCall in result.toolCalls {
                    let toolResult = await executeToolCall(toolCall)

                    let toolMessage = Message(
                        role: .tool,
                        content: [.text(toolResult.content)],
                        toolCallID: toolCall.id
                    )
                    session.appendMessage(toolMessage)
                    updateCurrentSession(session)
                }
                continue
            }

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

            if let content = choice.delta.content {
                accumulatedText += content
                assistantMessage.content = [.text(accumulatedText)]
                session.messages[assistantIndex] = assistantMessage
                updateCurrentSession(session)
                onStreamDelta?(content)
            }

            if let reasoning = choice.delta.reasoningContent {
                accumulatedText += reasoning
                assistantMessage.content = [.text(accumulatedText)]
                session.messages[assistantIndex] = assistantMessage
                updateCurrentSession(session)
            }

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

        let toolCalls = accumulatedToolCalls.sorted(by: { $0.key < $1.key }).map { (_, acc) in
            ToolCall(
                id: acc.id,
                function: ToolCall.FunctionCall(name: acc.name, arguments: acc.arguments)
            )
        }

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

    // MARK: - Session Title Generation

    private func generateSessionTitle(sessionID: UUID) async {
        guard let provider = currentProvider,
              let idx = sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        let session = sessions[idx]

        // Collect first few messages for context
        let relevantMessages = session.messages.prefix(4).compactMap { msg -> ChatCompletionRequest.ChatMessage? in
            guard msg.role == .user || msg.role == .assistant else { return nil }
            let text = String(msg.textContent.prefix(200))
            guard !text.isEmpty else { return nil }
            return ChatCompletionRequest.ChatMessage(role: msg.role.rawValue, content: text)
        }

        guard !relevantMessages.isEmpty else { return }

        var titleMessages: [ChatCompletionRequest.ChatMessage] = [
            ChatCompletionRequest.ChatMessage(
                role: "system",
                content: "Generate a short title (4-7 words) for this conversation. Return ONLY the title text, nothing else. No quotes. No punctuation at the end."
            )
        ]
        titleMessages.append(contentsOf: relevantMessages)

        let request = ChatCompletionRequest(
            model: selectedModelID,
            messages: titleMessages,
            temperature: 0.3,
            maxTokens: 30,
            stream: false,
            streamOptions: nil,
            tools: nil
        )

        do {
            let response = try await provider.complete(request)
            if let title = response.choices.first?.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
               !title.isEmpty {
                sessions[idx].title = String(title.prefix(60))
                if currentSession?.id == sessionID {
                    currentSession = sessions[idx]
                }
                sessionService.save(sessions[idx])
            }
        } catch {
            // Fallback: use first user message truncated
            if let firstText = session.messages.first(where: { $0.role == .user })?.textContent {
                let fallback = String(firstText.prefix(50))
                sessions[idx].title = fallback.count < firstText.count ? fallback + "..." : fallback
                if currentSession?.id == sessionID {
                    currentSession = sessions[idx]
                }
                sessionService.save(sessions[idx])
            }
        }
    }

    // MARK: - Message Building

    private func buildChatMessages(from session: Session) -> [ChatCompletionRequest.ChatMessage] {
        var messages: [ChatCompletionRequest.ChatMessage] = []

        let dynamicPrompt = buildDynamicSystemPrompt()
        messages.append(ChatCompletionRequest.ChatMessage(
            role: "system",
            content: dynamicPrompt
        ))

        for msg in session.messages {
            switch msg.role {
            case .user:
                // Build user content including file/image descriptions
                var userContent = msg.textContent
                for block in msg.content {
                    switch block {
                    case .image(_, let mimeType):
                        userContent += "\n[Attached image: \(mimeType)]"
                    case .fileReference(let file):
                        userContent += "\n[Attached file: \(file.fileName) (\(file.mimeType), \(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file)))]"
                        // If it's a text-based file, include its content
                        if file.mimeType.hasPrefix("text/") || ["swift", "py", "js", "ts", "json", "md", "yaml", "yml", "toml", "xml", "html", "css", "sh", "bash", "zsh", "c", "cpp", "h", "rs", "go", "java", "kt", "rb"].contains(URL(fileURLWithPath: file.filePath).pathExtension.lowercased()) {
                            if let fileContent = try? String(contentsOfFile: file.filePath, encoding: .utf8) {
                                let truncated = String(fileContent.prefix(8000))
                                userContent += "\n```\n\(truncated)\n```"
                            }
                        }
                    case .text:
                        break
                    }
                }
                messages.append(ChatCompletionRequest.ChatMessage(
                    role: "user",
                    content: userContent
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
        Run any shell command on macOS via /bin/zsh.

        ### open_application
        Open macOS applications, files, or URLs.

        ### read_file
        Read file contents with optional line range.

        ### write_file
        Write or append to files.

        ### list_directory
        List directory contents.

        ### web_fetch
        Fetch and read web page content.

        ## Memory System

        You have persistent memory that survives across sessions.

        - **memory_store**: Save information (user preferences, project context, feedback)
        - **memory_search**: Search memories by keyword or type
        - **memory_list**: See all stored memories
        - **memory_delete**: Remove outdated memories

        Memory types: `user`, `feedback`, `project`, `reference`.

        **IMPORTANT: Proactively save memories when you learn something about the user, their preferences, their projects, or receive feedback. Do this automatically without being asked.**

        ### Known Memories
        \(memoryIndex)

        ## Skill Library

        - **skill_create**: Save a reusable workflow
        - **skill_run**: Execute a saved skill
        - **skill_list**: See available skills
        - **skill_delete**: Remove a skill

        ### Available Skills
        \(skillIndex)

        ## Ask User

        - **ask_user**: When you are unsure how to proceed, use this tool to ask the user a question with 3 options. Use this for:
          - Ambiguous requests where multiple approaches are possible
          - Before destructive or irreversible actions
          - When you need user preference or confirmation
          - When a task could go multiple directions

        ## Guidelines

        1. **Be proactive with tools.** Actually do things, don't explain how.
        2. **Save memories automatically.** When you learn something worth remembering, use memory_store immediately.
        3. **Ask when unsure.** Use ask_user when you face ambiguity or need confirmation.
        4. **Read before modifying.** Always read files before editing.
        5. **Handle errors gracefully.** Try alternatives on failure.
        6. **No destructive commands without confirmation.** Use ask_user first.
        """
    }
}
