import Foundation
import TillyCore
#if canImport(AppKit)
import AppKit
#endif

/// Read and write the system clipboard.
public final class ClipboardTool: ToolExecutable, @unchecked Sendable {
    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "clipboard",
                description: "Read or write the macOS system clipboard. Use 'read' to get current clipboard content, 'write' to set it. Useful for transferring data between apps.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object(["type": .string("string"), "enum": .array([.string("read"), .string("write")]), "description": .string("'read' to get clipboard, 'write' to set it.")]),
                        "content": .object(["type": .string("string"), "description": .string("Text to write to clipboard (required for write action).")]),
                    ]),
                    "required": .array([.string("action")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable { let action: String; let content: String? }
        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        #if canImport(AppKit)
        switch args.action {
        case "read":
            let text = NSPasteboard.general.string(forType: .string) ?? "(clipboard is empty)"
            return ToolResult(content: text)
        case "write":
            guard let content = args.content else { return ToolResult(content: "No content to write", isError: true) }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
            return ToolResult(content: "Copied \(content.count) chars to clipboard.")
        default:
            return ToolResult(content: "Unknown action: \(args.action)", isError: true)
        }
        #else
        return ToolResult(content: "Clipboard not available on this platform", isError: true)
        #endif
    }
}
