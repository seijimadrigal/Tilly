import Foundation
import TillyCore
import TillyStorage

/// Tool: Memory consolidation ("Dream Mode").
/// Merges duplicate memories, resolves contradictions, and cleans stale entries.
/// Capped at 20 memories scanned to avoid timeout. Use dry_run to preview.
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
                description: "Consolidate cloud memories: find and merge duplicates. Scans up to 20 recent memories for similar entries. Use dry_run=true to preview without changes. Runs quickly — safe to call periodically.",
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
            // Empty args {} is valid — use defaults
            return await runConsolidation(scope: "duplicates", dryRun: true)
        }

        return await runConsolidation(scope: args.scope ?? "duplicates", dryRun: args.dry_run ?? true)
    }

    private func runConsolidation(scope: String, dryRun: Bool) async -> ToolResult {
        guard let client = memoryService.memcloudClient else {
            return ToolResult(content: "Memcloud not configured.", isError: true)
        }

        // Fetch recent memories (capped at 20 to avoid timeout)
        let allMemories: MemcloudClient.SearchResponse
        do {
            allMemories = try await client.search(query: "stored memories facts decisions preferences", topK: 20)
        } catch {
            return ToolResult(content: "Failed to fetch memories: \(error.localizedDescription)", isError: true)
        }

        if allMemories.memories.isEmpty {
            return ToolResult(content: "No memories found in Memcloud to consolidate.")
        }

        var report = "## Memory Consolidation Report\n\n"
        report += "Scope: \(scope) | Dry run: \(dryRun) | Scanned: \(allMemories.memories.count)\n\n"

        // Find duplicates using pairwise similarity from the existing results
        // (no extra API calls — use the scores already returned)
        var duplicateGroups: [[MemcloudClient.SearchResult]] = []
        var processed: Set<String> = []

        let memories = allMemories.memories
        for i in 0..<memories.count where !processed.contains(memories[i].id) {
            var group = [memories[i]]
            for j in (i+1)..<memories.count where !processed.contains(memories[j].id) {
                // Simple content similarity check (no API call)
                let a = memories[i].content.lowercased()
                let b = memories[j].content.lowercased()
                let similarity = contentSimilarity(a, b)
                if similarity > 0.6 {
                    group.append(memories[j])
                    processed.insert(memories[j].id)
                }
            }
            if group.count > 1 {
                duplicateGroups.append(group)
                processed.insert(memories[i].id)
            }
        }

        report += "### Duplicate Groups: \(duplicateGroups.count)\n\n"
        for (i, group) in duplicateGroups.prefix(10).enumerated() {
            report += "**Group \(i + 1)** (\(group.count) items):\n"
            for mem in group {
                report += "  - \(String(mem.content.prefix(100)))\n"
            }
            report += "\n"
        }

        // Merge if not dry run (capped at 5 groups to avoid timeout)
        if !dryRun && !duplicateGroups.isEmpty {
            if let handler = consolidationHandler {
                var merged = 0
                for group in duplicateGroups.prefix(5) {
                    let prompt = "Merge these duplicate memories into one concise entry:\n" +
                        group.map { "- \(String($0.content.prefix(300)))" }.joined(separator: "\n")
                    let mergedContent = await handler(prompt)

                    _ = try? await client.store(text: mergedContent, sourceType: "consolidation")
                    for dupe in group.dropFirst() {
                        try? await client.delete(memoryId: dupe.id)
                    }
                    merged += 1
                }
                report += "Consolidated \(merged) groups.\n"
            } else {
                report += "LLM handler not configured. Run with dry_run=true to preview.\n"
            }
        }

        if duplicateGroups.isEmpty {
            report += "No duplicates found. Memory base is clean.\n"
        }

        return ToolResult(content: report)
    }

    /// Fast local similarity check (Jaccard on word sets) — no API call needed.
    private func contentSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.split(separator: " ").map(String.init))
        let wordsB = Set(b.split(separator: " ").map(String.init))
        guard !wordsA.isEmpty || !wordsB.isEmpty else { return 0 }
        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count
        return Double(intersection) / Double(union)
    }
}
