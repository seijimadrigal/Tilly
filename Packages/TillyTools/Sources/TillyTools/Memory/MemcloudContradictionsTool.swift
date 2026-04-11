import Foundation
import TillyCore
import TillyStorage

/// Tool #41: Check for contradictions between a new fact and existing memories.
public final class MemcloudContradictionsTool: ToolExecutable, @unchecked Sendable {
    private let memoryService: MemoryService

    public init(service: MemoryService) { self.memoryService = service }

    public var definition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: .init(
                name: "memcloud_check_contradictions",
                description: "Check if a new fact contradicts existing memories. Returns conflicting memories with confidence scores and reasoning. Use before storing important facts to avoid inconsistencies.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "text": .object([
                            "type": .string("string"),
                            "description": .string("The new fact to check against existing memories (e.g., 'User prefers light mode').")
                        ]),
                        "entity": .object([
                            "type": .string("string"),
                            "description": .string("Optional: specific entity to check contradictions for (e.g., 'user', 'project_alpha').")
                        ])
                    ]),
                    "required": .array([.string("text")])
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Codable {
            let text: String
            let entity: String?
        }

        guard let data = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode(Args.self, from: data) else {
            return ToolResult(content: "Error: Required parameter 'text' missing.", isError: true)
        }

        guard let client = memoryService.memcloudClient else {
            return ToolResult(content: "Memcloud not configured.", isError: true)
        }

        do {
            let response = try await client.checkContradictions(
                text: args.text,
                entity: args.entity
            )

            var report = "## Contradiction Check\n\n"
            report += "New fact: \"\(args.text)\"\n"
            report += "Contradictions found: \(response.contradictions_found ?? 0)\n\n"

            if let pairs = response.pairs, !pairs.isEmpty {
                for (i, pair) in pairs.enumerated() {
                    let conf = pair.confidence ?? 0
                    let icon = conf >= 0.9 ? "🔴" : conf >= 0.7 ? "🟡" : "🟢"
                    report += "\(icon) **Conflict \(i + 1)** (confidence: \(String(format: "%.0f%%", conf * 100)))\n"
                    if let existing = pair.memory_a {
                        report += "  Existing: \(String(existing.content.prefix(150)))\n"
                    }
                    if let reasoning = pair.reasoning {
                        report += "  Reason: \(reasoning)\n"
                    }
                    if let suggestion = pair.suggestion {
                        report += "  Suggestion: \(suggestion)\n"
                    }
                    report += "\n"
                }
            } else {
                report += "No contradictions found. Safe to store.\n"
            }

            return ToolResult(content: report)
        } catch {
            return ToolResult(content: "Contradiction check failed: \(error.localizedDescription)", isError: true)
        }
    }
}
