import Foundation
import TillyCore

/// Find-and-replace editing within files — no need to rewrite the whole file.
public final class FileEditTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "edit_file",
                description: "Edit a file by finding and replacing text. Much more precise than write_file — only changes the specific part you want. Supports replacing first match or all matches. Always read_file first to see the exact text to replace.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "path": .object(["type": .string("string"), "description": .string("Path to the file to edit.")]),
                        "old_text": .object(["type": .string("string"), "description": .string("The exact text to find in the file. Must match precisely including whitespace and newlines.")]),
                        "new_text": .object(["type": .string("string"), "description": .string("The replacement text.")]),
                        "replace_all": .object(["type": .string("boolean"), "description": .string("Replace all occurrences (true) or just the first (false). Default false.")]),
                    ]),
                    "required": .array([.string("path"), .string("old_text"), .string("new_text")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable { let path: String; let old_text: String; let new_text: String; let replace_all: Bool? }
        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        let expanded = NSString(string: args.path).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return ToolResult(content: "File not found: \(args.path)", isError: true)
        }

        do {
            var content = try String(contentsOf: url, encoding: .utf8)
            guard content.contains(args.old_text) else {
                return ToolResult(content: "old_text not found in file. Make sure it matches exactly (including whitespace).", isError: true)
            }

            let count: Int
            if args.replace_all == true {
                let occurrences = content.components(separatedBy: args.old_text).count - 1
                content = content.replacingOccurrences(of: args.old_text, with: args.new_text)
                count = occurrences
            } else {
                if let range = content.range(of: args.old_text) {
                    content.replaceSubrange(range, with: args.new_text)
                    count = 1
                } else {
                    count = 0
                }
            }

            try content.write(to: url, atomically: true, encoding: .utf8)
            return ToolResult(content: "Edited \(args.path): replaced \(count) occurrence\(count == 1 ? "" : "s").")
        } catch {
            return ToolResult(content: "Edit failed: \(error.localizedDescription)", isError: true)
        }
    }
}
