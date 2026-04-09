import Foundation

public struct Session: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var messages: [Message]
    public var systemPrompt: SystemPrompt?
    public var providerID: String
    public var modelID: String
    public let createdAt: Date
    public var updatedAt: Date
    public var parentSessionID: UUID?
    public var forkPointIndex: Int?
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        title: String = "New Chat",
        messages: [Message] = [],
        systemPrompt: SystemPrompt? = nil,
        providerID: String = "ollama",
        modelID: String = "llama3.2",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        parentSessionID: UUID? = nil,
        forkPointIndex: Int? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.providerID = providerID
        self.modelID = modelID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.parentSessionID = parentSessionID
        self.forkPointIndex = forkPointIndex
        self.tags = tags
    }

    // Custom decoder to handle Firebase null/missing fields gracefully
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "New Chat"
        messages = try container.decodeIfPresent([Message].self, forKey: .messages) ?? []
        systemPrompt = try container.decodeIfPresent(SystemPrompt.self, forKey: .systemPrompt)
        providerID = try container.decodeIfPresent(String.self, forKey: .providerID) ?? ""
        modelID = try container.decodeIfPresent(String.self, forKey: .modelID) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        parentSessionID = try container.decodeIfPresent(UUID.self, forKey: .parentSessionID)
        forkPointIndex = try container.decodeIfPresent(Int.self, forKey: .forkPointIndex)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    public mutating func appendMessage(_ message: Message) {
        messages.append(message)
        updatedAt = Date()
    }

    public func forked(atIndex index: Int) -> Session {
        Session(
            title: "\(title) (fork)",
            messages: Array(messages.prefix(index)),
            systemPrompt: systemPrompt,
            providerID: providerID,
            modelID: modelID,
            parentSessionID: id,
            forkPointIndex: index,
            tags: tags
        )
    }
}
