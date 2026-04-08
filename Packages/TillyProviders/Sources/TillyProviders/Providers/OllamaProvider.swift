import Foundation
import TillyCore

public final class OllamaProvider: OpenAICompatibleProvider {
    override public var requiresAPIKey: Bool { false }

    public func listLocalModels() async throws -> [ModelInfo] {
        // Ollama also supports /api/tags for its native format
        let url = configuration.baseURL
            .deletingLastPathComponent()  // remove /v1
            .appendingPathComponent("api/tags")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        struct TagsResponse: Decodable {
            let models: [OllamaModel]
            struct OllamaModel: Decodable {
                let name: String
                let model: String
                let size: Int64?
            }
        }

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TagsResponse.self, from: data)

        return response.models.map { model in
            ModelInfo(
                id: model.name,
                name: model.name,
                provider: .ollama
            )
        }
    }

    override public func listModels() async throws -> [ModelInfo] {
        // Try Ollama's native API first, fall back to OpenAI-compat
        do {
            return try await listLocalModels()
        } catch {
            return try await super.listModels()
        }
    }
}
