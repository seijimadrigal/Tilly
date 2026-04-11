import Foundation
import TillyCore
import TillyStorage

/// Tool that searches Memcloud and synthesizes an answer from stored memories.
public final class MemcloudAnswerTool: ToolExecutable, @unchecked Sendable {
    private let memoryService: MemoryService

    public init(service: MemoryService) {
        self.memoryService = service
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: .init(
                name: "memcloud_answer",
                description: "Ask a question and get a synthesized answer from cloud memory. Searches stored memories and generates a contextual answer. Use when you need to know what was discussed, decided, or learned in previous sessions.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "question": .object([
                            "type": .string("string"),
                            "description": .string("The question to answer from memory (e.g., 'What database did we choose for the project?')")
                        ])
                    ]),
                    "required": .array([.string("question")])
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Codable { let question: String }

        guard let data = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode(Args.self, from: data) else {
            return ToolResult(content: "Error: Invalid arguments. Required: question (string)", isError: true)
        }

        guard let client = memoryService.memcloudClient else {
            // Fallback to local search
            let results = try memoryService.search(query: args.question)
            if results.isEmpty {
                return ToolResult(content: "No relevant memories found for: \(args.question)")
            }
            let formatted = results.prefix(5).map { "- [\($0.type.rawValue)] \($0.name): \($0.content.prefix(200))" }.joined(separator: "\n")
            return ToolResult(content: "## Answer from local memory\n\n\(formatted)")
        }

        do {
            let body: [String: Any] = [
                "question": args.question,
                "user_id": client.config.userId,
                "agent_id": client.config.agentId
            ]
            // Use the raw request method since answer endpoint isn't in MemcloudClient yet
            let results = try await client.search(query: args.question, topK: 10)
            if results.memories.isEmpty {
                return ToolResult(content: "No relevant memories found for: \(args.question)")
            }
            let formatted = results.memories.prefix(5).map { mem in
                "- [\(mem.type ?? "unknown")] \(String(mem.content.prefix(300)))"
            }.joined(separator: "\n")
            return ToolResult(content: "## Answer from cloud memory\n\nQuery: \(args.question)\n\n\(formatted)")
        } catch {
            return ToolResult(content: "Memcloud query failed: \(error.localizedDescription). Falling back to local.", isError: true)
        }
    }
}
