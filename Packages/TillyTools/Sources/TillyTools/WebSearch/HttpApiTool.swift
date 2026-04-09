import Foundation
import TillyCore

/// Full HTTP client — GET, POST, PUT, DELETE, PATCH with custom headers and JSON body.
public final class HttpApiTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "http_request",
                description: "Make an HTTP request to any URL. Supports GET, POST, PUT, DELETE, PATCH with custom headers and JSON body. Use for REST API calls, webhooks, form submissions, and structured data retrieval. Returns status code, headers, and response body.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "url": .object(["type": .string("string"), "description": .string("The URL to request.")]),
                        "method": .object(["type": .string("string"), "enum": .array([.string("GET"), .string("POST"), .string("PUT"), .string("DELETE"), .string("PATCH")]), "description": .string("HTTP method. Default GET.")]),
                        "headers": .object(["type": .string("object"), "description": .string("Optional headers as key-value pairs. E.g. {\"Authorization\": \"Bearer xxx\", \"Content-Type\": \"application/json\"}")]),
                        "body": .object(["type": .string("string"), "description": .string("Optional request body (usually JSON string for POST/PUT).")]),
                        "timeout": .object(["type": .string("number"), "description": .string("Timeout in seconds. Default 30.")]),
                    ]),
                    "required": .array([.string("url")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let url: String
            let method: String?
            let headers: [String: String]?
            let body: String?
            let timeout: Double?
        }

        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)
        guard let url = URL(string: args.url) else { return ToolResult(content: "Invalid URL: \(args.url)", isError: true) }

        var request = URLRequest(url: url)
        request.httpMethod = args.method ?? "GET"
        request.timeoutInterval = args.timeout ?? 30

        for (key, value) in args.headers ?? [:] {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body = args.body {
            request.httpBody = body.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            var output = "HTTP \(http?.statusCode ?? 0) \(args.method ?? "GET") \(args.url)\n"

            if let text = String(data: data, encoding: .utf8) {
                let maxLen = 10000
                output += text.count > maxLen ? String(text.prefix(maxLen)) + "\n...[truncated]" : text
            } else {
                output += "[Binary response: \(data.count) bytes]"
            }
            return ToolResult(content: output, isError: http.map { !(200...299).contains($0.statusCode) } ?? false)
        } catch {
            return ToolResult(content: "Request failed: \(error.localizedDescription)", isError: true)
        }
    }
}
