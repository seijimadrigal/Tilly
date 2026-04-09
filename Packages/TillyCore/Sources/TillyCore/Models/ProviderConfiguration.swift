import Foundation

public struct ProviderConfiguration: Codable, Sendable, Identifiable, Equatable {
    public var id: ProviderID { providerID }
    public let providerID: ProviderID
    public var displayName: String
    public var baseURL: URL
    public var isEnabled: Bool
    public var defaultModel: String?
    public var customHeaders: [String: String]
    public var maxRetries: Int
    public var timeoutSeconds: Double

    public init(
        providerID: ProviderID,
        displayName: String,
        baseURL: URL,
        isEnabled: Bool = true,
        defaultModel: String? = nil,
        customHeaders: [String: String] = [:],
        maxRetries: Int = 3,
        timeoutSeconds: Double = 60
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.baseURL = baseURL
        self.isEnabled = isEnabled
        self.defaultModel = defaultModel
        self.customHeaders = customHeaders
        self.maxRetries = maxRetries
        self.timeoutSeconds = timeoutSeconds
    }

    public static let defaults: [ProviderConfiguration] = [
        ProviderConfiguration(
            providerID: .openRouter,
            displayName: "OpenRouter",
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            defaultModel: "anthropic/claude-sonnet-4",
            customHeaders: ["HTTP-Referer": "https://tilly.app", "X-Title": "Tilly"]
        ),
        ProviderConfiguration(
            providerID: .ollama,
            displayName: "Ollama (Local)",
            baseURL: URL(string: "http://localhost:11434/v1")!,
            defaultModel: "llama3.2"
        ),
        ProviderConfiguration(
            providerID: .dashScope,
            displayName: "Alibaba Qwen",
            baseURL: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!,
            defaultModel: "qwen-plus"
        ),
        ProviderConfiguration(
            providerID: .deepSeek,
            displayName: "DeepSeek",
            baseURL: URL(string: "https://api.deepseek.com/v1")!,
            defaultModel: "deepseek-chat"
        ),
        ProviderConfiguration(
            providerID: .moonshot,
            displayName: "Kimi (Moonshot)",
            baseURL: URL(string: "https://api.moonshot.ai/v1")!,
            defaultModel: "moonshot-v1-8k"
        ),
        ProviderConfiguration(
            providerID: .zai,
            displayName: "ZAI (Zhipu AI)",
            baseURL: URL(string: "https://open.bigmodel.cn/api/paas/v4")!,
            defaultModel: "glm-4-flash"
        ),
        ProviderConfiguration(
            providerID: .zaiCoding,
            displayName: "ZAI Coding",
            baseURL: URL(string: "https://api.z.ai/api/coding/paas/v4")!,
            defaultModel: "glm-5.1"
        ),
    ]
}
