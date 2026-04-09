import Foundation
import TillyCore

/// Tool that lets the main agent delegate a sub-task to a child agent.
/// The child runs its own independent agent loop with restricted tools
/// and returns the result as text.
public final class DelegateTaskTool: ToolExecutable, @unchecked Sendable {
    /// Closure that creates and runs a sub-agent. Set by AppState.
    /// Parameters: (task, role, allowedTools, maxRounds) -> result string
    public var handler: ((String, String, [String]?, Int) async -> String)?

    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "delegate_task",
                description: """
                Delegate a sub-task to an independent child agent. The child agent runs its own tool loop and returns the result. Use this for:
                - Research tasks (child uses web_fetch to gather info while you continue)
                - File exploration (child reads/lists files and summarizes)
                - Complex sub-problems that benefit from focused attention
                - Parallel workstreams where the child handles one part

                The child agent has its own context window and tool access. It cannot see the parent conversation. Give it clear, specific instructions.
                """,
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "task": .object([
                            "type": .string("string"),
                            "description": .string("Clear, specific instructions for the sub-agent. Include all context it needs since it cannot see the parent conversation."),
                        ]),
                        "role": .object([
                            "type": .string("string"),
                            "description": .string("The sub-agent's role/persona. E.g., 'researcher', 'code reviewer', 'file organizer', 'documentation writer'."),
                        ]),
                        "allowed_tools": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("string")]),
                            "description": .string("Optional list of tool names the sub-agent can use. Defaults to: web_fetch, read_file, list_directory, execute_command, scratchpad_write. Keep it minimal for focused work."),
                        ]),
                        "max_rounds": .object([
                            "type": .string("integer"),
                            "description": .string("Max tool-call rounds for the sub-agent. Default 10. Use more for complex research, less for simple lookups."),
                        ]),
                    ]),
                    "required": .array([.string("task"), .string("role")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let task: String
            let role: String
            let allowed_tools: [String]?
            let max_rounds: Int?
        }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments")
        }

        let args = try JSONDecoder().decode(Args.self, from: data)

        guard let handler else {
            return ToolResult(
                content: "Sub-agent delegation not available (no handler configured)",
                isError: true
            )
        }

        let result = await handler(
            args.task,
            args.role,
            args.allowed_tools,
            args.max_rounds ?? 10
        )

        return ToolResult(content: "## Sub-Agent Result (\(args.role))\n\n\(result)")
    }
}
