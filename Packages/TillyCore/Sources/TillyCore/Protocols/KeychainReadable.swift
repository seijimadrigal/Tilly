import Foundation

public protocol KeychainReadable: Sendable {
    func getAPIKey(for provider: ProviderID) throws -> String?
}
