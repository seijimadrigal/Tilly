import Foundation
import TillyCore

/// Search the web via Brave Search API — fast, structured JSON results.
/// Falls back to Tavily, then DuckDuckGo if Brave fails.
public final class WebSearchTool: ToolExecutable, @unchecked Sendable {
    private let braveApiKey = "BSAlwJKXsAETeTNSQgRXv6ZePlelUex"
    private let tavilyApiKey = "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"

    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "web_search",
                description: "Search the web using Brave Search. Returns titles, URLs, and content snippets. Use for finding information, documentation, current events, and research. Follow up with web_fetch to read full pages.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object(["type": .string("string"), "description": .string("The search query.")]),
                        "num_results": .object(["type": .string("integer"), "description": .string("Number of results. Default 5, max 20.")]),
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
        let maxResults = min(args.num_results ?? 5, 20)

        let isAdvanced = (args.search_depth ?? "basic") == "advanced"
        let braveCount = isAdvanced ? max(maxResults, 15) : maxResults

        // Try Brave Search first
        let braveResult = await braveSearch(query: args.query, count: braveCount, freshness: isAdvanced ? "pw" : nil)
        if !braveResult.isError {
            // For advanced: if Brave returned few results, enrich with Tavily
            if isAdvanced {
                let resultLines = braveResult.content.components(separatedBy: "\n").filter { $0.contains("http") }
                if resultLines.count < 3 {
                    let tavilyResult = await tavilySearch(query: args.query, maxResults: maxResults, depth: "advanced")
                    if !tavilyResult.isError {
                        return ToolResult(content: braveResult.content + "\n--- Additional results ---\n\n" + tavilyResult.content)
                    }
                }
            }
            return braveResult
        }

        // Fallback to Tavily
        let tavilyResult = await tavilySearch(query: args.query, maxResults: maxResults, depth: args.search_depth ?? "basic")
        if !tavilyResult.isError { return tavilyResult }

        // Last resort: DuckDuckGo
        return await ddgSearch(query: args.query, maxResults: maxResults)
    }

    // MARK: - Brave Search (primary)

    private func braveSearch(query: String, count: Int, freshness: String? = nil) async -> ToolResult {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        var urlString = "https://api.search.brave.com/res/v1/web/search?q=\(encoded)&count=\(count)"
        if let freshness { urlString += "&freshness=\(freshness)" }
        guard let url = URL(string: urlString) else {
            return ToolResult(content: "Invalid query", isError: true)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(braveApiKey)", forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                return ToolResult(content: "Brave Search error (HTTP \(code))", isError: true)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ToolResult(content: "Failed to parse Brave response", isError: true)
            }

            var output = "Search results for: \(query)\n\n"

            // Web results
            if let web = json["web"] as? [String: Any],
               let results = web["results"] as? [[String: Any]] {
                for (i, result) in results.enumerated() {
                    let title = result["title"] as? String ?? "Untitled"
                    let resultUrl = result["url"] as? String ?? ""
                    let description = result["description"] as? String ?? ""

                    output += "\(i + 1). \(title)\n"
                    output += "   \(resultUrl)\n"
                    if !description.isEmpty {
                        output += "   \(String(description.prefix(250)))\n"
                    }
                    output += "\n"
                }
            }

            if output == "Search results for: \(query)\n\n" {
                return ToolResult(content: "No results found for: \(query)")
            }

            return ToolResult(content: output)
        } catch {
            return ToolResult(content: "Brave Search failed: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - Tavily (fallback 1)

    private func tavilySearch(query: String, maxResults: Int, depth: String) async -> ToolResult {
        let requestBody: [String: Any] = [
            "api_key": tavilyApiKey,
            "query": query,
            "max_results": maxResults,
            "search_depth": depth,
            "include_answer": true,
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody),
              let url = URL(string: "https://api.tavily.com/search") else {
            return ToolResult(content: "Tavily request build failed", isError: true)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                return ToolResult(content: "Tavily error (HTTP \(code))", isError: true)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ToolResult(content: "Failed to parse Tavily response", isError: true)
            }

            var output = "Search results for: \(query)\n\n"

            if let answer = json["answer"] as? String, !answer.isEmpty {
                output += "**Quick Answer:** \(answer)\n\n"
            }

            if let results = json["results"] as? [[String: Any]] {
                for (i, result) in results.enumerated() {
                    let title = result["title"] as? String ?? "Untitled"
                    let resultUrl = result["url"] as? String ?? ""
                    let content = result["content"] as? String ?? ""
                    output += "\(i + 1). \(title)\n   \(resultUrl)\n"
                    if !content.isEmpty { output += "   \(String(content.prefix(200)))\n" }
                    output += "\n"
                }
            }

            if output == "Search results for: \(query)\n\n" {
                return ToolResult(content: "No results found for: \(query)")
            }
            return ToolResult(content: output)
        } catch {
            return ToolResult(content: "Tavily failed: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - DuckDuckGo (fallback 2)

    private func ddgSearch(query: String, maxResults: Int) async -> ToolResult {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1") else {
            return ToolResult(content: "Search failed: invalid query", isError: true)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ToolResult(content: "DuckDuckGo: failed to parse", isError: true)
            }

            var output = "Search results for: \(query) (via DuckDuckGo)\n\n"

            if let abstract = json["Abstract"] as? String, !abstract.isEmpty {
                let source = json["AbstractSource"] as? String ?? ""
                let abstractURL = json["AbstractURL"] as? String ?? ""
                output += "**Answer:** \(abstract)\n"
                if !abstractURL.isEmpty { output += "Source: \(source) — \(abstractURL)\n" }
                output += "\n"
            }

            if let topics = json["RelatedTopics"] as? [[String: Any]] {
                for (i, topic) in topics.prefix(maxResults).enumerated() {
                    if let text = topic["Text"] as? String,
                       let firstURL = topic["FirstURL"] as? String {
                        output += "\(i + 1). \(String(text.prefix(200)))\n   \(firstURL)\n\n"
                    }
                }
            }

            if output == "Search results for: \(query) (via DuckDuckGo)\n\n" {
                return ToolResult(content: "No results found for: \(query)")
            }
            return ToolResult(content: output)
        } catch {
            return ToolResult(content: "All search engines failed: \(error.localizedDescription)", isError: true)
        }
    }
}
