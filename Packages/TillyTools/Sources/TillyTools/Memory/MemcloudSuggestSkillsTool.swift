import Foundation
import TillyCore
import TillyStorage

/// Tool #39: Analyze cloud memories for repeated task patterns and suggest reusable skills.
public final class MemcloudSuggestSkillsTool: ToolExecutable, @unchecked Sendable {

    private let memoryService: MemoryService
    private let skillService: SkillService

    /// LLM handler for pattern analysis. Set by AppState.
    public var analysisHandler: ((String) async -> String)?

    public init(memoryService: MemoryService, skillService: SkillService) {
        self.memoryService = memoryService
        self.skillService = skillService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            type: "function",
            function: .init(
                name: "memcloud_suggest_skills",
                description: "Analyze cloud memories for repeated task patterns and suggest creating reusable skills. Scans for similar workflows, repeated tool sequences, and common tasks that appear 3+ times. Use to discover automation opportunities from past behavior.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "focus_area": .object([
                            "type": .string("string"),
                            "description": .string("Area to focus on (e.g., 'deployments', 'testing', 'file management'). Searches Memcloud for this domain.")
                        ]),
                        "min_occurrences": .object([
                            "type": .string("integer"),
                            "description": .string("Minimum pattern occurrences to suggest. Default 3.")
                        ])
                    ]),
                    "required": .array([])
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Codable {
            let focus_area: String?
            let min_occurrences: Int?
        }

        guard let data = arguments.data(using: .utf8),
              let args = try? JSONDecoder().decode(Args.self, from: data) else {
            return ToolResult(content: "Error: Invalid arguments", isError: true)
        }

        guard let client = memoryService.memcloudClient else {
            return ToolResult(content: "Memcloud not configured. Enable it first.", isError: true)
        }

        let focus = args.focus_area ?? "tasks and workflows"
        let minOcc = args.min_occurrences ?? 3

        // Search for task-related memories
        let queries = ["completed task workflow", "executed command deployment", focus]
        var allMemories: [MemcloudClient.SearchResult] = []
        var seen: Set<String> = []

        for query in queries {
            do {
                let response = try await client.search(query: query, topK: 30)
                for mem in response.memories where seen.insert(mem.id).inserted {
                    allMemories.append(mem)
                }
            } catch { continue }
        }

        if allMemories.isEmpty {
            return ToolResult(content: "No task memories found yet. As you use more tools and complete tasks, patterns will emerge for skill suggestions.")
        }

        // Check existing skills to avoid duplicates
        let existingSkills = (try? skillService.list()) ?? []

        // Analyze with LLM if handler available
        if let handler = analysisHandler {
            let memoryDump = allMemories.prefix(50).map { "- \(String($0.content.prefix(300)))" }.joined(separator: "\n")
            let existingList = existingSkills.isEmpty ? "(none)" :
                existingSkills.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")

            let prompt = """
            Analyze these memories for repeated patterns appearing \(minOcc)+ times.
            Focus: \(focus)

            ## Memories
            \(memoryDump)

            ## Existing Skills (do NOT suggest duplicates)
            \(existingList)

            For each pattern found, suggest a skill:
            1. **Name**: Short name
            2. **Trigger**: Comma-separated trigger phrases
            3. **Description**: One line
            4. **Instructions**: Step-by-step with specific tools to use
            5. **Occurrences**: How many times this pattern appeared

            If no patterns with \(minOcc)+ occurrences, say "No strong patterns detected yet."
            """

            let analysis = await handler(prompt)
            return ToolResult(content: """
                ## Skill Suggestions from Memory Patterns

                \(analysis)

                Use `skill_create` to create any suggested skill.
                """)
        }

        // Fallback without LLM
        return ToolResult(content: """
            ## Memory Pattern Analysis (basic)

            Found \(allMemories.count) task memories in focus area: \(focus).
            Top memory topics:
            \(allMemories.prefix(10).map { "- \(String($0.content.prefix(150)))" }.joined(separator: "\n"))

            Configure LLM handler for intelligent pattern detection.
            """)
    }
}
