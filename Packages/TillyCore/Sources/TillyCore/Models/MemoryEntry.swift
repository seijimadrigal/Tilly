import Foundation

public enum MemoryType: String, Codable, Sendable, CaseIterable {
    case user
    case feedback
    case project
    case reference
}

public struct MemoryEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let type: MemoryType
    public let content: String
    public let created: Date
    public var updated: Date
    public var tier: MemoryTier?

    public init(
        id: String,
        name: String,
        type: MemoryType,
        content: String,
        created: Date = Date(),
        updated: Date = Date(),
        tier: MemoryTier? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.content = content
        self.created = created
        self.updated = updated
        self.tier = tier
    }

    /// One-line summary for MEMORY.md index
    public var indexLine: String {
        let summary = content.prefix(100).replacingOccurrences(of: "\n", with: " ")
        return "- [\(name)](\(id).md) — \(summary)"
    }
}
