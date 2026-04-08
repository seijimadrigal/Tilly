import Foundation

public struct SystemPrompt: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var content: String
    public var isDefault: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String = "Default",
        content: String = "You are a helpful assistant.",
        isDefault: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
