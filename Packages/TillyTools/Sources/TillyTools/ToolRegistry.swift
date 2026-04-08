import Foundation
import TillyCore

public final class ToolRegistry: @unchecked Sendable {
    private var tools: [String: any ToolExecutable] = [:]

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
    public static func withBuiltinTools() -> ToolRegistry {
        let registry = ToolRegistry()
        registry.register(ShellExecutor())
        registry.register(AppLauncher())
        registry.register(FileReadTool())
        registry.register(FileWriteTool())
        registry.register(DirectoryListTool())
        registry.register(WebFetchTool())
        return registry
    }
}
