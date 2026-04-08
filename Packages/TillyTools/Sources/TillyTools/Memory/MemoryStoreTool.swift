import Foundation
import TillyCore
import TillyStorage

public final class MemoryStoreTool: ToolExecutable, @unchecked Sendable {
    private let service: MemoryService

    public init(service: MemoryService) { self.service = service }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "memory_store",
                description: "Save a persistent memory that will be available across all future sessions. Use this to remember user preferences, project context, important decisions, and feedback about what approaches work. Memories persist even after the app is closed.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object([
                            "type": .string("string"),
                            "description": .string("Short descriptive name for this memory (e.g., 'User prefers Swift')."),
                        ]),
                        "memory_type": .object([
                            "type": .string("string"),
                            "enum": .array([.string("user"), .string("feedback"), .string("project"), .string("reference")]),
                            "description": .string("Category: 'user' (about the person), 'feedback' (how to work), 'project' (current work context), 'reference' (where to find things)."),
                        ]),
                        "content": .object([
                            "type": .string("string"),
                            "description": .string("The memory content. Be specific and include context about why this matters."),
                        ]),
                    ]),
                    "required": .array([.string("name"), .string("memory_type"), .string("content")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let name: String
            let memory_type: String
            let content: String
        }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments")
        }

        let args = try JSONDecoder().decode(Args.self, from: data)

        guard let type = MemoryType(rawValue: args.memory_type) else {
            return ToolResult(
                content: "Invalid memory type '\(args.memory_type)'. Use: user, feedback, project, reference",
                isError: true
            )
        }

        let entry = try service.store(name: args.name, type: type, content: args.content)
        return ToolResult(content: "Memory saved: '\(entry.name)' (type: \(entry.type.rawValue), id: \(entry.id))")
    }
}
