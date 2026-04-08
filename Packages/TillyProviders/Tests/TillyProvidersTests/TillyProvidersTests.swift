import Testing
@testable import TillyProviders
import TillyCore

@Test func providerFactoryCreatesAllProviders() {
    struct MockKeychain: KeychainReadable {
        func getAPIKey(for provider: ProviderID) throws -> String? { "test-key" }
    }

    let keychain = MockKeychain()
    for config in ProviderConfiguration.defaults {
        let provider = ProviderFactory.createProvider(for: config, keychain: keychain)
        #expect(provider.id == config.providerID)
    }
}
