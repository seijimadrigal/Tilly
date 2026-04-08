import Foundation
import TillyCore
import TillyStorage

public final class MemoryListTool: ToolExecutable, @unchecked Sendable {
    private let service: MemoryService

    public init(service: MemoryService) { self.service = service }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "memory_list",
                description: "List all stored memories. Returns the memory index showing all saved memories with their types and summaries.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        let index = service.loadIndex()
        return ToolResult(content: "Stored memories:\n\n\(index)")
    }
}
