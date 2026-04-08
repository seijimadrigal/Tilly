import Foundation
import TillyCore
import TillyStorage

public final class SkillCreateTool: ToolExecutable, @unchecked Sendable {
    private let service: SkillService

    public init(service: SkillService) { self.service = service }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "skill_create",
                description: "Save a reusable skill (workflow) that can be invoked later. Skills are step-by-step instructions that use tools to accomplish a task. Create skills when you discover useful workflows that the user might want to repeat.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object([
                            "type": .string("string"),
                            "description": .string("Human-readable name for the skill (e.g., 'Deploy to Production')."),
                        ]),
                        "description": .object([
                            "type": .string("string"),
                            "description": .string("One-line description of what this skill does."),
                        ]),
                        "trigger": .object([
                            "type": .string("string"),
                            "description": .string("Comma-separated trigger phrases (e.g., 'deploy, push to prod, ship it')."),
                        ]),
                        "instructions": .object([
                            "type": .string("string"),
                            "description": .string("Full step-by-step instructions for executing this skill. Include which tools to use and what to check."),
                        ]),
                    ]),
                    "required": .array([.string("name"), .string("description"), .string("trigger"), .string("instructions")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let name: String
            let description: String
            let trigger: String
            let instructions: String
        }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments")
        }

        let args = try JSONDecoder().decode(Args.self, from: data)
        let entry = try service.create(
            name: args.name,
            description: args.description,
            trigger: args.trigger,
            instructions: args.instructions
        )

        return ToolResult(content: "Skill saved: '\(entry.name)' (id: \(entry.id))\nTriggers: \(entry.trigger)")
    }
}
