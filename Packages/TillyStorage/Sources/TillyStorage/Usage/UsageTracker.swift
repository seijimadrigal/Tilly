import Foundation
import TillyCore

public actor UsageTracker {
    private var entries: [ModelUsageEntry] = []
    private let storageURL: URL

    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        storageURL = appSupport.appendingPathComponent("Tilly/usage.json")
        Task { await load() }
    }

    public func record(entry: ModelUsageEntry) {
        entries.append(entry)
        // Keep last 1000 entries in memory
        if entries.count > 1000 {
            entries = Array(entries.suffix(1000))
        }
        Task { await save() }
    }

    public func summaryForSession(_ sessionID: UUID) -> UsageSummary {
        let filtered = entries.filter { $0.sessionID == sessionID }
        return buildSummary(from: filtered)
    }

    public func summaryForToday() -> UsageSummary {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let filtered = entries.filter { $0.timestamp >= today }
        return buildSummary(from: filtered)
    }

    public func summaryAllTime() -> UsageSummary {
        buildSummary(from: entries)
    }

    private func buildSummary(from entries: [ModelUsageEntry]) -> UsageSummary {
        guard !entries.isEmpty else { return .empty }

        let totalTokens = entries.reduce(0) { $0 + $1.totalTokens }
        let totalCost = entries.reduce(0.0) { $0 + $1.estimatedCost }
        let avgLatency = entries.reduce(0) { $0 + $1.latencyMs } / entries.count

        var byModel: [String: UsageSummary.ModelBreakdown] = [:]
        for entry in entries {
            let existing = byModel[entry.modelID] ?? UsageSummary.ModelBreakdown(tokens: 0, cost: 0, requests: 0)
            byModel[entry.modelID] = UsageSummary.ModelBreakdown(
                tokens: existing.tokens + entry.totalTokens,
                cost: existing.cost + entry.estimatedCost,
                requests: existing.requests + 1
            )
        }

        return UsageSummary(
            totalTokens: totalTokens,
            totalCost: totalCost,
            totalRequests: entries.count,
            averageLatencyMs: avgLatency,
            byModel: byModel
        )
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Array(entries.suffix(500))) else { return }
        let dir = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: storageURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let loaded = try? JSONDecoder().decode([ModelUsageEntry].self, from: data) else { return }
        entries = loaded
    }
}
