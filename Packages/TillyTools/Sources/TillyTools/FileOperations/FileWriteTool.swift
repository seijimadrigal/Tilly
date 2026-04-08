import Foundation
import TillyCore

public final class FileWriteTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "write_file",
                description: "Write content to a file. Creates the file if it doesn't exist, or overwrites it if it does. Creates parent directories as needed.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object([
                            "type": .string("string"),
                            "description": .string("Absolute or relative path to the file to write."),
                        ]),
                        "content": .object([
                            "type": .string("string"),
                            "description": .string("The content to write to the file."),
                        ]),
                        "append": .object([
                            "type": .string("boolean"),
                            "description": .string("If true, append to the file instead of overwriting. Defaults to false."),
                        ]),
                    ]),
                    "required": .array([.string("path"), .string("content")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let path: String
            let content: String
            let append: Bool?
        }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments encoding")
        }

        let args = try JSONDecoder().decode(Args.self, from: data)
        let expandedPath = NSString(string: args.path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        do {
            // Create parent directories if needed
            let parentDir = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.createDirectory(
                    at: parentDir,
                    withIntermediateDirectories: true
                )
            }

            if args.append == true, FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                handle.seekToEndOfFile()
                if let data = args.content.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try args.content.write(to: url, atomically: true, encoding: .utf8)
            }

            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
            return ToolResult(
                content: "Successfully wrote \(size) bytes to \(args.path)"
            )
        } catch {
            return ToolResult(
                content: "Failed to write file: \(error.localizedDescription)",
                isError: true
            )
        }
    }
}
