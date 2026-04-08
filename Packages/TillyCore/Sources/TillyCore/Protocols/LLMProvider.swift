import Foundation

public protocol LLMProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    var configuration: ProviderConfiguration { get }

    func listModels() async throws -> [ModelInfo]
    func complete(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse
    func stream(_ request: ChatCompletionRequest) -> AsyncThrowingStream<StreamDelta, Error>
    func isAvailable() async -> Bool
}
