import Foundation
import TillyCore
import TillyStorage

public final class SkillRunTool: ToolExecutable, @unchecked Sendable {
    private let service: SkillService

    public init(service: SkillService) { self.service = service }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "skill_run",
                description: "Load and execute a saved skill by name or ID. Returns the skill's full instructions which you should then follow step by step using the appropriate tools.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object([
                            "type": .string("string"),
                            "description": .string("The name or ID of the skill to run."),
                        ]),
                    ]),
                    "required": .array([.string("name")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable { let name: String }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments")
        }

        let args = try JSONDecoder().decode(Args.self, from: data)

        do {
            let skill = try service.load(name: args.name)
            return ToolResult(content: """
            # Running Skill: \(skill.name)

            \(skill.description)

            ## Instructions
            \(skill.instructions)

            ---
            Follow these instructions now using the available tools.
            """)
        } catch {
            return ToolResult(
                content: "Skill not found: '\(args.name)'. Use skill_list to see available skills.",
                isError: true
            )
        }
    }
}
