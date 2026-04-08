import Foundation
import TillyCore
import TillyStorage

public final class SkillDeleteTool: ToolExecutable, @unchecked Sendable {
    private let service: SkillService

    public init(service: SkillService) { self.service = service }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "skill_delete",
                description: "Delete a saved skill by name.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object([
                            "type": .string("string"),
                            "description": .string("The name of the skill to delete."),
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
            try service.delete(name: args.name)
            return ToolResult(content: "Skill '\(args.name)' deleted.")
        } catch {
            return ToolResult(content: "Failed to delete skill: \(error.localizedDescription)", isError: true)
        }
    }
}
