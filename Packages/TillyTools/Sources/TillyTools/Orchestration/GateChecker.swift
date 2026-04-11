import Foundation
import TillyCore

/// Checks tool calls against gate policies to determine if human approval is needed.
public struct GateChecker: Sendable {
    private let policies: [GatePolicy]

    public init(policies: [GatePolicy] = GatePolicy.defaults) {
        self.policies = policies
    }

    /// Check if a tool call requires human approval. Returns the triggered policy or nil.
    public func shouldGate(toolCall: ToolCall) -> GatePolicy? {
        let toolName = toolCall.function.name
        let args = toolCall.function.arguments.lowercased()

        for policy in policies {
            let toolMatch = policy.toolPatterns.contains(where: { toolName == $0 })
            if !toolMatch { continue }

            if policy.argPatterns.isEmpty {
                return policy  // Tool match alone is enough
            }

            let argMatch = policy.argPatterns.contains(where: { args.contains($0.lowercased()) })
            if argMatch {
                return policy
            }
        }
        return nil
    }
}
