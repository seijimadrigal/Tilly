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
