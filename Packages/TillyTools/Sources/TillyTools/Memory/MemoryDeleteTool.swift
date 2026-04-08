import Foundation
import TillyCore
import TillyStorage

public final class MemoryDeleteTool: ToolExecutable, @unchecked Sendable {
    private let service: MemoryService

    public init(service: MemoryService) { self.service = service }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "memory_delete",
                description: "Delete a stored memory by name. Use this when a memory is outdated or no longer relevant.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object([
                            "type": .string("string"),
                            "description": .string("The name of the memory to delete."),
                        ]),
                    ]),
                    "required": .array([.string("name")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable { let name: String }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments")
        }

        let args = try JSONDecoder().decode(Args.self, from: data)

        do {
            try service.delete(name: args.name)
            return ToolResult(content: "Memory '\(args.name)' deleted.")
        } catch {
            return ToolResult(content: "Failed to delete memory: \(error.localizedDescription)", isError: true)
        }
    }
}
