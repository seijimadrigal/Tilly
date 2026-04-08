import Foundation
import TillyCore

open class OpenAICompatibleProvider: @unchecked Sendable, LLMProvider {
    public let id: ProviderID
    public let displayName: String
    public let configuration: ProviderConfiguration
    private let keychain: any KeychainReadable
    private let session: URLSession

    open var requiresAPIKey: Bool { configuration.providerID.requiresAPIKey }
    open var chatCompletionsPath: String { "/chat/completions" }
    open var modelsPath: String { "/models" }

    open func additionalHeaders() -> [String: String] { [:] }

    public init(configuration: ProviderConfiguration, keychain: any KeychainReadable) {
        self.id = configuration.providerID
        self.displayName = configuration.displayName
        self.configuration = configuration
        self.keychain = keychain

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.timeoutSeconds
        config.httpAdditionalHeaders = ["Content-Type": "application/json"]
        self.session = URLSession(configuration: config)
    }

    // MARK: - LLMProvider

    public func listModels() async throws -> [ModelInfo] {
        let url = configuration.baseURL.appendingPathComponent(modelsPath)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        try applyAuth(&request)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        struct ModelsResponse: Decodable {
            let data: [ModelEntry]
            struct ModelEntry: Decodable {
                let id: String
                let owned_by: String?
            }
        }

        let models = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return models.data.map { entry in
            ModelInfo(
                id: entry.id,
                name: entry.id,
                provider: id
            )
        }
    }

    public func complete(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        let urlRequest = try buildRequest(for: request)
        let (data, response) = try await session.data(for: urlRequest)
        try validateResponse(response, data: data)
        return try JSONDecoder.api.decode(ChatCompletionResponse.self, from: data)
    }

    public func stream(_ request: ChatCompletionRequest) -> AsyncThrowingStream<StreamDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var streamRequest = request
                    streamRequest.stream = true
                    let urlRequest = try buildRequest(for: streamRequest)

                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    try validateResponse(response, data: nil)

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        // Skip empty lines, comments (keepalives)
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)

                        if payload == "[DONE]" { break }

                        guard let jsonData = payload.data(using: .utf8) else { continue }

                        do {
                            let delta = try JSONDecoder.api.decode(StreamDelta.self, from: jsonData)
                            continuation.yield(delta)
                        } catch {
                            // Skip malformed lines rather than aborting the whole stream
                            continue
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: TillyError.cancelled)
                } catch let urlError as URLError where urlError.code == .cancelled {
                    continuation.finish(throwing: TillyError.cancelled)
                } catch {
                    continuation.finish(throwing: mapError(error))
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func isAvailable() async -> Bool {
        let url = configuration.baseURL.appendingPathComponent(modelsPath)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        try? applyAuth(&request)

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                return (200...299).contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Private Helpers

    private func buildRequest(for completion: ChatCompletionRequest) throws -> URLRequest {
        let url = configuration.baseURL.appendingPathComponent(chatCompletionsPath)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        try applyAuth(&request)

        // Apply custom provider headers
        for (key, value) in configuration.customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        for (key, value) in additionalHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        request.httpBody = try encoder.encode(completion)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return request
    }

    private func applyAuth(_ request: inout URLRequest) throws {
        guard requiresAPIKey else { return }

        guard let apiKey = try keychain.getAPIKey(for: id) else {
            throw TillyError.authenticationRequired(id)
        }

        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    private func validateResponse(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { return }

        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw TillyError.invalidAPIKey(id)
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
            throw TillyError.rateLimited(retryAfter: retryAfter)
        case 529:
            throw TillyError.overloaded
        default:
            var message: String?
            if let data = data {
                if let errorResp = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                    message = errorResp.error.message
                } else {
                    message = String(data: data, encoding: .utf8)
                }
            }
            throw TillyError.httpError(statusCode: http.statusCode, message: message)
        }
    }

    private func mapError(_ error: Error) -> Error {
        if let tillyError = error as? TillyError {
            return tillyError
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return TillyError.timeout
            case .cancelled:
                return TillyError.cancelled
            default:
                return TillyError.networkError(urlError)
            }
        }
        return TillyError.networkError(error)
    }
}

extension JSONDecoder {
    static let api: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
}
