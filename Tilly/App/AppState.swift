import Foundation
import SwiftUI
import TillyCore
import TillyProviders
import TillyStorage
import TillyTools
#if os(macOS)
import Security
#endif

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

    // MARK: - Detail Panel Routing
    enum DetailViewTarget: Equatable {
        case chat
        case memoryDetail(MemoryEntry)
        case skillDetail(SkillEntry)
        case credentialDetail(KeychainCredential)
    }
    var detailTarget: DetailViewTarget = .chat

    func showChat() { detailTarget = .chat }

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

    /// Core tools always sent to LLM. Extended tools omitted when context is large.
    private let coreToolNames: Set<String> = [
        "execute_command", "read_file", "write_file", "edit_file", "list_directory",
        "web_search", "web_fetch", "http_request", "git",
        "memory_store", "memory_search", "skill_run", "ask_user",
        "scratchpad_write", "scratchpad_read", "delegate_task",
    ]

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
        setupSkillChainHandler()
        setupSkillPlanHandler()
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

    private func setupSkillChainHandler() {
        toolRegistry.skillChainTool?.runSkillHandler = { [weak self] skillName, context in
            guard let self else { return "Chain unavailable" }
            return await self.runSkillInChain(skillName: skillName, context: context)
        }
    }

    private func runSkillInChain(skillName: String, context: String) async -> String {
        guard let provider = currentProvider else { return "No provider" }

        let skill: SkillEntry
        do {
            skill = try skillService.load(name: skillName)
        } catch {
            return "Skill not found: \(skillName)"
        }

        let taskPrompt = """
        Execute the following skill with the given context.

        ## Skill: \(skill.name)
        \(skill.instructions)

        ## Context
        \(context)

        Complete the skill's instructions using the available tools and return a clear result.
        """

        let subTools: [any ToolExecutable] = [
            ShellExecutor(), FileReadTool(), FileWriteTool(), FileEditTool(),
            DirectoryListTool(), WebFetchTool(), WebSearchTool(), HttpApiTool(),
            ScratchpadWriteTool(service: scratchpadService), ScratchpadReadTool(service: scratchpadService),
        ]

        let runner = SubAgentRunner(
            provider: provider,
            model: selectedModelID,
            tools: subTools,
            maxRounds: 15,
            systemPrompt: "You are a focused skill executor. Follow the skill instructions precisely and return a clear result. No meta-commentary."
        )

        do {
            return try await runner.run(task: taskPrompt)
        } catch {
            return "Skill execution error: \(error.localizedDescription)"
        }
    }

    private func setupSkillPlanHandler() {
        toolRegistry.skillPlanTool?.planHandler = { [weak self] task, catalog in
            guard let self else { return "Planning unavailable" }
            return await self.runSkillPlanner(task: task, catalog: catalog)
        }
    }

    private func runSkillPlanner(task: String, catalog: String) async -> String {
        guard let provider = currentProvider else { return "No provider" }

        let plannerPrompt = """
        You are a skill planning specialist for the Tilly AI agent. Given a task and a catalog of available skills, recommend the optimal chain of skills to accomplish the task.

        For each recommended skill, explain:
        1. Why this skill is needed for this step
        2. What inputs it needs and where they come from
        3. What outputs it produces for downstream skills

        Also identify:
        - Missing prerequisites (credentials, API keys, missing tools)
        - Gaps where no existing skill covers a needed step
        - Alternative approaches if the primary chain might fail

        Format your response as:
        ## Recommended Chain
        1. **Skill Name** (id) — reason
           Inputs: ... → Outputs: ...

        ## Prerequisites
        - List any credentials or setup needed

        ## Gaps
        - Steps where no skill exists

        ## Reasoning
        Brief explanation of why this chain is optimal.
        """

        let runner = SubAgentRunner(
            provider: provider,
            model: selectedModelID,
            tools: [],  // Pure reasoning, no tools needed
            maxRounds: 1,
            systemPrompt: plannerPrompt
        )

        do {
            return try await runner.run(task: "Task: \(task)\n\n\(catalog)")
        } catch {
            return "Planning error: \(error.localizedDescription)"
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

            // Smart tool selection: send fewer tools when context is large
            let tools: [ToolDefinition]?
            if toolsEnabled {
                let estimatedTokens = chatMessages.reduce(0) { $0 + ($1.content?.count ?? 0) } / 4
                if estimatedTokens > 40_000 {
                    // Context is large — send only core tools to save space
                    tools = toolRegistry.definitions.filter { coreToolNames.contains($0.function.name) }
                } else {
                    tools = toolRegistry.definitions
                }
            } else {
                tools = nil
            }

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

            let result: StreamResult
            do {
                result = try await streamResponse(
                    request: request,
                    provider: provider,
                    session: &session
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // LLM error (HTTP 400, rate limit, etc.) — don't kill the entire loop
                DiagnosticLogger.shared.error("LLM error in round \(round + 1): \(error.localizedDescription)")

                let errorMsg = Message(
                    role: .assistant,
                    content: [.text("Error communicating with the model: \(error.localizedDescription)\n\nThis can happen when the conversation is too long. Try starting a new chat.")]
                )
                session.appendMessage(errorMsg)
                updateCurrentSession(session)
                break  // Exit loop gracefully instead of crashing
            }

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
                                DiagnosticLogger.shared.error("Tool \(tc.function.name) threw: \(error.localizedDescription)")
                                return (tc, errResult)
                            }
                            let duration = Date().timeIntervalSince(start)
                            DiagnosticLogger.shared.toolCall(
                                name: tc.function.name,
                                args: tc.function.arguments,
                                duration: duration,
                                resultSize: result.content.count
                            )
                            if result.isError {
                                DiagnosticLogger.shared.error("Tool \(tc.function.name) returned error", detail: String(result.content.prefix(300)))
                            }
                            return (tc, result)
                        }
                    }
                    var results: [(ToolCall, ToolResult)] = []
                    for await pair in group { results.append(pair) }
                    return results
                }

                // Append results in original order — offload large results to files
                for tc in toolCalls {
                    if let (_, toolResult) = toolResults.first(where: { $0.0.id == tc.id }) {
                        currentToolName = tc.function.name
                        currentToolSummary = extractToolSummary(tc)

                        let trimmedResult = offloadIfLarge(toolResult, callID: tc.id)
                        let toolMessage = Message(
                            role: .tool,
                            content: [.text(trimmedResult.content)],
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
    /// Offload large tool results to file, keep only a preview in the message history.
    /// This prevents context overflow from web_fetch, execute_command, etc.
    private func offloadIfLarge(_ result: ToolResult, callID: String) -> ToolResult {
        let maxInline = 1500
        guard result.content.count > maxInline else { return result }

        let path = "/tmp/tilly-tool-\(callID.prefix(8)).txt"
        try? result.content.write(toFile: path, atomically: true, encoding: .utf8)

        let preview = String(result.content.prefix(500))
            .replacingOccurrences(of: "\n", with: " ")
        let replacement = "[Full output saved: \(path) (\(result.content.count) chars)]\n\(preview)..."
        DiagnosticLogger.shared.log(.system, "Offloaded \(result.content.count) chars to \(path)")
        return ToolResult(content: replacement, isError: result.isError)
    }

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
    /// Dual-threshold context compression (Hermes pattern).
    /// Soft at 30% (~24K tokens): summarize old tool results.
    /// Hard at 50% (~40K tokens): full prune to last 6 messages.
    private func compressIfNeeded(_ messages: [ChatCompletionRequest.ChatMessage]) -> [ChatCompletionRequest.ChatMessage] {
        let totalChars = messages.reduce(0) { $0 + ($1.content?.count ?? 0) }
        let estimatedTokens = totalChars / 4

        let softThreshold = 24_000   // 30% of 80K budget — summarize tool results
        let hardThreshold = 40_000   // 50% of 80K budget — full compression

        guard messages.count > 3 else { return messages }

        // --- Hard compression: keep system + last 6, summarize everything else ---
        if estimatedTokens > hardThreshold {
            DiagnosticLogger.shared.log(.system, "Hard compression: \(estimatedTokens) tokens → keeping last 6 msgs")

            let systemPrompt = messages[0]
            let keepCount = min(6, messages.count - 1)
            let recentMessages = Array(messages.suffix(keepCount))
            let prunedCount = messages.count - 1 - keepCount

            let compressionNote = ChatCompletionRequest.ChatMessage(
                role: "system",
                content: "[Context compressed: \(prunedCount) older messages removed to fit context window. Use scratchpad_read and memory_search to recover context if needed.]"
            )

            return [systemPrompt, compressionNote] + recentMessages
        }

        // --- Soft compression: truncate old tool results to 1 line each ---
        if estimatedTokens > softThreshold {
            DiagnosticLogger.shared.log(.system, "Soft compression: \(estimatedTokens) tokens → trimming old tool results")

            let protectedTail = 8
            guard messages.count > protectedTail + 1 else { return messages }

            var compressed = [messages[0]]  // System prompt

            // Process middle messages — trim tool results
            let middleEnd = messages.count - protectedTail
            for i in 1..<middleEnd {
                let msg = messages[i]
                if msg.role == "tool", let content = msg.content, content.count > 200 {
                    // Replace verbose tool result with 1-line summary
                    let preview = String(content.prefix(100)).replacingOccurrences(of: "\n", with: " ")
                    compressed.append(ChatCompletionRequest.ChatMessage(
                        role: "tool",
                        content: "[trimmed] \(preview)...",
                        toolCallID: msg.toolCallID
                    ))
                } else {
                    compressed.append(msg)
                }
            }

            // Keep recent messages untouched
            compressed.append(contentsOf: messages.suffix(protectedTail))
            return compressed
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
        let usage: StreamDelta.Usage?
        let latencyMs: Int?
    }

    // MARK: - Dynamic System Prompt

    // MARK: - Credential Listing (Keychain)

    #if os(macOS)
    func listCredentials() -> [KeychainCredential] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return [] }

        return items.compactMap { item in
            let server = item[kSecAttrServer as String] as? String ?? ""
            let account = item[kSecAttrAccount as String] as? String ?? ""
            let label = item[kSecAttrLabel as String] as? String ?? server
            guard !server.isEmpty || !account.isEmpty else { return nil }
            return KeychainCredential(label: label, server: server, account: account)
        }.sorted { $0.label < $1.label }
    }
    #endif

    func buildDynamicSystemPrompt() -> String {
        // Only show recent memories/skills to save tokens
        let allMemories = (try? memoryService.list()) ?? []
        let recentMemories = allMemories.suffix(3).map(\.indexLine).joined(separator: "\n")
        let memoryCount = allMemories.count

        let allSkills = (try? skillService.list()) ?? []
        let recentSkills = allSkills.suffix(3).map(\.indexLine).joined(separator: "\n")
        let skillCount = allSkills.count

        let scratchpad = String(scratchpadService.read().prefix(800))

        return """
        You are Tilly, an AI agent on macOS with full computer access via tools. Respond naturally — NEVER narrate your thinking.

        You have \(toolRegistry.definitions.count) tools (see tool definitions). Key ones: execute_command, read/write/edit_file, web_search, web_fetch, http_request, git, browser, screenshot, clipboard, memory_store/search, skill_run/chain/test/plan, delegate_task, ask_user, scratchpad_write/read, plan_task.

        Set timeout on execute_command: 10 quick, 60 normal, 300 builds, 600 large, 900 docker.
        Large tool results are auto-saved to /tmp/tilly-tool-*.txt — use read_file to access full output.

        **Scratchpad** (session working memory):
        \(scratchpad.isEmpty ? "(empty)" : scratchpad)

        **Memory** (\(memoryCount) total — use memory_search for more):
        \(recentMemories.isEmpty ? "(none)" : recentMemories)
        Save memories AUTOMATICALLY: user prefs → user, feedback → feedback, project details → project, URLs → reference.

        **Skills** (\(skillCount) total — use skill_list for more):
        \(recentSkills.isEmpty ? "(none)" : recentSkills)

        **Documents & Reports**: When generating reports, analyses, or documents:
        1. ALWAYS use write_file to save the document to the user's Desktop (~/Desktop/) as .md, .txt, .html, or .pdf
        2. Tell the user where the file was saved so they can open it
        3. For short responses (under 500 words), write inline. For longer content, ALWAYS save to a file.
        4. Use open_application to open the file after saving if appropriate.

        **Rules**: Plan before 3+ tool calls. Be proactive. Use scratchpad. Save memories. Ask when unsure. Read before editing. No destructive commands without confirmation. After multi-step tasks, save reusable workflows as skills.
        """
    }
}
