import Foundation

public enum ProviderID: String, Codable, Sendable, CaseIterable, Identifiable {
    case openRouter = "openrouter"
    case ollama = "ollama"
    case dashScope = "dashscope"
    case deepSeek = "deepseek"
    case moonshot = "moonshot"
    case zai = "zai"
    case zaiCoding = "zai_coding"
    case google = "google"
    case xai = "xai"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama (Local)"
        case .dashScope: return "Alibaba Qwen"
        case .deepSeek: return "DeepSeek"
        case .moonshot: return "Kimi (Moonshot)"
        case .zai: return "ZAI (Zhipu AI)"
        case .zaiCoding: return "ZAI Coding"
        case .google: return "Google Gemini"
        case .xai: return "xAI Grok"
        }
    }

    public var requiresAPIKey: Bool {
        self != .ollama
    }

    public var icon: String {
        switch self {
        case .openRouter: return "arrow.triangle.branch"
        case .ollama: return "desktopcomputer"
        case .dashScope: return "cloud.fill"
        case .deepSeek: return "magnifyingglass.circle.fill"
        case .moonshot: return "moon.fill"
        case .zai: return "cpu.fill"
        case .zaiCoding: return "chevron.left.forwardslash.chevron.right"
        case .google: return "sparkle"
        case .xai: return "bolt.circle.fill"
        }
    }
}

public enum ConnectionStatus: Sendable, Equatable {
    case untested
    case testing
    case connected(modelCount: Int)
    case failed(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
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
