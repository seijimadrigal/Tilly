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
    private enum DefaultsKey {
        static let selectedProviderID = "selectedProviderID"
        static let selectedModelID = "selectedModelID"
    }

    var providerConfigs: [ProviderConfiguration] = ProviderConfiguration.defaults
    var selectedProviderID: ProviderID = .zaiCoding
    var selectedModelID: String = "glm-5.1"
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
    private let maxToolRounds = 50

    // MARK: - Progress Visibility
    var agentRound: Int = 0
    var currentToolName: String?
    var currentToolSummary: String?

    // MARK: - Auth & Remote
    let authService = AuthService()
    let firebaseRelay = FirebaseRelay()
    var onStreamDelta: ((String) -> Void)?

    // MARK: - Services
    let keychainService = KeychainService()
    let memoryService = MemoryService()
    let skillService = SkillService()
    let sessionService = SessionService()
    let scratchpadService = ScratchpadService()
    private var providers: [ProviderID: any LLMProvider] = [:]

    init() {
        toolRegistry = ToolRegistry.withBuiltinTools(
            memoryService: memoryService,
            skillService: skillService,
            scratchpadService: scratchpadService
        )
        setupAskUserHandler()
        setupDelegateTaskHandler()
        setupKeychainHandler()
        setupFirebaseRelay()
        initializeProviders()
        loadSessions()
        restoreProviderSelection()
        authService.restoreSession()
    }

    // MARK: - Provider Selection Persistence

    private func restoreProviderSelection() {
        if let savedRaw = UserDefaults.standard.string(forKey: DefaultsKey.selectedProviderID),
           let saved = ProviderID(rawValue: savedRaw) {
            selectedProviderID = saved
        }
        if let savedModel = UserDefaults.standard.string(forKey: DefaultsKey.selectedModelID),
           !savedModel.isEmpty {
            selectedModelID = savedModel
        }
    }

    func saveProviderSelection() {
        UserDefaults.standard.set(selectedProviderID.rawValue, forKey: DefaultsKey.selectedProviderID)
        UserDefaults.standard.set(selectedModelID, forKey: DefaultsKey.selectedModelID)
        // Sync to Firebase for cross-device persistence
        firebaseRelay.syncSettings(providerID: selectedProviderID.rawValue, modelID: selectedModelID)
    }

    private func setupFirebaseRelay() {
        firebaseRelay.appState = self
        // Bridge streaming deltas to iOS via Firebase
        onStreamDelta = { [weak self] delta in
            self?.firebaseRelay.sendToiOS(
                RemoteMessage(type: .streamDelta, text: delta)
            )
        }
    }

    /// Called after sign-in to start the Firebase relay
    func onAuthStateChanged() {
        if let uid = authService.userID {
            firebaseRelay.start(userID: uid)
            // Sync settings to Firebase
            firebaseRelay.syncSettings(
                providerID: selectedProviderID.rawValue,
                modelID: selectedModelID
            )
        } else {
            firebaseRelay.stop()
        }
    }

    // MARK: - Sub-Agent Delegation

    private func setupKeychainHandler() {
        // Reuse the ask_user approval flow for keychain access
        toolRegistry.keychainPasswordTool?.approvalHandler = { [weak self] question, options in
            guard let self else { return "Denied" }
            return await self.showAskUserPopup(question: question, options: options)
        }
    }

    private func setupDelegateTaskHandler() {
        toolRegistry.delegateTaskTool?.handler = { [weak self] task, role, allowedTools, maxRounds in
            guard let self else { return "Sub-agent unavailable" }
            return await self.runSubAgent(task: task, role: role, allowedTools: allowedTools, maxRounds: maxRounds)
        }
    }

    private func runSubAgent(task: String, role: String, allowedTools: [String]?, maxRounds: Int) async -> String {
        guard let provider = currentProvider else {
            return "Error: No LLM provider configured"
        }

        // Build restricted tool set for the sub-agent
        let defaultToolNames = ["web_search", "web_fetch", "http_request", "read_file", "list_directory", "execute_command", "edit_file", "git", "scratchpad_write", "scratchpad_read"]
        let allowedNames = Set(allowedTools ?? defaultToolNames)

        // Get tools from registry by re-creating them (sub-agent gets its own instances)
        var subTools: [any ToolExecutable] = []
        if allowedNames.contains("execute_command") { subTools.append(ShellExecutor()) }
        if allowedNames.contains("read_file") { subTools.append(FileReadTool()) }
        if allowedNames.contains("write_file") { subTools.append(FileWriteTool()) }
        if allowedNames.contains("edit_file") { subTools.append(FileEditTool()) }
        if allowedNames.contains("list_directory") { subTools.append(DirectoryListTool()) }
        if allowedNames.contains("web_fetch") { subTools.append(WebFetchTool()) }
        if allowedNames.contains("web_search") { subTools.append(WebSearchTool()) }
        if allowedNames.contains("http_request") { subTools.append(HttpApiTool()) }
        if allowedNames.contains("git") { subTools.append(GitTool()) }
        if allowedNames.contains("open_application") { subTools.append(AppLauncher()) }
        if allowedNames.contains("scratchpad_write") { subTools.append(ScratchpadWriteTool(service: scratchpadService)) }
        if allowedNames.contains("scratchpad_read") { subTools.append(ScratchpadReadTool(service: scratchpadService)) }
        if allowedNames.contains("memory_store") { subTools.append(MemoryStoreTool(service: memoryService)) }
        if allowedNames.contains("memory_search") { subTools.append(MemorySearchTool(service: memoryService)) }

        let subPrompt = """
        You are a focused sub-agent with the role: \(role).

        You have been delegated a specific task by the main Tilly agent. Complete this task thoroughly and return a clear, well-structured result.

        CRITICAL: Respond directly. No internal reasoning. No meta-commentary. Just do the work and report results.

        You have access to these tools: \(subTools.map(\.definition.function.name).joined(separator: ", "))
        """

        let runner = SubAgentRunner(
            provider: provider,
            model: selectedModelID,
            tools: subTools,
            maxRounds: maxRounds,
            systemPrompt: subPrompt
        )

        do {
            return try await runner.run(task: task)
        } catch {
            return "Sub-agent error: \(error.localizedDescription)"
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
        firebaseRelay.sendToiOS(RemoteMessage(
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
        scratchpadService.clear()
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
        syncSessionToFirebase(session)
    }

    func selectSession(_ session: Session) {
        currentSession = session
    }

    func deleteSession(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        sessionService.delete(session.id)
        firebaseRelay.deleteSession(session.id)
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
        // NOTE: Firebase sync is NOT done here to avoid spamming on every streaming token.
        // Instead, syncSessionToFirebase() is called explicitly at key moments.
    }

    /// Sync current session to Firebase. Call after streaming ends, not during.
    func syncSessionToFirebase(_ session: Session) {
        firebaseRelay.syncSession(session)
        firebaseRelay.syncSessionIndex()
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
                DiagnosticLogger.shared.error("Agent loop error: \(error.localizedDescription)", detail: String(describing: error))
                let errorMessage = Message(
                    role: .assistant,
                    content: [.text("Error: \(error.localizedDescription)")]
                )
                session.appendMessage(errorMessage)
                updateCurrentSession(session)
            }
        }

        isStreaming = false

        // Sync completed session to Firebase + notify iOS
        if let session = currentSession {
            syncSessionToFirebase(session)
        }
        firebaseRelay.sendToiOS(RemoteMessage(type: .streamEnd))

        // Auto-generate title — on first exchange and again after 4+ messages for better context
        let needsTitle = session.title == "New Chat" ||
            (session.messages.count >= 4 && session.messages.count <= 6 && isGenericTitle(session.title))
        if needsTitle && session.messages.contains(where: { $0.role == .assistant && !$0.textContent.isEmpty }) {
            let sid = session.id
            Task { @MainActor [weak self] in
                await self?.generateSessionTitle(sessionID: sid)
            }
        }
    }

    /// The core agent loop: stream -> detect tool calls -> execute -> repeat
    private func runAgentLoop(session: inout Session, provider: any LLMProvider) async throws {
        agentRound = 0

        for round in 0..<maxToolRounds {
            agentRound = round + 1
            DiagnosticLogger.shared.agentRound(round + 1, maxRounds: maxToolRounds)

            // Checkpoint every 10 rounds
            if round > 0 && round % 10 == 0 {
                scratchpadService.append(
                    section: "Progress",
                    content: "Checkpoint at round \(round)/\(maxToolRounds)"
                )
            }

            let chatMessages = buildChatMessages(from: session)
            let tools = toolsEnabled ? toolRegistry.definitions : nil

            DiagnosticLogger.shared.llmRequest(
                model: selectedModelID,
                messageCount: chatMessages.count,
                toolCount: tools?.count ?? 0
            )

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

            DiagnosticLogger.shared.llmResponse(
                model: selectedModelID,
                tokens: result.usage?.totalTokens,
                latency: result.latencyMs,
                finishReason: result.finishReason
            )

            if !result.toolCalls.isEmpty {
                DiagnosticLogger.shared.log(.agent, "\(result.toolCalls.count) tool calls to execute")

                let toolCalls = result.toolCalls
                let registry = toolRegistry

                let toolResults: [(ToolCall, ToolResult)] = await withTaskGroup(
                    of: (ToolCall, ToolResult).self,
                    returning: [(ToolCall, ToolResult)].self
                ) { group in
                    for tc in toolCalls {
                        group.addTask {
                            let start = Date()
                            let result: ToolResult
                            do {
                                result = try await registry.execute(toolCall: tc)
                            } catch {
                                let errResult = ToolResult(content: "Tool error: \(error.localizedDescription)", isError: true)
                                await DiagnosticLogger.shared.error("Tool \(tc.function.name) threw: \(error.localizedDescription)")
                                return (tc, errResult)
                            }
                            let duration = Date().timeIntervalSince(start)
                            await DiagnosticLogger.shared.toolCall(
                                name: tc.function.name,
                                args: tc.function.arguments,
                                duration: duration,
                                resultSize: result.content.count
                            )
                            if result.isError {
                                await DiagnosticLogger.shared.error("Tool \(tc.function.name) returned error", detail: String(result.content.prefix(300)))
                            }
                            return (tc, result)
                        }
                    }
                    var results: [(ToolCall, ToolResult)] = []
                    for await pair in group { results.append(pair) }
                    return results
                }

                // Append results in original order
                for tc in toolCalls {
                    if let (_, toolResult) = toolResults.first(where: { $0.0.id == tc.id }) {
                        currentToolName = tc.function.name
                        currentToolSummary = extractToolSummary(tc)

                        let toolMessage = Message(
                            role: .tool,
                            content: [.text(toolResult.content)],
                            toolCallID: tc.id
                        )
                        session.appendMessage(toolMessage)
                        updateCurrentSession(session)
                    }
                }
                currentToolName = nil
                currentToolSummary = nil
                continue
            }

            break
        }
        agentRound = 0
        currentToolName = nil
        currentToolSummary = nil
    }

    /// Check if a title is too generic and should be regenerated with more context
    private func isGenericTitle(_ title: String) -> Bool {
        let lowered = title.lowercased()
        let generic = ["hello", "hi", "hey", "greeting", "chat", "new chat", "conversation", "help", "question", "request"]
        return generic.contains(where: { lowered.contains($0) }) || title.count < 8
    }

    /// Extract a brief summary from tool call arguments for progress display.
    private func extractToolSummary(_ toolCall: ToolCall) -> String {
        guard let data = toolCall.function.arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return toolCall.function.name
        }
        if let cmd = json["command"] as? String { return "$ \(String(cmd.prefix(60)))" }
        if let target = json["target"] as? String { return target }
        if let path = json["path"] as? String { return path }
        if let url = json["url"] as? String { return String(url.prefix(60)) }
        if let name = json["name"] as? String { return name }
        if let goal = json["goal"] as? String { return String(goal.prefix(60)) }
        return toolCall.function.name
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

        let latency = Int(Date().timeIntervalSince(startTime) * 1000)

        return StreamResult(
            text: accumulatedText,
            toolCalls: toolCalls,
            finishReason: finishReason,
            usage: usage,
            latencyMs: latency
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

        // Collect messages for context — include tool calls to understand the task
        let relevantMessages = session.messages.prefix(8).compactMap { msg -> ChatCompletionRequest.ChatMessage? in
            guard msg.role == .user || msg.role == .assistant else { return nil }
            let text = String(msg.textContent.prefix(300))
            guard !text.isEmpty else { return nil }
            return ChatCompletionRequest.ChatMessage(role: msg.role.rawValue, content: text)
        }

        guard !relevantMessages.isEmpty else { return }

        var titleMessages: [ChatCompletionRequest.ChatMessage] = [
            ChatCompletionRequest.ChatMessage(
                role: "system",
                content: """
                Generate a concise title (3-6 words) that describes the PROJECT or TASK in this conversation. Focus on WHAT is being done, not the greeting. Examples of good titles: "Setup Python Flask API", "Debug Xcode Build Error", "Research LLM Agent Patterns", "Clean Up Desktop Files". Return ONLY the title, nothing else. No quotes, no punctuation at the end, no explanations.
                """
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

        // Context compression: if estimated tokens exceed budget, prune old messages
        return compressIfNeeded(messages)
    }

    /// Estimate token count (~4 chars per token) and prune old messages if over budget.
    private func compressIfNeeded(_ messages: [ChatCompletionRequest.ChatMessage]) -> [ChatCompletionRequest.ChatMessage] {
        let contextBudget = 80_000  // Conservative budget for most models
        let threshold = contextBudget * 60 / 100  // Compress at 60%

        let totalChars = messages.reduce(0) { $0 + ($1.content?.count ?? 0) }
        let estimatedTokens = totalChars / 4

        guard estimatedTokens > threshold else { return messages }

        // Keep: system prompt (first), last 10 messages
        guard messages.count > 11 else { return messages }

        let systemPrompt = messages[0]
        let middleMessages = Array(messages[1..<(messages.count - 10)])
        let recentMessages = Array(messages.suffix(10))

        // Summarize the middle (oldest) messages
        let summary = middleMessages.prefix(20).compactMap { msg -> String? in
            guard let content = msg.content, !content.isEmpty else { return nil }
            let preview = String(content.prefix(100)).replacingOccurrences(of: "\n", with: " ")
            return "[\(msg.role)]: \(preview)"
        }.joined(separator: "\n")

        let compressionNote = ChatCompletionRequest.ChatMessage(
            role: "system",
            content: "[Context compressed: \(middleMessages.count) older messages summarized]\n\(summary)"
        )

        return [systemPrompt, compressionNote] + recentMessages
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
        let usage: StreamDelta.Usage?
        let latencyMs: Int?
    }

    // MARK: - Dynamic System Prompt

    func buildDynamicSystemPrompt() -> String {
        let memoryIndex = memoryService.loadIndex()
        let skillIndex = skillService.loadIndex()
        let scratchpad = scratchpadService.read()

        return """
        You are Tilly, a powerful AI agent running as a native macOS application. You have direct access to the user's computer through tools, persistent memory, a skill library, and working scratchpad.

        CRITICAL: Always respond directly to the user in a natural, conversational tone. NEVER write your internal thoughts, reasoning process, or meta-commentary in your response. Do NOT say things like "The user is asking...", "Let me think about...", "I should...", or narrate what you're doing. Just respond naturally as if you're talking to a friend. Your output goes directly to the user — they see everything you write.

        ## Tools

        **Execution**: execute_command (shell), open_application, background_run (non-blocking)
        **Files**: read_file, write_file, edit_file (find-and-replace), list_directory
        **Web**: web_search (DuckDuckGo), web_fetch (read page), http_request (GET/POST/PUT/DELETE with headers+body)
        **Browser**: browser (control Safari — navigate, read_page, run_javascript, click, type_text, list_tabs)
        **Git**: git (status/diff/log/add/commit/branch/checkout/push/pull/stash/clone)
        **System**: screenshot, clipboard (read/write), notify (macOS alerts), analyze_image (OCR + metadata)
        **Audio**: audio (speak text aloud, play audio files, list voices)
        **Advanced**: create_tool (write custom Python/Bash/Node scripts that persist), mcp (connect to MCP servers for external tools)

        Set timeout on execute_command: 10 quick, 60 normal, 300 builds, 600 large ops, 900 docker/clone.

        ## Working Scratchpad (Session Memory)
        Your working memory for the current task. Use it to stay organized during complex work.
        - **scratchpad_write**: Write/append sections (Plan, Progress, Findings, Notes)
        - **scratchpad_read**: Read current scratchpad
        - **plan_task**: Create a structured plan with numbered steps

        ### Current Scratchpad
        \(scratchpad.isEmpty ? "(empty — use plan_task to start)" : scratchpad)

        ## Persistent Memory (Cross-Session)
        - **memory_store**: Save info (types: user, feedback, project, reference)
        - **memory_search**: Search by keyword/type
        - **memory_list** / **memory_delete**: Manage memories

        IMPORTANT — You MUST save memories in these situations:
        - User tells you their name, job, preferences, or how they like to work → type: user
        - User corrects you or gives feedback on your approach → type: feedback
        - You discover project details (tech stack, file structure, goals) → type: project
        - You find useful URLs, docs, or references → type: reference
        Do this AUTOMATICALLY after learning the information. Don't ask permission. Don't wait. Just save it.

        ### Known Memories
        \(memoryIndex)

        ## Skill Library
        - **skill_create** / **skill_run** / **skill_list** / **skill_delete**

        ### Available Skills
        \(skillIndex)

        ## User Interaction
        - **ask_user**: Ask the user a question with 3 options when unsure.

        ## Sub-Agent Delegation
        - **delegate_task**: Spawn a child agent to handle a sub-task independently. The child runs its own tool loop and returns results. Use this for:
          - Research tasks: delegate web research while you work on implementation
          - File analysis: delegate reading/exploring a codebase
          - Parallel work: split a complex task into parts
          - Specialized roles: "code reviewer", "researcher", "documentation writer"
        The child cannot see this conversation. Give it complete, self-contained instructions.

        ## Guidelines

        1. **Plan before executing.** For tasks needing 3+ tool calls, use plan_task first.
        2. **Be proactive.** Actually do things, don't explain how.
        3. **Use the scratchpad.** Track progress, record findings, update your plan.
        4. **Save memories.** When you learn user preferences, project context, or feedback — save it immediately.
        5. **Ask when unsure.** Use ask_user for ambiguity or before destructive actions.
        6. **Read before modifying.** Always read files before editing.
        7. **Handle errors gracefully.** Try alternatives on failure.
        8. **No destructive commands without confirmation.**

        ## Self-Improvement
        After completing a multi-step task (5+ tool calls):
        1. If the workflow was useful and reusable, save it as a skill (skill_create).
        2. Store what worked/didn't as a feedback memory (memory_store, type: feedback).
        3. Only do this for genuinely reusable patterns, not one-off tasks.
        """
    }
}
