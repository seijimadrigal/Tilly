import Foundation
import TillyCore

/// Routes tasks to the optimal LLM model based on complexity and task type.
public struct ModelRouter: Sendable {
    public struct ModelRoute: Sendable {
        public let providerID: ProviderID
        public let modelID: String
        public let tier: ModelTier
        public let reason: String
    }

    public enum ModelTier: String, Sendable {
        case flash      // Cheapest, fastest — classification, simple queries
        case standard   // Good balance — most tasks
        case premium    // Best quality — complex reasoning, orchestration
    }

    public struct ModelProfile: Sendable {
        public let providerID: ProviderID
        public let modelID: String
        public let tier: ModelTier
        public let costPer1KTokens: Double
        public let maxContext: Int
    }

    private let profiles: [ModelProfile]

    public init(profiles: [ModelProfile] = ModelProfile.defaults) {
        self.profiles = profiles
    }

    /// Route based on complexity score (0.0 = trivial, 1.0 = very complex)
    public func route(complexity: Double, userOverride: ProviderID? = nil) -> ModelRoute {
        if let override = userOverride, let profile = profiles.first(where: { $0.providerID == override }) {
            return ModelRoute(providerID: profile.providerID, modelID: profile.modelID, tier: profile.tier, reason: "User override")
        }

        let targetTier: ModelTier
        if complexity < 0.3 {
            targetTier = .flash
        } else if complexity < 0.7 {
            targetTier = .standard
        } else {
            targetTier = .premium
        }

        guard let profile = profiles.first(where: { $0.tier == targetTier }) else {
            let fallback = profiles.first ?? ModelProfile.defaults.first!
            return ModelRoute(providerID: fallback.providerID, modelID: fallback.modelID, tier: fallback.tier, reason: "Fallback")
        }

        return ModelRoute(providerID: profile.providerID, modelID: profile.modelID, tier: profile.tier, reason: "Complexity \(String(format: "%.1f", complexity)) → \(targetTier.rawValue)")
    }

    /// Get cost per 1K tokens for a model
    public func costFor(modelID: String) -> Double {
        profiles.first { $0.modelID == modelID }?.costPer1KTokens ?? 0.001
    }
}
