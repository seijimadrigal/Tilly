import Foundation
import TillyCore

public final class WebFetchTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "web_fetch",
                description: "Fetch the content of a web page and return its text. Useful for reading documentation, checking APIs, or researching information. Returns the page text content (HTML tags stripped).",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "url": .object([
                            "type": .string("string"),
                            "description": .string("The URL to fetch content from."),
                        ]),
                    ]),
                    "required": .array([.string("url")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let url: String
        }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments encoding")
        }

        let args = try JSONDecoder().decode(Args.self, from: data)

        guard let url = URL(string: args.url) else {
            return ToolResult(content: "Invalid URL: \(args.url)", isError: true)
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Tilly/0.1",
                forHTTPHeaderField: "User-Agent"
            )

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return ToolResult(content: "Invalid response from \(args.url)", isError: true)
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                return ToolResult(
                    content: "HTTP \(httpResponse.statusCode) from \(args.url)",
                    isError: true
                )
            }

            guard var text = String(data: data, encoding: .utf8) else {
                return ToolResult(content: "Could not decode response as text", isError: true)
            }

            // Basic HTML tag stripping
            text = stripHTML(text)

            // Truncate
            let maxLength = 10000
            if text.count > maxLength {
                text = String(text.prefix(maxLength)) + "\n... [truncated]"
            }

            return ToolResult(content: text)
        } catch {
            return ToolResult(
                content: "Fetch failed: \(error.localizedDescription)",
                isError: true
            )
        }
    }

    private func stripHTML(_ html: String) -> String {
        // Remove script and style blocks
        var text = html
        let patterns = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
            "<[^>]+>",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: " "
                )
            }
        }

        // Decode common HTML entities
        text = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        // Collapse whitespace
        if let regex = try? NSRegularExpression(pattern: "\\s+") {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
