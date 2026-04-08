import Foundation
import TillyCore

/// A tool that lets the model ask the user a question mid-task.
/// The UI layer sets the `handler` closure to show a dialog and return the user's choice.
public final class AskUserTool: ToolExecutable, @unchecked Sendable {
    /// Callback that the UI sets. Called with (question, [options]) and returns the chosen option string.
    /// If nil, the tool falls back to returning a message asking the model to proceed with its best judgment.
    public var handler: (@MainActor (String, [String]) async -> String)?

    public init() {}

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "ask_user",
                description: "Ask the user a question when you are unsure how to proceed during a task. Present 3 clear options for them to choose from. Use this when: you encounter ambiguity, need to make a decision that affects the outcome, need confirmation before a destructive action, or want user preference on an approach.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "question": .object([
                            "type": .string("string"),
                            "description": .string("The question to ask the user. Be specific and concise."),
                        ]),
                        "option_1": .object([
                            "type": .string("string"),
                            "description": .string("First option - describe what will happen if chosen."),
                        ]),
                        "option_2": .object([
                            "type": .string("string"),
                            "description": .string("Second option - describe what will happen if chosen."),
                        ]),
                        "option_3": .object([
                            "type": .string("string"),
                            "description": .string("Third option - describe what will happen if chosen."),
                        ]),
                    ]),
                    "required": .array([.string("question"), .string("option_1"), .string("option_2"), .string("option_3")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let question: String
            let option_1: String
            let option_2: String
            let option_3: String
        }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments")
        }

        let args = try JSONDecoder().decode(Args.self, from: data)
        let options = [args.option_1, args.option_2, args.option_3]

        if let handler = handler {
            let answer = await handler(args.question, options)
            return ToolResult(content: "User chose: \(answer)")
        } else {
            // Fallback: no UI handler set
            return ToolResult(
                content: "Unable to ask user (no UI handler). Question was: \(args.question). Options: 1) \(args.option_1) 2) \(args.option_2) 3) \(args.option_3). Proceed with your best judgment.",
                isError: false
            )
        }
    }
}
