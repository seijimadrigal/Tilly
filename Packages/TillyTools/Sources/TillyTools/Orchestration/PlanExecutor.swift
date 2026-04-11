import Foundation
import TillyCore

/// Generates and manages structured execution plans for complex tasks.
public actor PlanExecutor {
    public struct Plan: Codable, Sendable {
        public let goal: String
        public var steps: [Step]
        public var status: Status

        public struct Step: Codable, Sendable, Identifiable {
            public let id: Int
            public let description: String
            public var status: StepStatus
            public var result: String?

            public enum StepStatus: String, Codable, Sendable {
                case pending, inProgress, completed, failed, skipped
            }
        }

        public enum Status: String, Codable, Sendable {
            case planning, executing, revising, completed, failed
        }

        public init(goal: String, steps: [Step]) {
            self.goal = goal
            self.steps = steps
            self.status = .planning
        }
    }

    private let provider: any LLMProvider
    private let model: String

    public init(provider: any LLMProvider, model: String) {
        self.provider = provider
        self.model = model
    }

    /// Generate a plan from a user goal.
    public func generatePlan(goal: String, context: String) async throws -> Plan {
        let prompt = """
        Create a step-by-step execution plan for this goal. Respond with ONLY valid JSON:
        {"steps": [{"id": 1, "description": "step description"}, ...]}

        Goal: \(goal)
        Context: \(String(context.prefix(1000)))

        Rules:
        - 3-10 steps maximum
        - Each step should be a single, actionable task
        - Order steps by dependency
        - Be specific about what tools to use
        """

        let request = ChatCompletionRequest(
            model: model,
            messages: [
                ChatCompletionRequest.ChatMessage(role: "system", content: "You are a task planner. Output JSON only."),
                ChatCompletionRequest.ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: 1000,
            stream: false
        )

        let response = try await provider.complete(request)
        guard let text = response.choices.first?.message.content else {
            throw TillyError.planExecutionFailed("No plan generated")
        }

        return parsePlan(goal: goal, text: text)
    }

    /// Mark a step as complete and return the updated plan.
    public func completeStep(_ plan: inout Plan, stepIndex: Int, result: String) {
        guard stepIndex < plan.steps.count else { return }
        plan.steps[stepIndex].status = .completed
        plan.steps[stepIndex].result = result

        if plan.steps.allSatisfy({ $0.status == .completed || $0.status == .skipped }) {
            plan.status = .completed
        }
    }

    /// Mark a step as failed.
    public func failStep(_ plan: inout Plan, stepIndex: Int, error: String) {
        guard stepIndex < plan.steps.count else { return }
        plan.steps[stepIndex].status = .failed
        plan.steps[stepIndex].result = "Error: \(error)"
    }

    /// Get the next pending step index.
    public func nextPendingStep(_ plan: Plan) -> Int? {
        plan.steps.firstIndex { $0.status == .pending }
    }

    /// Format plan as markdown for scratchpad.
    public func formatPlan(_ plan: Plan) -> String {
        var md = "## Plan: \(plan.goal)\nStatus: \(plan.status.rawValue)\n\n"
        for step in plan.steps {
            let icon = switch step.status {
            case .pending: "[ ]"
            case .inProgress: "[~]"
            case .completed: "[x]"
            case .failed: "[!]"
            case .skipped: "[-]"
            }
            md += "\(icon) \(step.id). \(step.description)"
            if let result = step.result {
                md += " → \(String(result.prefix(100)))"
            }
            md += "\n"
        }
        return md
    }

    private func parsePlan(goal: String, text: String) -> Plan {
        // Try to extract JSON from the response
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stepsArray = json["steps"] as? [[String: Any]] else {
            // Fallback: create a single-step plan
            return Plan(goal: goal, steps: [
                Plan.Step(id: 1, description: goal, status: .pending)
            ])
        }

        let steps = stepsArray.enumerated().map { index, step in
            Plan.Step(
                id: (step["id"] as? Int) ?? (index + 1),
                description: (step["description"] as? String) ?? "Step \(index + 1)",
                status: .pending
            )
        }

        return Plan(goal: goal, steps: steps)
    }
}
