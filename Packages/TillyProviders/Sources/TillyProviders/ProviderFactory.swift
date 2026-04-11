import Foundation
import TillyCore

public enum ProviderFactory {
    public static func createProvider(
        for config: ProviderConfiguration,
        keychain: any KeychainReadable
    ) -> any LLMProvider {
        switch config.providerID {
        case .openRouter:
            return OpenRouterProvider(configuration: config, keychain: keychain)
        case .ollama:
            return OllamaProvider(configuration: config, keychain: keychain)
        case .dashScope:
            return DashScopeProvider(configuration: config, keychain: keychain)
        case .deepSeek:
            return DeepSeekProvider(configuration: config, keychain: keychain)
        case .moonshot:
            return MoonshotProvider(configuration: config, keychain: keychain)
        case .zai:
            return ZAIProvider(configuration: config, keychain: keychain)
        case .zaiCoding:
            return ZAIProvider(configuration: config, keychain: keychain)
        case .google:
            return OpenAICompatibleProvider(configuration: config, keychain: keychain)
        case .xai:
            return OpenAICompatibleProvider(configuration: config, keychain: keychain)
        }
    }
}
