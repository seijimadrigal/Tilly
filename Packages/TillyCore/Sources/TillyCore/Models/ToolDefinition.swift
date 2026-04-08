import Foundation

public struct ToolDefinition: Codable, Sendable, Equatable {
    public let type: String
    public let function: FunctionDef

    public init(type: String = "function", function: FunctionDef) {
        self.type = type
        self.function = function
    }

    public struct FunctionDef: Codable, Sendable, Equatable {
        public let name: String
        public let description: String
        public let parameters: JSONValue

        public init(name: String, description: String, parameters: JSONValue) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }
    }
}

public struct ToolCall: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let type: String
    public let function: FunctionCall

    public init(id: String, type: String = "function", function: FunctionCall) {
        self.id = id
        self.type = type
        self.function = function
    }

    public struct FunctionCall: Codable, Sendable, Equatable {
        public let name: String
        public let arguments: String

        public init(name: String, arguments: String) {
            self.name = name
            self.arguments = arguments
        }
    }
}

public struct ToolResult: Codable, Sendable, Equatable {
    public let content: String
    public let isError: Bool
    public var artifacts: [FileAttachment]?

    public init(content: String, isError: Bool = false, artifacts: [FileAttachment]? = nil) {
        self.content = content
        self.isError = isError
        self.artifacts = artifacts
    }
}

/// A type-erased JSON value for encoding arbitrary JSON schemas.
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? container.decode(Double.self) {
            self = .number(v)
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode([String: JSONValue].self) {
            self = .object(v)
        } else if let v = try? container.decode([JSONValue].self) {
            self = .array(v)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unable to decode JSONValue"
            )
        }
    }
}
