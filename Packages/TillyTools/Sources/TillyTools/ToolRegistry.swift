import Foundation
import TillyCore
import TillyStorage

public final class ToolRegistry: @unchecked Sendable {
    private var tools: [String: any ToolExecutable] = [:]

    /// The ask_user tool instance, exposed so the UI can set its handler.
    public private(set) var askUserTool: AskUserTool?

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
        skillService: SkillService = SkillService()
    ) -> ToolRegistry {
        let registry = ToolRegistry()

        // Core tools
        registry.register(ShellExecutor())
        registry.register(AppLauncher())
        registry.register(FileReadTool())
        registry.register(FileWriteTool())
        registry.register(DirectoryListTool())
        registry.register(WebFetchTool())

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

        // User interaction
        let askUser = AskUserTool()
        registry.register(askUser)
        registry.askUserTool = askUser

        return registry
    }
}
