import Foundation
import TillyCore
import TillyStorage

public final class SkillListTool: ToolExecutable, @unchecked Sendable {
    private let service: SkillService

    public init(service: SkillService) { self.service = service }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "skill_list",
                description: "List all available skills with their names, descriptions, and trigger phrases.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        let index = service.loadIndex()
        return ToolResult(content: "Available skills:\n\n\(index)")
    }
}
