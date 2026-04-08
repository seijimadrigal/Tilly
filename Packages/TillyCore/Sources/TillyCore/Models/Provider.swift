import Foundation

public enum ProviderID: String, Codable, Sendable, CaseIterable, Identifiable {
    case openRouter = "openrouter"
    case ollama = "ollama"
    case dashScope = "dashscope"
    case deepSeek = "deepseek"
    case moonshot = "moonshot"
    case zai = "zai"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama (Local)"
        case .dashScope: return "Alibaba Qwen"
        case .deepSeek: return "DeepSeek"
        case .moonshot: return "Kimi (Moonshot)"
        case .zai: return "ZAI (Zhipu AI)"
        }
    }

    public var requiresAPIKey: Bool {
        self != .ollama
    }
}

public struct ModelInfo: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let provider: ProviderID
    public var contextWindow: Int?
    public var maxOutputTokens: Int?

    public init(
        id: String,
        name: String,
        provider: ProviderID,
        contextWindow: Int? = nil,
        maxOutputTokens: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
    }
}
