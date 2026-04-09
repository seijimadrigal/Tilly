import Foundation
import TillyCore
import TillyStorage

public final class ToolRegistry: @unchecked Sendable {
    private var tools: [String: any ToolExecutable] = [:]

    /// The ask_user tool instance, exposed so the UI can set its handler.
    public private(set) var askUserTool: AskUserTool?

    /// The delegate_task tool instance, exposed so AppState can set its handler.
    public private(set) var delegateTaskTool: DelegateTaskTool?

    public init() {}

    public func register(_ tool: any ToolExecutable) {
        tools[tool.definition.function.name] = tool
    }

    public var definitions: [ToolDefinition] {
        tools.values.map(\.definition)
    }

    public func execute(toolCall: ToolCall) async throws -> ToolResult {
        guard let tool = tools[toolCall.function.name] else {
            throw TillyError.unknownTool(toolCall.function.name)
        }
        return try await tool.execute(arguments: toolCall.function.arguments)
    }

    /// Creates a registry with all built-in tools pre-registered.
    public static func withBuiltinTools(
        memoryService: MemoryService = MemoryService(),
        skillService: SkillService = SkillService(),
        scratchpadService: ScratchpadService = ScratchpadService()
    ) -> ToolRegistry {
        let registry = ToolRegistry()

        // Core tools
        registry.register(ShellExecutor())
        registry.register(AppLauncher())
        registry.register(FileReadTool())
        registry.register(FileWriteTool())
        registry.register(FileEditTool())
        registry.register(DirectoryListTool())
        registry.register(WebFetchTool())
        registry.register(WebSearchTool())
        registry.register(HttpApiTool())
        registry.register(GitTool())
        registry.register(BackgroundTaskTool())
        registry.register(ScreenshotTool())
        registry.register(ClipboardTool())
        registry.register(NotificationTool())

        // Memory tools
        registry.register(MemoryStoreTool(service: memoryService))
        registry.register(MemorySearchTool(service: memoryService))
        registry.register(MemoryListTool(service: memoryService))
        registry.register(MemoryDeleteTool(service: memoryService))

        // Skill tools
        registry.register(SkillCreateTool(service: skillService))
        registry.register(SkillListTool(service: skillService))
        registry.register(SkillRunTool(service: skillService))
        registry.register(SkillDeleteTool(service: skillService))

        // Scratchpad / planning tools
        registry.register(ScratchpadWriteTool(service: scratchpadService))
        registry.register(ScratchpadReadTool(service: scratchpadService))
        registry.register(PlanTaskTool(service: scratchpadService))

        // Browser, vision, audio, MCP, custom tools
        registry.register(BrowserTool())
        registry.register(VisionTool())
        registry.register(AudioTool())
        registry.register(MCPClientTool())
        registry.register(CreateToolTool())

        // User interaction
        let askUser = AskUserTool()
        registry.register(askUser)
        registry.askUserTool = askUser

        // Sub-agent delegation
        let delegateTask = DelegateTaskTool()
        registry.register(delegateTask)
        registry.delegateTaskTool = delegateTask

        return registry
    }
}
