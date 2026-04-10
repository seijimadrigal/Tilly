import Foundation
import TillyCore
import TillyStorage

public final class PlanTaskTool: ToolExecutable, @unchecked Sendable {
    private let service: ScratchpadService
    private let memoryService: MemoryService?
    public init(service: ScratchpadService, memoryService: MemoryService? = nil) {
        self.service = service
        self.memoryService = memoryService
    }

    public var definition: ToolDefinition {
        ToolDefinition(
            function: ToolDefinition.FunctionDef(
                name: "plan_task",
                description: "Create a structured plan before executing a complex task. Writes a numbered checklist to your scratchpad. Use this for any task that will need 3+ tool calls. Plans help you stay organized and ensure you don't miss steps.",
                parameters: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "goal": .object([
                            "type": .string("string"),
                            "description": .string("What you want to accomplish."),
                        ]),
                        "steps": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("string")]),
                            "description": .string("Ordered list of steps to complete the goal."),
                        ]),
                        "estimated_rounds": .object([
                            "type": .string("integer"),
                            "description": .string("Estimated number of tool-call rounds this plan will take."),
                        ]),
                    ]),
                    "required": .array([.string("goal"), .string("steps")]),
                ])
            )
        )
    }

    public func execute(arguments: String) async throws -> ToolResult {
        struct Args: Decodable {
            let goal: String
            let steps: [String]
            let estimated_rounds: Int?
        }

        guard let data = arguments.data(using: .utf8) else {
            throw TillyError.toolExecutionFailed("Invalid arguments")
        }
        let args = try JSONDecoder().decode(Args.self, from: data)

        var plan = "Goal: \(args.goal)\n"
        if let est = args.estimated_rounds {
            plan += "Estimated rounds: ~\(est)\n"
        }
        plan += "\n"
        for (i, step) in args.steps.enumerated() {
            plan += "- [ ] \(i + 1). \(step)\n"
        }

        // Query Memcloud for lessons from similar past tasks
        var lessons = ""
        if let client = memoryService?.memcloudClient {
            do {
                let results = try await client.search(query: args.goal, topK: 5)
                let relevant = results.memories.filter {
                    ($0.rerank_score ?? $0.rrf_score ?? 0) > 0.3
                }
                if !relevant.isEmpty {
                    lessons = "\n\n## Lessons from Memory\n"
                    for mem in relevant.prefix(3) {
                        lessons += "- \(String(mem.content.prefix(200)))\n"
                    }
                }
            } catch {}
        }
        // Fallback to local memory
        if lessons.isEmpty, let memService = memoryService {
            let local = (try? memService.search(query: args.goal)) ?? []
            if !local.isEmpty {
                lessons = "\n\n## Lessons from Memory (local)\n"
                for entry in local.prefix(3) {
                    lessons += "- [\(entry.type.rawValue)] \(entry.name): \(String(entry.content.prefix(200)))\n"
                }
            }
        }
        plan += lessons

        service.write("")  // Clear first
        service.append(section: "Plan", content: plan)

        return ToolResult(content: "Plan created with \(args.steps.count) steps. Use scratchpad_write to update progress as you go.")
    }
}
