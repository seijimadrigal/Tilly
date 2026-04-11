import Foundation
import TillyCore
import TillyStorage

/// Tool: Memory consolidation via Memcloud server-side "Dream Mode".
/// Uses the /v1/memories/consolidate endpoint for server-side dedup + merge.
public final class MemcloudConsolidateTool: ToolExecutable, @unchecked Sendable {

    private let memoryService: MemoryService
    public var consolidationHandler: ((String) async -> String)?

    public init(service: MemoryService) {
        self.memoryService = service
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: .init(
                name: "memcloud_consolidate",
                description: "Server-side memory consolidation (Dream Mode). Finds duplicate memories, suggests merges, and optionally applies them. Use dry_run=true to preview. Runs on the server — fast and reliable.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "scope": .object([
                            "type": .string("string"),
                            "enum": .array([.string("all"), .string("duplicates"), .string("stale")]),
                            "description": .string("What to consolidate. Default 'duplicates'.")
                        ]),
                        "dry_run": .object([
                            "type": .string("boolean"),
                            "description": .string("Preview changes without applying. Default true.")
                        ]),
                        "threshold": .object([
                            "type": .string("number"),
                            "description": .string("Similarity threshold for duplicates (0.0-1.0). Default 0.85.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Max memories to scan. Default 50.")
                        ])
                    ]),
                    "required": .array([])
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Codable {
            let scope: String?
            let dry_run: Bool?
            let threshold: Double?
            let limit: Int?
        }

        let args: Args
        if let data = arguments.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Args.self, from: data) {
            args = decoded
        } else {
            args = Args(scope: nil, dry_run: nil, threshold: nil, limit: nil)
        }

        guard let client = memoryService.memcloudClient else {
            return ToolResult(content: "Memcloud not configured.", isError: true)
        }

        do {
            let response = try await client.consolidateServer(
                scope: args.scope ?? "duplicates",
                threshold: args.threshold ?? 0.85,
                dryRun: args.dry_run ?? true,
                limit: args.limit ?? 50
            )

            var report = "## Memory Consolidation Report\n\n"
            report += "Scanned: \(response.scanned ?? 0) | Dry run: \(args.dry_run ?? true)\n\n"

            if let groups = response.duplicate_groups, !groups.isEmpty {
                report += "### \(groups.count) Duplicate Groups Found\n\n"
                for group in groups.prefix(10) {
                    report += "**Group \(group.group_id ?? 0)** (\(group.memories?.count ?? 0) items):\n"
                    for mem in (group.memories ?? []) {
                        report += "  - \(String(mem.content.prefix(120)))\n"
                    }
                    if let merge = group.suggested_merge {
                        report += "  → Suggested merge: \(String(merge.prefix(200)))\n"
                    }
                    report += "\n"
                }
            } else {
                report += "No duplicates found. Memory base is clean.\n"
            }

            if let actions = response.actions_taken, !actions.isEmpty {
                report += "\n### Actions: \(actions.map { "\($0.key): \($0.value)" }.joined(separator: ", "))\n"
            }

            return ToolResult(content: report)
        } catch {
            return ToolResult(content: "Consolidation failed: \(error.localizedDescription)", isError: true)
        }
    }
}
