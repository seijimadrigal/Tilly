import Foundation
import TillyCore

/// HTTP client for the Memcloud Memory-as-a-Service API.
/// Handles all communication with the Memcloud REST API including
/// memory storage, search, recall, and synchronization.
public final class MemcloudClient: @unchecked Sendable {

    // MARK: - Configuration

    public struct Config: Sendable {
        public let apiURL: String
        public let apiKey: String
        public let userId: String
        public let agentId: String

        public init(
            apiURL: String = "https://api.memcloud.dev/v1",
            apiKey: String,
            userId: String = "default",
            agentId: String = "tilly"
        ) {
            self.apiURL = apiURL.hasSuffix("/") ? String(apiURL.dropLast()) : apiURL
            self.apiKey = apiKey
            self.userId = userId
            self.agentId = agentId
        }
    }

    public struct Provenance: Sendable {
        public let sourceTool: String
        public let sessionId: String
        public let agentRole: String

        public init(sourceTool: String = "unknown", sessionId: String = "unknown", agentRole: String = "main") {
            self.sourceTool = sourceTool
            self.sessionId = sessionId
            self.agentRole = agentRole
        }

        public var asMetadata: [String: String] {
            ["source_tool": sourceTool, "session_id": sessionId, "agent_role": agentRole]
        }
    }

    // MARK: - Response Types

    public struct AddResponse: Codable, Sendable {
        public let status: String
        public let memories_created: Int?
        public let memory_ids: [String]?
        public let importance: Int?
    }

    public struct SearchResult: Codable, Sendable {
        public let id: String
        public let content: String
        public let type: String?
        public let confidence: Double?
        public let rrf_score: Double?
        public let rerank_score: Double?
        public let sources: [String]?
        public let created_at: String?
    }

    public struct SearchResponse: Codable, Sendable {
        public let memories: [SearchResult]
    }

    public struct RecallResponse: Codable, Sendable {
        public let context: String
        public let format: String
        public let token_count: Int
        public let sections: [String: Int]
        public let latency_ms: Double
    }

    public struct HealthResponse: Codable, Sendable {
        public let status: String
        public let version: String
    }

    // MARK: - Properties

    public let config: Config
    private let session: URLSession

    // MARK: - Init

