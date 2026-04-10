import Foundation

public struct ChatCompletionRequest: Encodable, Sendable {
    public let model: String
    public let messages: [ChatMessage]
    public var temperature: Double?
    public var maxTokens: Int?
    public var topP: Double?
    public var stream: Bool
    public var streamOptions: StreamOptions?
    public var tools: [ToolDefinition]?
    public var stop: [String]?

    public init(
        model: String,
        messages: [ChatMessage],
        temperature: Double? = nil,
        maxTokens: Int? = 16384,
        topP: Double? = nil,
        stream: Bool = true,
        streamOptions: StreamOptions? = StreamOptions(),
        tools: [ToolDefinition]? = nil,
        stop: [String]? = nil
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.stream = stream
        self.streamOptions = streamOptions
        self.tools = tools
        self.stop = stop
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
        case topP = "top_p"
        case stream
        case streamOptions = "stream_options"
        case tools, stop
    }

    public struct ChatMessage: Encodable, Sendable {
        public let role: String
        public let content: String?
        public var toolCalls: [ToolCall]?
        public var toolCallID: String?
        public var name: String?

        public init(
            role: String,
            content: String? = nil,
            toolCalls: [ToolCall]? = nil,
            toolCallID: String? = nil,
            name: String? = nil
        ) {
            self.role = role
            self.content = content
            self.toolCalls = toolCalls
            self.toolCallID = toolCallID
            self.name = name
        }

        enum CodingKeys: String, CodingKey {
            case role, content, name
            case toolCalls = "tool_calls"
            case toolCallID = "tool_call_id"
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            try container.encodeIfPresent(content, forKey: .content)
            try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
            try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
            try container.encodeIfPresent(name, forKey: .name)
        }
    }

    public struct StreamOptions: Encodable, Sendable {
        public var includeUsage: Bool

        public init(includeUsage: Bool = true) {
            self.includeUsage = includeUsage
        }

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }
}
