import Foundation
import TillyCore

/// Search the web via DuckDuckGo (no API key needed).
public final class WebSearchTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "web_search",
                description: "Search the web using DuckDuckGo. Returns titles, URLs, and snippets for the top results. Use this when you need to find information, documentation, or current events. Follow up with web_fetch to read specific pages.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object(["type": .string("string"), "description": .string("The search query.")]),
                        "num_results": .object(["type": .string("integer"), "description": .string("Number of results to return. Default 5, max 10.")]),
                    ]),
                    "required": .array([.string("query")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable { let query: String; let num_results: Int? }
        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        let maxResults = min(args.num_results ?? 5, 10)
        let encoded = args.query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? args.query

        // Use DuckDuckGo HTML search (no API key needed)
        let searchURL = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)")!
        var request = URLRequest(url: searchURL)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Tilly/0.1", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else {
                return ToolResult(content: "Failed to decode search results", isError: true)
            }

            let results = parseResults(html: html, maxResults: maxResults)

            if results.isEmpty {
                return ToolResult(content: "No results found for: \(args.query)")
            }

            var output = "Search results for: \(args.query)\n\n"
            for (i, result) in results.enumerated() {
                output += "\(i + 1). \(result.title)\n"
                output += "   \(result.url)\n"
                if !result.snippet.isEmpty {
                    output += "   \(result.snippet)\n"
                }
                output += "\n"
            }

            return ToolResult(content: output)
        } catch {
            return ToolResult(content: "Search failed: \(error.localizedDescription)", isError: true)
        }
    }

    private struct SearchResult {
        let title: String
        let url: String
        let snippet: String
    }

    private func parseResults(html: String, maxResults: Int) -> [SearchResult] {
        var results: [SearchResult] = []

        // Parse DuckDuckGo HTML results — look for result links
        let linkPattern = #"<a rel="nofollow" class="result__a" href="([^"]+)"[^>]*>(.+?)</a>"#
        let snippetPattern = #"<a class="result__snippet"[^>]*>(.+?)</a>"#

        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: .dotMatchesLineSeparators),
              let snippetRegex = try? NSRegularExpression(pattern: snippetPattern, options: .dotMatchesLineSeparators) else {
            return results
        }

        let range = NSRange(html.startIndex..., in: html)
        let linkMatches = linkRegex.matches(in: html, range: range)
        let snippetMatches = snippetRegex.matches(in: html, range: range)

        for (i, match) in linkMatches.enumerated() {
            if results.count >= maxResults { break }

            guard let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else { continue }

            let url = String(html[urlRange])
            let title = stripTags(String(html[titleRange]))
            var snippet = ""

            if i < snippetMatches.count {
                if let snippetRange = Range(snippetMatches[i].range(at: 1), in: html) {
                    snippet = stripTags(String(html[snippetRange]))
                }
            }

            guard url.hasPrefix("http") else { continue }
            results.append(SearchResult(title: title, url: url, snippet: snippet))
        }

        return results
    }

    private func stripTags(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive) else { return html }
        return regex.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
