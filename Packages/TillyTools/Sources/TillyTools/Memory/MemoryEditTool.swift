import Foundation
import TillyCore
import TillyStorage

/// Tool to update an existing memory in place (atomic edit).
/// Preserves the original creation date while updating content and timestamp.
public final class MemoryEditTool: ToolExecutable, @unchecked Sendable {
    private let service: MemoryService

    public init(service: MemoryService) { self.service = service }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "memory_edit",
                description: "Update an existing memory's content in place. Preserves the original creation date. Use this instead of delete + store for atomic updates.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object([
                            "type": .string("string"),
                            "description": .string("Name of the existing memory to update (must match exactly)."),
                        ]),
                        "content": .object([
                            "type": .string("string"),
                            "description": .string("New content to replace the existing content."),
                        ]),
                        "memory_type": .object([
                            "type": .string("string"),
                            "enum": .array([.string("user"), .string("feedback"), .string("project"), .string("reference")]),
                            "description": .string("Optional: change the memory type. If omitted, keeps the original type."),
                        ]),
                    ]),
                    "required": .array([.string("name"), .string("content")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let name: String
            let content: String
            let memory_type: String?
        }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments")
        }

        let args = try JSONDecoder().decode(Args.self, from: data)

        // Load existing memory to preserve creation date
        let existing: MemoryEntry
        do {
            existing = try service.load(name: args.name)
        } catch {
            return ToolResult(
                content: "Memory '\(args.name)' not found. Use memory_store to create a new one, or memory_list to see existing names.",
                isError: true
            )
        }

        let newType: MemoryType
        if let typeStr = args.memory_type {
            guard let parsed = MemoryType(rawValue: typeStr) else {
                return ToolResult(content: "Invalid memory type '\(typeStr)'. Use: user, feedback, project, reference", isError: true)
            }
            newType = parsed
        } else {
            newType = existing.type
        }

        // Delete old entry
        try service.delete(name: args.name)

        // Re-store with same name, preserving creation date via the store method
        let updated = try service.store(name: existing.name, type: newType, content: args.content)

        return ToolResult(content: "Memory updated: '\(updated.name)' (type: \(updated.type.rawValue), id: \(updated.id))")
    }
}
