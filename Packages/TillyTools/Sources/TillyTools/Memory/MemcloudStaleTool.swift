import Foundation
import TillyCore
import TillyStorage

/// Tool #40: Find stale memories that should be reviewed or archived.
public final class MemcloudStaleTool: ToolExecutable, @unchecked Sendable {
    private let memoryService: MemoryService

    public init(service: MemoryService) { self.memoryService = service }

    public var definition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: .init(
                name: "memcloud_stale",
                description: "Find stale cloud memories — low decay score, never accessed, or superseded by newer facts. Returns candidates for review or cleanup. Use periodically to keep memory base fresh.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "threshold": .object([
                            "type": .string("number"),
                            "description": .string("Decay score threshold (0.0-1.0). Memories below this are stale. Default 0.2.")
                        ]),
                        "min_age_days": .object([
                            "type": .string("integer"),
                            "description": .string("Minimum age in days to consider. Default 7.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Max candidates to return. Default 20.")
                        ])
                    ]),
                    "required": .array([])
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Codable {
            let threshold: Double?
            let min_age_days: Int?
            let limit: Int?
        }

        let args: Args
        if let data = arguments.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Args.self, from: data) {
            args = decoded
        } else {
            args = Args(threshold: nil, min_age_days: nil, limit: nil)
        }

        guard let client = memoryService.memcloudClient else {
            return ToolResult(content: "Memcloud not configured.", isError: true)
        }

        do {
            let response = try await client.getStaleMemories(
                threshold: args.threshold ?? 0.2,
                minAgeDays: args.min_age_days ?? 7,
                limit: args.limit ?? 20
            )

            var report = "## Stale Memories Report\n\n"
            report += "Total stale: \(response.total_stale ?? 0)\n"

            if let reasons = response.by_reason, !reasons.isEmpty {
                report += "By reason: \(reasons.map { "\($0.key): \($0.value)" }.joined(separator: ", "))\n"
            }
            report += "\n"

            if let candidates = response.candidates, !candidates.isEmpty {
                for (i, c) in candidates.enumerated() {
                    report += "\(i + 1). [\(c.memory_type ?? "unknown")] \(String((c.content ?? "").prefix(120)))\n"
                    report += "   Decay: \(String(format: "%.2f", c.decay_score ?? 0)) | Age: \(c.days_old ?? 0)d | Accessed: \(c.access_count ?? 0)x | Reason: \(c.stale_reason ?? "unknown")\n"
                    if let rec = c.recommendation { report += "   Recommendation: \(rec)\n" }
                    report += "\n"
                }
            } else {
                report += "No stale memories found. Memory base is fresh.\n"
            }

            return ToolResult(content: report)
        } catch {
            return ToolResult(content: "Stale check failed: \(error.localizedDescription)", isError: true)
        }
    }
}
