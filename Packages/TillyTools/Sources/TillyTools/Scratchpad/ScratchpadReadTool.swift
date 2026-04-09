import Foundation
import TillyCore
import TillyStorage

public final class ScratchpadReadTool: ToolExecutable, @unchecked Sendable {
    private let service: ScratchpadService
    public init(service: ScratchpadService) { self.service = service }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "scratchpad_read",
                description: "Read the current contents of your working scratchpad. Contains your plans, progress, findings, and notes for the current session.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        let content = service.read()
        if content.isEmpty {
            return ToolResult(content: "(Scratchpad is empty. Use scratchpad_write to start organizing your work.)")
        }
        return ToolResult(content: content)
    }
}
