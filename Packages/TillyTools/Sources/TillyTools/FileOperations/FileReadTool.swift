import Foundation
import TillyCore

public final class FileReadTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "read_file",
                description: "Read the contents of a file at the given path. Returns the file text content. For binary files, returns a description. Supports reading specific line ranges.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Absolute or relative path to the file to read."),
                        ]),
                        "start_line": .object([
                            "type": .string("integer"),
                            "description": .string("Optional 1-based start line number. If provided, only lines from this number onward are returned."),
                        ]),
                        "end_line": .object([
                            "type": .string("integer"),
                            "description": .string("Optional 1-based end line number. If provided, only lines up to this number are returned."),
                        ]),
                    ]),
                    "required": .array([.string("path")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let path: String
            let start_line: Int?
            let end_line: Int?
        }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments encoding")
        }

        let args = try JSONDecoder().decode(Args.self, from: data)
        let expandedPath = NSString(string: args.path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return ToolResult(content: "File not found: \(args.path)", isError: true)
        }

        guard FileManager.default.isReadableFile(atPath: url.path) else {
            return ToolResult(content: "File is not readable: \(args.path)", isError: true)
        }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            var lines = content.components(separatedBy: .newlines)

            // Apply line range if specified
            if let startLine = args.start_line {
                let start = max(0, startLine - 1)
                lines = Array(lines.dropFirst(start))
            }
            if let endLine = args.end_line {
                let adjustedEnd: Int
                if let startLine = args.start_line {
                    adjustedEnd = endLine - startLine + 1
                } else {
                    adjustedEnd = endLine
                }
                lines = Array(lines.prefix(max(0, adjustedEnd)))
            }

            var result = lines.joined(separator: "\n")

            // Truncate very long files
            let maxLength = 15000
            if result.count > maxLength {
                result = String(result.prefix(maxLength))
                    + "\n... [file truncated at \(maxLength) chars, use start_line/end_line to read specific sections]"
            }

            return ToolResult(content: result)
        } catch {
            return ToolResult(
                content: "Failed to read file: \(error.localizedDescription)",
                isError: true
            )
        }
    }
}
