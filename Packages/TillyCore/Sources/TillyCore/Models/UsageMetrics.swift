import Foundation

/// Tracks per-model token usage, cost, and latency for a single LLM call.
public struct ModelUsageEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let providerID: String
    public let modelID: String
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let estimatedCost: Double
    public let latencyMs: Int
    public let sessionID: UUID?

    public init(
        timestamp: Date = Date(),
        providerID: String,
        modelID: String,
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int,
        estimatedCost: Double,
        latencyMs: Int,
        sessionID: UUID? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.providerID = providerID
        self.modelID = modelID
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.estimatedCost = estimatedCost
        self.latencyMs = latencyMs
        self.sessionID = sessionID
    }
}

/// Aggregated cost/usage summary for a session, day, or all time.
public struct UsageSummary: Sendable {
    public let totalTokens: Int
    public let totalCost: Double
    public let totalRequests: Int
    public let averageLatencyMs: Int
    public let byModel: [String: ModelBreakdown]

    public struct ModelBreakdown: Sendable {
        public let tokens: Int
        public let cost: Double
        public let requests: Int

        public init(tokens: Int, cost: Double, requests: Int) {
            self.tokens = tokens
            self.cost = cost
            self.requests = requests
        }
    }

    public init(
        totalTokens: Int,
        totalCost: Double,
        totalRequests: Int,
        averageLatencyMs: Int,
        byModel: [String: ModelBreakdown]
    ) {
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.totalRequests = totalRequests
        self.averageLatencyMs = averageLatencyMs
        self.byModel = byModel
    }

    public static let empty = UsageSummary(
        totalTokens: 0, totalCost: 0, totalRequests: 0, averageLatencyMs: 0, byModel: [:]
    )
}
