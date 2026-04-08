import Foundation
import TillyCore
import TillyStorage

public final class MemorySearchTool: ToolExecutable, @unchecked Sendable {
    private let service: MemoryService

    public init(service: MemoryService) { self.service = service }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "memory_search",
                description: "Search through stored memories by keyword and/or type. Returns matching memory entries with their full content.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Search keyword to match against memory names and content. Leave empty to match all."),
                        ]),
                        "memory_type": .object([
                            "type": .string("string"),
                            "enum": .array([.string("user"), .string("feedback"), .string("project"), .string("reference")]),
                            "description": .string("Optional: filter by memory type."),
                        ]),
                    ]),
                    "required": .array([.string("query")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let query: String
            let memory_type: String?
        }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments")
        }

        let args = try JSONDecoder().decode(Args.self, from: data)
        let type = args.memory_type.flatMap { MemoryType(rawValue: $0) }

        let results = try service.search(query: args.query, type: type)

        if results.isEmpty {
            return ToolResult(content: "No memories found matching '\(args.query)'\(type.map { " (type: \($0.rawValue))" } ?? "")")
        }

        let formatted = results.map { entry in
            "### \(entry.name) [\(entry.type.rawValue)]\n\(entry.content)"
        }.joined(separator: "\n\n---\n\n")

        return ToolResult(content: "Found \(results.count) memor\(results.count == 1 ? "y" : "ies"):\n\n\(formatted)")
    }
}
