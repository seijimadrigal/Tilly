import Foundation

public struct SkillEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let trigger: String
    public let instructions: String
    public let created: Date

    public init(
        id: String,
        name: String,
        description: String,
        trigger: String,
        instructions: String,
        created: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.trigger = trigger
        self.instructions = instructions
        self.created = created
    }

    /// One-line summary for SKILLS.md index
    public var indexLine: String {
        "- **\(name)** (`\(id)`) — \(description)"
    }
}
