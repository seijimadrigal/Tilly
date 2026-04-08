import Foundation

public struct StreamDelta: Decodable, Sendable {
    public let id: String?
    public let object: String?
    public let choices: [StreamChoice]?
    public let usage: Usage?

    public struct StreamChoice: Decodable, Sendable {
        public let index: Int
        public let delta: Delta
        public let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, delta
            case finishReason = "finish_reason"
        }

        public struct Delta: Decodable, Sendable {
            public let role: String?
            public let content: String?
            public let reasoningContent: String?
            public let toolCalls: [ToolCallDelta]?

            enum CodingKeys: String, CodingKey {
                case role, content
                case reasoningContent = "reasoning_content"
                case toolCalls = "tool_calls"
            }
        }
    }

    public struct Usage: Decodable, Sendable {
        public let promptTokens: Int?
        public let completionTokens: Int?
        public let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

public struct ToolCallDelta: Decodable, Sendable {
    public let index: Int
    public let id: String?
    public let type: String?
    public let function: FunctionCallDelta?

    public struct FunctionCallDelta: Decodable, Sendable {
        public let name: String?
        public let arguments: String?
    }
}

public struct ChatCompletionResponse: Decodable, Sendable {
    public let id: String
    public let object: String
    public let created: Int
    public let model: String
    public let choices: [Choice]
    public let usage: StreamDelta.Usage?

    public struct Choice: Decodable, Sendable {
        public let index: Int
        public let message: ResponseMessage
        public let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }

        public struct ResponseMessage: Decodable, Sendable {
            public let role: String
            public let content: String?
            public let toolCalls: [ToolCall]?

            enum CodingKeys: String, CodingKey {
                case role, content
                case toolCalls = "tool_calls"
            }
        }
    }
}

public struct APIErrorResponse: Decodable, Sendable {
    public let error: APIError

    public struct APIError: Decodable, Sendable {
        public let message: String
        public let type: String?
        public let code: String?
    }
}
