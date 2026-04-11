import Foundation
import TillyCore

/// Classifies incoming user requests to determine the optimal handling path.
/// Uses a cheap/fast model for classification to minimize overhead.
public struct TriageRouter: Sendable {
    public enum Route: Sendable, Equatable {
        case direct                                    // Simple answer, no tools
        case singleTool(String)                        // One tool predicted
        case specialist(role: String, tools: [String]) // Sub-agent delegation
        case planAndExecute                            // Complex multi-step
    }

    public struct Classification: Sendable {
        public let route: Route
        public let complexity: Double  // 0.0 = trivial, 1.0 = very complex
        public let reason: String
    }

    private let provider: any LLMProvider
    private let routingModel: String

    public init(provider: any LLMProvider, routingModel: String) {
        self.provider = provider
        self.routingModel = routingModel
    }

    public func classify(userMessage: String, context: String) async throws -> Classification {
        let prompt = """
        Classify this user request. Respond with ONLY valid JSON (no markdown):
        {"route": "direct|single_tool|specialist|plan_and_execute", "complexity": 0.0-1.0, "reason": "brief explanation", "tool": "tool_name_if_single", "role": "specialist_role_if_applicable"}

        Available tools: execute_command, read_file, write_file, edit_file, list_directory, web_search, web_fetch, http_request, git, memory_store, memory_search, memcloud_recall, skill_run, ask_user, delegate_task, plan_task, screenshot, clipboard

        Context: \(String(context.prefix(500)))

        User request: \(userMessage)
        """

        let request = ChatCompletionRequest(
            model: routingModel,
            messages: [
                ChatCompletionRequest.ChatMessage(role: "system", content: "You are a request classifier. Output JSON only."),
                ChatCompletionRequest.ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: 200,
            stream: false
        )

        let response = try await provider.complete(request)
        guard let text = response.choices.first?.message.content else {
            return Classification(route: .direct, complexity: 0.3, reason: "No classification response")
        }

        return parseClassification(text)
    }

    private func parseClassification(_ text: String) -> Classification {
        let cleaned = extractJSON(text)
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Classification(route: .direct, complexity: 0.3, reason: "Parse failed: \(String(text.prefix(80)))")
        }

        let routeStr = json["route"] as? String ?? "direct"
        let complexity = json["complexity"] as? Double ?? 0.3
        let reason = json["reason"] as? String ?? ""
        let tool = json["tool"] as? String
        let role = json["role"] as? String

        let route: Route
        switch routeStr {
        case "single_tool":
            route = .singleTool(tool ?? "execute_command")
        case "specialist":
            route = .specialist(role: role ?? "researcher", tools: ["web_search", "web_fetch", "read_file"])
        case "plan_and_execute":
            route = .planAndExecute
        default:
            route = .direct
        }

        return Classification(route: route, complexity: complexity, reason: reason)
    }

    /// Strip markdown fences and extract the JSON object from LLM output.
    private func extractJSON(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("{") { return cleaned }
        if let range = cleaned.range(of: "\\{[^}]+\\}", options: .regularExpression) {
            return String(cleaned[range])
        }
        return cleaned
    }
}
