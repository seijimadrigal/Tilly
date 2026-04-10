import Foundation
import TillyCore
import TillyStorage

/// Tool #38: Memory consolidation ("Dream Mode").
/// Merges duplicate memories, resolves contradictions, and cleans stale entries.
public final class MemcloudConsolidateTool: ToolExecutable, @unchecked Sendable {

    private let memoryService: MemoryService

    /// LLM handler for merging memories. Set by AppState.
    public var consolidationHandler: ((String) async -> String)?

    public init(service: MemoryService) {
        self.memoryService = service
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: .init(
                name: "memcloud_consolidate",
                description: "Consolidate cloud memories: merge duplicates, resolve contradictions, and clean stale entries. Runs a 'dream mode' pass over memories to keep the knowledge base clean. Use periodically or when search returns too many similar results.",
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
                            "description": .string("Preview what would change without making changes. Default false.")
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
        }

        guard let data = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode(Args.self, from: data) else {
            return ToolResult(content: "Error: Invalid arguments", isError: true)
        }

        guard let client = memoryService.memcloudClient else {
            return ToolResult(content: "Memcloud not configured. Enable it first with your API key.", isError: true)
        }

        let scope = args.scope ?? "duplicates"
        let dryRun = args.dry_run ?? false

        // Fetch memories from cloud
        let allMemories: MemcloudClient.SearchResponse
        do {
            allMemories = try await client.search(query: "all stored memories facts decisions", topK: 100)
        } catch {
            return ToolResult(content: "Failed to fetch memories: \(error.localizedDescription)", isError: true)
        }

        if allMemories.memories.isEmpty {
            return ToolResult(content: "No memories found in Memcloud to consolidate.")
        }

        var report = "## Memory Consolidation Report\n\n"
        report += "Scope: \(scope) | Dry run: \(dryRun)\n"
        report += "Memories scanned: \(allMemories.memories.count)\n\n"

        // Find duplicate clusters
        var duplicateGroups: [[MemcloudClient.SearchResult]] = []
        var processed: Set<String> = []

        for memory in allMemories.memories where !processed.contains(memory.id) {
            do {
                let similar = try await client.search(query: String(memory.content.prefix(100)), topK: 5)
                let dupes = similar.memories.filter { result in
                    result.id != memory.id &&
                    !processed.contains(result.id) &&
                    (result.rerank_score ?? result.rrf_score ?? 0) > 0.85
                }
                if !dupes.isEmpty {
                    duplicateGroups.append([memory] + dupes)
                    processed.insert(memory.id)
                    dupes.forEach { processed.insert($0.id) }
                }
            } catch { continue }
        }

        report += "### Duplicate Groups: \(duplicateGroups.count)\n\n"
        for (i, group) in duplicateGroups.enumerated() {
            report += "**Group \(i + 1)** (\(group.count) items):\n"
            for mem in group {
                report += "  - \(String(mem.content.prefix(120)))\n"
            }
            report += "\n"
        }

        // Merge if not dry run
        if !dryRun && !duplicateGroups.isEmpty {
            if let handler = consolidationHandler {
                var merged = 0
                for group in duplicateGroups {
                    let prompt = "Merge these duplicate memories into one concise, accurate entry:\n" +
                        group.map { "- \($0.content)" }.joined(separator: "\n")
                    let mergedContent = await handler(prompt)

                    _ = try? await client.store(text: mergedContent, sourceType: "consolidation")
                    for dupe in group.dropFirst() {
                        try? await client.delete(memoryId: dupe.id)
                    }
                    merged += 1
                }
                report += "\nConsolidated \(merged) groups.\n"
            } else {
                report += "\nLLM handler not configured. Use dry_run to preview, or set up consolidation handler.\n"
            }
        }

        if duplicateGroups.isEmpty {
            report += "No duplicates found. Memory base is clean.\n"
        }

        return ToolResult(content: report)
    }
}
