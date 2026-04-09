import Foundation
import TillyCore
import TillyStorage

public final class ScratchpadWriteTool: ToolExecutable, @unchecked Sendable {
    private let service: ScratchpadService
    public init(service: ScratchpadService) { self.service = service }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "scratchpad_write",
                description: "Write to your working scratchpad — your session-scoped working memory for organizing complex tasks. Use sections to structure your notes: Plan, Progress, Findings, Notes. The scratchpad persists throughout this session and is visible in your system prompt.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "action": .object([
                            "type": .string("string"),
                            "enum": .array([.string("write"), .string("append"), .string("clear")]),
                            "description": .string("'write' overwrites everything, 'append' adds to a section, 'clear' empties the scratchpad."),
                        ]),
                        "section": .object([
                            "type": .string("string"),
                            "description": .string("Section name: Plan, Progress, Findings, Notes, or any custom name."),
                        ]),
                        "content": .object([
                            "type": .string("string"),
                            "description": .string("The content to write or append."),
                        ]),
                    ]),
                    "required": .array([.string("action")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let action: String
            let section: String?
            let content: String?
        }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments")
        }
        let args = try JSONDecoder().decode(Args.self, from: data)

        switch args.action {
        case "write":
            service.write(args.content ?? "")
            return ToolResult(content: "Scratchpad updated.")
        case "append":
            service.append(section: args.section ?? "Notes", content: args.content ?? "")
            return ToolResult(content: "Appended to \(args.section ?? "Notes") section.")
        case "clear":
            service.clear()
            return ToolResult(content: "Scratchpad cleared.")
        default:
            return ToolResult(content: "Unknown action: \(args.action). Use write, append, or clear.", isError: true)
        }
    }
}
