import Foundation

public struct Message: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let role: Role
    public var content: [ContentBlock]
    public var toolCalls: [ToolCall]?
    public var toolCallID: String?
    public let timestamp: Date
    public var metadata: MessageMetadata?

    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    public init(
        id: UUID = UUID(),
        role: Role,
        content: [ContentBlock],
        toolCalls: [ToolCall]? = nil,
        toolCallID: String? = nil,
        timestamp: Date = Date(),
        metadata: MessageMetadata? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.timestamp = timestamp
        self.metadata = metadata
    }

    // Custom decoder to handle Firebase null/missing fields
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decodeIfPresent([ContentBlock].self, forKey: .content) ?? []
        toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        metadata = try container.decodeIfPresent(MessageMetadata.self, forKey: .metadata)
    }

    public var textContent: String {
        content.compactMap { block in
            if case .text(let text) = block { return text }
            return nil
        }.joined()
    }
}

public enum ContentBlock: Codable, Sendable, Equatable {
    case text(String)
    case thinking(String)
    case image(data: Data, mimeType: String)
    case fileReference(FileAttachment)

    private enum CodingKeys: String, CodingKey {
        case type, text, thinking, data, mimeType, file
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .thinking(let text):
            try container.encode("thinking", forKey: .type)
            try container.encode(text, forKey: .thinking)
        case .image(let data, let mimeType):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .fileReference(let file):
            try container.encode("file", forKey: .type)
            try container.encode(file, forKey: .file)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "thinking":
            self = .thinking(try container.decodeIfPresent(String.self, forKey: .thinking) ?? "")
        case "image":
            self = .image(
                data: try container.decode(Data.self, forKey: .data),
                mimeType: try container.decode(String.self, forKey: .mimeType)
            )
        case "file":
            self = .fileReference(try container.decode(FileAttachment.self, forKey: .file))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown content block type: \(type)"
            )
        }
    }
}

public struct MessageMetadata: Codable, Sendable, Equatable {
    public var model: String?
    public var provider: String?
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?
    public var finishReason: String?
    public var latencyMs: Int?

    public init(
        model: String? = nil,
        provider: String? = nil,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil,
        finishReason: String? = nil,
        latencyMs: Int? = nil
    ) {
        self.model = model
        self.provider = provider
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.finishReason = finishReason
        self.latencyMs = latencyMs
    }
}

public struct FileAttachment: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let fileName: String
    public let filePath: String
    public let mimeType: String
    public let sizeBytes: Int64

    public init(
        id: UUID = UUID(),
        fileName: String,
        filePath: String,
        mimeType: String,
        sizeBytes: Int64
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
    }
}
