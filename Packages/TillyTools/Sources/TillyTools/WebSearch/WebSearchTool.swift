import Foundation
import TillyCore

/// Search the web via Tavily API — structured JSON results, no HTML scraping.
public final class WebSearchTool: ToolExecutable, @unchecked Sendable {
    private let apiKey = "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"

    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "web_search",
                description: "Search the web using Tavily. Returns titles, URLs, and content snippets. Use for finding information, documentation, current events, and research. Follow up with web_fetch to read full pages.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object(["type": .string("string"), "description": .string("The search query.")]),
                        "num_results": .object(["type": .string("integer"), "description": .string("Number of results. Default 5, max 10.")]),
                        "search_depth": .object(["type": .string("string"), "enum": .array([.string("basic"), .string("advanced")]), "description": .string("'basic' for quick search, 'advanced' for deeper research. Default basic.")]),
                    ]),
                    "required": .array([.string("query")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let query: String
            let num_results: Int?
            let search_depth: String?
        }

        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        let maxResults = min(args.num_results ?? 5, 10)

        // Build Tavily API request
        let requestBody: [String: Any] = [
            "api_key": apiKey,
            "query": args.query,
            "max_results": maxResults,
            "search_depth": args.search_depth ?? "basic",
            "include_answer": true,
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody),
              let url = URL(string: "https://api.tavily.com/search") else {
            return ToolResult(content: "Failed to build search request", isError: true)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return ToolResult(content: "Invalid response from Tavily", isError: true)
            }

            guard (200...299).contains(http.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                return ToolResult(content: "Tavily API error (HTTP \(http.statusCode)): \(errorBody)", isError: true)
            }

            // Parse Tavily JSON response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ToolResult(content: "Failed to parse Tavily response", isError: true)
            }

            var output = "Search results for: \(args.query)\n\n"

            // Include Tavily's AI-generated answer if available
            if let answer = json["answer"] as? String, !answer.isEmpty {
                output += "**Quick Answer:** \(answer)\n\n"
            }

            // Parse individual results
            if let results = json["results"] as? [[String: Any]] {
                for (i, result) in results.enumerated() {
                    let title = result["title"] as? String ?? "Untitled"
                    let url = result["url"] as? String ?? ""
                    let content = result["content"] as? String ?? ""

                    output += "\(i + 1). \(title)\n"
                    output += "   \(url)\n"
                    if !content.isEmpty {
                        let snippet = String(content.prefix(200))
                        output += "   \(snippet)\n"
                    }
                    output += "\n"
                }
            }

            if output == "Search results for: \(args.query)\n\n" {
                return ToolResult(content: "No results found for: \(args.query)")
            }

            return ToolResult(content: output)
        } catch {
            return ToolResult(content: "Search failed: \(error.localizedDescription)", isError: true)
        }
    }
}