    public init(config: Config) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: sessionConfig)
    }

    // MARK: - Health

    /// Check if the Memcloud API is reachable.
    public func health() async throws -> HealthResponse {
        return try await get("/health")
    }

    // MARK: - Memory Operations

    /// Store a memory in Memcloud. The extraction pipeline runs server-side.
    public func store(text: String, poolId: String? = nil, sourceType: String = "agent", provenance: Provenance? = nil) async throws -> AddResponse {
        var body: [String: Any] = [
            "text": text,
            "user_id": config.userId,
            "agent_id": config.agentId,
            "source_type": sourceType
        ]
        if let poolId { body["pool_id"] = poolId }
        if let provenance { body["metadata"] = provenance.asMetadata }
        return try await post("/memories/", body: body)
    }

    /// Search memories by semantic query.
    public func search(query: String, topK: Int = 10, poolId: String? = nil) async throws -> SearchResponse {
        var body: [String: Any] = [
            "query": query,
            "user_id": config.userId,
            "agent_id": config.agentId,
            "top_k": topK
        ]
        if let poolId { body["pool_id"] = poolId }
        return try await post("/memories/search/", body: body)
    }

    /// Get pre-assembled context for agent injection.
    public func recall(
        query: String? = nil,
        tokenBudget: Int = 4000,
        format: String = "markdown"
    ) async throws -> RecallResponse {
        var body: [String: Any] = [
            "user_id": config.userId,
            "agent_id": config.agentId,
            "token_budget": tokenBudget,
            "format": format,
            "include_profile": true,
            "include_recent": true
        ]
        if let query { body["query"] = query }
        return try await post("/recall", body: body)
    }

    /// Delete a memory by ID.
    public func delete(memoryId: String) async throws {
        let _: [String: String] = try await request(
            method: "DELETE",
            path: "/memories/\(memoryId)"
        )
    }

    // MARK: - Sync

    /// Sync a local MemoryEntry to Memcloud.
    public func syncEntry(_ entry: MemoryEntry, provenance: Provenance? = nil) async throws -> AddResponse {
        let text = "[\(entry.type.rawValue)] \(entry.name): \(entry.content)"
        return try await store(text: text, sourceType: "tilly_sync", provenance: provenance)
    }

    /// Check if similar content already exists in Memcloud (for dedup).
    public func isDuplicate(content: String, threshold: Double = 0.90) async throws -> Bool {
        let snippet = String(content.prefix(200))
        let response = try await search(query: snippet, topK: 3)
        return response.memories.contains { result in
            let score = result.rerank_score ?? result.rrf_score ?? result.confidence ?? 0.0
            return score >= threshold
        }
    }

    /// Store a session summary to Memcloud.
    public func storeSessionSummary(sessionId: String, title: String, summary: String) async throws -> AddResponse {
        let text = "[session_summary] Session '\(title)' (id: \(sessionId)): \(summary)"
        return try await store(text: text, sourceType: "session_summary")
    }

    /// Recall recent session summaries.
    public func recallSessionSummaries(count: Int = 3) async throws -> SearchResponse {
        return try await search(query: "session_summary recent sessions", topK: count)
    }

    // MARK: - Phase 5 Endpoints (traces, consolidate, stale, contradictions)

    /// Capture a tool execution trace for procedural memory extraction.
    public func captureTrace(
        sessionId: String,
        task: String,
        toolCalls: [[String: Any]],
        outcome: String,
        durationMs: Int
    ) async throws -> TraceResponse {
        let toolNames = toolCalls.compactMap { $0["tool"] as? String }
        let body: [String: Any] = [
            "user_id": config.userId,
            "agent_id": config.agentId,
            "session_id": sessionId,
            "trace": [
                "task": task,
                "tools_used": toolNames,
                "tool_calls": toolCalls,
                "outcome": outcome,
                "duration_ms": durationMs
            ]
        ]
        return try await post("/traces", body: body)
    }

    /// Server-side memory consolidation (dream mode).
    public func consolidateServer(
        scope: String = "duplicates",
        threshold: Double = 0.85,
        dryRun: Bool = true,
        limit: Int = 50
    ) async throws -> ConsolidateResponse {
        let body: [String: Any] = [
            "user_id": config.userId,
            "scope": scope,
            "threshold": threshold,
            "dry_run": dryRun,
            "limit": limit
        ]
        return try await post("/memories/consolidate", body: body)
    }

    /// Get stale memories that should be reviewed or archived.
    public func getStaleMemories(
        threshold: Double = 0.2,
        minAgeDays: Int = 7,
        limit: Int = 50
    ) async throws -> StaleResponse {
        return try await get("/memories/stale?user_id=\(config.userId)&threshold=\(threshold)&min_age_days=\(minAgeDays)&limit=\(limit)")
    }

    /// Check for contradictions between a new fact and existing memories.
    public func checkContradictions(
        text: String? = nil,
        entity: String? = nil,
        limit: Int = 20
    ) async throws -> ContradictionResponse {
        var body: [String: Any] = [
            "user_id": config.userId,
            "limit": limit
        ]
        if let text { body["text"] = text }
        if let entity { body["entity"] = entity }
        return try await post("/memories/check-contradictions", body: body)
    }

    // MARK: - Phase 5 Response Types

    public struct TraceResponse: Codable, Sendable {
        public let status: String?
        public let trace_id: String?
        public let memories_created: Int?
        public let counts: [String: Int]?
        public let memory_ids: [String]?
    }

    public struct ConsolidateResponse: Codable, Sendable {
        public let scanned: Int?
        public let duplicate_groups: [DuplicateGroup]?
        public let stale_candidates: [StaleCandidateEntry]?
        public let actions_taken: [String: Int]?

        public struct DuplicateGroup: Codable, Sendable {
            public let group_id: Int?
            public let memories: [GroupMemory]?
            public let suggested_merge: String?

            public struct GroupMemory: Codable, Sendable {
                public let id: String
                public let content: String
                public let score: Double?
            }
        }

        public struct StaleCandidateEntry: Codable, Sendable {
            public let id: String
            public let content: String?
            public let stale_reason: String?
        }
    }

    public struct StaleResponse: Codable, Sendable {
        public let total_stale: Int?
        public let by_reason: [String: Int]?
        public let candidates: [StaleCandidate]?

        public struct StaleCandidate: Codable, Sendable {
            public let id: String
            public let content: String?
            public let memory_type: String?
            public let decay_score: Double?
            public let access_count: Int?
            public let days_old: Int?
            public let stale_reason: String?
            public let recommendation: String?
        }
    }

    public struct ContradictionResponse: Codable, Sendable {
        public let contradictions_found: Int?
        public let pairs: [ContradictionPair]?

        public struct ContradictionPair: Codable, Sendable {
            public let memory_a: ContradictionMemory?
            public let memory_b: ContradictionMemory?
            public let confidence: Double?
            public let reasoning: String?
            public let suggestion: String?

            public struct ContradictionMemory: Codable, Sendable {
                public let id: String
                public let content: String
            }
        }
    }

    // MARK: - Phase 4 Endpoints (batch, pools, temporal, graph)

    /// Batch sync: store multiple entries in sequential calls.
    /// Falls back to individual stores if batch endpoint unavailable.
    public func batchSync(entries: [MemoryEntry], provenance: Provenance? = nil) async throws -> [AddResponse] {
        var results: [AddResponse] = []
        for entry in entries {
            let privacy = PrivacyFilter.classify(entry.content)
            guard privacy != .sensitive else { continue }
            let isDup = (try? await isDuplicate(content: entry.content)) ?? false
            if !isDup {
                let result = try await syncEntry(entry, provenance: provenance)
                results.append(result)
            }
        }
        return results
    }

    /// List memories in a specific pool.
    public func listPoolMemories(poolId: String, topK: Int = 50) async throws -> SearchResponse {
        return try await search(query: "pool_entry", topK: topK, poolId: poolId)
    }

    /// Temporal query: search memories within a time range.
    public func searchTemporal(
        query: String,
        after: Date? = nil,
        before: Date? = nil,
        topK: Int = 10
    ) async throws -> SearchResponse {
        let formatter = ISO8601DateFormatter()
        var body: [String: Any] = [
            "query": query,
            "user_id": config.userId,
            "agent_id": config.agentId,
            "top_k": topK
        ]
        if let after { body["after"] = formatter.string(from: after) }
        if let before { body["before"] = formatter.string(from: before) }
        return try await post("/memories/search/", body: body)
    }

    /// Query the knowledge graph for related entities.
    public func queryGraph(query: String, depth: Int = 2) async throws -> GraphResponse {
        let body: [String: Any] = [
            "query": query,
            "user_id": config.userId,
            "agent_id": config.agentId,
            "depth": depth
        ]
        return try await post("/graph/query", body: body)
    }

    /// Get the dynamic agent profile (MEMORY.md-like summary).
    public func getAgentProfile() async throws -> ProfileResponse {
        return try await get("/agents/\(config.agentId)/profile/")
    }

    /// Preview memory decay effects.
    public func previewDecay() async throws -> DecayPreviewResponse {
        return try await get("/decay/preview/")
    }

    // MARK: - Phase 4 Response Types

    public struct GraphResponse: Codable, Sendable {
        public let nodes: [GraphNode]?
        public let edges: [GraphEdge]?
        public let query: String?

        public struct GraphNode: Codable, Sendable {
            public let id: String
            public let label: String?
            public let type: String?
        }
        public struct GraphEdge: Codable, Sendable {
            public let source: String
            public let target: String
            public let relationship: String?
            public let weight: Double?
        }
    }

    public struct ProfileResponse: Codable, Sendable {
        public let profile: String?
        public let updated_at: String?
    }

    public struct DecayPreviewResponse: Codable, Sendable {
        public let memories_affected: Int?
        public let preview: [DecayEntry]?

        public struct DecayEntry: Codable, Sendable {
            public let id: String
            public let content: String?
            public let current_score: Double?
            public let projected_score: Double?
        }
    }

    // MARK: - HTTP Helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        return try await request(method: "GET", path: path)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        return try await request(method: "POST", path: path, body: body)
    }

    private func request<T: Decodable>(
        method: String,
        path: String,
        body: [String: Any]? = nil
    ) async throws -> T {
        guard let url = URL(string: config.apiURL + path) else {
            throw TillyError.apiError("Invalid Memcloud URL: \(config.apiURL + path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TillyError.apiError("Invalid response from Memcloud")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TillyError.httpError(statusCode: httpResponse.statusCode, message: "Memcloud: \(errorBody)")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}
