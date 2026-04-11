import Foundation
import TillyCore

/// Evaluates agent output quality before returning to the user.
public struct ReflectionAgent: Sendable {
    private let provider: any LLMProvider
    private let model: String

    public init(provider: any LLMProvider, model: String) {
        self.provider = provider
        self.model = model
    }

    public struct ReflectionResult: Sendable {
        public let isAcceptable: Bool
        public let score: Double      // 0.0-1.0
        public let issues: [String]
        public let suggestion: String?
    }

    /// Critique the agent's response. Returns assessment with optional revision suggestion.
    public func critique(
        userRequest: String,
        agentResponse: String,
        toolsUsed: [String]
    ) async throws -> ReflectionResult {
        let prompt = """
        Evaluate this agent response. Respond with ONLY valid JSON:
        {"acceptable": true/false, "score": 0.0-1.0, "issues": ["issue1", ...], "suggestion": "how to improve or null"}

        User asked: \(String(userRequest.prefix(500)))
        Agent responded: \(String(agentResponse.prefix(1000)))
        Tools used: \(toolsUsed.joined(separator: ", "))

        Criteria:
        1. Does it actually answer the user's question?
        2. Is it complete or does it leave things unfinished?
        3. Is the information accurate (no obvious contradictions)?
        4. Is it well-structured and easy to understand?
        """

        let request = ChatCompletionRequest(
            model: model,
            messages: [
                ChatCompletionRequest.ChatMessage(role: "system", content: "You are a quality evaluator. Output JSON only."),
                ChatCompletionRequest.ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: 300,
            stream: false
        )

        let response = try await provider.complete(request)
        guard let text = response.choices.first?.message.content else {
            return ReflectionResult(isAcceptable: true, score: 0.7, issues: [], suggestion: nil)
        }

        return parseReflection(text)
    }

    private func parseReflection(_ text: String) -> ReflectionResult {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ReflectionResult(isAcceptable: true, score: 0.7, issues: [], suggestion: nil)
        }

        let acceptable = json["acceptable"] as? Bool ?? true
        let score = json["score"] as? Double ?? 0.7
        let issues = json["issues"] as? [String] ?? []
        let suggestion = json["suggestion"] as? String

        return ReflectionResult(
            isAcceptable: acceptable,
            score: score,
            issues: issues,
            suggestion: suggestion
        )
    }
}
