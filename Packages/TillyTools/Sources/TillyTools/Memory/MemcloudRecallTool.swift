import Foundation
import TillyCore
import TillyStorage

/// Tool that fetches pre-assembled context from Memcloud's /v1/recall endpoint.
/// Returns a structured memory context (profile + relevant memories + recent context)
/// ready to inform the agent's next response.
public final class MemcloudRecallTool: ToolExecutable, @unchecked Sendable {

    private let memoryService: MemoryService

    public init(service: MemoryService) {
        self.memoryService = service
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: .init(
                name: "memcloud_recall",
                description: """
                    Recall relevant context from Memcloud's cloud memory. Returns a pre-assembled \
                    context block containing user profile, relevant memories matching the query, \
                    and recent context — ready to use for informed responses. Use this when you \
                    need to know what you've learned about the user, project, or topic across \
                    previous sessions. Falls back to local memory if Memcloud is not configured.
                    """,
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("What to recall. E.g., 'user preferences', 'project status', 'what we discussed about databases'")
                        ]),
                        "token_budget": .object([
                            "type": .string("integer"),
                            "description": .string("Maximum tokens for the context block. Default 4000.")
                        ]),
                        "format": .object([
                            "type": .string("string"),
                            "enum": .array([.string("markdown"), .string("xml"), .string("text")]),
                            "description": .string("Output format. Default 'markdown'.")
                        ])
                    ]),
                    "required": .array([.string("query")])
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Codable {
            let query: String
            let token_budget: Int?
            let format: String?
        }

        guard let data = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode(Args.self, from: data) else {
            return ToolResult(content: "Error: Invalid arguments. Required: query (string)", isError: true)
        }

        // Try Memcloud first
        if let client = memoryService.memcloudClient {
            do {
                let response = try await client.recall(
                    query: args.query,
                    tokenBudget: args.token_budget ?? 4000,
                    format: args.format ?? "markdown"
                )
                return ToolResult(
                    content: """
                        ## Memcloud Recall (\(response.token_count) tokens, \(String(format: "%.0f", response.latency_ms))ms)

                        \(response.context)
                        """
                )
            } catch {
                // Fall back to local memory
                return try fallbackToLocal(query: args.query, error: error)
            }
        }

        // No Memcloud configured — use local memory
        return try fallbackToLocal(query: args.query, error: nil)
    }

    private func fallbackToLocal(query: String, error: Error?) throws -> ToolResult {
        let results = try memoryService.search(query: query)
        let source = error != nil ? "(Memcloud unavailable, using local memory)" : "(local memory)"

        if results.isEmpty {
            return ToolResult(content: "No memories found matching '\(query)' \(source)")
        }

        let formatted = results.prefix(10).map { entry in
            "- [\(entry.type.rawValue)] **\(entry.name)**: \(entry.content.prefix(200))"
        }.joined(separator: "\n")

        return ToolResult(content: """
            ## Memory Recall \(source)

            \(formatted)
            """)
    }
}
