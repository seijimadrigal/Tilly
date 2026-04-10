import Foundation
import TillyCore
import TillyStorage

/// Run a sequence of skills, passing outputs from one as inputs to the next.
public final class SkillChainTool: ToolExecutable, @unchecked Sendable {
    private let skillService: SkillService
    private let scratchpadService: ScratchpadService

    /// Closure that runs a single skill with context. Set by AppState.
    /// Parameters: (skillName, contextString) -> result string
    public var runSkillHandler: ((String, String) async -> String)?

    public init(skillService: SkillService, scratchpadService: ScratchpadService) {
        self.skillService = skillService
        self.scratchpadService = scratchpadService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "skill_chain",
                description: "Run multiple skills in sequence, passing data between them. Each skill's output becomes context for the next. Use skill_plan first to determine the optimal chain, then skill_test to verify prerequisites, then skill_chain to execute.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "skills": .object(["type": .string("array"), "items": .object(["type": .string("string")]), "description": .string("Ordered list of skill names/IDs to execute.")]),
                        "inputs": .object(["type": .string("object"), "description": .string("Initial key-value inputs to seed the chain. E.g. {\"topic\": \"AI agents\", \"depth\": \"detailed\"}")]),
                    ]),
                    "required": .array([.string("skills")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let skills: [String]
            let inputs: [String: String]?
        }

        guard let data = arguments.data(using: .utf8) else { throw TillyError.toolExecutionFailed("Invalid args") }
        let args = try JSONDecoder().decode(Args.self, from: data)

        guard !args.skills.isEmpty else {
            return ToolResult(content: "No skills specified", isError: true)
        }

        guard let handler = runSkillHandler else {
            return ToolResult(content: "Skill chain handler not configured", isError: true)
        }

        // Load all skills first to validate
        var loadedSkills: [SkillEntry] = []
        for name in args.skills {
            do {
                let skill = try skillService.load(name: name)
                loadedSkills.append(skill)
            } catch {
                return ToolResult(content: "Skill not found: '\(name)'. Chain aborted.", isError: true)
            }
        }

        // Initialize chain context
        var chainContext = args.inputs ?? [:]
        var chainResults: [String] = []

        scratchpadService.append(section: "Skill Chain", content: "Starting chain: \(args.skills.joined(separator: " → "))")

        // Execute each skill in order
        for (index, skill) in loadedSkills.enumerated() {
            let stepLabel = "Step \(index + 1)/\(loadedSkills.count): \(skill.name)"
            scratchpadService.append(section: "Progress", content: "Running \(stepLabel)")

            // Check required inputs exist
            for input in skill.inputs {
                if chainContext[input] == nil {
                    return ToolResult(
                        content: "Chain stopped at \(stepLabel): missing required input '\(input)'\n\nAvailable context keys: \(chainContext.keys.sorted().joined(separator: ", "))",
                        isError: true
                    )
                }
            }

            // Build context string for this skill
            var contextStr = "## Chain Context (Step \(index + 1)/\(loadedSkills.count))\n"
            for (key, value) in chainContext {
                let preview = value.count > 500 ? String(value.prefix(500)) + "..." : value
                contextStr += "**\(key)**: \(preview)\n"
            }
            if index > 0 {
                contextStr += "\n## Previous Step Output:\n\(chainResults.last ?? "(none)")\n"
            }

            // Run the skill
            let result = await handler(skill.name, contextStr)

            // Store outputs
            for output in skill.outputs {
                chainContext[output] = result
            }
            // Also store under the skill name for generic access
            chainContext[skill.id] = result
            chainResults.append(result)

            scratchpadService.append(section: "Progress", content: "✓ \(stepLabel) complete (\(result.count) chars)")
        }

        // Build final summary
        var summary = "# Skill Chain Complete\n\n"
        summary += "Chain: \(loadedSkills.map(\.name).joined(separator: " → "))\n"
        summary += "Steps: \(loadedSkills.count)\n\n"

        for (i, skill) in loadedSkills.enumerated() {
            let preview = chainResults[i].count > 200 ? String(chainResults[i].prefix(200)) + "..." : chainResults[i]
            summary += "## Step \(i + 1): \(skill.name)\n\(preview)\n\n"
        }

        summary += "## Final Output\n\(chainResults.last ?? "(empty)")"

        return ToolResult(content: summary)
    }
}
