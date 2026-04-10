import Foundation
import TillyCore
import TillyStorage

/// Analyze a task and recommend the optimal skill chain.
public final class SkillPlanTool: ToolExecutable, @unchecked Sendable {
    private let skillService: SkillService

    /// Closure that runs the planning sub-agent. Set by AppState.
    /// Parameters: (taskDescription, skillCatalog) -> recommended plan string
    public var planHandler: ((String, String) async -> String)?

    public init(skillService: SkillService) {
        self.skillService = skillService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "skill_plan",
                description: "Analyze a task and recommend the optimal sequence of skills to accomplish it. Returns a recommended chain with reasoning, prerequisites, and gaps. Use before skill_chain to plan the best approach.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "task": .object(["type": .string("string"), "description": .string("Description of the task to accomplish.")]),
                        "max_skills": .object(["type": .string("integer"), "description": .string("Max skills in the chain. Default 5.")]),
                    ]),
                    "required": .array([.string("task")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable { let task: String; let max_skills: Int? }
        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        guard let handler = planHandler else {
            return ToolResult(content: "Skill planning handler not configured", isError: true)
        }

        // Build skill catalog
        let skills: [SkillEntry]
        do {
            skills = try skillService.list()
        } catch {
            return ToolResult(content: "Failed to load skills: \(error.localizedDescription)", isError: true)
        }

        if skills.isEmpty {
            return ToolResult(content: "No skills available. Create skills first with skill_create.")
        }

        var catalog = "# Available Skills (\(skills.count))\n\n"
        for skill in skills {
            catalog += "## \(skill.name) (`\(skill.id)`)\n"
            catalog += "Description: \(skill.description)\n"
            catalog += "Triggers: \(skill.trigger)\n"
            if !skill.inputs.isEmpty { catalog += "Inputs: \(skill.inputs.joined(separator: ", "))\n" }
            if !skill.outputs.isEmpty { catalog += "Outputs: \(skill.outputs.joined(separator: ", "))\n" }
            if !skill.dependencies.isEmpty { catalog += "Dependencies: \(skill.dependencies.joined(separator: ", "))\n" }
            if !skill.tests.isEmpty { catalog += "Tests: \(skill.tests.count) prerequisites defined\n" }
            catalog += "\n"
        }

        let maxSkills = args.max_skills ?? 5
        let taskWithConstraints = "\(args.task)\n\nConstraint: Use at most \(maxSkills) skills."

        let plan = await handler(taskWithConstraints, catalog)

        return ToolResult(content: plan)
    }
}
