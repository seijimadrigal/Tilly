import Foundation
import TillyCore

public actor SharedMemoryPool {
    public let poolId: String
    private let client: MemcloudClient
    private var localCache: [String: String] = [:]

    public init(taskId: String, client: MemcloudClient) {
        self.poolId = "pool_\(taskId.prefix(32))"
        self.client = client
    }

    public func write(key: String, value: String, agentRole: String) async throws {
        localCache[key] = value
        let provenance = MemcloudClient.Provenance(
            sourceTool: "shared_pool",
            sessionId: poolId,
            agentRole: agentRole
        )
        _ = try await client.store(
            text: "[\(key)] \(value)",
            poolId: poolId,
            sourceType: "pool_entry",
            provenance: provenance
        )
    }

    public func read(key: String) async throws -> String? {
        if let cached = localCache[key] { return cached }
        let results = try await client.search(query: key, topK: 1, poolId: poolId)
        return results.memories.first?.content
    }

    public func readAll() async throws -> [String: String] {
        // Use pool-scoped list via search with broad wildcard query
        // Each pool entry was stored with "[\(key)] \(value)" format
        let results = try await client.search(query: "pool_entry \(poolId)", topK: 50, poolId: poolId)
        var merged = localCache
        for mem in results.memories {
            // Extract key from stored format "[\(key)] \(value)"
            let content = mem.content
            if content.hasPrefix("["), let closeBracket = content.firstIndex(of: "]") {
                let key = String(content[content.index(after: content.startIndex)..<closeBracket])
                let value = String(content[content.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)
                merged[key] = value
            } else {
                merged[mem.id] = content
            }
        }
        return merged
    }

    public func contextSummary() async -> String {
        guard let entries = try? await readAll() else { return "" }
        if entries.isEmpty { return "" }
        return entries.map { "[\($0.key)] \($0.value.prefix(200))" }.joined(separator: "\n")
    }
}
