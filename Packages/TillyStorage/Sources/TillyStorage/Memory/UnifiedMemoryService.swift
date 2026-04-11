import Foundation
import TillyCore

public actor UnifiedMemoryService {
    public let local: MemoryService
    private var cloudContext: String?
    private var sessionSummaries: String?
    private var fetchTask: Task<Void, Never>?

    public init(local: MemoryService) {
        self.local = local
    }

    // Store: local + cloud write-through
    public func store(name: String, type: MemoryType, content: String, tier: MemoryTier? = nil) async throws -> MemoryEntry {
        // Local store (synchronous, via nonisolated local)
        let entry = try local.store(name: name, type: type, content: content)
        // Cloud sync happens in MemoryService.store() background task
        return entry
    }

    // Search: merge local + cloud results
    public func search(query: String, type: MemoryType? = nil) async throws -> [MemoryEntry] {
        let localResults = try local.search(query: query, type: type)
        // Cloud search for enrichment (non-blocking)
        if let client = local.memcloudClient {
            do {
                let cloudResults = try await client.search(query: query, topK: 10)
                // Return local results + any cloud-only results
                // (cloud enriches but doesn't replace local)
                let localIDs = Set(localResults.map(\.id))
                let cloudOnly = cloudResults.memories.filter { result in
                    !localIDs.contains(result.id)
                }
                if !cloudOnly.isEmpty {
                    // Append cloud-only as synthetic entries
                    var merged = localResults
                    for cloud in cloudOnly.prefix(5) {
                        merged.append(MemoryEntry(
                            id: cloud.id,
                            name: cloud.type ?? "cloud",
                            type: .reference,
                            content: cloud.content,
                            tier: .semantic
                        ))
                    }
                    return merged
                }
            } catch {
                // Cloud search failed — local results are sufficient
            }
        }
        return localResults
    }

    // Recall: combined local + cloud context for prompt injection
    public func recall(query: String? = nil, tokenBudget: Int = 2000) async -> RecallResult {
        let localEntries = (try? local.list()) ?? []
        let recentLocal = localEntries.suffix(3).map(\.indexLine).joined(separator: "\n")

        var cloudCtx: String? = nil
        if let client = local.memcloudClient {
            cloudCtx = try? await client.recall(
                query: query,
                tokenBudget: tokenBudget,
                format: "markdown"
            ).context
        }

        var merged = ""
        if !recentLocal.isEmpty { merged += recentLocal + "\n" }
        if let cloud = cloudCtx, !cloud.isEmpty { merged += "\n" + cloud }

        return RecallResult(
            localEntries: Array(localEntries.suffix(3)),
            cloudContext: cloudCtx,
            merged: merged.isEmpty ? "(no memories)" : merged
        )
    }

    // Refresh cached context (call on new session)
    public func refreshCache() async {
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            guard let self else { return }
            guard let client = await self.local.memcloudClient else { return }

            async let recallResult = client.recall(tokenBudget: 2000, format: "markdown")
            async let summaryResult = client.recallSessionSummaries(count: 3)

            if let recall = try? await recallResult {
                await self.setCachedContext(recall.context)
            }
            if let summaries = try? await summaryResult {
                let text = summaries.memories.map { "- \(String($0.content.prefix(300)))" }.joined(separator: "\n")
                await self.setCachedSummaries(text)
            }
        }
    }

    // Reconcile: sync any local-only entries to cloud
    public func reconcile() async {
        guard let client = local.memcloudClient else { return }
        let localEntries = (try? local.list()) ?? []
        for entry in localEntries {
            let privacy = PrivacyFilter.classify(entry.content)
            guard privacy != .sensitive else { continue }
            let isDup = (try? await client.isDuplicate(content: entry.content)) ?? false
            if !isDup {
                _ = try? await client.syncEntry(entry)
            }
        }
    }

    public func delete(name: String) async throws {
        try local.delete(name: name)
    }

    public func list() async throws -> [MemoryEntry] {
        try local.list()
    }

    // Cached context accessors
    public func getCachedContext() -> String? { cloudContext }
    public func getCachedSummaries() -> String? { sessionSummaries }

    private func setCachedContext(_ ctx: String) { cloudContext = ctx }
    private func setCachedSummaries(_ s: String) { sessionSummaries = s }

    public struct RecallResult: Sendable {
        public let localEntries: [MemoryEntry]
        public let cloudContext: String?
        public let merged: String
    }
}
