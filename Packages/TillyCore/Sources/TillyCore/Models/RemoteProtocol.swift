import Foundation

// MARK: - WebSocket Message Protocol (shared between Mac and iOS)

public enum RemoteMessageType: String, Codable, Sendable {
    case sendMessage = "send_message"
    case listSessions = "list_sessions"
    case selectSession = "select_session"
    case newSession = "new_session"

    case streamDelta = "stream_delta"
    case streamEnd = "stream_end"
    case sessionList = "session_list"
    case sessionSelected = "session_selected"
    case sessionCreated = "session_created"
    case fullSession = "full_session"

    case askUser = "ask_user"
    case askUserResponse = "ask_user_response"

    case error = "error"
}

public struct RemoteMessage: Codable, Sendable {
    public let type: RemoteMessageType
    public var text: String?
    public var sessionID: UUID?
    public var sessions: [SessionSummary]?
    public var session: Session?
    public var options: [String]?
    public var error: String?

    public init(
        type: RemoteMessageType,
        text: String? = nil,
        sessionID: UUID? = nil,
        sessions: [SessionSummary]? = nil,
        session: Session? = nil,
        options: [String]? = nil,
        error: String? = nil
    ) {
        self.type = type
        self.text = text
        self.sessionID = sessionID
        self.sessions = sessions
        self.session = session
        self.options = options
        self.error = error
    }

    public func encoded() -> Data? {
        try? JSONEncoder.remoteEncoder.encode(self)
    }

    public static func decoded(from data: Data) -> RemoteMessage? {
        try? JSONDecoder.remoteDecoder.decode(RemoteMessage.self, from: data)
    }
}

public struct SessionSummary: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let messageCount: Int
    public let updatedAt: Date
    public let providerID: String
    public let modelID: String

    public init(from session: Session) {
        self.id = session.id
        self.title = session.title
        self.messageCount = session.messages.count
        self.updatedAt = session.updatedAt
        self.providerID = session.providerID
        self.modelID = session.modelID
    }

    public init(id: UUID, title: String, messageCount: Int, updatedAt: Date, providerID: String, modelID: String) {
        self.id = id
        self.title = title
        self.messageCount = messageCount
        self.updatedAt = updatedAt
        self.providerID = providerID
        self.modelID = modelID
    }
}

// MARK: - Shared encoder/decoder

extension JSONEncoder {
    public static let remoteEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    public static let remoteDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
